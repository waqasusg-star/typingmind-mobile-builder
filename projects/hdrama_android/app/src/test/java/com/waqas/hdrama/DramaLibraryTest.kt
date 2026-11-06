package com.waqas.hdrama

import android.content.Context
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowAlertDialog
import org.robolectric.Robolectric
import org.robolectric.Shadows.shadowOf
import android.view.View
import android.view.ViewGroup

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class DramaLibraryTest {
    private val context: Context get() = RuntimeEnvironment.getApplication()
    private val url get() = "https://en.hdrama.net/series/saved-story"
    @Before fun clear() {
        context.getSharedPreferences("drama_library",0).edit().clear().commit()
        context.getSharedPreferences("playback",0).edit().clear().commit()
    }
    @Test fun favoritesAndExactProgressSurviveNewStoreInstance() {
        val store = DramaLibrary(context)
        assertTrue(store.toggleFavorite(url,"My Drama"))
        store.saveProgress(url,"My Drama",17,42_125)
        val saved = DramaLibrary(context).favorites().single()
        assertEquals(url,saved.url);assertEquals("My Drama",saved.title)
        assertEquals(17,saved.episode);assertEquals(42_125L,saved.position)
        assertFalse(store.toggleFavorite(url,"My Drama"))
        assertTrue(DramaLibrary(context).favorites().isEmpty())
        assertEquals(42_125L,DramaLibrary(context).get(url)?.position)
    }
    @Test fun everyEpisodeHasIndependentPersistentPositionAndRemovingFavoriteKeepsAllPositions() {
        val store = DramaLibrary(context)
        store.saveProgress(url,"Saved",1,41_250,90_000)
        store.saveProgress(url,"Saved",2,15_375,110_000)
        store.toggleFavorite(url,"Saved");store.removeFavorite(url)
        val restored = DramaLibrary(context)
        assertEquals(41_250L,restored.episodePosition(url,1))
        assertEquals(15_375L,restored.episodePosition(url,2))
        assertEquals(0L,restored.episodePosition(url,3))
        assertEquals(110_000L,restored.get(url)!!.duration)
        val second = url.replace("saved-story","other")
        assertEquals(0L,restored.episodePosition(second,1))
    }
    @Test fun legacyPositionRemainsAvailableAfterWatchingAnotherEpisode() {
        context.getSharedPreferences("playback",0).edit().putInt("episode:$url",8).putLong("position:$url",29_500).commit()
        val store = DramaLibrary(context)
        assertEquals(29_500L,store.episodePosition(url,8))
        store.saveProgress(url,"Saved",8,29_500)
        store.saveProgress(url,"Saved",9,12_500)
        assertEquals(29_500L,DramaLibrary(context).episodePosition(url,8))
    }
    @Test fun favoriteRowIncludesPosterTitleEpisodeAndDuration() {
        val store = DramaLibrary(context);store.saveProgress(url,"Saved Story",9,12_000,90_000);store.toggleFavorite(url,"Saved Story")
        val c = Robolectric.buildActivity(MainActivity::class.java).create()
        try {
            all(c.get().window.decorView).first { it.contentDescription == "My List" }.performClick()
            val list = ShadowAlertDialog.getLatestAlertDialog().listView
            val row = list.adapter.getView(0,null,list)
            assertTrue(all(row).any { it is android.widget.ImageView && it.contentDescription == "Saved Story poster" })
            assertTrue(all(row).filterIsInstance<android.widget.TextView>().any { it.text == "Saved Story" })
            assertTrue(all(row).filterIsInstance<android.widget.TextView>().any { it.text.toString().contains("EP. 9 · 0:12 / 1:30") })
        } finally { c.destroy() }
    }
    @Test fun previousVersionProgressMigratesWhenFavorited() {
        context.getSharedPreferences("playback",0).edit().putInt("episode:$url",8).putLong("position:$url",29_500).commit()
        val store = DramaLibrary(context);store.toggleFavorite(url,"Existing Drama")
        assertEquals(8,store.favorites().single().episode);assertEquals(29_500L,store.favorites().single().position)
    }
    @Test fun corruptAndForeignRecordsDoNotLaunchOtherSites() {
        context.getSharedPreferences("drama_library",0).edit().putString("records","broken").commit()
        val store = DramaLibrary(context);assertTrue(store.favorites().isEmpty())
        assertFalse(store.toggleFavorite("https://example.com/series/foreign","Wrong site"))
        store.saveProgress(url,"Valid",-1,-5);assertEquals(1,store.get(url)?.episode);assertEquals(0L,store.get(url)?.position)
        assertTrue(store.favorites().isEmpty())
    }
    private fun all(v: View): List<View> = listOf(v) + if (v is ViewGroup) (0 until v.childCount).flatMap { all(v.getChildAt(it)) } else emptyList()
    @Test fun browserMyListLaunchesSavedSeriesWithoutOverridingResumeEpisode() {
        val store = DramaLibrary(context);store.saveProgress(url,"Saved Story",9,12_000);store.toggleFavorite(url,"Saved Story")
        val c = Robolectric.buildActivity(MainActivity::class.java).create()
        try {
            val activity = c.get();all(activity.window.decorView).first { it.contentDescription == "My List" }.performClick()
            val dialog = ShadowAlertDialog.getLatestAlertDialog()
            assertNotNull(dialog);assertTrue(dialog.listView.adapter.getItem(0).toString().contains("EP. 9"))
            shadowOf(dialog).clickOnItem(0)
            val intent = shadowOf(activity).nextStartedActivity
            assertEquals(PlayerActivity::class.java.name,intent.component?.className)
            assertEquals(url,intent.getStringExtra("series"));assertFalse(intent.hasExtra("episode"))
        } finally { c.destroy() }
    }    @Test fun longPressRemovesOnlyTheHeldDramaAndKeepsResumeHistory() {
        val store = DramaLibrary(context)
        val second = url.replace("saved-story","second-story")
        store.saveProgress(url,"First Drama",7,31_000);store.toggleFavorite(url,"First Drama")
        store.saveProgress(second,"Second Drama",4,22_000);store.toggleFavorite(second,"Second Drama")
        val c = Robolectric.buildActivity(MainActivity::class.java).create()
        try {
            val activity = c.get()
            all(activity.window.decorView).first { it.contentDescription == "My List" }.performClick()
            val dialog = ShadowAlertDialog.getLatestAlertDialog();val list = dialog.listView
            val held = store.favorites().first()
            assertTrue(list.onItemLongClickListener.onItemLongClick(list,list.adapter.getView(0,null,list),0,list.adapter.getItemId(0)))
            assertFalse(store.get(held.url)!!.favorite);assertEquals(held.position,store.get(held.url)!!.position)
            assertEquals(held.episode,store.get(held.url)!!.episode);assertEquals(1,list.adapter.count)
            assertNull(shadowOf(activity).nextStartedActivity)
            val remaining = store.favorites().single()
            shadowOf(dialog).clickOnItem(0)
            assertEquals(remaining.url,shadowOf(activity).nextStartedActivity.getStringExtra("series"))
        } finally { c.destroy() }
    }
    @Test fun removingTheLastFavoriteClosesListAndRepeatedRemovalNeverAddsItBack() {
        val store = DramaLibrary(context);store.saveProgress(url,"Saved",3,14_000);store.toggleFavorite(url,"Saved")
        val c = Robolectric.buildActivity(MainActivity::class.java).create()
        try {
            val activity = c.get();all(activity.window.decorView).first { it.contentDescription == "My List" }.performClick()
            val dialog = ShadowAlertDialog.getLatestAlertDialog();val list = dialog.listView
            list.onItemLongClickListener.onItemLongClick(list,list.adapter.getView(0,null,list),0,list.adapter.getItemId(0))
            assertTrue(store.favorites().isEmpty());assertFalse(dialog.isShowing);assertFalse(store.removeFavorite(url))
            assertEquals(14_000L,store.get(url)?.position);assertEquals(3,store.get(url)?.episode)
            assertNull(shadowOf(activity).nextStartedActivity)
        } finally { c.destroy() }
    }

    @Test fun historyClearPreservesFavoritesAndEveryEpisodeResumeAndWatchingAddsSeriesAgain() {
        val store = DramaLibrary(context)
        store.toggleFavorite(url,"Saved")
        assertTrue(store.history().isEmpty())
        store.saveProgress(url,"Saved",1,28_500,90_000)
        store.saveProgress(url,"Saved",2,10_250,90_000)
        val second = url.replace("saved-story","second")
        store.saveProgress(second,"Second",3,5_000,60_000)
        assertEquals(2,store.history().size)
        store.removeHistory(url)
        assertEquals(listOf(second),store.history().map { it.url })
        assertTrue(store.get(url)!!.favorite)
        assertEquals(28_500L,store.episodePosition(url,1)); assertEquals(10_250L,store.episodePosition(url,2))
        store.clearHistory(); assertTrue(DramaLibrary(context).history().isEmpty())
        store.saveProgress(url,"Saved",2,15_000,90_000)
        assertEquals(url,DramaLibrary(context).history().single().url)
    }
    @Test fun oldProgressAppearsInHistoryButNeverResurrectsAfterClear() {
        context.getSharedPreferences("playback",0).edit().putInt("episode:$url",8).putLong("position:$url",29_500).commit()
        val store = DramaLibrary(context)
        assertEquals(8,store.history().single().episode)
        store.clearHistory(); assertTrue(DramaLibrary(context).history().isEmpty())
        assertEquals(29_500L,DramaLibrary(context).episodePosition(url,8))
    }

    @Test fun completedEpisodesRestartButUnfinishedEpisodesKeepExactIndependentPositions() {
        val store = DramaLibrary(context)
        store.saveProgress(url,"Story",1,120_000,120_000,completed = true)
        store.saveProgress(url,"Story",2,24_125,90_000)
        assertEquals(0L,DramaLibrary(context).episodePosition(url,1))
        assertEquals(24_125L,DramaLibrary(context).episodePosition(url,2))
        store.saveProgress(url,"Story",1,5_125,120_000)
        assertEquals(5_125L,DramaLibrary(context).episodePosition(url,1))
    }
    @Test fun oldEndTimestampMigratesToReplayWithoutResettingAnUnfinishedEpisode() {
        context.getSharedPreferences("drama_library",0).edit().putString("records",
            org.json.JSONArray().put(org.json.JSONObject().put("url",url).put("title","Old Story").put("episode",8).put("position",90_000).put("duration",90_000)).toString()).commit()
        assertEquals(0L,DramaLibrary(context).episodePosition(url,8))
        DramaLibrary(context).saveProgress(url,"Old Story",9,30_500,90_000)
        assertEquals(30_500L,DramaLibrary(context).episodePosition(url,9))
    }

}
