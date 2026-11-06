package com.waqas.hdrama

import android.content.Intent
import android.os.Looper
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import androidx.media3.ui.AspectRatioFrameLayout
import android.graphics.Rect
import android.os.Bundle
import android.view.WindowManager
import org.robolectric.shadows.ShadowAlertDialog
import org.junit.Assert.*
import org.junit.Test
import org.junit.Before
import org.robolectric.RuntimeEnvironment
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.time.Duration
import java.lang.reflect.Proxy

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@androidx.annotation.OptIn(markerClass = [UnstableApi::class])
class PlayerTapTest {
    @Before fun clearProgress() {
        val app: android.app.Application = RuntimeEnvironment.getApplication()
        shadowOf(app).grantPermissions("${app.packageName}.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION")
        RuntimeEnvironment.getApplication().getSharedPreferences("drama_library",0).edit().clear().commit()
        RuntimeEnvironment.getApplication().getSharedPreferences("playback",0).edit().clear().commit()
    }
    private fun all(v: View): List<View> = listOf(v) + if (v is ViewGroup) (0 until v.childCount).flatMap { all(v.getChildAt(it)) } else emptyList()
    private fun fixture(test: (PlayerView,ExoPlayer,PlayerChrome,PlayerActivity) -> Unit) {
        val url = "https://en.hdrama.net/series/story"
        PlaybackHandoff.offer(Series("Story",url,listOf(Episode(1,"$url/episode-1"),Episode(2,"$url/episode-2"),Episode(3,"$url/episode-3"))))
        val controller = Robolectric.buildActivity(PlayerActivity::class.java,Intent().putExtra("series",url)).create()
        val activity = controller.get()
        val player = ExoPlayer.Builder(activity).build()
        try {
            // A queued item tests real tap state changes without fetching any video.
            player.setMediaItem(MediaItem.fromUri("https://media.example/test.mp4"));player.playWhenReady = true
            PlayerActivity::class.java.getDeclaredField("player").apply { isAccessible = true }.set(activity,player)
            val video = all(activity.window.decorView).filterIsInstance<PlayerView>().single()
            val chrome = all(activity.window.decorView).filterIsInstance<PlayerChrome>().single()
            val root = video.parent as View
            root.measure(View.MeasureSpec.makeMeasureSpec(360,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(800,View.MeasureSpec.EXACTLY));root.layout(0,0,360,800)
            chrome.setPlayback(true,true)
            test(video,player,chrome,activity)
        } finally { player.release();controller.destroy() }
    }
    // Make seeking available even though this queued test item has no network source.
    // Delegate seeking to the real ExoPlayer so the previous seek gestures would fail these assertions.
    private fun seekableVideo(activity: PlayerActivity, delegate: ExoPlayer) {
        val proxy = Proxy.newProxyInstance(ExoPlayer::class.java.classLoader,arrayOf(ExoPlayer::class.java)) { _,method,args ->
            when (method.name) {
                "getDuration" -> 120_000L
                "isCurrentMediaItemSeekable" -> true
                else -> method.invoke(delegate,*(args ?: emptyArray()))
            }
        } as ExoPlayer
        PlayerActivity::class.java.getDeclaredField("player").apply { isAccessible = true }.set(activity,proxy)
    }
    private fun tap(video: PlayerView) {
        val now = SystemClock.uptimeMillis()
        for (action in listOf(MotionEvent.ACTION_DOWN,MotionEvent.ACTION_UP)) {
            val e = MotionEvent.obtain(now,now + if (action == MotionEvent.ACTION_UP) 20 else 0,action,100f,100f,0)
            video.dispatchTouchEvent(e);e.recycle()
        }
    }
    @Test fun allScreenTapsToggleControlsWithoutChangingPlayback() = fixture { video,player,chrome,_ ->
        chrome.showControls(false)
        tap(video);shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(400));assertTrue(player.playWhenReady);assertTrue(chrome.controlsVisible)
        tap(video);shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(400));assertTrue(player.playWhenReady);assertFalse(chrome.controlsVisible)
        tap(video);shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(400));assertTrue(player.playWhenReady);assertTrue(chrome.controlsVisible)
    }
    @Test fun centralControlPausesAndResumesDirectly() = fixture { _,player,chrome,_ ->
        chrome.playPause.performClick();assertFalse(player.playWhenReady)
        chrome.playPause.performClick();assertTrue(player.playWhenReady)
    }
    @Test fun verticalSwipeSelectsOneEpisodeWithoutPauseTap() = fixture { video,player,_,activity ->
        PlayerActivity::class.java.getDeclaredField("started").apply { isAccessible = true }.set(activity,true)
        val now = SystemClock.uptimeMillis()
        for ((action,y,offset) in listOf(Triple(MotionEvent.ACTION_DOWN,600f,0L),Triple(MotionEvent.ACTION_MOVE,400f,100L),Triple(MotionEvent.ACTION_MOVE,250f,160L),Triple(MotionEvent.ACTION_UP,200f,200L))) {
            val e = MotionEvent.obtain(now,now+offset,action,100f,y,0);video.dispatchTouchEvent(e);e.recycle()
        }
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(400))
        assertEquals(1,PlayerActivity::class.java.getDeclaredField("index").apply { isAccessible = true }.getInt(activity))
        assertTrue(player.playWhenReady)
    }
    @Test fun doubleTapDoesNotSeekOrPause() = fixture { video,player,_,activity ->
        seekableVideo(activity,player)
        player.seekTo(24_000)
        tap(video);shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(60));tap(video)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(400));assertTrue(player.playWhenReady);assertEquals(24_000L,player.currentPosition)
    }
    @Test fun horizontalDragsPreviewAndCommitWithoutChangingEpisodeOrPlayback() = fixture { video,player,chrome,activity ->
        seekableVideo(activity,player)
        for (direction in listOf(1f,-1f)) {
            player.seekTo(24_000); chrome.showControls(false)
            val now = SystemClock.uptimeMillis()
            for ((action,x,offset) in listOf(Triple(MotionEvent.ACTION_DOWN,180f,0L),Triple(MotionEvent.ACTION_MOVE,180f + direction * 90f,100L),Triple(MotionEvent.ACTION_UP,180f + direction * 120f,200L))) {
                val e = MotionEvent.obtain(now,now+offset,action,x,300f,0);video.dispatchTouchEvent(e);e.recycle()
                if (action == MotionEvent.ACTION_MOVE) {
                    assertFalse(player.playWhenReady)
                    assertTrue(PlayerActivity::class.java.getDeclaredField("scrubbing").apply { isAccessible = true }.getBoolean(activity))
                }
            }
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(400))
            val expected = ScreenSeek.target(24_000,direction * 120f,video.width,120_000)
            assertEquals(expected,player.currentPosition);assertTrue(player.playWhenReady)
            assertEquals(0,PlayerActivity::class.java.getDeclaredField("index").apply { isAccessible = true }.getInt(activity))
        }
    }
    @Test fun cancelledHorizontalPreviewRestoresOriginalPausedPosition() = fixture { video,player,_,activity ->
        seekableVideo(activity,player); player.seekTo(24_000); player.pause()
        val now = SystemClock.uptimeMillis()
        for ((action,x,offset) in listOf(Triple(MotionEvent.ACTION_DOWN,180f,0L),Triple(MotionEvent.ACTION_MOVE,280f,100L),Triple(MotionEvent.ACTION_CANCEL,300f,200L))) {
            val e = MotionEvent.obtain(now,now+offset,action,x,300f,0);video.dispatchTouchEvent(e);e.recycle()
        }
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(400))
        assertEquals(24_000L,player.currentPosition);assertFalse(player.playWhenReady)
    }
    @Test fun accessibleScreenClickOnlyTogglesVisibility() = fixture { video,player,chrome,_ ->
        video.performClick();assertTrue(player.playWhenReady);assertFalse(chrome.controlsVisible)
        video.performClick();assertTrue(player.playWhenReady);assertTrue(chrome.controlsVisible)
        chrome.playPause.performClick();assertFalse(player.playWhenReady)
        video.performClick();assertFalse(player.playWhenReady);assertFalse(chrome.controlsVisible)
        video.performClick();assertFalse(player.playWhenReady);assertTrue(chrome.controlsVisible)
    }
    @Test fun holdUsesOnePointFiveWithoutControlsAndReleaseRestoresSpeed() = fixture { video,player,chrome,activity ->
        PlayerActivity::class.java.getDeclaredField("baseSpeed").apply { isAccessible = true }.setFloat(activity,1.25f)
        player.setPlaybackSpeed(1.25f)
        for (initialVisibility in listOf(true,false)) {
            chrome.showControls(initialVisibility)
            val now = SystemClock.uptimeMillis()
            val down = MotionEvent.obtain(now,now,MotionEvent.ACTION_DOWN,100f,100f,0)
            video.dispatchTouchEvent(down);down.recycle()
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(700))
            assertEquals(1.5f,player.playbackParameters.speed,0f);assertFalse(chrome.controlsVisible)
            assertTrue(player.playWhenReady)
            assertTrue(all(chrome).none { it is android.widget.TextView && it.visibility == View.VISIBLE && it.text == "1.5×" })
            val up = MotionEvent.obtain(now,SystemClock.uptimeMillis(),MotionEvent.ACTION_UP,100f,100f,0)
            video.dispatchTouchEvent(up);up.recycle()
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(400))
            assertEquals(1.25f,player.playbackParameters.speed,0f);assertFalse(chrome.controlsVisible)
            assertTrue(player.playWhenReady)
        }
    }
    @Test fun checkpointSavesFavoriteEpisodeAndExactPosition() = fixture { _,player,chrome,activity ->
        player.seekTo(24_000)
        chrome.favoriteControl.performClick()
        val saved = DramaLibrary(activity).favorites().single()
        assertEquals("Story",saved.title);assertEquals(1,saved.episode);assertEquals(24_000L,saved.position)
        chrome.favoriteControl.performClick();assertTrue(DramaLibrary(activity).favorites().isEmpty())
        assertEquals(24_000L,DramaLibrary(activity).get(saved.url)?.position)
    }
    @Test fun reopeningSavedDramaRestoresItsEpisodeAndPosition() {
        val app = RuntimeEnvironment.getApplication()
        val url = "https://en.hdrama.net/series/resume"
        val library = DramaLibrary(app)
        library.saveProgress(url,"Resume",3,37_500);library.toggleFavorite(url,"Resume")
        for (explicit in listOf(0,3,2)) {
            PlaybackHandoff.offer(Series("Resume",url,(1..3).map { Episode(it,"$url/episode-$it") }))
            val c = Robolectric.buildActivity(PlayerActivity::class.java,Intent().putExtra("series",url).putExtra("episode",explicit)).create()
            try {
                val activity = c.get()
                assertEquals(if (explicit == 2) 1 else 2,PlayerActivity::class.java.getDeclaredField("index").apply { isAccessible = true }.getInt(activity))
                assertEquals(if (explicit == 2) 0L else 37_500L,PlayerActivity::class.java.getDeclaredField("position").apply { isAccessible = true }.getLong(activity))
            } finally { c.destroy() }
        }
    }    @Test fun heldHeartRemovesFavoriteWithoutLosingPositionOrStartingHoldSpeed() = fixture { _,player,chrome,activity ->
        player.seekTo(19_000);chrome.favoriteControl.performClick()
        assertEquals(1,DramaLibrary(activity).favorites().size)
        assertTrue(chrome.favoriteControl.getChildAt(0).performLongClick())
        assertTrue(DramaLibrary(activity).favorites().isEmpty())
        assertEquals(19_000L,DramaLibrary(activity).get("https://en.hdrama.net/series/story")?.position)
        assertEquals(1f,player.playbackParameters.speed,0f)
        chrome.favoriteControl.performLongClick();assertTrue(DramaLibrary(activity).favorites().isEmpty())
    }
    @Test fun removingFromPlayerListUpdatesTheVisibleHeart() = fixture { _,_,chrome,activity ->
        chrome.favoriteControl.performClick();chrome.myListControl.performClick()
        val dialog = ShadowAlertDialog.getLatestAlertDialog();val list = dialog.listView
        list.onItemLongClickListener.onItemLongClick(list,list.adapter.getView(0,null,list),0,list.adapter.getItemId(0))
        assertEquals("Add to favorites",chrome.favoriteControl.getChildAt(0).contentDescription)
        assertTrue(DramaLibrary(activity).favorites().isEmpty())
    }
    @Test fun playerKeepsWholeFrameAndStatusBarFollowsControls() = fixture { video,_,_,activity ->
        assertEquals(AspectRatioFrameLayout.RESIZE_MODE_FIT,video.resizeMode)
        assertEquals(0,activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_FULLSCREEN)
        val frame = video.findViewById<AspectRatioFrameLayout>(androidx.media3.ui.R.id.exo_content_frame)
        frame.setAspectRatio(9f / 16f)
        val root = video.parent as View
        root.measure(View.MeasureSpec.makeMeasureSpec(360,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(800,View.MeasureSpec.EXACTLY));root.layout(0,0,360,800)
        val bounds = Rect();frame.getDrawingRect(bounds);(root as ViewGroup).offsetDescendantRectToMyCoords(frame,bounds)
        assertTrue("Fit crops the frame: $bounds",bounds.left >= 0 && bounds.top >= 0 && bounds.right <= 360 && bounds.bottom <= 800)
        val show = PlayerActivity::class.java.getDeclaredMethod("showControls",Boolean::class.javaPrimitiveType).apply { isAccessible = true }
        show.invoke(activity,false)
        assertTrue(activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_FULLSCREEN != 0)
        activity.onWindowFocusChanged(true)
        assertTrue(activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_FULLSCREEN != 0)
        assertEquals(0,activity.window.decorView.systemUiVisibility and View.SYSTEM_UI_FLAG_HIDE_NAVIGATION)
        assertEquals(0,activity.window.decorView.systemUiVisibility and View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY)
        val insets = androidx.core.view.WindowInsetsCompat.Builder().setInsets(androidx.core.view.WindowInsetsCompat.Type.navigationBars(),androidx.core.graphics.Insets.of(0,0,0,24)).build()
        androidx.core.view.ViewCompat.dispatchApplyWindowInsets(root,insets)
        assertEquals(24,(video.layoutParams as android.widget.FrameLayout.LayoutParams).bottomMargin)
        show.invoke(activity,true)
        assertEquals(0,activity.window.attributes.flags and WindowManager.LayoutParams.FLAG_FULLSCREEN)
    }
    @Test fun returningToAnEpisodeKeepsItsExactCheckpointAndQuickSwitchesDoNotOverwriteIt() = fixture { _,player,_,activity ->
        PlayerActivity::class.java.getDeclaredField("started").apply { isAccessible = true }.set(activity,true)
        val choose = PlayerActivity::class.java.getDeclaredMethod("choose",Int::class.javaPrimitiveType,Boolean::class.javaPrimitiveType,Boolean::class.javaPrimitiveType).apply { isAccessible = true }
        player.seekTo(24_125)
        choose.invoke(activity,1,false,false)
        assertEquals(24_125L,DramaLibrary(activity).episodePosition("https://en.hdrama.net/series/story",1))
        choose.invoke(activity,2,false,false)
        choose.invoke(activity,0,false,false)
        assertEquals(24_125L,PlayerActivity::class.java.getDeclaredField("position").apply { isAccessible = true }.getLong(activity))
        assertEquals(24_125L,DramaLibrary(activity).episodePosition("https://en.hdrama.net/series/story",1))
    }
    @Test fun endingAnEpisodeAutomaticallySelectsTheNextWithoutAnAutoButton() = fixture { _,_,_,activity ->
        PlayerActivity::class.java.getDeclaredField("started").apply { isAccessible = true }.set(activity,true)
        val listener = PlayerActivity::class.java.getDeclaredField("listener").apply { isAccessible = true }.get(activity) as androidx.media3.common.Player.Listener
        listener.onPlaybackStateChanged(androidx.media3.common.Player.STATE_ENDED)
        assertEquals(1,PlayerActivity::class.java.getDeclaredField("index").apply { isAccessible = true }.getInt(activity))
    }
    @Test fun seekingToTheEndDoesNotSwitchEpisodesUntilScrubbingFinishes() = fixture { _,_,_,activity ->
        PlayerActivity::class.java.getDeclaredField("started").apply { isAccessible = true }.set(activity,true)
        PlayerActivity::class.java.getDeclaredField("scrubbing").apply { isAccessible = true }.setBoolean(activity,true)
        val listener = PlayerActivity::class.java.getDeclaredField("listener").apply { isAccessible = true }.get(activity) as androidx.media3.common.Player.Listener
        listener.onPlaybackStateChanged(androidx.media3.common.Player.STATE_ENDED)
        assertEquals(0,PlayerActivity::class.java.getDeclaredField("index").apply { isAccessible = true }.getInt(activity))
    }
    @Test @Config(sdk = [31]) fun automaticPipIsEnabledOnlyForActivePlaybackAndNotAppNavigation() = fixture { _,player,_,activity ->
        shadowOf(activity.packageManager).setSystemFeature(android.content.pm.PackageManager.FEATURE_PICTURE_IN_PICTURE,true)
        val proxy = Proxy.newProxyInstance(ExoPlayer::class.java.classLoader,arrayOf(ExoPlayer::class.java)) { _,method,args ->
            if (method.name == "isPlaying") true else method.invoke(player,*(args ?: emptyArray()))
        } as ExoPlayer
        PlayerActivity::class.java.getDeclaredField("player").apply { isAccessible = true }.set(activity,proxy)
        val params = PlayerActivity::class.java.getDeclaredMethod("pipParams").apply { isAccessible = true }
        assertTrue((params.invoke(activity) as android.app.PictureInPictureParams).isAutoEnterEnabled)
        PlayerActivity::class.java.getDeclaredField("pipSuppressed").apply { isAccessible = true }.setBoolean(activity,true)
        assertFalse((params.invoke(activity) as android.app.PictureInPictureParams).isAutoEnterEnabled)
    }
    @Test fun pipActionsAreScopedAndSeekAndTogglePlayback() = fixture { _,player,_,activity ->
        seekableVideo(activity,player);player.seekTo(24_000)
        val params = PlayerActivity::class.java.getDeclaredMethod("pipParams").apply { isAccessible = true }.invoke(activity) as android.app.PictureInPictureParams
        assertEquals(listOf("Rewind 10 seconds","Pause","Forward 10 seconds"),params.actions.map { it.title.toString() })
        for (action in params.actions) {
            val intent = shadowOf(action.actionIntent).savedIntent
            assertEquals(activity.packageName,intent.`package`)
            assertEquals("${activity.packageName}.PIP_CONTROL",intent.action)
        }
        val handle = PlayerActivity::class.java.getDeclaredMethod("handlePipAction",String::class.java).apply { isAccessible = true }
        handle.invoke(activity,"forward");assertEquals(34_000L,player.currentPosition)
        handle.invoke(activity,"back");assertEquals(24_000L,player.currentPosition)
        player.seekTo(3_000);handle.invoke(activity,"back");assertEquals(0L,player.currentPosition)
        player.seekTo(115_000);handle.invoke(activity,"forward");assertEquals(120_000L,player.currentPosition)
        handle.invoke(activity,"toggle");assertFalse(player.playWhenReady)
        val paused = PlayerActivity::class.java.getDeclaredMethod("pipParams").apply { isAccessible = true }.invoke(activity) as android.app.PictureInPictureParams
        assertEquals("Play",paused.actions[1].title)
        handle.invoke(activity,"toggle");assertTrue(player.playWhenReady)
    }
    @Test fun manualFillChoiceSurvivesActivityRecreation() {
        val url = "https://en.hdrama.net/series/fit-story"
        PlaybackHandoff.offer(Series("Fit Story",url,listOf(Episode(1,"$url/episode-1"))))
        val intent = Intent().putExtra("series",url)
        val c = Robolectric.buildActivity(PlayerActivity::class.java,intent).create()
        val state = Bundle()
        try {
            val activity = c.get();val views = all(activity.window.decorView)
            views.filterIsInstance<PlayerChrome>().single().actions.fit()
            assertEquals(AspectRatioFrameLayout.RESIZE_MODE_ZOOM,views.filterIsInstance<PlayerView>().single().resizeMode)
            c.saveInstanceState(state)
        } finally { c.destroy() }
        val restored = Robolectric.buildActivity(PlayerActivity::class.java,intent).create(state)
        try { assertEquals(AspectRatioFrameLayout.RESIZE_MODE_ZOOM,all(restored.get().window.decorView).filterIsInstance<PlayerView>().single().resizeMode) }
        finally { restored.destroy() }
    }

    @Test fun returningToOldFinishedPositionRestartsInsteadOfImmediatelyAutoAdvancing() = fixture { _,player,_,activity ->
        player.seekTo(120_000)
        val proxy = Proxy.newProxyInstance(ExoPlayer::class.java.classLoader,arrayOf(ExoPlayer::class.java)) { _,method,args ->
            when (method.name) {
                "getDuration" -> 120_000L
                "getPlaybackState" -> androidx.media3.common.Player.STATE_ENDED
                else -> method.invoke(player,*(args ?: emptyArray()))
            }
        } as ExoPlayer
        PlayerActivity::class.java.getDeclaredField("player").apply { isAccessible = true }.set(activity,proxy)
        PlayerActivity::class.java.getDeclaredField("started").apply { isAccessible = true }.setBoolean(activity,true)
        PlayerActivity::class.java.getDeclaredField("position").apply { isAccessible = true }.setLong(activity,120_000)
        PlayerActivity::class.java.getDeclaredField("resumeTarget").apply { isAccessible = true }.setLong(activity,120_000)
        PlayerActivity::class.java.getDeclaredField("validatingResume").apply { isAccessible = true }.setBoolean(activity,true)
        val listener = PlayerActivity::class.java.getDeclaredField("listener").apply { isAccessible = true }.get(activity) as androidx.media3.common.Player.Listener
        listener.onPlaybackStateChanged(androidx.media3.common.Player.STATE_ENDED)
        assertEquals(0L,player.currentPosition); assertTrue(player.playWhenReady)
        assertEquals(0,PlayerActivity::class.java.getDeclaredField("index").apply { isAccessible = true }.getInt(activity))
        assertEquals(0L,DramaLibrary(activity).episodePosition("https://en.hdrama.net/series/story",1))
    }
    @Test fun pausedCompletedEpisodeAlsoRestartsOnReturn() = fixture { _,player,_,activity ->
        seekableVideo(activity,player); player.seekTo(120_000); player.pause()
        val listener = PlayerActivity::class.java.getDeclaredField("listener").apply { isAccessible = true }.get(activity) as androidx.media3.common.Player.Listener
        listener.onPlaybackStateChanged(androidx.media3.common.Player.STATE_ENDED)
        assertEquals(0L,DramaLibrary(activity).episodePosition("https://en.hdrama.net/series/story",1))
        assertFalse(player.playWhenReady)
    }

    @Test fun lateDurationDoesNotMistakeAnUnfinishedResumeForAnOldEndTimestamp() = fixture { _,player,_,activity ->
        var total = androidx.media3.common.C.TIME_UNSET
        val proxy = Proxy.newProxyInstance(ExoPlayer::class.java.classLoader,arrayOf(ExoPlayer::class.java)) { _,method,args ->
            if (method.name == "getDuration") total else method.invoke(player,*(args ?: emptyArray()))
        } as ExoPlayer
        PlayerActivity::class.java.getDeclaredField("player").apply { isAccessible = true }.set(activity,proxy)
        PlayerActivity::class.java.getDeclaredField("started").apply { isAccessible = true }.setBoolean(activity,true)
        PlayerActivity::class.java.getDeclaredField("resumeTarget").apply { isAccessible = true }.setLong(activity,24_000)
        PlayerActivity::class.java.getDeclaredField("validatingResume").apply { isAccessible = true }.setBoolean(activity,true)
        val listener = PlayerActivity::class.java.getDeclaredField("listener").apply { isAccessible = true }.get(activity) as androidx.media3.common.Player.Listener
        listener.onPlaybackStateChanged(androidx.media3.common.Player.STATE_READY)
        total = 120_000; player.seekTo(120_000)
        PlayerActivity::class.java.getDeclaredField("position").apply { isAccessible = true }.setLong(activity,120_000)
        listener.onPlaybackStateChanged(androidx.media3.common.Player.STATE_ENDED)
        assertEquals(1,PlayerActivity::class.java.getDeclaredField("index").apply { isAccessible = true }.getInt(activity))
    }

}
