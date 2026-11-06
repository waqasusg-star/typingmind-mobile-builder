package com.waqas.hdrama

import android.os.Handler
import android.os.Looper
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.SeekParameters
import androidx.media3.exoplayer.video.VideoFrameMetadataListener

/** Preview directly in the full video; serialize seeks and preserve play/pause and saved history. */
@androidx.annotation.OptIn(markerClass = [UnstableApi::class])
class VideoScrubber(private val chrome: PlayerChrome, private val player: ExoPlayer) {
    private val handler = Handler(Looper.getMainLooper())
    private var active = false
    private var wasPlaying = false
    private var original = 0L
    private var originalSeek = SeekParameters.DEFAULT
    private var target = 0L
    private var issued = 0L
    private var epoch = 0
    private var queued = false
    private var awaitingFrame = false
    private val frameListener = VideoFrameMetadataListener { _,_,_,_ -> handler.post { onFrameReady() } }
    private val dispatch = Runnable {
        queued = false
        if (active && !awaitingFrame) {
            issued = target; epoch++; awaitingFrame = true
            player.seekTo(issued); handler.postDelayed(timeout,1000)
        }
    }
    private val timeout = Runnable {
        if (active && awaitingFrame) { awaitingFrame = false; if (target != issued) request() }
    }
    fun start() {
        original = player.currentPosition; wasPlaying = player.playWhenReady
        originalSeek = player.seekParameters; active = true
        target = original; issued = original
        player.pause(); player.setSeekParameters(SeekParameters.CLOSEST_SYNC)
        player.setVideoFrameMetadataListener(frameListener); chrome.showSeeking(true)
    }
    fun update(position: Long, duration: Long) {
        if (!active) return
        target = position.coerceIn(0,duration.coerceAtLeast(0)); request()
    }
    private fun request() {
        if (active && !queued && !awaitingFrame && target != issued) { queued = true; handler.postDelayed(dispatch,100) }
    }
    fun onFrameReady(delay: Long = 32) {
        if (!active || !awaitingFrame) return
        val requestEpoch = epoch
        handler.postDelayed({
            if (active && awaitingFrame && requestEpoch == epoch) {
                handler.removeCallbacks(timeout); awaitingFrame = false
                if (target != issued) request()
            }
        },delay)
    }
    fun finish(position: Long) = close(position)
    fun stop() = close(original)
    private fun close(position: Long) {
        if (!active) return
        active = false; epoch++; handler.removeCallbacksAndMessages(null)
        player.clearVideoFrameMetadataListener(frameListener)
        player.setSeekParameters(SeekParameters.EXACT); player.seekTo(position.coerceAtLeast(0))
        player.setSeekParameters(originalSeek); player.playWhenReady = wasPlaying
        chrome.showSeeking(false)
    }
}
