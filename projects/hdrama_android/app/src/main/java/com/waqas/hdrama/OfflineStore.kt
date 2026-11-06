package com.waqas.hdrama

import android.content.Context
import android.net.Uri
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.cache.*
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.offline.*
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.C
import androidx.media3.exoplayer.scheduler.Requirements
import kotlinx.coroutines.suspendCancellableCoroutine
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

data class OfflineMetadata(val series: Series, val index: Int, val quality: Int, val stream: Stream? = null, val error: String = "") {
    val id: String get() = series.episodes[index].pageUrl
    fun json(): JSONObject = JSONObject().put("title",series.title).put("series",series.url).put("index",index)
        .put("poster",series.posterUrl).put("season",series.seasonLabel).put("quality",quality).put("error",error).put("episodes",JSONArray().apply {
            series.episodes.forEach { put(JSONObject().put("number",it.number).put("page",it.pageUrl)) }
        }).apply { stream?.let { put("stream",JSONObject().put("url",it.url).put("referer",it.referer).put("ua",it.userAgent).put("mime",it.mimeType)) } }
    companion object {
        fun parse(bytes: ByteArray): OfflineMetadata = parse(JSONObject(bytes.toString(Charsets.UTF_8)))
        fun parse(json: JSONObject): OfflineMetadata {
            val list = json.getJSONArray("episodes")
            val series = Series(json.getString("title"),json.getString("series"),(0 until list.length()).map {
                val ep = list.getJSONObject(it); Episode(ep.getInt("number"),ep.getString("page"))
            },json.optString("poster"),json.optString("season"))
            require(SitePolicy.seriesUrl(series.url) != null && series.episodes.all { SitePolicy.siteUrl(it.pageUrl) })
            val index = json.getInt("index"); require(index in series.episodes.indices)
            val stream = json.optJSONObject("stream")?.let { Stream(it.getString("url"),it.getString("referer"),it.getString("ua"),it.optString("mime").takeIf { value -> value.isNotBlank() && value != "null" }) }
            return OfflineMetadata(series,index,json.optInt("quality"),stream,json.optString("error"))
        }
    }
}

/** Durable app-private cache. Completed downloads are never evicted by streaming/preloading. */
@androidx.annotation.OptIn(markerClass = [UnstableApi::class])
object OfflineStore {
    private var cache: SimpleCache? = null
    private var manager: DownloadManager? = null
    private val executor = Executors.newFixedThreadPool(3)
    @Synchronized fun cache(context: Context): SimpleCache = cache ?: SimpleCache(File(context.applicationContext.filesDir,"offline-media"),NoOpCacheEvictor(),StandaloneDatabaseProvider(context.applicationContext)).also { cache = it }
    fun http(stream: Stream) = OkHttpDataSource.Factory(Network.mediaClient).setUserAgent(stream.userAgent)
        .setDefaultRequestProperties(mapOf("Referer" to stream.referer,"Origin" to Uri.parse(stream.referer).let { "${it.scheme}://${it.authority}" }))
    @Synchronized fun manager(context: Context): DownloadManager = manager ?: DownloadManager(context.applicationContext,
        DefaultDownloadIndex(StandaloneDatabaseProvider(context.applicationContext)), DownloaderFactory { request ->
            val metadata = OfflineMetadata.parse(request.data)
            DefaultDownloaderFactory(CacheDataSource.Factory().setCache(cache(context))
                .setUpstreamDataSourceFactory(http(checkNotNull(metadata.stream))),executor).createDownloader(request)
        }).apply {
            maxParallelDownloads = 2
            setRequirements(Requirements(Requirements.NETWORK or if (wifiOnly(context)) Requirements.NETWORK_UNMETERED else 0))
            resumeDownloads()
        }.also { manager = it }
    fun downloads(context: Context): List<Download> = manager(context).downloadIndex.getDownloads().use { cursor ->
        buildList { while (cursor.moveToNext()) add(cursor.download) }
    }
    fun completed(context: Context, id: String): Download? = manager(context).downloadIndex.getDownload(id)?.takeIf { it.state == Download.STATE_COMPLETED }
    fun offlineData(context: Context) = CacheDataSource.Factory().setCache(cache(context)).setUpstreamDataSourceFactory(null)
    private fun prefs(context: Context) = context.getSharedPreferences("offline_queue",Context.MODE_PRIVATE)
    fun pending(context: Context): List<OfflineMetadata> {
        val array = runCatching { JSONArray(prefs(context).getString("items","[]")) }.getOrElse { JSONArray() }
        return (0 until array.length()).mapNotNull { runCatching { OfflineMetadata.parse(array.getJSONObject(it)) }.getOrNull() }
    }
    private fun write(context: Context, items: List<OfflineMetadata>) { prefs(context).edit().putString("items",JSONArray().apply { items.forEach { put(it.json()) } }.toString()).commit() }
    fun queue(context: Context, series: Series, indices: List<Int>, quality: Int) {
        val old = pending(context).associateBy { it.id }.toMutableMap()
        indices.filter { it in series.episodes.indices }.forEach { i ->
            val item = OfflineMetadata(series,i,quality)
            if (completed(context,item.id) == null) old[item.id] = item
        }; write(context,old.values.toList())
    }
    fun removePending(context: Context, id: String) { write(context,pending(context).filterNot { it.id == id }) }
    fun removePending(context: Context, ids: Set<String>) { write(context,pending(context).filterNot { it.id in ids }) }
    fun failPending(context: Context, id: String) { write(context,pending(context).map { if (it.id == id) it.copy(error = "Source unavailable. Recheck website access, then retry.") else it }) }
    fun retryPending(context: Context, id: String? = null) { write(context,pending(context).map { if (id == null || it.id == id) it.copy(error = "") else it }) }
    fun wifiOnly(context: Context): Boolean = prefs(context).getBoolean("wifi",false)
    fun isPaused(context: Context): Boolean = prefs(context).getBoolean("paused",false)
    fun setPaused(context: Context, paused: Boolean) { prefs(context).edit().putBoolean("paused",paused).commit() }
    fun setWifiOnly(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean("wifi",enabled).apply()
        manager(context).setRequirements(Requirements(Requirements.NETWORK or if (enabled) Requirements.NETWORK_UNMETERED else 0))
    }
    suspend fun prepare(context: Context, metadata: OfflineMetadata): DownloadRequest = suspendCancellableCoroutine { continuation ->
        val stream = checkNotNull(metadata.stream)
        val item = MediaItem.Builder().setUri(stream.url).setMimeType(stream.mimeType).build()
        val helper = DownloadHelper.forMediaItem(context,item,DefaultRenderersFactory(context),http(stream))
        val cleanup = ReleaseOnce { helper.release() }
        continuation.invokeOnCancellation { android.os.Handler(android.os.Looper.getMainLooper()).post { cleanup.release() } }
        helper.prepare(object : DownloadHelper.Callback {
            override fun onPrepared(helper: DownloadHelper) {
                if (!continuation.isActive) { cleanup.release(); return }
                try {
                    for (period in 0 until helper.periodCount) {
                        val builder = DownloadHelper.getDefaultTrackSelectorParameters(context).buildUpon().setForceHighestSupportedBitrate(true)
                        if (metadata.quality > 0) {
                            val info = helper.getMappedTrackInfo(period)
                            val options = buildList {
                                for (renderer in 0 until info.rendererCount) if (info.getRendererType(renderer) == C.TRACK_TYPE_VIDEO) {
                                    val groups = info.getTrackGroups(renderer)
                                    for (g in 0 until groups.length) for (track in 0 until groups[g].length) {
                                        val pixels = QualityOptions.pixels(groups[g].getFormat(track))
                                        if (pixels > 0 && info.getTrackSupport(renderer,g,track) == C.FORMAT_HANDLED)
                                            add(VideoQuality(pixels,groups[g],track))
                                    }
                                }
                            }
                            val nearest = QualityOptions.nearest(options.map { it.pixels },metadata.quality)
                            options.firstOrNull { it.pixels == nearest }?.let { builder.addOverride(TrackSelectionOverride(it.group,it.track)) }
                        }
                        helper.replaceTrackSelections(period,builder.build())
                    }
                    val request = helper.getDownloadRequest(metadata.id,metadata.json().toString().toByteArray())
                    if (continuation.isActive) continuation.resume(request)
                } catch (e: Exception) { if (continuation.isActive) continuation.resumeWithException(e) }
                finally { cleanup.release() }
            }
            override fun onPrepareError(helper: DownloadHelper, e: IOException) {
                cleanup.release(); if (continuation.isActive) continuation.resumeWithException(e)
            }
        })
    }
}
