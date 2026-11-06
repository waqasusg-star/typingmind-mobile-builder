package com.waqas.hdrama

import android.content.Context
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.util.UnstableApi
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.cache.*
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.*
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.source.preload.DefaultPreloadManager
import androidx.media3.exoplayer.source.preload.TargetPreloadStatusControl
import java.io.File

@androidx.annotation.OptIn(markerClass = [UnstableApi::class])
object VideoCache {
    private var cache: SimpleCache? = null
    @Synchronized fun get(context: Context): SimpleCache = cache ?: SimpleCache(
        File(context.applicationContext.cacheDir, "episode-media"),
        LeastRecentlyUsedCacheEvictor(128L * 1024 * 1024),
        StandaloneDatabaseProvider(context.applicationContext)
    ).also { cache = it }
}

/** Preload three seconds of one upcoming episode without a second video decoder/player. */
@androidx.annotation.OptIn(markerClass = [UnstableApi::class])
class PlaybackEngine(context: Context) {
    private val context = context.applicationContext
    var currentIndex = 0
        set(value) { field = value; preload.setCurrentPlayingIndex(value) }
    var allowPreload = false
    private data class Registered(val index: Int, val stream: Stream, val item: MediaItem)
    private val registered = mutableMapOf<String, Registered>()
    private val loadControl = DefaultLoadControl.Builder()
        .setBufferDurationsMs(15_000, 30_000, 750, 1_500)
        .setBackBuffer(10_000, true).build()
    private val builder = DefaultPreloadManager.Builder(this.context,
        TargetPreloadStatusControl<Int> { rank ->
            if (allowPreload && rank == currentIndex + 1)
                DefaultPreloadManager.Status(DefaultPreloadManager.Status.STAGE_LOADED_FOR_DURATION_MS, 3_000)
            else null
        }).setLoadControl(loadControl)
    private val preload = builder.build()
    val player: ExoPlayer = builder.buildExoPlayer(ExoPlayer.Builder(this.context)
        .setSeekBackIncrementMs(10_000).setSeekForwardIncrementMs(10_000))

    private fun register(series: Series, index: Int, stream: Stream): MediaItem {
        val episode = series.episodes[index]
        registered[episode.pageUrl]?.let { old ->
            if (old.stream == stream) return old.item
            preload.remove(old.item)
        }
        // One index holds exactly one source: replace a different episode left in the same slot.
        registered.values.firstOrNull { it.index == index }?.let { stale ->
            preload.remove(stale.item);registered.remove(stale.item.mediaId)
        }
        val data = CacheDataSource.Factory().setCache(VideoCache.get(context))
            .setUpstreamDataSourceFactory(OkHttpDataSource.Factory(Network.mediaClient)
                .setUserAgent(stream.userAgent)
                .setDefaultRequestProperties(mapOf("Referer" to stream.referer, "Origin" to "https://en.hdrama.net")))
            .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR)
        val item = MediaItem.Builder().setUri(stream.url).setMimeType(stream.mimeType)
            .setMediaId(episode.pageUrl).setMediaMetadata(MediaMetadata.Builder()
                .setTitle(series.title).setSubtitle("Episode ${episode.number}").build()).build()
        preload.add(DefaultMediaSourceFactory(data).createMediaSource(item), index)
        registered[episode.pageUrl] = Registered(index, stream, item)
        return item
    }
    fun play(series: Series, index: Int, stream: Stream, position: Long) {
        currentIndex = index
        allowPreload = false
        val item = register(series, index, stream)
        player.setMediaSource(checkNotNull(preload.getMediaSource(item)), position)
        player.prepare()
        registered.values.filter { kotlin.math.abs(it.index - index) > 1 }.toList().forEach {
            preload.remove(it.item); registered.remove(it.item.mediaId)
        }
    }
    fun playOffline(request: androidx.media3.exoplayer.offline.DownloadRequest, position: Long) {
        allowPreload = false; preload.invalidate()
        player.setMediaSource(DefaultMediaSourceFactory(OfflineStore.offlineData(context)).createMediaSource(request.toMediaItem()),position)
        player.prepare()
    }
    fun stageNext(series: Series, index: Int, stream: Stream) { register(series, index, stream); preload.invalidate() }
    fun updatePreload(allowed: Boolean) {
        if (allowPreload != allowed) { allowPreload = allowed; preload.invalidate() }
    }
    fun release() { player.release(); preload.release(); registered.clear() }
}
