package com.waqas.hdrama

import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.*
import android.webkit.WebView
import android.widget.*
import androidx.core.graphics.Insets
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import org.robolectric.shadows.ShadowAlertDialog
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class BrowserScreenTest {
    private fun all(v: View): List<View> = listOf(v) + if (v is ViewGroup) (0 until v.childCount).flatMap { all(v.getChildAt(it)) } else emptyList()
    @Test fun browserHasFullHeightWebViewAndCompactPlayAndMyListOverlays() {
        val c = Robolectric.buildActivity(MainActivity::class.java).create()
        try {
            val views = all(c.get().window.decorView)
            val web = views.filterIsInstance<WebView>().single()
            assertEquals(ViewGroup.LayoutParams.MATCH_PARENT,web.layoutParams.width)
            assertEquals(ViewGroup.LayoutParams.MATCH_PARENT,web.layoutParams.height)
            assertTrue(views.none { it is EditText || it is Button })
            assertEquals(4,views.filterIsInstance<ImageButton>().size)
            assertEquals(View.VISIBLE,views.first { it.contentDescription == "Downloads" }.visibility)
            assertEquals(View.VISIBLE,views.first { it.contentDescription == "My List" }.visibility)
            assertNull(ShadowAlertDialog.getLatestAlertDialog())
        } finally { c.destroy() }
    }
    @Test @Config(sdk = [29]) fun browserButtonsClearWebsiteMenuAndHomeGestureArea() {
        val c = Robolectric.buildActivity(MainActivity::class.java).create().start().visible()
        try {
            val views = all(c.get().window.decorView)
            val web = views.filterIsInstance<WebView>().single()
            val root = web.parent as View
            val insets = WindowInsetsCompat.Builder().setInsets(WindowInsetsCompat.Type.mandatorySystemGestures(),Insets.of(0,0,0,24)).build()
            ViewCompat.dispatchApplyWindowInsets(root,insets)
            for (button in views.filterIsInstance<ImageButton>()) {
                val row = button.parent.parent as LinearLayout
                val params = row.layoutParams as FrameLayout.LayoutParams
                assertTrue("Button covers the website menu",params.bottomMargin == c.get().dp(60) + 24)
            }
            assertEquals(ViewGroup.LayoutParams.MATCH_PARENT,web.layoutParams.height)
        } finally { c.destroy() }
    }
    @Test fun browserActionsShareOneRowWithLargerSquareTargets() {
        val c = Robolectric.buildActivity(MainActivity::class.java).create()
        try {
            val buttons = all(c.get().window.decorView).filterIsInstance<ImageButton>()
            val row = buttons.first().parent.parent as LinearLayout
            assertTrue(buttons.all { it.parent.parent === row })
            assertEquals(LinearLayout.HORIZONTAL,row.orientation)
            assertEquals(listOf("My List","Downloads","History","Play in native player"),(0 until row.childCount).map { ((row.getChildAt(it) as LinearLayout).getChildAt(0) as ImageButton).contentDescription.toString() })
            assertTrue(buttons.all { it.layoutParams.width == c.get().dp(64) && it.layoutParams.height == c.get().dp(64) })
        } finally { c.destroy() }
    }
    @Test fun seriesShowsIconWithoutDialogAndIconLaunchesCorrectNativeEpisode() {
        val c = Robolectric.buildActivity(MainActivity::class.java).create()
        try {
            val activity = c.get();val web = all(activity.window.decorView).filterIsInstance<WebView>().single()
            val url = "https://en.hdrama.net/series/story/episode-2";web.loadUrl(url)
            val html = "<h1>Story Episode 2</h1><a href='/series/story/episode-1'>1</a><a href='/series/story/episode-2'>2</a>"
            val data = JSONObject().put("url",url).put("html",html).put("blocked",false)
            MainActivity::class.java.getDeclaredMethod("acceptSnapshot",JSONObject::class.java).apply { isAccessible = true }.invoke(activity,data)
            assertNull(ShadowAlertDialog.getLatestAlertDialog())
            val icon = all(activity.window.decorView).filterIsInstance<ImageButton>().single { it.contentDescription?.toString()?.endsWith("in native player") == true }
            assertEquals(View.VISIBLE,icon.visibility);icon.performClick()
            val intent = shadowOf(activity).nextStartedActivity
            assertEquals(PlayerActivity::class.java.name,intent.component?.className)
            assertEquals(2,intent.getIntExtra("episode",0))
        } finally { c.destroy() }
    }
    @Test fun appIsNamedHDramaAndAdaptiveIconRenders() {
        val app = org.robolectric.RuntimeEnvironment.getApplication()
        assertEquals("HDrama",app.applicationInfo.loadLabel(app.packageManager))
        val path = System.getenv("HDRAMA_UI_PREVIEW_DIR") ?: return
        val icon = app.applicationInfo.loadIcon(app.packageManager)
        val bitmap = Bitmap.createBitmap(192,192,Bitmap.Config.ARGB_8888);icon.setBounds(0,0,192,192);icon.draw(Canvas(bitmap))
        File(path).mkdirs();File(path,"hdrama-icon.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG,100,it) };bitmap.recycle()
    }
    @Test fun dockTracksMeasuredFooterAndHistoryButtonOpensNativeHistory() {
        val c = Robolectric.buildActivity(MainActivity::class.java).create()
        try {
            val activity = c.get(); val views = all(activity.window.decorView)
            val web = views.filterIsInstance<WebView>().single()
            val url = SitePolicy.HOME; web.loadUrl(url)
            val root = web.parent as View
            root.measure(View.MeasureSpec.makeMeasureSpec(360,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(800,View.MeasureSpec.EXACTLY));root.layout(0,0,360,800)
            // Robolectric has no WebView layout provider; set its viewport after laying out native children.
            web.bottom = 800; web.right = 360; assertEquals(800,web.height)
            MainActivity::class.java.getDeclaredMethod("acceptSnapshot",JSONObject::class.java).apply { isAccessible = true }
                .invoke(activity,JSONObject().put("url",url).put("html","").put("footerHeight",72).put("viewportHeight",800))
            val history = views.first { it.contentDescription == "History" }
            val row = history.parent.parent as LinearLayout
            assertEquals(72 + activity.dp(4),(row.layoutParams as FrameLayout.LayoutParams).bottomMargin)
            val play = views.filterIsInstance<ImageButton>().first { it.contentDescription == "Play in native player" }
            assertEquals(View.GONE,(play.parent as View).visibility)
            history.performClick()
            assertEquals(HistoryActivity::class.java.name,shadowOf(activity).nextStartedActivity.component?.className)
        } finally { c.destroy() }
    }

    @Test @Config(sdk = [31]) fun keyboardHidesDockAndDismissalRestoresItsNormalFooterPosition() {
        val c = Robolectric.buildActivity(MainActivity::class.java).create().start().visible()
        try {
            val activity = c.get(); val views = all(activity.window.decorView)
            val web = views.filterIsInstance<WebView>().single(); val root = web.parent as View
            val row = views.first { it.contentDescription == "History" }.parent.parent as LinearLayout
            val keyboard = WindowInsetsCompat.Builder()
                .setInsets(WindowInsetsCompat.Type.ime(),Insets.of(0,0,0,300))
                .setVisible(WindowInsetsCompat.Type.ime(),true).build()
            ViewCompat.dispatchApplyWindowInsets(root,keyboard)
            assertEquals(View.GONE,row.visibility)
            val drag = MotionEvent.obtain(0,0,MotionEvent.ACTION_DOWN,20f,20f,0)
            assertFalse((root as PullRefreshLayout).canRefresh(drag));drag.recycle()
            web.bottom = 500
            MainActivity::class.java.getDeclaredMethod("acceptSnapshot",JSONObject::class.java).apply { isAccessible = true }
                .invoke(activity,JSONObject().put("url",SitePolicy.HOME).put("viewportHeight",500).put("footerHeight",96))
            assertEquals(View.GONE,row.visibility)
            val normal = WindowInsetsCompat.Builder().setInsets(WindowInsetsCompat.Type.mandatorySystemGestures(),Insets.of(0,0,0,24))
                .setInsets(WindowInsetsCompat.Type.ime(),Insets.NONE).setVisible(WindowInsetsCompat.Type.ime(),false).build()
            ViewCompat.dispatchApplyWindowInsets(root,normal)
            assertEquals(View.VISIBLE,row.visibility)
            assertEquals(activity.dp(60)+24,(row.layoutParams as FrameLayout.LayoutParams).bottomMargin)
        } finally { c.destroy() }
    }

    @Test fun oldPageSnapshotCannotResurrectPlayAfterNavigatingAway() {
        val c = Robolectric.buildActivity(MainActivity::class.java).create()
        try {
            val activity = c.get();val web = all(activity.window.decorView).filterIsInstance<WebView>().single()
            val url = SitePolicy.HOME.removeSuffix("/") + "/series/review-story/episode-1"; web.loadUrl(url)
            val inspect = MainActivity::class.java.getDeclaredMethod("acceptSnapshot",JSONObject::class.java).apply { isAccessible = true }
            val old = JSONObject().put("url",url).put("html","<h1>Review Story</h1><a href='/series/review-story/episode-1'>1</a>")
            inspect.invoke(activity,old)
            web.loadUrl(SitePolicy.HOME)
            shadowOf(web).webViewClient.onPageStarted(web,SitePolicy.HOME,null)
            inspect.invoke(activity,old)
            val play = all(activity.window.decorView).filterIsInstance<ImageButton>().first { it.contentDescription?.toString()?.endsWith("in native player") == true }
            assertEquals(View.GONE,play.visibility)
        } finally { c.destroy() }
    }
    @Test fun cancelledInspectionCannotClearANewerInspectionInFlight() {
        val c = Robolectric.buildActivity(MainActivity::class.java).create()
        try {
            val activity = c.get();val web = all(activity.window.decorView).filterIsInstance<WebView>().single()
            MainActivity::class.java.getDeclaredField("active").apply { isAccessible = true }.setBoolean(activity,true)
            val inspect = MainActivity::class.java.getDeclaredMethod("inspectPage").apply { isAccessible = true }
            inspect.invoke(activity)
            val old = shadowOf(web).lastEvaluatedJavascriptCallback
            val url = SitePolicy.HOME.removeSuffix("/") + "/series/review-new/episode-1";web.loadUrl(url)
            shadowOf(web).webViewClient.onPageStarted(web,url,null)
            inspect.invoke(activity)
            old.onReceiveValue(JSONObject.quote(JSONObject().put("url",SitePolicy.HOME).put("html","").toString()))
            assertTrue(MainActivity::class.java.getDeclaredField("inspecting").apply { isAccessible = true }.getBoolean(activity))
        } finally { c.destroy() }
    }

}
