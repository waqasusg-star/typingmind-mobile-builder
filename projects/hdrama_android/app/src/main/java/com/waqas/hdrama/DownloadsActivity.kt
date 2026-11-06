package com.waqas.hdrama

import android.app.AlertDialog
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.*
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout
import android.webkit.WebSettings
import android.view.Gravity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.offline.*

@androidx.annotation.OptIn(markerClass = [UnstableApi::class])
class DownloadsActivity : ComponentActivity() {
    private lateinit var rows: LinearLayout
    private lateinit var usage: TextView
    private lateinit var title: TextView
    private var folderUrl: String? = null
    private val tiles = mutableMapOf<String,Pair<OfflineMetadata,TextView>>()
    private val artworkAttempted = mutableSetOf<String>()
    private val handler = Handler(Looper.getMainLooper())
    private val tick = object : Runnable { override fun run() { render(); handler.postDelayed(this,1000) } }
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        androidx.core.view.WindowCompat.setDecorFitsSystemWindows(window,false)
        folderUrl = state?.getString("folder")
        onBackPressedDispatcher.addCallback(this,object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() { back() }
        })
        window.statusBarColor = AppColors.background; window.navigationBarColor = Color.BLACK
        val root = column().apply { setBackgroundColor(AppColors.background); pad(16) }
        val header = screenHeader("Downloads") { back() }; title = header.second; root.addView(header.first)
        usage = label("",12f).apply { setTextColor(AppColors.muted); setPadding(0,dp(8),0,dp(12)) }; root.addView(usage)
        root.addView(row().apply {
            weight(button("Pause all") {
                OfflineStore.setPaused(this@DownloadsActivity,true)
                stopService(Intent(this@DownloadsActivity,EpisodePreparationService::class.java))
                OfflineStore.manager(this@DownloadsActivity).setStopReason(null,1)
            })
            weight(button("Resume all") {
                OfflineStore.setPaused(this@DownloadsActivity,false)
                OfflineStore.retryPending(this@DownloadsActivity)
                OfflineStore.manager(this@DownloadsActivity).setStopReason(null,0)
                OfflineStore.manager(this@DownloadsActivity).resumeDownloads()
                EpisodePreparationService.start(this@DownloadsActivity)
            })
        })
        root.addView(Switch(this).apply {
            text = "Wi-Fi only"; minHeight = dp(56); setTextColor(Color.WHITE)
            thumbTintList = android.content.res.ColorStateList(arrayOf(intArrayOf(android.R.attr.state_checked),intArrayOf()),intArrayOf(accent,AppColors.muted))
            trackTintList = android.content.res.ColorStateList(arrayOf(intArrayOf(android.R.attr.state_checked),intArrayOf()),intArrayOf(0x66a491ff.toInt(),AppColors.stroke))
            isChecked = OfflineStore.wifiOnly(this@DownloadsActivity)
            setOnCheckedChangeListener { _,enabled -> OfflineStore.setWifiOnly(this@DownloadsActivity,enabled) }
        })
        rows = column()
        root.addView(ScrollView(this).apply { isVerticalScrollBarEnabled = false; addView(rows) },LinearLayout.LayoutParams(-1,0,1f))
        setContentView(root)
        ViewCompat.setOnApplyWindowInsetsListener(root) { v,insets ->
            val safe = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
            v.setPadding(dp(16)+safe.left,dp(8)+safe.top,dp(16)+safe.right,dp(16)+safe.bottom); WindowInsetsCompat.CONSUMED
        }
    }
    override fun onStart() {
        super.onStart(); handler.post(tick)
        if (!OfflineStore.isPaused(this) && (OfflineStore.pending(this).any { it.error.isEmpty() } || OfflineStore.downloads(this).any { it.state in listOf(Download.STATE_QUEUED,Download.STATE_DOWNLOADING) && it.stopReason == 0 })) EpisodePreparationService.start(this)
    }
    override fun onStop() { handler.removeCallbacks(tick); super.onStop() }
    private fun back() { if (folderUrl != null) { folderUrl = null;rows.tag = null;render() } else finish() }
    override fun onSaveInstanceState(outState: Bundle) { outState.putString("folder",folderUrl);super.onSaveInstanceState(outState) }
    private fun render() {
        val records = OfflineStore.downloads(this).associateBy { it.request.id }.toMutableMap()
        OfflineStore.manager(this).currentDownloads.forEach { records[it.request.id] = it }
        val allPending = OfflineStore.pending(this)
        val folders = DownloadFolders.group(allPending + records.values.filterNot { it.state == Download.STATE_REMOVING }.mapNotNull { runCatching { OfflineMetadata.parse(it.request.data) }.getOrNull() })
        if (folderUrl != null && folderUrl !in folders) folderUrl = null
        val pending = allPending.filter { it.series.url == folderUrl }
        val visibleRecords = records.values.filter { runCatching { OfflineMetadata.parse(it.request.data).series.url == folderUrl }.getOrDefault(false) }
        title.text = folderUrl?.let { folders[it]?.firstOrNull()?.series?.title } ?: "Downloads"
        val savedRecords = records.values.filter { it.state == Download.STATE_COMPLETED }
        usage.text = "${savedRecords.size} saved · %.1f MB offline · %.1f GB free".format(savedRecords.sumOf { it.bytesDownloaded }.toDouble()/1048576,filesDir.usableSpace.toDouble()/1073741824)
        // Preserve scrolling and touch targets while only percentages change.
        val signature = folderUrl.orEmpty() + folders.keys.joinToString() + OfflineStore.isPaused(this).toString() + allPending.joinToString { it.id + it.error } + records.values.joinToString { "${it.request.id}:${it.state}:${it.stopReason}" }
        if (rows.tag == signature) {
            updateTiles(records)
            return
        }
        rows.tag = signature; rows.removeAllViews(); tiles.clear()
        if (folderUrl == null) {
            folders.values.sortedBy { it.first().series.title.lowercase() }.forEach { episodes ->
                val series = SeriesArtwork.enrich(this,episodes.first().series)
                val saved = episodes.count { records[it.id]?.state == Download.STATE_COMPLETED }
                val cover = seriesHeader(series,"$saved saved · ${episodes.size} episodes    ›")
                cover.contentDescription = "Open series folder: ${series.title}"
                cover.setOnClickListener { folderUrl = series.url;rows.tag = null;render() }
                cover.setOnLongClickListener { confirmDelete(series.title,episodes.map { it.id });true }
                rows.addView(cover,LinearLayout.LayoutParams(-1,-2).apply { bottomMargin = dp(12) })
                hydrateArtwork(series)
            }
            if (folders.isEmpty()) rows.addView(emptyState("download","Ready for offline watching","Open a series and tap Download to save episodes for your next journey."))
            return
        }
        folders[folderUrl]?.firstOrNull()?.series?.let { series ->
            rows.addView(seriesHeader(SeriesArtwork.enrich(this,series),"Episodes · ${folders[folderUrl]?.size}"),LinearLayout.LayoutParams(-1,-2).apply { bottomMargin = dp(16) })
        }
        val grid = GridLayout(this).apply { columnCount = 5 }
        val episodes = folders[folderUrl].orEmpty()
        episodes.forEachIndexed { cell, metadata ->
            val download = records[metadata.id]
            val number = metadata.series.episodes[metadata.index].number
            val ready = download?.state == Download.STATE_COMPLETED
            val badge = badge(download,metadata.error.isNotEmpty())
            val tile = label("$number\n$badge",15f).apply {
                gravity = Gravity.CENTER;typeface = android.graphics.Typeface.DEFAULT_BOLD
                background = surface(if (ready) AppColors.raised else AppColors.surface,12,true); isFocusable = true;setTextColor(if (ready) accent else Color.WHITE)
                contentDescription = "Episode $number" + if (ready) ", downloaded" else ", " + (download?.let { description(it) } ?: "queued")
                setOnClickListener { if (ready) play(metadata) else episodeOptions(metadata,download) }
                setOnLongClickListener { confirmDelete("${metadata.series.title} · Episode $number",listOf(metadata.id));true }
            }
            tiles[metadata.id] = metadata to tile
            grid.addView(tile,GridLayout.LayoutParams(GridLayout.spec(cell / 5),GridLayout.spec(cell % 5,1f)).apply {
                width = 0;height = dp(56);setMargins(dp(3),dp(3),dp(3),dp(3))
            })
        }
        repeat((5 - episodes.size % 5) % 5) { offset ->
            val cell = episodes.size + offset
            grid.addView(View(this),GridLayout.LayoutParams(GridLayout.spec(cell / 5),GridLayout.spec(cell % 5,1f)).apply { width = 0;height = dp(56);setMargins(dp(3),dp(3),dp(3),dp(3)) })
        }
        rows.addView(label("Tap to play · Hold to delete",12f).apply { alpha = .65f;pad(8) })
        rows.addView(grid,LinearLayout.LayoutParams(-1,-2))
    }
    private fun badge(download: Download?, failed: Boolean): String = when {
        download?.state == Download.STATE_COMPLETED -> "✓"
        download?.state == Download.STATE_FAILED || failed -> "!"
        download?.stopReason != null && download.stopReason != 0 -> "Ⅱ"
        download?.state == Download.STATE_DOWNLOADING -> if (download.percentDownloaded >= 0) "${download.percentDownloaded.toInt()}%" else "↓"
        else -> "…"
    }
    private fun updateTiles(records: Map<String,Download>) {
        tiles.forEach { (id,entry) ->
            val (metadata,tile) = entry; val download = records[id]
            val number = metadata.series.episodes[metadata.index].number
            val text = "$number\n${badge(download,metadata.error.isNotEmpty())}"
            if (tile.text.toString() != text) tile.text = text
            tile.contentDescription = "Episode $number, " + (download?.let(::description) ?: "queued")
        }
    }
    private fun play(metadata: OfflineMetadata) {
        startActivity(Intent(this,PlayerActivity::class.java).putExtra("series",metadata.series.url)
            .putExtra("episode",metadata.series.episodes[metadata.index].number).putExtra("offline",metadata.id))
    }
    private fun confirmDelete(label: String, ids: List<String>) {
        AlertDialog.Builder(this).setTitle("Delete downloads?").setMessage("$label\n${ids.size} episode(s). Favorites and watch progress are kept.")
            .setNegativeButton("Cancel",null).setPositiveButton("Delete") { _,_ ->
                OfflineStore.removePending(this,ids.toSet())
                ids.forEach { id ->
                    if (OfflineStore.manager(this).downloadIndex.getDownload(id) != null) OfflineStore.manager(this).removeDownload(id)
                }
                rows.tag = null;render()
            }.show().also(::polishDialog)
    }
    private fun episodeOptions(metadata: OfflineMetadata, download: Download?) {
        // A download stopped by network requirements is resumable even when no stop reason is stored.
        val resumable = download == null || download.state == Download.STATE_FAILED ||
            download.state == Download.STATE_STOPPED || download.stopReason != 0
        val label = if (download == null || download.state == Download.STATE_FAILED) "Retry download" else if (resumable) "Resume download" else "Pause download"
        AlertDialog.Builder(this).setTitle("Episode ${metadata.series.episodes[metadata.index].number}")
            .setMessage(download?.let { description(it) } ?: metadata.error.ifBlank { "Waiting to prepare source" })
            .setPositiveButton(label) { _,_ ->
                if (download == null) OfflineStore.retryPending(this,metadata.id)
                else if (download.state == Download.STATE_FAILED) {
                    OfflineStore.manager(this).removeDownload(metadata.id)
                    OfflineStore.queue(this,metadata.series,listOf(metadata.index),metadata.quality)
                } else OfflineStore.manager(this).setStopReason(metadata.id,if (resumable) 0 else 1)
                if (resumable) {
                    OfflineStore.setPaused(this,false)
                    OfflineStore.manager(this).resumeDownloads()
                    EpisodePreparationService.start(this)
                }
                rows.tag = null;render()
            }.setNegativeButton("Close",null).setNeutralButton("Delete") { _,_ -> confirmDelete("Episode ${metadata.series.episodes[metadata.index].number}",listOf(metadata.id)) }.show().also(::polishDialog)
    }
    private fun seriesHeader(series: Series, subtitle: String): LinearLayout = seriesCard(series.url,series.title,
        series.seasonLabel.ifBlank { "Series folder" },subtitle,"${series.title} thumbnail")
    private fun hydrateArtwork(series: Series) {
        if (SeriesArtwork.hasPoster(this,series.url) || !artworkAttempted.add(series.url)) return
        val connection = getSystemService(android.net.ConnectivityManager::class.java)
        if (connection.getNetworkCapabilities(connection.activeNetwork)?.hasCapability(android.net.NetworkCapabilities.NET_CAPABILITY_VALIDATED) != true) return
        lifecycleScope.launch {
            try {
                var metadata = series
                if (SeriesArtwork.enrich(this@DownloadsActivity,series).posterUrl.isBlank()) {
                    metadata = withTimeout(15000) {
                        val host = window.decorView.findViewById<android.view.ViewGroup>(android.R.id.content)
                        Repository(BrowserResolver(this@DownloadsActivity,host)).series(series.url)
                    }
                    SeriesArtwork.remember(this@DownloadsActivity,metadata)
                }
                SeriesArtwork.cache(this@DownloadsActivity,metadata)
            } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
            catch (_: Exception) { /* A failed poster must not prevent offline playback. */ }
            if (SeriesArtwork.hasPoster(this@DownloadsActivity,series.url)) rows.refreshPosters()
        }
    }
    private fun description(d: Download): String = when (d.state) {
        Download.STATE_COMPLETED -> "Ready offline · %.1f MB".format(d.bytesDownloaded.toDouble()/1048576)
        Download.STATE_FAILED -> "Download failed. Retry to refresh its source."
        Download.STATE_STOPPED -> "Paused"
        Download.STATE_DOWNLOADING -> if (d.percentDownloaded >= 0) "Downloading · ${d.percentDownloaded.toInt()}%" else "Downloading · %.1f MB".format(d.bytesDownloaded.toDouble()/1048576)
        Download.STATE_REMOVING -> "Deleting…"
        else -> "Queued · waiting for network"
    }
}
