package com.waqas.hdrama

import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@androidx.annotation.OptIn(markerClass = [UnstableApi::class])
class PlaybackEngineTest {
    @Test fun stagingAnUpcomingSourceDoesNotReplaceOrStartTheCurrentPlayer() {
        val engine = PlaybackEngine(RuntimeEnvironment.getApplication())
        try {
            val a = Episode(1,"https://en.hdrama.net/series/story/episode-1")
            val b = Episode(2,"https://en.hdrama.net/series/story/episode-2")
            val series = Series("Story","https://en.hdrama.net/series/story",listOf(a,b))
            engine.currentIndex = 0
            engine.stageNext(series,1,Stream("https://media.example/next.m3u8",b.pageUrl,"test"))
            assertEquals(0,engine.player.mediaItemCount)
            assertEquals(Player.STATE_IDLE,engine.player.playbackState)
            assertFalse(engine.player.playWhenReady)
            // The player and preloader share their construction components and release cleanly.
        } finally { engine.release() }
    }
}
