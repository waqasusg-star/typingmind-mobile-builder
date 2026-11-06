package com.waqas.hdrama

import android.app.AlertDialog
import android.content.Context
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowAlertDialog

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class HistoryActivityTest {
    private val context: Context get() = RuntimeEnvironment.getApplication()
    private val url = "https://en.hdrama.net/series/recent-story"
    private fun all(v: View): List<View> = listOf(v) + if (v is ViewGroup) (0 until v.childCount).flatMap { all(v.getChildAt(it)) } else emptyList()
    @Before fun clear() {
        context.getSharedPreferences("drama_library",0).edit().clear().commit()
        context.getSharedPreferences("playback",0).edit().clear().commit()
    }
    @Test fun cardShowsPosterTitleEpisodeAndTimingAndLaunchesResume() {
        DramaLibrary(context).saveProgress(url,"Recent Story",7,31_000,120_000)
        val c = Robolectric.buildActivity(HistoryActivity::class.java).create().start().resume()
        try {
            val views = all(c.get().window.decorView)
            assertTrue(views.any { it.contentDescription == "Recent Story poster" })
            assertTrue(views.filterIsInstance<TextView>().any { it.text == "EP.7 · 0:31 / 2:00" })
            views.first { it.contentDescription == "Continue watching: Recent Story" }.performClick()
            val intent = shadowOf(c.get()).nextStartedActivity
            assertEquals(PlayerActivity::class.java.name,intent.component?.className)
            assertEquals(url,intent.getStringExtra("series")); assertFalse(intent.hasExtra("episode"))
        } finally { c.pause().stop().destroy() }
    }
    @Test fun holdAndClearRequireConfirmationAndOnlyRemoveSelectedHistory() {
        val library = DramaLibrary(context)
        library.saveProgress(url,"Recent Story",7,31_000,120_000)
        val second = url.replace("recent-story","another"); library.saveProgress(second,"Other",2,12_000,90_000)
        val c = Robolectric.buildActivity(HistoryActivity::class.java).create().start().resume()
        try {
            all(c.get().window.decorView).first { it.contentDescription == "Continue watching: Recent Story" }.performLongClick()
            val dialog = ShadowAlertDialog.getLatestAlertDialog()
            assertEquals(2,library.history().size)
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).performClick(); shadowOf(android.os.Looper.getMainLooper()).idle()
            assertEquals(listOf(second),library.history().map { it.url })
            assertEquals(31_000L,library.episodePosition(url,7))
            all(c.get().window.decorView).first { it.contentDescription == "Clear history" }.performClick()
            assertEquals(1,library.history().size)
            ShadowAlertDialog.getLatestAlertDialog().getButton(AlertDialog.BUTTON_POSITIVE).performClick(); shadowOf(android.os.Looper.getMainLooper()).idle()
            assertTrue(library.history().isEmpty())
        } finally { c.pause().stop().destroy() }
    }
}
