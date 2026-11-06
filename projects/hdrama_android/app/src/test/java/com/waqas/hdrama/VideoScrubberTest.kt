package com.waqas.hdrama

import android.graphics.Bitmap
import android.os.Looper
import android.view.LayoutInflater
import android.view.View
import androidx.media3.common.MediaItem
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.time.Duration

@androidx.annotation.OptIn(markerClass = [androidx.media3.common.util.UnstableApi::class])
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class VideoScrubberTest {
    @Test fun renderedFramesSerializeSeeksAndFinishRestoresPlaybackWhileCancelRestoresOriginalPosition() {
        val context = android.view.ContextThemeWrapper(RuntimeEnvironment.getApplication(),R.style.AppTheme)
        val chrome = PlayerChrome(context,PlayerChrome.Actions(back = {},episodes = {},speed = {},rotate = {},fit = {},toggle = {},retry = {},access = {}))
        val video = LayoutInflater.from(context).inflate(R.layout.player_video,null) as PlayerView
        val p = ExoPlayer.Builder(context).build()
        try {
            p.setMediaItem(MediaItem.fromUri("https://media.example/video.mp4"));p.seekTo(24_000);p.playWhenReady = true
            val preview = VideoScrubber(chrome,p)
            preview.start();assertFalse(p.playWhenReady)
            preview.update(10_000,90_000)
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(110));assertEquals(10_000L,p.currentPosition)
            preview.update(20_000,90_000)
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(300));assertEquals(10_000L,p.currentPosition)
            preview.onFrameReady()
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(150));assertEquals(20_000L,p.currentPosition)
            preview.onFrameReady();shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(40))
            preview.finish(37_125);assertTrue(p.playWhenReady);assertEquals(37_125L,p.currentPosition)
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(2100));assertEquals(37_125L,p.currentPosition)
            p.playWhenReady = false
            preview.start();preview.update(5_000,90_000)
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(110));preview.stop()
            assertFalse(p.playWhenReady);assertEquals(37_125L,p.currentPosition)
        } finally { p.release() }
    }
}
