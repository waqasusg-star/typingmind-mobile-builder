package com.waqas.hdrama

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.webkit.WebView
import android.widget.FrameLayout
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.offline.*
import androidx.media3.exoplayer.offline.DownloadManager
import androidx.media3.exoplayer.scheduler.Scheduler
import kotlinx.coroutines.*

private const val CHANNEL = "offline-downloads"
fun downloadChannel(context: Context) {
    context.getSystemService(NotificationManager::class.java).createNotificationChannel(NotificationChannel(CHANNEL,"Episode downloads",NotificationManager.IMPORTANCE_LOW))
}
fun downloadsIntent(context: Context): PendingIntent = PendingIntent.getActivity(context,0,Intent(context,DownloadsActivity::class.java),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

/** A single foreground service owns source preparation and Media3 transfers, including while the app is closed. */
@androidx.annotation.OptIn(markerClass = [UnstableApi::class])
class EpisodePreparationService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var job: Job? = null
    private lateinit var host: FrameLayout
    private val repository by lazy { Repository(BrowserResolver(this,host)) }
    override fun onCreate() {
        super.onCreate(); downloadChannel(this)
        host = FrameLayout(this)
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Android 12+ can refuse a foreground start made while the app is in the background.
        try { startForeground(403,notification("Preparing episode downloads…")) }
        catch (e: Exception) { stopSelf();return START_NOT_STICKY }
        if (job?.isActive != true) job = scope.launch {
            try {
                val downloads = OfflineStore.manager(this@EpisodePreparationService)
                var waited = 0
                while (!downloads.isInitialized && waited < 200) { delay(50);waited++ }
                if (!downloads.isInitialized) { stopSelf();return@launch }
                while (isActive) {
                    if (OfflineStore.isPaused(this@EpisodePreparationService)) break
                    val task = OfflineStore.pending(this@EpisodePreparationService).firstOrNull { it.error.isEmpty() }
                    if (task == null) {
                        if (downloads.currentDownloads.none { it.state in listOf(Download.STATE_QUEUED,Download.STATE_DOWNLOADING,Download.STATE_RESTARTING,Download.STATE_REMOVING) }) break
                        getSystemService(NotificationManager::class.java).notify(403,notification("Saving episodes for offline watching"))
                        delay(1000); continue
                    }
                    val manager = getSystemService(android.net.ConnectivityManager::class.java)
                    val network = manager.getNetworkCapabilities(manager.activeNetwork)
                    if (network?.hasCapability(android.net.NetworkCapabilities.NET_CAPABILITY_VALIDATED) != true ||
                        (OfflineStore.wifiOnly(this@EpisodePreparationService) && !network.hasCapability(android.net.NetworkCapabilities.NET_CAPABILITY_NOT_METERED))) {
                        getSystemService(NotificationManager::class.java).notify(403,notification(if (OfflineStore.wifiOnly(this@EpisodePreparationService)) "Waiting for Wi-Fi…" else "Waiting for network…"))
                        delay(3000); continue
                    }
                    getSystemService(NotificationManager::class.java).notify(403,notification("Preparing episode ${task.series.episodes[task.index].number}"))
                    try {
                        val stream = withTimeout(40_000) { repository.stream(task.series.episodes[task.index]) }
                        scope.launch { SeriesArtwork.remember(this@EpisodePreparationService,task.series);SeriesArtwork.cache(this@EpisodePreparationService,task.series) }
                        val request = withTimeout(40_000) { OfflineStore.prepare(this@EpisodePreparationService,task.copy(stream = stream)) }
                        if (!OfflineStore.isPaused(this@EpisodePreparationService) && OfflineStore.pending(this@EpisodePreparationService).any { it == task }) {
                            downloads.addDownload(request)
                            downloads.resumeDownloads()
                            OfflineStore.removePending(this@EpisodePreparationService,task.id)
                            delay(200)
                        }
                    } catch (e: TimeoutCancellationException) { OfflineStore.failPending(this@EpisodePreparationService,task.id) }
                    catch (e: CancellationException) { throw e }
                    catch (e: Exception) { OfflineStore.failPending(this@EpisodePreparationService,task.id) }
                }
            } finally { stopForeground(STOP_FOREGROUND_REMOVE);stopSelf() }
        }
        return START_STICKY
    }
    private fun notification(message: String) = DownloadNotificationHelper(this,CHANNEL).buildProgressNotification(
        this,android.R.drawable.stat_sys_download,downloadsIntent(this),message,OfflineStore.manager(this).currentDownloads,OfflineStore.manager(this).notMetRequirements)
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onTimeout(startId: Int, fgsType: Int) { OfflineStore.manager(this).pauseDownloads(); scope.cancel(); stopSelf() }
    override fun onDestroy() {
        scope.cancel();stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
    companion object {
        fun start(context: Context) { ContextCompat.startForegroundService(context,Intent(context,EpisodePreparationService::class.java)) }
    }
}
