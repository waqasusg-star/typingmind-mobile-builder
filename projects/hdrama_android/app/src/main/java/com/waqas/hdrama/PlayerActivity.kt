package com.waqas.hdrama

import android.app.AlertDialog
import android.content.Intent
import androidx.activity.result.contract.ActivityResultContracts
import android.app.PictureInPictureParams
import android.app.PendingIntent
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import android.graphics.drawable.Icon
import androidx.core.content.ContextCompat
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Color
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Rational
import android.view.*
import android.widget.*
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.lifecycleScope
import androidx.media3.common.*
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.TimeoutCancellationException
import kotlin.math.abs

@androidx.annotation.OptIn(markerClass = [UnstableApi::class])
class PlayerActivity : ComponentActivity() {
    private lateinit var root: FrameLayout
    private lateinit var video: PlayerView
    private lateinit var chrome: PlayerChrome
    private lateinit var heading: TextView
    private lateinit var episodeLabel: TextView
    private lateinit var positionLabel: TextView
    private lateinit var status: TextView
    private lateinit var spinner: ProgressBar
    private lateinit var seek: SeekBar
    private lateinit var retry: TextView
    private lateinit var accessButton: TextView
    private lateinit var speed: TextView
    private lateinit var repository: Repository
    private var player: ExoPlayer? = null
    private var engine: PlaybackEngine? = null
    private var sources: SessionStreams? = null
    private var prefetchJob: Job? = null
    private var stagedNext: Pair<String, String>? = null
    private var prefetchRetryAfter = 0L
    private var prefetchBlocked = false
    private var series: Series? = null
    private var index = 0
    private var position = 0L
    private var desiredPlay = true
    private var baseSpeed = 1f
    private var pipSuppressed = false
    private var pipReceiverRegistered = false
    private var pipSignature = ""
    private val pipReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (isInPictureInPictureMode && intent.action == "$packageName.PIP_CONTROL") handlePipAction(intent.getStringExtra("command").orEmpty())
        }
    }
    private var seekPreview: VideoScrubber? = null
    private var restoredEpisode = 0
    private var resumeTarget = 0L
    private var validatingResume = false
    private var loading = false
    private var started = false
    private var horizontalOrigin = 0L
    private var horizontalTarget = 0L
    private var horizontalDuration = 0L
    private var horizontalDrag = false
    private var scrubbing = false
    private var full = true
    private var fill = false
    private var manualFit = false
    private var quality = 0
    private var offlineOnly = false
    private var currentStream: Stream? = null
    private var controls = true
    private var holdSpeed = false
    private var verticalDrag = false
    private var dragAxis = EpisodeSwipe.Axis.NONE
    private var verticalDelta = 0f
    private lateinit var transitionFrame: ImageView
    private var gestureVelocity: VelocityTracker? = null
    private var job: Job? = null
    private var waitingForAccess = false
    private var accessPageUrl = ""
    private var accessBlocked = false
    private var lastAccessMessage = "Website access was not confirmed."
    private val accessCheck = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        waitingForAccess = false
        if (result.resultCode == RESULT_OK) {
            accessBlocked = false
            if (series == null) loadSeries() else choose(index, resume = true)
        } else showError("Website access was not confirmed. The website may still block this app.", accessRequired = true)
    }
    private val handler = Handler(Looper.getMainLooper())
    private val preferences by lazy { getSharedPreferences("playback", MODE_PRIVATE) }
    private lateinit var seriesUrl: String
    private val library by lazy { DramaLibrary(this) }
    private var lastCheckpoint = 0L
    private val hide = Runnable { if (player?.isPlaying == true && !scrubbing) showControls(false) }
    private val startupTimeout = Runnable {
        if (started && !loading && player?.playbackState == Player.STATE_BUFFERING) {
            player?.stop()
            showError("The video server did not start playback. Tap Retry source to refresh the stream.")
        }
    }
    private val ticker = object : Runnable {
        override fun run() {
            updateProgress()
            maybePreload()
            if (!loading && player?.playbackState == Player.STATE_READY && android.os.SystemClock.elapsedRealtime() - lastCheckpoint >= 5000) checkpoint()
            handler.postDelayed(this, 300)
        }
    }
    private val listener = object : Player.Listener {
        override fun onPlaybackStateChanged(state: Int) {
            spinner.visibility = if (loading || state == Player.STATE_BUFFERING) View.VISIBLE else View.GONE
            if ((state == Player.STATE_READY || state == Player.STATE_ENDED) && !loading && !scrubbing && validatingResume) {
                val total = duration()
                if (total > 0) {
                    validatingResume = false
                    // Old versions stored the end timestamp without an explicit completion flag.
                    if (resumeTarget >= total) {
                        val current = series
                        if (current != null) library.saveProgress(seriesUrl,current.title,current.episodes[index].number,total,total,completed = true)
                        position = 0; player?.seekTo(0); player?.playWhenReady = desiredPlay
                        updateControls(); updateProgress()
                        if (state == Player.STATE_ENDED) return
                    }
                }
            }
            if (state == Player.STATE_READY && !loading) { handler.removeCallbacks(startupTimeout); chrome.showStatus("") }
            if (state == Player.STATE_BUFFERING) engine?.updatePreload(false)
            if (state == Player.STATE_ENDED && !loading && !scrubbing) checkpoint(completed = true)
            if (state == Player.STATE_ENDED && !loading && !scrubbing && player?.playWhenReady == true) {
                val following = EpisodeOrder.next(index, series?.episodes?.size ?: 0)
                if (following != null) choose(following)
                else {
                    desiredPlay = false
                    chrome.showStatus("You’ve reached the final episode.")
                    showControls(true)
                }
            }
            updateControls()
        }
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            if (isPlaying) { window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON); scheduleHide() }
            else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            updateControls()
        }
        override fun onRenderedFirstFrame() {
            seekPreview?.onFrameReady()
            video.animate().alpha(1f).setDuration(120).start()
            if (player?.playWhenReady == true && !scrubbing && !verticalDrag) showControls(false)
        }
        override fun onVideoSizeChanged(videoSize: VideoSize) { updatePipParams() }
        override fun onTracksChanged(tracks: Tracks) { player?.let { QualityOptions.apply(it,quality) } }
        override fun onPlayerError(error: PlaybackException) {
            handler.removeCallbacks(startupTimeout)
            loading = false
            spinner.visibility = View.GONE
            chrome.showStatus("Playback failed (${error.errorCodeName}). Retry to refresh the stream.", retryVisible = true)
            showControls(true)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        seriesUrl = SitePolicy.seriesUrl(intent.getStringExtra("series").orEmpty()) ?: run { finish(); return }
        accessPageUrl = savedInstanceState?.getString("accessPage") ?: seriesUrl
        waitingForAccess = savedInstanceState?.getBoolean("waitingForAccess") ?: false
        accessBlocked = savedInstanceState?.getBoolean("accessBlocked") ?: false
        lastAccessMessage = savedInstanceState?.getString("accessMessage") ?: lastAccessMessage
        position = savedInstanceState?.getLong("position") ?: library.get(seriesUrl)?.position ?: 0
        baseSpeed = savedInstanceState?.getFloat("speed") ?: 1f
        desiredPlay = savedInstanceState?.getBoolean("playing") ?: true
        restoredEpisode = savedInstanceState?.getInt("episodeNumber") ?: 0
        full = savedInstanceState?.getBoolean("full") ?: true
        manualFit = savedInstanceState?.getBoolean("manualFit",false) ?: false
        fill = manualFit && savedInstanceState?.getBoolean("fill",false) == true
        quality = preferences.getInt("quality",0)
        offlineOnly = intent.hasExtra("offline")
        buildUi()
        ContextCompat.registerReceiver(this,pipReceiver,IntentFilter("$packageName.PIP_CONTROL"),ContextCompat.RECEIVER_NOT_EXPORTED)
        pipReceiverRegistered = true
        repository = Repository(BrowserResolver(this, root))
        series = if (offlineOnly) intent.getStringExtra("offline")?.let { OfflineStore.completed(this,it) }?.let { OfflineMetadata.parse(it.request.data).series } else PlaybackHandoff.take(seriesUrl)
        series?.let { initialEpisode(it) }
        setFullscreen(full)
        if (accessBlocked) showError(lastAccessMessage, accessRequired = true, accessUrl = accessPageUrl)
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (requestedOrientation == ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE) {
                    requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                } else finish()
            }
        })
    }

    private fun buildUi() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        root = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        video = (layoutInflater.inflate(R.layout.player_video, root, false) as PlayerView).apply {
            useController = false
            resizeMode = if (fill) AspectRatioFrameLayout.RESIZE_MODE_ZOOM else AspectRatioFrameLayout.RESIZE_MODE_FIT
            setKeepContentOnPlayerReset(true)
            setShowBuffering(PlayerView.SHOW_BUFFERING_NEVER)
            contentDescription = "Video. Tap to show or hide controls. Use the center button to pause or play. Swipe up or down for episodes. Swipe left or right, or use the progress bar, to seek. Hold for 1.5 times speed."
            setOnClickListener { showControls(!chrome.controlsVisible) }
        }
        root.addView(video, FrameLayout.LayoutParams(-1,-1))
        transitionFrame = ImageView(this).apply { scaleType = if (fill) ImageView.ScaleType.CENTER_CROP else ImageView.ScaleType.FIT_CENTER; visibility = View.GONE; setBackgroundColor(Color.BLACK) }
        root.addView(transitionFrame,FrameLayout.LayoutParams(-1,-1))
        chrome = PlayerChrome(this, PlayerChrome.Actions(
            back = { onBackPressedDispatcher.onBackPressed() },
            episodes = { selectEpisode() }, speed = { selectSpeed() },
            rotate = { requestedOrientation = if (resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE)
                ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT else ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE },
            fit = {
                manualFit = true
                fill = !fill
                video.resizeMode = if (fill) AspectRatioFrameLayout.RESIZE_MODE_ZOOM else AspectRatioFrameLayout.RESIZE_MODE_FIT
                transitionFrame.scaleType = if (fill) ImageView.ScaleType.CENTER_CROP else ImageView.ScaleType.FIT_CENTER
            },
            toggle = { togglePlayback() },
            favorite = { toggleFavorite() }, myList = { openMyList() }, removeFavorite = { removeCurrentFavorite() },
            quality = { selectQuality() }, download = { selectDownloads() }, downloads = { suppressPip(); startActivity(Intent(this,DownloadsActivity::class.java)) },
            retry = { choose(index,resume = true,refresh = true) }, pip = { requestPip() }, access = {
                checkpoint(); job?.cancel(); prefetchJob?.cancel(); sources?.clear()
                handler.removeCallbacks(startupTimeout); waitingForAccess = true; player?.pause()
                suppressPip()
                accessCheck.launch(Intent(this,AccessActivity::class.java).putExtra("page",accessPageUrl))
            }
        ))
        root.addView(chrome,FrameLayout.LayoutParams(-1,-1))
        heading = chrome.heading; episodeLabel = chrome.episode; positionLabel = chrome.position
        status = chrome.status; retry = chrome.retry; accessButton = chrome.access; speed = chrome.speed
        spinner = chrome.spinner; seek = chrome.seek
        seek.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onStartTrackingTouch(s: SeekBar) {
                scrubbing = true; handler.removeCallbacks(hide)
                player?.let { p ->
                    seekPreview = VideoScrubber(chrome,p).also {
                        it.start(); it.update(duration() * s.progress / 10_000,duration())
                    }
                }
            }
            override fun onProgressChanged(s: SeekBar,value: Int,fromUser: Boolean) {
                if (fromUser) { val d = duration(); positionLabel.text = "${time(d * value / 10_000)} / ${time(d)}"; chrome.remaining.text = "−${time(d - d * value / 10_000)}"; seekPreview?.update(d * value / 10_000,d) }
            }
            override fun onStopTrackingTouch(s: SeekBar) {
                val d = duration(); val selected = d * s.progress / 10_000
                if (seekPreview != null) seekPreview?.finish(selected) else if (d > 0) player?.seekTo(selected)
                seekPreview = null
                scrubbing = false; checkpoint()
                if (player?.playbackState == Player.STATE_ENDED) listener.onPlaybackStateChanged(Player.STATE_ENDED)
                scheduleHide()
            }
        })
        setContentView(root)
        ViewCompat.setOnApplyWindowInsetsListener(root) { _,insets ->
            val safe = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
            val gestures = insets.getInsets(WindowInsetsCompat.Type.mandatorySystemGestures())
            val bottom = maxOf(safe.bottom,gestures.bottom)
            (video.layoutParams as FrameLayout.LayoutParams).bottomMargin = bottom
            (transitionFrame.layoutParams as FrameLayout.LayoutParams).bottomMargin = bottom
            chrome.applyInsets(safe.left,safe.top,safe.right,bottom); insets
        }
        setupGestures()
    }

    private fun togglePlayback() {
        val p = player ?: return
        if (loading || p.mediaItemCount == 0) { chrome.feedback("Opening episode…"); return }
        if (p.playbackState == Player.STATE_ENDED) { p.seekTo(0); desiredPlay = true }
        else desiredPlay = !p.playWhenReady
        p.playWhenReady = desiredPlay
        showControls(true)
        chrome.feedback(if (desiredPlay) "Playing" else "Paused", persistent = false)
        checkpoint(); updateControls(); scheduleHide()
    }

    private fun setupGestures() {
        val velocity = VelocityTracker.obtain().also { gestureVelocity = it }
        var touchStartX = 0f
        val detector = GestureDetector(this,object : GestureDetector.SimpleOnGestureListener() {
            override fun onDown(e: android.view.MotionEvent): Boolean {
                dragAxis = EpisodeSwipe.Axis.NONE
                verticalDrag = false;horizontalDrag = false;verticalDelta = 0f;return true
            }
            override fun onSingleTapConfirmed(e: android.view.MotionEvent): Boolean { video.performClick();return true }
            override fun onLongPress(e: android.view.MotionEvent) {
                if (dragAxis == EpisodeSwipe.Axis.NONE && !scrubbing && !verticalDrag && !loading && (player?.mediaItemCount ?: 0) > 0) {
                    holdSpeed = true; player?.setPlaybackSpeed(1.5f); chrome.clearFeedback(); showControls(false)
                }
            }
            override fun onScroll(e1: android.view.MotionEvent?,e2: android.view.MotionEvent,dx: Float,dy: Float): Boolean {
                if (e1 == null || holdSpeed) return false
                val x = e2.x - e1.x;val y = e2.y - e1.y
                if (dragAxis == EpisodeSwipe.Axis.NONE) dragAxis = EpisodeSwipe.axis(x,y,dp(20).toFloat())
                if (dragAxis == EpisodeSwipe.Axis.VERTICAL) {
                    verticalDrag = true;verticalDelta = y;handler.removeCallbacks(hide)
                    video.translationY = (y * .2f).coerceIn(-video.height * .2f,video.height * .2f)
                    return true
                }
                if (dragAxis == EpisodeSwipe.Axis.HORIZONTAL) {
                    val p = player ?: return false
                    if (loading || duration() <= 0 || !p.isCurrentMediaItemSeekable) return false
                    if (!horizontalDrag) {
                        horizontalOrigin = p.currentPosition; horizontalDuration = duration()
                        horizontalDrag = true; scrubbing = true; handler.removeCallbacks(hide)
                        showControls(true)
                        seekPreview = VideoScrubber(chrome,p).also { it.start() }
                    }
                    horizontalTarget = ScreenSeek.target(horizontalOrigin,x,video.width,horizontalDuration)
                    previewPosition(horizontalTarget,horizontalDuration)
                    return true
                }
                return false
            }
        })
        video.setOnTouchListener { _,event ->
            if (event.actionMasked == android.view.MotionEvent.ACTION_DOWN) { velocity.clear(); touchStartX = event.x }
            velocity.addMovement(event);detector.onTouchEvent(event)
            if (event.actionMasked == android.view.MotionEvent.ACTION_UP || event.actionMasked == android.view.MotionEvent.ACTION_CANCEL) {
                if (verticalDrag) {
                    velocity.computeCurrentVelocity(1000)
                    val selected = if (event.actionMasked == android.view.MotionEvent.ACTION_UP)
                        EpisodeSwipe.target(index,series?.episodes?.size ?: 0,verticalDelta,video.height,velocity.yVelocity,resources.displayMetrics.density) else null
                    if (selected != null) shiftEpisode(selected,verticalDelta < 0)
                    else video.animate().translationY(0f).setDuration(160).start()
                }
                if (horizontalDrag) {
                    if (event.actionMasked == android.view.MotionEvent.ACTION_UP) {
                        horizontalTarget = ScreenSeek.target(horizontalOrigin,event.x - touchStartX,video.width,horizontalDuration)
                        seekPreview?.finish(horizontalTarget)
                    } else seekPreview?.stop()
                    seekPreview = null; scrubbing = false; horizontalDrag = false
                    checkpoint(); updateProgress()
                    if (player?.playbackState == Player.STATE_ENDED) listener.onPlaybackStateChanged(Player.STATE_ENDED)
                }
                if (holdSpeed) { player?.setPlaybackSpeed(baseSpeed);chrome.clearFeedback() }
                holdSpeed = false;verticalDrag = false;scrubbing = false;dragAxis = EpisodeSwipe.Axis.NONE;scheduleHide()
            };true
        }
    }
    private fun previewPosition(selected: Long, total: Long) {
        seek.progress = if (total > 0) (selected * 10_000 / total).toInt() else 0
        positionLabel.text = "${time(selected)} / ${time(total)}"
        chrome.remaining.text = "−${time((total-selected).coerceAtLeast(0))}"
        seekPreview?.update(selected,total)
    }
    private fun shiftEpisode(selected: Int,up: Boolean) {
        video.animate().cancel();transitionFrame.animate().cancel()
        val bitmap = (video.videoSurfaceView as? TextureView)?.takeIf { it.isAvailable }?.bitmap
        video.translationY = 0f
        if (bitmap != null) {
            transitionFrame.setImageBitmap(bitmap);transitionFrame.translationY = 0f;transitionFrame.visibility = View.VISIBLE
            video.alpha = 0f
            transitionFrame.animate().translationY(if (up) -root.height.toFloat() else root.height.toFloat()).setDuration(220)
                .withEndAction { transitionFrame.visibility = View.GONE; transitionFrame.setImageDrawable(null); transitionFrame.translationY = 0f }.start()
        }
        choose(selected)
    }

    private fun loadSeries() {
        job?.cancel()
        handler.removeCallbacks(startupTimeout)
        job = lifecycleScope.launch {
            accessBlocked = false; accessButton.visibility = View.GONE
            loading = true; spinner.visibility = View.VISIBLE; chrome.showStatus("Loading episodes…")
            try {
                val loaded = repository.series(seriesUrl)
                series = loaded; initialEpisode(loaded)
                // Launch outside this job so its cancellation cannot cancel the new request.
                handler.post { if (started) choose(index, resume = true) }
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) { loading = false; showError(e.message ?: "Could not load the series.", e is SiteAccessException, (e as? SiteAccessException)?.pageUrl) }
        }
    }

    private fun initialEpisode(loaded: Series) {
        heading.text = loaded.title
        SeriesArtwork.remember(this,loaded)
        lifecycleScope.launch { SeriesArtwork.cache(this@PlayerActivity,loaded) }
        val requested = intent.getIntExtra("episode",0)
        val saved = library.get(seriesUrl)
        val number = restoredEpisode.takeIf { it > 0 } ?: requested.takeIf { it > 0 } ?: saved?.episode ?: loaded.episodes.first().number
        val found = loaded.episodes.indexOfFirst { it.number == number }
        index = found.coerceAtLeast(0)
        if (found < 0) position = 0 else if (restoredEpisode == 0) position = library.episodePosition(seriesUrl,loaded.episodes[index].number)
        restoredEpisode = 0
        intent.removeExtra("episode")
        chrome.setFavorite(saved?.favorite == true)
    }

    private fun choose(newIndex: Int, resume: Boolean = false, refresh: Boolean = false) {
        val current = series ?: run { loadSeries(); return }
        if (newIndex !in current.episodes.indices || !started) return
        seekPreview?.stop(); seekPreview = null; scrubbing = false
        checkpoint()
        job?.cancel()
        handler.removeCallbacks(startupTimeout)
        if (!resume) { position = library.episodePosition(seriesUrl,current.episodes[newIndex].number); desiredPlay = true }
        prefetchJob?.cancel(); prefetchJob = null
        sources?.cancelExcept(current.episodes[newIndex].pageUrl)
        prefetchBlocked = false; prefetchRetryAfter = 0L; stagedNext = null
        // Keep prepared next samples until the new source is handed to the player.
        chrome.clearFeedback()
        index = newIndex
        resumeTarget = position
        validatingResume = position > 0
        loading = true; currentStream = null
        player?.stop(); player?.clearMediaItems()
        accessBlocked = false
        loading = true; holdSpeed = false; scrubbing = false
        chrome.showStatus("Opening episode ${current.episodes[index].number}…")
        spinner.visibility = View.VISIBLE; showControls(true); updateControls()
        job = lifecycleScope.launch {
            try {
                val downloaded = OfflineStore.completed(this@PlayerActivity,current.episodes[newIndex].pageUrl)
                if (downloaded != null) {
                    loading = false; currentStream = null; chrome.showStatus("")
                    checkNotNull(engine).playOffline(downloaded.request,position)
                    player?.setPlaybackSpeed(baseSpeed); player?.playWhenReady = desiredPlay
                    updateControls(); return@launch
                }
                check(!offlineOnly) { "This episode is not downloaded. Choose a saved episode or return to Downloads." }
                val stream = withTimeout(35_000) { checkNotNull(sources).get(current.episodes[newIndex],refresh) }
                currentStream = stream
                val p = player ?: return@launch
                loading = false; chrome.showStatus("")
                checkNotNull(engine).play(current,newIndex,stream,position)
                p.setPlaybackSpeed(baseSpeed); p.playWhenReady = desiredPlay
                handler.postDelayed(startupTimeout, 35_000)
                updateControls()
            } catch (_: TimeoutCancellationException) {
                loading = false; showError("Opening the episode timed out. Tap Retry source.")
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) { loading = false; showError(e.message ?: "Could not open the episode.", e is SiteAccessException, (e as? SiteAccessException)?.pageUrl) }
        }
    }

    private fun showError(message: String, accessRequired: Boolean = false, accessUrl: String? = null) {
        if (accessUrl != null) accessPageUrl = accessUrl
        accessBlocked = accessRequired
        if (accessRequired) lastAccessMessage = message
        transitionFrame.animate().cancel(); transitionFrame.visibility = View.GONE; transitionFrame.setImageDrawable(null); video.translationY = 0f; video.alpha = 1f
        spinner.visibility = View.GONE; chrome.showStatus(message,retryVisible = !accessRequired,accessVisible = accessRequired)
        heading.text = series?.title ?: if (accessRequired) "Website access blocked" else "Story unavailable"
        retry.visibility = if (accessRequired) View.GONE else View.VISIBLE
        accessButton.visibility = if (accessRequired) View.VISIBLE else View.GONE
        showControls(true); updateControls()
    }
    private fun duration(): Long = (player?.duration ?: 0).takeIf { it > 0 && it != C.TIME_UNSET } ?: 0
    private fun updateProgress() {
        val p = player ?: return
        val d = duration()
        seek.isEnabled = !loading && d > 0 && p.isCurrentMediaItemSeekable
        if (!scrubbing) {
            val current = p.currentPosition.coerceAtLeast(0)
            seek.progress = if (d > 0) (current * 10_000 / d).toInt() else 0
            seek.secondaryProgress = if (d > 0) (p.bufferedPosition * 10_000 / d).toInt() else 0
            positionLabel.text = if (d > 0) "${time(current)} / ${time(d)}" else "${time(current)} / --:--"
            chrome.remaining.text = if (d > 0) "−${time((d - current).coerceAtLeast(0))}" else ""
        }
    }
    private fun updateControls() {
        val current = series
        chrome.setPlayback(player?.playWhenReady == true && player?.playbackState != Player.STATE_ENDED,
            !loading && player?.mediaItemCount != 0 && player != null)
        speed.text = "Speed"; speed.contentDescription = "Playback speed ${baseSpeed} times"
        if (current != null) {
            val playing = current.episodes.getOrNull(index)
            if (playing != null) chrome.setEpisode(playing.number,current.episodes.size)
        }
        updatePipParams()
    }
    private fun maybePreload() {
        val current = series ?: return
        val p = player ?: return
        if (!started || loading || waitingForAccess || accessBlocked || prefetchBlocked || offlineOnly || currentStream == null) return
        val following = EpisodeOrder.next(index,current.episodes.size) ?: return
        val ahead = p.bufferedPosition - p.currentPosition
        val nearEnd = duration() > 0 && duration() - p.currentPosition < 15_000
        val ready = p.playbackState == Player.STATE_READY
        engine?.updatePreload(ready && (ahead >= 8_000 || nearEnd))
        if (!ready || (ahead < 3_000 && !nearEnd) || prefetchJob?.isActive == true || android.os.SystemClock.elapsedRealtime() < prefetchRetryAfter) return
        val episode = current.episodes[following]
        val cached = sources?.peek(episode)
        if (cached != null && stagedNext == (episode.pageUrl to cached.url)) return
        prefetchJob = lifecycleScope.launch(start = CoroutineStart.LAZY) {
            try {
                val stream = withTimeout(35_000) { checkNotNull(sources).get(episode) }
                if (started && !loading && index + 1 == following) {
                    engine?.stageNext(current,following,stream); stagedNext = episode.pageUrl to stream.url
                }
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) {
                prefetchRetryAfter = android.os.SystemClock.elapsedRealtime() + 15_000
                if (e is SiteAccessException) prefetchBlocked = true
            } finally { prefetchJob = null }
        }
        prefetchJob?.start()
    }

    private fun toggleFavorite() {
        val current = series ?: return
        checkpoint()
        chrome.setFavorite(library.toggleFavorite(seriesUrl, current.title))
        scheduleHide()
    }
    private fun removeCurrentFavorite() {
        if (series == null) return
        checkpoint(); library.removeFavorite(seriesUrl); chrome.setFavorite(false); scheduleHide()
    }
    private fun openMyList() {
        checkpoint(); handler.removeCallbacks(hide)
        val dialog = showMyList(this, library, onFavoritesChanged = { chrome.setFavorite(library.get(seriesUrl)?.favorite == true) }) { item ->
            if (item.url != seriesUrl) {
                checkpoint(); player?.pause(); suppressPip()
                startActivity(Intent(this, PlayerActivity::class.java).putExtra("series", item.url))
                finish()
            }
        }
        polishDialog(dialog); immersiveDialog(dialog)
        dialog.setOnDismissListener { setFullscreen(full); scheduleHide() }
    }

    private fun selectEpisode() {
        val current = series ?: return
        handler.removeCallbacks(hide)
        val dialog = episodeSheet(this,current,index,onEpisode = { if (it != index) shiftEpisode(it,it > index) })
        dialog.setOnDismissListener { setFullscreen(full); scheduleHide() }
    }
    private fun selectQuality() {
        val p = player ?: return
        handler.removeCallbacks(hide)
        qualitySheet(this,p,quality) { pixels ->
            quality = pixels; preferences.edit().putInt("quality",pixels).apply()
            QualityOptions.apply(p,pixels)
        }.setOnDismissListener { setFullscreen(full); scheduleHide() }
    }
    private fun selectDownloads() {
        val current = series ?: return
        handler.removeCallbacks(hide)
        var downloadQuality = preferences.getInt("downloadQuality",quality)
        val options = player?.let { QualityOptions.available(it.currentTracks).map { value -> value.pixels } } ?: emptyList()
        val dialog = episodeSheet(this,current,index,downloadMode = true,downloadQuality = downloadQuality,
            downloadQualities = options,onDownloadQuality = { downloadQuality = it; preferences.edit().putInt("downloadQuality",it).apply() },onDownload = { selected ->
            if (android.os.Build.VERSION.SDK_INT >= 33 && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)
                requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),42)
            OfflineStore.setPaused(this,false)
            OfflineStore.queue(this,current,selected,downloadQuality)
            EpisodePreparationService.start(this)
            Toast.makeText(this,"Episodes queued. Open Downloads for progress.",Toast.LENGTH_LONG).show()
        })
        dialog.setOnDismissListener { setFullscreen(full); scheduleHide() }
    }
    private fun selectSpeed() {
        val choices = floatArrayOf(.5f, .75f, 1f, 1.25f, 1.5f, 1.75f, 2f)
        val dialog = AlertDialog.Builder(this).setTitle("Playback speed").setSingleChoiceItems(
            choices.map { "${it}×" }.toTypedArray(), choices.indexOfFirst { it == baseSpeed }
        ) { dialog, selected ->
            baseSpeed = choices[selected]; player?.setPlaybackSpeed(baseSpeed); updateControls(); dialog.dismiss()
        }.setNegativeButton("Close", null).show()
        polishDialog(dialog); immersiveDialog(dialog)
    }
    private fun showControls(visible: Boolean) {
        controls = visible && !holdSpeed
        chrome.showControls(controls && !isInPictureInPictureMode)
        syncSystemBars()
        if (controls) scheduleHide() else handler.removeCallbacks(hide)
    }
    private fun scheduleHide() { handler.removeCallbacks(hide); if (!scrubbing && !holdSpeed && chrome.controlsVisible) handler.postDelayed(hide, 3000) }
    private fun setFullscreen(enabled: Boolean) {
        full = enabled
        if (android.os.Build.VERSION.SDK_INT >= 28) {
            window.attributes = window.attributes.apply {
                layoutInDisplayCutoutMode = if (android.os.Build.VERSION.SDK_INT >= 30)
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
                else WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
        syncSystemBars()
    }
    private fun syncSystemBars() {
        if (!::root.isInitialized) return
        val visible = controls && !holdSpeed && !isInPictureInPictureMode
        if (visible) window.clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
        else window.addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
        WindowCompat.getInsetsController(window, root).apply {
            isAppearanceLightStatusBars = false
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_DEFAULT
            if (visible) show(WindowInsetsCompat.Type.statusBars()) else hide(WindowInsetsCompat.Type.statusBars())
            if (isInPictureInPictureMode) hide(WindowInsetsCompat.Type.navigationBars()) else show(WindowInsetsCompat.Type.navigationBars())
        }
    }
    private fun immersiveDialog(dialog: AlertDialog) {
        if (!full || isInPictureInPictureMode) return
        dialog.window?.let { w ->
            w.clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
            WindowCompat.getInsetsController(w,w.decorView).apply {
                systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_DEFAULT
                show(WindowInsetsCompat.Type.systemBars())
            }
        }
    }
    override fun onResume() {
        super.onResume()
        pipSuppressed = false; updatePipParams()
        if (::root.isInitialized && !isInPictureInPictureMode) setFullscreen(full)
    }
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && ::root.isInitialized && !isInPictureInPictureMode) setFullscreen(full)
    }
    private fun canAutoPip(): Boolean = !pipSuppressed && !isFinishing && !loading && !waitingForAccess && (player?.isPlaying == true || (player?.playWhenReady == true && player?.playbackState == Player.STATE_BUFFERING)) &&
        packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    private fun pipParams(): PictureInPictureParams {
        val size = player?.videoSize
        val ratio = if (size != null && size.width > 0 && size.height > 0) {
            val raw = size.width.toFloat() * size.pixelWidthHeightRatio / size.height
            Rational((raw.coerceIn(1f / 2.39f,2.39f) * 1000).toInt(),1000)
        } else Rational(9,16)
        val builder = PictureInPictureParams.Builder().setAspectRatio(ratio).setActions(pipActions())
        if (::video.isInitialized) {
            val bounds = android.graphics.Rect()
            if (video.getGlobalVisibleRect(bounds)) builder.setSourceRectHint(bounds)
        }
        if (android.os.Build.VERSION.SDK_INT >= 31) builder.setAutoEnterEnabled(canAutoPip()).setSeamlessResizeEnabled(true)
        return builder.build()
    }
    private fun pipActions(): List<RemoteAction> {
        val p = player
        val ready = !loading && p != null && p.mediaItemCount > 0
        fun action(command: String, title: String, drawable: Int, enabled: Boolean): RemoteAction {
            val intent = Intent("$packageName.PIP_CONTROL").setPackage(packageName).putExtra("command",command)
            val pending = PendingIntent.getBroadcast(this,when(command) { "back" -> 71; "toggle" -> 72; else -> 73 },intent,PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            return RemoteAction(Icon.createWithResource(this,drawable),title,title,pending).apply { isEnabled = enabled }
        }
        return listOf(action("back","Rewind 10 seconds",android.R.drawable.ic_media_rew,ready && p?.isCurrentMediaItemSeekable == true),
            action("toggle",if (p?.playWhenReady == true) "Pause" else "Play",if (p?.playWhenReady == true) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,ready),
            action("forward","Forward 10 seconds",android.R.drawable.ic_media_ff,ready && p?.isCurrentMediaItemSeekable == true))
    }
    private fun handlePipAction(command: String) {
        val p = player ?: return
        if (loading || p.mediaItemCount == 0) return
        when (command) {
            "toggle" -> togglePlayback()
            "back", "forward" -> if (p.isCurrentMediaItemSeekable) {
                p.seekTo((p.currentPosition + if (command == "back") -10_000 else 10_000).coerceIn(0,duration().takeIf { it > 0 } ?: Long.MAX_VALUE))
                checkpoint(); updateControls()
            }
        }
    }
    /** The progress ticker calls this ten times a second; only real state changes need an IPC update. */
    private fun pipStateSignature(): String {
        val size = player?.videoSize
        return listOf(
            canAutoPip(),isInPictureInPictureMode,loading,
            player?.playWhenReady == true,player?.mediaItemCount ?: 0,
            player?.isCurrentMediaItemSeekable == true,
            size?.width ?: 0,size?.height ?: 0,size?.pixelWidthHeightRatio ?: 0f
        ).joinToString("|")
    }
    private fun updatePipParams() {
        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) return
        val signature = pipStateSignature()
        if (signature == pipSignature) return
        pipSignature = signature
        runCatching { setPictureInPictureParams(pipParams()) }
    }
    private fun requestPip() {
        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) {
            chrome.feedback("Picture in picture is not available on this device");return
        }
        seekPreview?.stop(); seekPreview = null; scrubbing = false
        runCatching { enterPictureInPictureMode(pipParams()) }
            .onFailure { chrome.feedback("Picture in picture is unavailable right now") }
    }
    private fun suppressPip() { pipSuppressed = true; updatePipParams() }
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        seekPreview?.stop(); seekPreview = null; scrubbing = false; checkpoint()
        if (android.os.Build.VERSION.SDK_INT < 31 && canAutoPip()) runCatching { enterPictureInPictureMode(pipParams()) }
    }
    override fun finish() { if (::chrome.isInitialized) suppressPip(); super.finish() }
    override fun onPictureInPictureModeChanged(inPip: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(inPip, newConfig); if (inPip) { seekPreview?.stop(); seekPreview = null; scrubbing = false }; chrome.pip(inPip); showControls(!inPip)
        if (!inPip) setFullscreen(full)
    }
    private fun checkpoint() = checkpoint(false)
    private fun checkpoint(completed: Boolean) {
        val current = series ?: return
        // A refreshed series can briefly disagree with the selected index; never index past its list.
        val episode = current.episodes.getOrNull(index) ?: return
        if (loading || scrubbing || player == null || player?.mediaItemCount == 0) return
        player?.takeIf { it.mediaItemCount > 0 }?.let {
            position = it.currentPosition.coerceAtLeast(0)
            if (!waitingForAccess) desiredPlay = it.playWhenReady
        }
        preferences.edit().putInt("episode:$seriesUrl", episode.number)
            .putLong("position:$seriesUrl", position).apply()
        library.saveProgress(seriesUrl, current.title, episode.number, position,duration(),completed || player?.playbackState == Player.STATE_ENDED)
        lastCheckpoint = android.os.SystemClock.elapsedRealtime()
    }
    override fun onStart() {
        super.onStart()
        if (!::repository.isInitialized) return
        started = true
        engine = PlaybackEngine(this)
        player = engine!!.player.apply {
            setAudioAttributes(AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(),true)
            setHandleAudioBecomingNoisy(true); addListener(listener)
        }
        sources = SessionStreams(lifecycleScope,{ android.os.SystemClock.elapsedRealtime() },repository::stream)
        video.player = player
        handler.post(ticker)
        if (!waitingForAccess && !accessBlocked) { if (series == null) loadSeries() else choose(index, resume = true) }
    }
    override fun onStop() {
        started = false; seekPreview?.stop(); seekPreview = null; scrubbing = false; checkpoint(); job?.cancel(); handler.removeCallbacks(ticker); handler.removeCallbacks(hide)
        handler.removeCallbacks(startupTimeout)
        if (::video.isInitialized) { video.player = null;video.animate().cancel();video.translationY = 0f;video.alpha = 1f }
        if (::transitionFrame.isInitialized) { transitionFrame.animate().cancel();transitionFrame.setImageDrawable(null);transitionFrame.visibility = View.GONE }
        prefetchJob?.cancel(); prefetchJob = null; sources?.clear(); sources = null
        player?.removeListener(listener); engine?.release(); engine = null; player = null
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        super.onStop()
    }
    override fun onSaveInstanceState(outState: Bundle) {
        checkpoint()
        outState.putBoolean("accessBlocked", accessBlocked); outState.putString("accessMessage", lastAccessMessage)
        outState.putString("accessPage", accessPageUrl); outState.putBoolean("waitingForAccess", waitingForAccess)
        outState.putInt("episodeNumber",series?.episodes?.getOrNull(index)?.number ?: 0)
        outState.putLong("position", position); outState.putFloat("speed", baseSpeed)
        outState.putBoolean("playing", desiredPlay); outState.putBoolean("full", full); outState.putBoolean("fill",fill); outState.putBoolean("manualFit",manualFit)
        super.onSaveInstanceState(outState)
    }
    override fun onDestroy() { if (pipReceiverRegistered) { unregisterReceiver(pipReceiver); pipReceiverRegistered = false }; seekPreview?.stop(); seekPreview = null; handler.removeCallbacksAndMessages(null); gestureVelocity?.recycle(); gestureVelocity = null; super.onDestroy() }
}
