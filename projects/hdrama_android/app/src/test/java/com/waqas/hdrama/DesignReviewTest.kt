package com.waqas.hdrama

import android.app.Activity
import android.content.Context
import android.graphics.*
import android.view.*
import android.widget.*
import androidx.core.graphics.ColorUtils
import androidx.media3.exoplayer.offline.*
import androidx.media3.common.util.UnstableApi
import org.junit.Assert.*
import org.junit.Before
import org.junit.After
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@androidx.annotation.OptIn(markerClass = [UnstableApi::class])
class DesignReviewTest {
    private val context: Context get() = RuntimeEnvironment.getApplication()
    private val url get() = SitePolicy.HOME.removeSuffix("/") + "/series/design-review"
    private fun all(view: View): List<View> = listOf(view) + if (view is ViewGroup) (0 until view.childCount).flatMap { all(view.getChildAt(it)) } else emptyList()
    private fun layout(view: View,w: Int,h: Int) {
        repeat(2) { view.measure(View.MeasureSpec.makeMeasureSpec(w,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(h,View.MeasureSpec.EXACTLY));view.layout(0,0,w,h) }
    }
    private fun render(view: View,name: String,w: Int,h: Int) {
        val destination = System.getenv("HDRAMA_UI_PREVIEW_DIR") ?: return
        layout(view,w,h)
        val bitmap = Bitmap.createBitmap(w,h,Bitmap.Config.ARGB_8888);view.draw(Canvas(bitmap))
        File(destination).mkdirs();File(destination,"review-${java.net.URI(SitePolicy.HOME).host}-$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG,100,it) };bitmap.recycle()
    }
    private fun release() {
        for (name in listOf("manager","cache")) {
            val field = OfflineStore::class.java.getDeclaredField(name).apply { isAccessible = true }
            when (val resource = field.get(OfflineStore)) {
                is DownloadManager -> resource.release()
                is androidx.media3.datasource.cache.SimpleCache -> resource.release()
            }
            field.set(OfflineStore,null)
        }
    }
    @Before fun prepare() {
        release(); RuntimeEnvironment.setFontScale(1f)
        context.getSharedPreferences("drama_library",0).edit().clear().commit()
        context.getSharedPreferences("playback",0).edit().clear().commit()
        context.getSharedPreferences("offline_queue",0).edit().clear().commit()
    }
    @After fun cleanup() { release(); RuntimeEnvironment.setFontScale(1f) }
    @Test fun paletteKeepsSecondaryTextAndPrimaryActionTextReadable() {
        assertTrue(ColorUtils.calculateContrast(AppColors.muted,AppColors.surface) >= 4.5)
        assertTrue(ColorUtils.calculateContrast(AppColors.background,accent) >= 4.5)
    }
    @Test fun browserDockAdaptsToNarrowPhonesAndDoesNotSpreadAcrossWideWindows() {
        val c = Robolectric.buildActivity(MainActivity::class.java).create()
        try {
            val views = all(c.get().window.decorView)
            val buttons = views.filterIsInstance<ImageButton>()
            val row = buttons.first().parent.parent as BrowserDock
            val play = buttons.first { it.contentDescription == "Play in native player" };play.visibility = View.VISIBLE;(play.parent as View).visibility = View.VISIBLE
            for (w in listOf(256,280,320,760)) {
                layout(row,w,96)
                assertTrue(row.measuredWidth <= c.get().dp(440))
                buttons.forEach { button ->
                    val rect = Rect();button.getDrawingRect(rect);row.offsetDescendantRectToMyCoords(button,rect)
                    assertTrue("Dock target outside narrow window: $rect",rect.left >= 0 && rect.right <= row.width)
                    assertTrue(button.width >= c.get().dp(48) && button.height >= c.get().dp(48))
                }
                render(row,"dock-$w",minOf(w,c.get().dp(440)),96)
            }
        } finally { c.destroy() }
    }
    @Test fun shortLandscapeSheetKeepsEpisodeGridScrollableAndDownloadActionUsableWithLargeFonts() {
        RuntimeEnvironment.setFontScale(1.3f)
        val c = Robolectric.buildActivity(Activity::class.java).setup()
        val series = Series("A Very Long Series Name That Still Needs a Readable Episode Selector",url,(1..38).map { Episode(it,"$url/episode-$it") })
        val dialog = episodeSheet(c.get(),series,1,downloadMode = true)
        try {
            val root = all(dialog.window!!.decorView).filterIsInstance<LinearLayout>().first { it.background is android.graphics.drawable.GradientDrawable }
            layout(root,568,260)
            val scroll = all(root).filterIsInstance<ScrollView>().single()
            val grid = all(root).filterIsInstance<GridLayout>().single()
            assertTrue(scroll.height > 0);assertEquals(30,grid.childCount)
            val gridBounds = Rect();grid.getDrawingRect(gridBounds);root.offsetDescendantRectToMyCoords(grid,gridBounds)
            assertTrue("Episode choices start outside the visible sheet",gridBounds.top < scroll.bottom)
            assertTrue(scroll.getChildAt(0).height > scroll.height)
            val submit = all(root).filterIsInstance<Button>().single { it.text == "Download selected" }
            assertTrue(submit.height >= c.get().dp(48));assertTrue(submit.bottom <= root.height)
            all(root).filterIsInstance<Button>().single { it.text == "Clear" }.performClick()
            assertFalse(submit.isEnabled)
            all(grid).first { it.contentDescription?.toString()?.startsWith("Episode 3") == true }.performClick()
            assertTrue(submit.isEnabled)
            render(root,"download-sheet-landscape-large-font",568,260)
        } finally { dialog.dismiss();c.destroy() }
    }
    @Test fun nativeListsAndEmptyStatesRenderWithoutMissingActions() {
        val history = Robolectric.buildActivity(HistoryActivity::class.java).create()
        try {
            val activity = history.get();val renderMethod = HistoryActivity::class.java.getDeclaredMethod("render").apply { isAccessible = true }
            renderMethod.invoke(activity)
            val root = activity.findViewById<ViewGroup>(android.R.id.content).getChildAt(0)
            render(root,"history-empty",360,800)
            DramaLibrary(activity).saveProgress(url,"The Long Story of a Second Chance and an Unexpected Return",12,45_125,120_000)
            renderMethod.invoke(activity);render(root,"history-list",360,800)
            assertTrue(all(root).any { it.contentDescription?.toString()?.startsWith("Continue watching:") == true })
            assertTrue(all(root).any { it.contentDescription == "Back" })
        } finally { history.destroy() }
        val downloads = Robolectric.buildActivity(DownloadsActivity::class.java).create()
        try {
            val activity = downloads.get();val renderMethod = DownloadsActivity::class.java.getDeclaredMethod("render").apply { isAccessible = true }
            renderMethod.invoke(activity)
            val root = activity.findViewById<ViewGroup>(android.R.id.content).getChildAt(0)
            render(root,"downloads-empty",360,800)
            val series = Series("The Long Story of a Second Chance",url,(1..7).map { Episode(it,"$url/episode-$it") })
            OfflineStore.queue(activity,series,series.episodes.indices.toList(),720);renderMethod.invoke(activity)
            render(root,"downloads-folders",360,800)
            all(root).first { it.contentDescription?.toString()?.startsWith("Open series folder:") == true }.performClick()
            render(root,"downloads-episodes",360,800)
            assertEquals(10,all(root).filterIsInstance<GridLayout>().single().childCount)
        } finally { downloads.destroy() }
    }
    @Test fun downloadingPercentagesUpdateExistingTilesInsteadOfRebuildingTheFolder() {
        val series = Series("Progress Test",url,listOf(Episode(1,"$url/episode-1")))
        OfflineStore.queue(context,series,listOf(0),720)
        val metadata = OfflineStore.pending(context).single()
        val c = Robolectric.buildActivity(DownloadsActivity::class.java).create()
        try {
            val activity = c.get()
            DownloadsActivity::class.java.getDeclaredField("folderUrl").apply { isAccessible = true }.set(activity,url)
            DownloadsActivity::class.java.getDeclaredMethod("render").apply { isAccessible = true }.invoke(activity)
            val tile = all(activity.window.decorView).filterIsInstance<TextView>().first { it.contentDescription?.toString()?.startsWith("Episode 1") == true }
            val progress = DownloadProgress().apply { percentDownloaded = 12f }
            val request = DownloadRequest.Builder(metadata.id,android.net.Uri.parse("https://media.example/review.mp4")).build()
            val download = Download(request,Download.STATE_DOWNLOADING,1,1,100,0,0,progress)
            val update = DownloadsActivity::class.java.getDeclaredMethod("updateTiles",Map::class.java).apply { isAccessible = true }
            update.invoke(activity,mapOf(metadata.id to download));assertEquals("1\n12%",tile.text.toString())
            progress.percentDownloaded = 63f;update.invoke(activity,mapOf(metadata.id to download))
            assertEquals("1\n63%",tile.text.toString());assertTrue(tile.contentDescription.toString().contains("63%"))
        } finally { c.destroy() }
    }
    @Test fun invalidPosterCacheRecoversAndUsesAnIntentionalPlaceholder() {
        val file = SeriesArtwork.file(context,url);file.parentFile!!.mkdirs();file.writeBytes(byteArrayOf(1,2,3))
        context.getSharedPreferences("series_artwork",0).edit().putString("poster-source:$url","https://media.example/poster.jpg").commit()
        assertTrue(SeriesArtwork.hasPoster(context,url));assertNull(SeriesArtwork.bitmap(context,url));assertFalse(SeriesArtwork.hasPoster(context,url))
        val view = context.poster(url,"Story")
        assertNotNull(view.drawable);assertEquals(ImageView.ScaleType.FIT_CENTER,view.scaleType)
    }
    @Test fun posterArrivalUpdatesTheSameCardWithoutRebuildingItsTouchTarget() {
        val card = context.seriesCard(url,"Story","Saved series","EP.2 · 0:24 / 2:00")
        val image = all(card).filterIsInstance<ImageView>().single()
        val file = SeriesArtwork.file(context,url);file.parentFile!!.mkdirs()
        val bitmap = Bitmap.createBitmap(60,90,Bitmap.Config.ARGB_8888);bitmap.eraseColor(0xff7b6dcc.toInt())
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG,85,it) };bitmap.recycle()
        context.getSharedPreferences("series_artwork",0).edit().putString("poster-source:$url","https://media.example/review-ready.jpg").commit()
        card.refreshPosters()
        assertSame(image,all(card).filterIsInstance<ImageView>().single())
        assertEquals(ImageView.ScaleType.CENTER_CROP,image.scaleType)
        assertEquals(0,image.paddingLeft)
        file.delete();context.getSharedPreferences("series_artwork",0).edit().remove("poster-source:$url").commit()
    }

    @Test fun qualitySheetHighlightsTheEffectiveSupportedQualityAndRetainsItsCompactHeight() {
        val c = Robolectric.buildActivity(Activity::class.java).setup()
        val player = androidx.media3.exoplayer.ExoPlayer.Builder(c.get()).build()
        val medium = androidx.media3.common.Format.Builder().setSampleMimeType("video/avc").setWidth(720).setHeight(1280).build()
        val small = medium.buildUpon().setWidth(540).setHeight(960).build()
        val group = androidx.media3.common.Tracks.Group(androidx.media3.common.TrackGroup("review",medium,small),true,
            intArrayOf(androidx.media3.common.C.FORMAT_HANDLED,androidx.media3.common.C.FORMAT_HANDLED),booleanArrayOf(true,false))
        val proxy = java.lang.reflect.Proxy.newProxyInstance(androidx.media3.exoplayer.ExoPlayer::class.java.classLoader,arrayOf(androidx.media3.exoplayer.ExoPlayer::class.java)) { _,method,args ->
            if (method.name == "getCurrentTracks") androidx.media3.common.Tracks(listOf(group)) else method.invoke(player,*(args ?: emptyArray()))
        } as androidx.media3.exoplayer.ExoPlayer
        val dialog = qualitySheet(c.get(),proxy,1080) {}
        try {
            assertTrue(all(dialog.window!!.decorView).any { it.contentDescription == "720P, selected" })
            assertFalse(all(dialog.window!!.decorView).any { it.contentDescription == "Auto, selected" })
            val height = dialog.window!!.attributes.height
            (dialog as PlayerSheetDialog).fitWindow()
            assertEquals(height,dialog.window!!.attributes.height)
        } finally { dialog.dismiss();player.release();c.destroy() }
    }

}
