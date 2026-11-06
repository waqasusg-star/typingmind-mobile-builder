package com.waqas.hdrama

import android.graphics.Bitmap
import kotlinx.coroutines.runBlocking
import org.jsoup.Jsoup
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import org.robolectric.Robolectric
import androidx.media3.common.util.UnstableApi
import android.view.View
import android.view.ViewGroup
import android.widget.TextView

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@androidx.annotation.OptIn(markerClass = [UnstableApi::class])
class DownloadFoldersTest {
    private val origin = "https://en.hdrama.net"
    private fun series(slug: String) = Series("Same title","$origin/series/$slug",(1..3).map { Episode(it,"$origin/series/$slug/episode-$it") })
    @Test fun seasonsWithMatchingTitlesRemainSeparateAndEpisodesSortNumerically() {
        val first = series("season-one").copy(seasonLabel = "Season 1")
        val second = series("season-two").copy(seasonLabel = "Season 2")
        val folders = DownloadFolders.group(listOf(OfflineMetadata(first,2,720),OfflineMetadata(second,1,720),OfflineMetadata(first,0,720)))
        assertEquals(2,folders.size)
        assertEquals(listOf(1,3),folders[first.url]!!.map { it.series.episodes[it.index].number })
        assertEquals(listOf(2),folders[second.url]!!.map { it.series.episodes[it.index].number })
    }
    @Test fun posterAndSeasonMetadataSurviveDownloadSerializationAndLegacyData() {
        val doc = Jsoup.parse("<meta property='og:image' content='/posters/show.jpg'>",origin)
        assertEquals("$origin/posters/show.jpg",SeriesArtwork.poster(doc,"Show"))
        val cover = Jsoup.parse("<meta property='og:image' content='/site-logo.jpg'><img alt='The Virgin’s Bucket List poster' src='/real-cover.jpg'>",origin)
        assertEquals("$origin/real-cover.jpg",SeriesArtwork.poster(cover,"The Virgin's Bucket List"))
        assertEquals("Season 2",SeriesArtwork.season("Show Season 2"))
        val metadata = OfflineMetadata(series("sample").copy(posterUrl = "$origin/poster.jpg",seasonLabel = "Season 2"),0,720)
        assertEquals(metadata,OfflineMetadata.parse(metadata.json()))
        val legacy = metadata.json().apply { remove("poster");remove("season") }
        assertEquals("",OfflineMetadata.parse(legacy).series.posterUrl)
        assertEquals("",OfflineMetadata.parse(legacy).series.seasonLabel)
    }
    @Test fun savedThumbnailIsReadableWithoutNetwork() = runBlocking {
        val context = RuntimeEnvironment.getApplication()
        val series = series("cached-art")
        SeriesArtwork.file(context,series.url).delete()
        val bitmap = Bitmap.createBitmap(100,160,Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(android.graphics.Color.BLUE)
        SeriesArtwork.frame(context,series.url,bitmap)
        assertFalse(SeriesArtwork.hasPoster(context,series.url))
        context.getSharedPreferences("series_artwork",0).edit().putString("poster-source:${series.url}","$origin/cover.jpg").commit()
        assertTrue(SeriesArtwork.hasPoster(context,series.url))
        assertNotNull(SeriesArtwork.bitmap(context,series.url))
        SeriesArtwork.remember(context,series.copy(posterUrl = "$origin/cover.jpg",seasonLabel = "Season 1"))
        assertEquals("$origin/cover.jpg",SeriesArtwork.enrich(context,series).posterUrl)
    }
    private fun all(view: View): List<View> = listOf(view) + if (view is ViewGroup) (0 until view.childCount).flatMap { all(view.getChildAt(it)) } else emptyList()
    @Test fun downloadsOverviewShowsFoldersAndOpeningOneDoesNotMixEpisodes() {
        val context = RuntimeEnvironment.getApplication()
        for (name in listOf("manager","cache")) {
            val field = OfflineStore::class.java.getDeclaredField(name).apply { isAccessible = true }
            when (val value = field.get(OfflineStore)) {
                is androidx.media3.exoplayer.offline.DownloadManager -> runCatching { value.release() }
                is androidx.media3.datasource.cache.SimpleCache -> runCatching { value.release() }
            };field.set(OfflineStore,null)
        }
        context.getSharedPreferences("offline_queue",0).edit().clear().commit()
        val first = series("one").copy(title = "First Drama")
        val second = series("two").copy(title = "Second Drama")
        OfflineStore.queue(context,first,listOf(0,2),720)
        OfflineStore.queue(context,second,listOf(1),720)
        OfflineStore.setPaused(context,true)
        val controller = Robolectric.buildActivity(DownloadsActivity::class.java).create().start()
        try {
            val activity = controller.get()
            val render = DownloadsActivity::class.java.getDeclaredMethod("render").apply { isAccessible = true }
            render.invoke(activity)
            val views = all(activity.window.decorView)
            assertEquals(2,views.count { it.contentDescription?.toString()?.startsWith("Open series folder:") == true })
            assertTrue(views.filterIsInstance<TextView>().none { it.text.toString().startsWith("Episode ") })
            val firstFolder = views.single { it.contentDescription == "Open series folder: First Drama" }
            assertTrue(firstFolder.performLongClick())
            val confirmation = org.robolectric.shadows.ShadowAlertDialog.getLatestAlertDialog()
            assertNotNull(confirmation);confirmation.dismiss()
            assertEquals(3,OfflineStore.pending(context).size)
            firstFolder.performClick()
            val episodes = all(activity.window.decorView).filterIsInstance<TextView>().filter { it.contentDescription?.toString()?.startsWith("Episode ") == true }.map { it.text.toString() }
            assertEquals(2,episodes.size)
            val tile = all(activity.window.decorView).single { it.contentDescription?.toString()?.startsWith("Episode 1,") == true }
            assertTrue(tile.performLongClick())
            val delete = org.robolectric.shadows.ShadowAlertDialog.getLatestAlertDialog()
            delete.getButton(android.content.DialogInterface.BUTTON_POSITIVE).performClick()
            org.robolectric.Shadows.shadowOf(android.os.Looper.getMainLooper()).idle()
            assertEquals(listOf(3),OfflineStore.pending(context).filter { it.series.url == first.url }.map { it.series.episodes[it.index].number })
            assertTrue(episodes.first().startsWith("1\n"));assertTrue(episodes.last().startsWith("3\n"))
            activity.onBackPressedDispatcher.onBackPressed()
            assertEquals(2,all(activity.window.decorView).count { it.contentDescription?.toString()?.startsWith("Open series folder:") == true })
            all(activity.window.decorView).single { it.contentDescription == "Open series folder: First Drama" }.performLongClick()
            org.robolectric.shadows.ShadowAlertDialog.getLatestAlertDialog().getButton(android.content.DialogInterface.BUTTON_POSITIVE).performClick()
            org.robolectric.Shadows.shadowOf(android.os.Looper.getMainLooper()).idle()
            assertEquals(listOf(second.url),OfflineStore.pending(context).map { it.series.url })
        } finally {
            controller.stop().destroy()
            for (name in listOf("manager","cache")) {
                val field = OfflineStore::class.java.getDeclaredField(name).apply { isAccessible = true }
                when (val value = field.get(OfflineStore)) {
                    is androidx.media3.exoplayer.offline.DownloadManager -> value.release()
                    is androidx.media3.datasource.cache.SimpleCache -> value.release()
                };field.set(OfflineStore,null)
            }
        }
    }
}
