package com.waqas.hdrama

import android.content.Intent
import androidx.media3.common.*
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.offline.*
import kotlinx.coroutines.async
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.test.runTest
import org.robolectric.Shadows.shadowOf
import android.os.Looper
import org.junit.Assert.*
import org.junit.Before
import org.junit.After
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import android.app.Activity
import android.widget.GridLayout
import android.widget.TextView
import android.view.View
import android.view.ViewGroup
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@androidx.annotation.OptIn(markerClass = [UnstableApi::class])
class OfflineFeaturesTest {
    @org.junit.Before fun allowSignedPipReceiver() {
        val app: android.app.Application = RuntimeEnvironment.getApplication()
        org.robolectric.Shadows.shadowOf(app).grantPermissions("${app.packageName}.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION")
    }
    private val context get() = RuntimeEnvironment.getApplication()
    private val url = "https://en.hdrama.net/series/offline-test"
    private fun series(count: Int = 3) = Series("Offline Test",url,(1..count).map { Episode(it,"$url/episode-$it") })
    private fun releaseOfflineResources() {
        for (fieldName in listOf("manager","cache")) {
            val field = OfflineStore::class.java.getDeclaredField(fieldName).apply { isAccessible = true }
            when (val resource = field.get(OfflineStore)) {
                is DownloadManager -> runCatching { resource.release() }
                is androidx.media3.datasource.cache.SimpleCache -> runCatching { resource.release() }
            };field.set(OfflineStore,null)
        }
    }
    @After fun cleanup() { releaseOfflineResources() }
    @Before fun clearQueue() { releaseOfflineResources(); context.getSharedPreferences("offline_queue",0).edit().clear().commit() }
    @Test fun qualityUsesPortraitWidthAndOnlySupportedFormats() {
        val full = Format.Builder().setSampleMimeType(MimeTypes.VIDEO_H264).setWidth(1080).setHeight(1920).build()
        val medium = full.buildUpon().setWidth(720).setHeight(1280).build()
        val group = Tracks.Group(TrackGroup("video",full,medium),true,intArrayOf(C.FORMAT_UNSUPPORTED_TYPE,C.FORMAT_HANDLED),booleanArrayOf(false,true))
        assertEquals(listOf(720),QualityOptions.available(Tracks(listOf(group))).map { it.pixels })
        assertEquals(1080,QualityOptions.pixels(full))
        assertEquals(720,QualityOptions.nearest(listOf(1080,720,540),900))
        assertEquals(540,QualityOptions.nearest(listOf(1080,720,540),240))
    }
    @Test fun persistedQueueDeduplicatesAndRetainsSeriesForOfflineOpening() {
        OfflineStore.queue(context,series(),listOf(0,1),720)
        OfflineStore.queue(context,series(),listOf(1,2),540)
        val items = OfflineStore.pending(context)
        assertEquals(3,items.size)
        assertEquals(540,items.single { it.index == 1 }.quality)
        val restored = OfflineMetadata.parse(items.first().json().toString().toByteArray())
        assertEquals(series(),restored.series)
        OfflineStore.failPending(context,items.first().id)
        assertTrue(OfflineStore.pending(context).first().error.isNotBlank())
        OfflineStore.retryPending(context,items.first().id)
        assertTrue(OfflineStore.pending(context).first().error.isEmpty())
        OfflineStore.removePending(context,items.first().id)
        assertEquals(2,OfflineStore.pending(context).size)
    }
    @Test fun pauseAndWifiPreferencesSurviveReopening() {
        OfflineStore.setPaused(context,true); OfflineStore.setWifiOnly(context,true)
        assertTrue(OfflineStore.isPaused(context));assertTrue(OfflineStore.wifiOnly(context))
        OfflineStore.setPaused(context,false);OfflineStore.setWifiOnly(context,false)
        assertFalse(OfflineStore.isPaused(context));assertFalse(OfflineStore.wifiOnly(context))
    }
    @Test fun progressiveDownloadRequestContainsOfflineSeriesAndRequestHeaders() = runTest {
        val stream = Stream("https://media.example/episode.mp4",url,"Test user agent","video/mp4")
        val metadata = OfflineMetadata(series(),1,720,stream)
        val prepared = async(start = CoroutineStart.UNDISPATCHED) { OfflineStore.prepare(context,metadata) }
        shadowOf(Looper.getMainLooper()).idle()
        val request = prepared.await()
        assertEquals(metadata.id,request.id)
        assertEquals(stream.url,request.uri.toString())
        assertEquals(metadata,OfflineMetadata.parse(request.data))
        assertTrue(request.streamKeys.isEmpty())
    }
    @Test fun offlineDataReadsCachedBytesAndCannotFetchMissingMedia() {
        val uri = "https://media.example/cache-test.mp4"
        val spec = androidx.media3.datasource.DataSpec.Builder().setUri(uri).setKey(uri).setLength(4).build()
        val sink = androidx.media3.datasource.cache.CacheDataSink(OfflineStore.cache(context),1024*1024)
        val hole = OfflineStore.cache(context).startReadWrite(uri,0,4)
        sink.open(spec);sink.write(byteArrayOf(1,2,3,4),0,4);sink.close();OfflineStore.cache(context).releaseHoleSpan(hole)
        val source = OfflineStore.offlineData(context).createDataSource()
        try {
            assertEquals(4L,source.open(spec))
            val result = ByteArray(4);assertEquals(4,source.read(result,0,4));assertArrayEquals(byteArrayOf(1,2,3,4),result)
        } finally { source.close() }
        val missing = OfflineStore.offlineData(context).createDataSource()
        try { assertTrue(runCatching { missing.open(androidx.media3.datasource.DataSpec(android.net.Uri.parse("https://media.example/never-downloaded.mp4"))) }.isFailure) }
        finally { missing.close() }
    }
    @Test fun completedEpisodeOpensFromSavedMetadataWithoutWebsiteHandoff() {
        val metadata = OfflineMetadata(series(),1,720,Stream("https://media.example/offline.mp4",url,"test","video/mp4"))
        val request = DownloadRequest.Builder(metadata.id,android.net.Uri.parse(metadata.stream!!.url)).setMimeType("video/mp4").setData(metadata.json().toString().toByteArray()).build()
        OfflineStore.manager(context).downloadIndex.let { it as WritableDownloadIndex }.putDownload(Download(request,Download.STATE_COMPLETED,1,1,100,0,0))
        val controller = Robolectric.buildActivity(PlayerActivity::class.java,Intent().putExtra("series",url).putExtra("episode",2).putExtra("offline",metadata.id)).create()
        try {
            val activity = controller.get()
            val localSeries = PlayerActivity::class.java.getDeclaredField("series").apply { isAccessible = true }.get(activity)
            assertEquals(metadata.series,localSeries)
            assertEquals(1,PlayerActivity::class.java.getDeclaredField("index").apply { isAccessible = true }.getInt(activity))
            assertTrue(PlayerActivity::class.java.getDeclaredField("offlineOnly").apply { isAccessible = true }.getBoolean(activity))
        } finally {
            controller.destroy()
            (OfflineStore.manager(context).downloadIndex as WritableDownloadIndex).removeDownload(metadata.id)
        }
    }
    private fun all(view: View): List<View> = listOf(view) + if (view is ViewGroup) (0 until view.childCount).flatMap { all(view.getChildAt(it)) } else emptyList()
    @Test fun episodeSheetShowsThirtyCellsFiveColumnsAndLastRange() {
        val controller = Robolectric.buildActivity(Activity::class.java).setup()
        val activity = controller.get()
        val dialog = episodeSheet(activity,series(38),0)
        try {
            val grid = all(dialog.window!!.decorView).filterIsInstance<GridLayout>().single()
            assertEquals(5,grid.columnCount); assertEquals(30,grid.childCount)
            all(dialog.window!!.decorView).filterIsInstance<TextView>().single { it.text == "31–38" }.performClick()
            assertEquals(10,grid.childCount); assertEquals(8,all(grid).filterIsInstance<TextView>().count { it.contentDescription?.toString()?.startsWith("Episode ") == true })
            assertTrue(all(grid).filterIsInstance<TextView>().any { it.contentDescription == "Episode 38" })
        } finally { dialog.dismiss();controller.destroy() }
    }
    @Test fun downloadSheetCanSelectWholeSeriesAcrossRanges() {
        val controller = Robolectric.buildActivity(Activity::class.java).setup()
        var selected = emptyList<Int>()
        val dialog = episodeSheet(controller.get(),series(38),0,downloadMode = true,onDownload = { selected = it })
        try {
            all(dialog.window!!.decorView).filterIsInstance<TextView>().single { it.text == "Select all" }.performClick()
            all(dialog.window!!.decorView).filterIsInstance<TextView>().single { it.text == "Download selected" }.performClick()
            assertEquals((0 until 38).toList(),selected)
        } finally { dialog.dismiss();controller.destroy() }
    }
    @Test fun renderEpisodeSheetForLayoutReview() {
        val target = System.getenv("DRAMA_UI_PREVIEW_DIR") ?: return
        val controller = Robolectric.buildActivity(Activity::class.java).setup()
        val dialog = episodeSheet(controller.get(),series(38),1)
        try {
            val view = all(dialog.window!!.decorView).filterIsInstance<android.widget.LinearLayout>().first { it.background is android.graphics.drawable.GradientDrawable }
            view.measure(View.MeasureSpec.makeMeasureSpec(360,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(560,View.MeasureSpec.EXACTLY))
            view.layout(0,0,360,560)
            val bitmap = android.graphics.Bitmap.createBitmap(360,560,android.graphics.Bitmap.Config.ARGB_8888)
            view.draw(android.graphics.Canvas(bitmap))
            val file = java.io.File(target,"episode-sheet.png");file.parentFile?.mkdirs()
            file.outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it) };bitmap.recycle()
        } finally { dialog.dismiss();controller.destroy() }
    }
}
