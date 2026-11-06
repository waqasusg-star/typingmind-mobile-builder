package com.waqas.hdrama

import kotlinx.coroutines.*
import kotlinx.coroutines.test.*
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class SessionStreamsTest {
    private val first = Episode(1,"https://en.hdrama.net/series/story/episode-1")
    private val second = Episode(2,"https://en.hdrama.net/series/story/episode-2")
    private fun result(e: Episode, token: Int = 1) = Stream("https://media.example/${e.number}.m3u8?token=$token",e.pageUrl,"ua")
    @Test fun nextPressSharesInFlightBackgroundResolution() = runTest {
        var calls = 0
        val store = SessionStreams(this,{currentTime},{ delay(100);calls++;result(it) })
        val background = async { store.get(second) }; runCurrent()
        val foreground = async { store.get(second) }; advanceUntilIdle()
        assertEquals(background.await(),foreground.await());assertEquals(1,calls)
    }
    @Test fun cancellingBackgroundWaitDoesNotCancelRequestedNext() = runTest {
        var calls = 0
        val store = SessionStreams(this,{currentTime},{calls++;delay(100);result(it)})
        val background = launch { store.get(second) };runCurrent();background.cancelAndJoin()
        val next = async { store.get(second) };advanceUntilIdle()
        assertEquals(result(second),next.await());assertEquals(1,calls)
    }
    @Test fun staleUrlsRefreshAndRetryForcesNewResolution() = runTest {
        var now = 0L;var calls = 0
        val store = SessionStreams(this,{now},{result(it,++calls)},ttlMs = 60_000)
        val firstLink = store.get(first);assertEquals(firstLink,store.get(first));assertEquals(1,calls)
        now = 60_000;assertNull(store.peek(first));assertNotEquals(firstLink,store.get(first))
        store.get(first,refresh = true);assertEquals(3,calls)
    }
    @Test fun unrelatedPrefetchIsCancelledWhileTargetRemains() = runTest {
        val store = SessionStreams(this,{currentTime},{delay(100);result(it)})
        val a = async { store.get(first) };val b = async { store.get(second) };runCurrent()
        store.cancelExcept(second.pageUrl);advanceUntilIdle()
        assertTrue(a.isCancelled);assertEquals(result(second),b.await())
    }
    @Test fun failedResolutionCanBeRetriedWithoutCachingError() = runTest {
        var calls = 0
        val loaders = CoroutineScope(SupervisorJob() + StandardTestDispatcher(testScheduler))
        val store = SessionStreams(loaders,{currentTime},{if (++calls == 1) throw java.io.IOException("offline") else result(it)})
        try {
            assertTrue(runCatching { store.get(first) }.isFailure);assertNull(store.peek(first))
            assertEquals(result(first),store.get(first));assertEquals(2,calls)
        } finally { store.clear(); loaders.cancel() }
    }
    @Test fun sessionIsBoundedAndClearRemovesWarmSources() = runTest {
        val store = SessionStreams(this,{currentTime},{result(it)})
        for (i in 1..4) store.get(Episode(i,"https://en.hdrama.net/series/story/episode-$i"))
        assertNull(store.peek(first));assertNotNull(store.peek(second));store.clear();assertNull(store.peek(second))
    }
    @Test fun browserHandoffIsConsumedOnceAndOnlyForMatchingSeries() {
        val series = Series("Story","https://en.hdrama.net/series/story",listOf(first,second))
        PlaybackHandoff.offer(series);assertEquals(series,PlaybackHandoff.take(series.url));assertNull(PlaybackHandoff.take(series.url))
        PlaybackHandoff.offer(series);assertNull(PlaybackHandoff.take("https://en.hdrama.net/series/other"))
    }
}
