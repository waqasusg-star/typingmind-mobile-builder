package com.waqas.hdrama

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Rect
import android.view.*
import android.widget.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class PlayerChromeTest {
    private fun chrome(toggle: () -> Unit = {}): PlayerChrome {
        val context = ContextThemeWrapper(RuntimeEnvironment.getApplication(),R.style.AppTheme)
        return PlayerChrome(context,PlayerChrome.Actions(back = {},episodes = {},speed = {},rotate = {},fit = {},toggle = toggle,retry = {},access = {}))
    }
    private fun layout(view: View,w: Int,h: Int) {
        repeat(2) {
            view.measure(View.MeasureSpec.makeMeasureSpec(w,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(h,View.MeasureSpec.EXACTLY))
            view.layout(0,0,w,h)
        }
    }
    private fun all(view: View): List<View> = listOf(view) + if (view is android.view.ViewGroup)
        (0 until view.childCount).flatMap { all(view.getChildAt(it)) } else emptyList()
    @Test fun noScrollingToolbarNextPreviousOrMoreButtons() {
        val chrome = chrome();layout(chrome,360,800)
        assertTrue(all(chrome).none { it is HorizontalScrollView || it is ScrollView })
        assertTrue(all(chrome).none { it.contentDescription?.toString() in listOf("Previous","Next","More") })
        assertTrue(all(chrome).none { it is Button })
    }
    @Test fun sideControlsRemainVisibleAndInsideCompactPortraitAndLandscape() {
        for ((w,h) in listOf(360 to 800,640 to 360,320 to 568,568 to 320)) {
            val chrome = chrome();chrome.heading.text = "Caged by His Twisted Love";chrome.setEpisode(2,76)
            layout(chrome,w,h)
            for (description in listOf("Favorite","My List","Episodes","Download","Quality","Player options","Playback speed","Pause video")) {
                val view = all(chrome).first { it.contentDescription?.toString() == description }
                val rect = Rect();view.getDrawingRect(rect);chrome.offsetDescendantRectToMyCoords(view,rect)
                assertTrue("$description outside $w x $h: $rect",rect.left >= 0 && rect.top >= 0 && rect.right <= w && rect.bottom <= h)
            }
        }
    }
    @Test fun errorCardDoesNotCoverSideActionsOnSmallScreens() {
        for ((w,h) in listOf(320 to 568,568 to 320)) {
            val chrome = chrome()
            chrome.showStatus("Could not open this episode. Retry to refresh the source.",retryVisible = true)
            layout(chrome,w,h)
            val panel = chrome.status.parent as View
            val errorRect = Rect();panel.getDrawingRect(errorRect);chrome.offsetDescendantRectToMyCoords(panel,errorRect)
            for (v in listOf(chrome.favoriteControl,chrome.myListControl)) {
                val r = Rect();v.getDrawingRect(r);chrome.offsetDescendantRectToMyCoords(v,r)
                assertFalse("Error $errorRect obscures $r at $w x $h",Rect.intersects(errorRect,r))
            }
        }
    }
    @Test fun raisedTimelineClearsHomeGestureAreaAndSideControls() {
        for ((w,h) in listOf(360 to 800,640 to 360,320 to 568,568 to 320)) {
            val chrome = chrome();chrome.applyInsets(0,0,0,24);layout(chrome,w,h)
            val rect = Rect();chrome.seek.getDrawingRect(rect);chrome.offsetDescendantRectToMyCoords(chrome.seek,rect)
            assertTrue("Seekbar too close to home gesture: $rect",h - rect.bottom >= 24 + 24)
            assertTrue(rect.left >= 0 && rect.right <= w && rect.top >= 0)
            for (description in listOf("Favorite","My List","Player options")) {
                val action = all(chrome).first { it.contentDescription?.toString() == description }
                val r = Rect();action.getDrawingRect(r);chrome.offsetDescendantRectToMyCoords(action,r)
                assertFalse("Timeline overlaps $description: $rect, $r",Rect.intersects(rect,r))
            }
        }
    }
    @Test fun navigationAndErrorActionsHaveCorrectEnabledAndVisibleStates() {
        var calls = 0;val chrome = chrome { calls++ }
        chrome.setPlayback(true,true);chrome.playPause.performClick();assertEquals(1,calls)
        chrome.setPlayback(false,false);assertFalse(chrome.playPause.isEnabled)
        assertEquals("Play video",chrome.playPause.contentDescription)
        chrome.showStatus("Retry",retryVisible = true);assertEquals(View.VISIBLE,chrome.retry.visibility);assertEquals(View.GONE,chrome.access.visibility)
        chrome.showStatus("Access",accessVisible = true);assertEquals(View.GONE,chrome.retry.visibility);assertEquals(View.VISIBLE,chrome.access.visibility)
    }
    @Test fun episodeBarIsBelowSeekAndRemovedControlsAreAbsent() {
        val c = chrome(); layout(c,360,800)
        val seek = Rect(); c.seek.getDrawingRect(seek); c.offsetDescendantRectToMyCoords(c.seek,seek)
        val episode = Rect(); c.episode.getDrawingRect(episode); c.offsetDescendantRectToMyCoords(c.episode,episode)
        assertTrue(episode.top >= seek.bottom)
        assertTrue(all(c).none { it.contentDescription in listOf("Fullscreen","Auto next","PiP","Rotate","Fit / Fill") })
        c.setFavorite(true)
        assertEquals(0xffff304f.toInt(),(c.favoriteControl.getChildAt(0) as ImageButton).imageTintList!!.defaultColor)
    }
    @Test fun singleColumnOrdersFavoriteListDownloadQualityAndOmitsDownloadsShortcut() {
        val c = chrome(); layout(c,360,800)
        val rail = c.favoriteControl.parent as GridLayout
        assertEquals(1,rail.columnCount)
        assertEquals(listOf("Favorite","My List","Download","Quality","Playback speed"),(0 until rail.childCount).map { rail.getChildAt(it).contentDescription.toString() })
        assertTrue(all(c).none { it.contentDescription == "Downloads" })
    }
    @Test fun chromeHasNoBackButtonOrThumbnailOverlay() {
        val c = chrome(); layout(c,360,800)
        assertTrue(all(c).none { it.contentDescription == "Back" })
        assertTrue(all(c).filterIsInstance<TextView>().none { it.text.toString().contains("preview",ignoreCase = true) })
    }
    @Test fun nativePortraitAndLandscapeRenderWithoutClipping() {
        val destination = System.getenv("HDRAMA_UI_PREVIEW_DIR") ?: return
        for ((w,h) in listOf(360 to 800,640 to 360,320 to 568,568 to 320)) {
            val chrome = chrome();chrome.heading.text = "Caged by His Twisted Love";chrome.setEpisode(2,76)
            chrome.position.text = "0:24 / 1:00";chrome.remaining.text = "−0:36";chrome.seek.progress = 4000;chrome.seek.secondaryProgress = 6500
            layout(chrome,w,h)
            val bitmap = Bitmap.createBitmap(w,h,Bitmap.Config.ARGB_8888);val canvas = Canvas(bitmap)
            canvas.drawColor(0xff262332.toInt());chrome.draw(canvas)
            File(destination).mkdirs();File(destination,"player-${w}x$h.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG,100,it) };bitmap.recycle()
        }
    }
    @Test fun topTitleAndEpisodeCountUseBoldOnlyForRunningEpisode() {
        val c = chrome(); c.heading.text = "Story"; c.setEpisode(7,40); layout(c,360,800)
        assertEquals("EP7 / EP40",c.runningEpisode.text.toString())
        val text = c.runningEpisode.text as android.text.Spanned
        val span = text.getSpans(0,text.length,android.text.style.StyleSpan::class.java).single()
        assertEquals(android.graphics.Typeface.BOLD,span.style)
        assertEquals(0,text.getSpanStart(span));assertEquals(3,text.getSpanEnd(span))
        val title = Rect();c.heading.getDrawingRect(title);c.offsetDescendantRectToMyCoords(c.heading,title)
        val ep = Rect();c.runningEpisode.getDrawingRect(ep);c.offsetDescendantRectToMyCoords(c.runningEpisode,ep)
        assertTrue(title.top < ep.top);assertTrue(ep.bottom < 88)
    }

}
