package com.waqas.hdrama

import android.annotation.SuppressLint
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.content.res.ColorStateList
import android.net.http.SslError
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.webkit.*
import android.widget.*
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import org.json.JSONObject
import org.json.JSONTokener
import java.io.ByteArrayInputStream

/** Full-height single-site browser with an explicit, compact native-play action. */
class MainActivity : ComponentActivity() {
    private lateinit var web: WebView
    private lateinit var nativePlay: ImageButton
    private lateinit var progress: ProgressBar
    private lateinit var myList: ImageButton
    private lateinit var downloads: ImageButton
    private lateinit var history: ImageButton
    private lateinit var refreshRoot: PullRefreshLayout
    private var keyboardVisible = false
    private var bottomSafe = 0
    private var footerHeight = 0
    private var viewportHeight = 0.0
    private lateinit var actionRow: LinearLayout
    private val library by lazy { DramaLibrary(this) }
    private var target: PlaybackTarget? = null
    private var validatedSeries: Series? = null
    private var currentPage = ""
    private var inspectionEpoch = 0
    private var inspecting = false
    private var inspectingEpoch = -1
    private var injectedDockCss = ""
    private var validatedPage = ""
    private var launchRequested = false
    private var active = false
    private var restoreScroll: Pair<Int,Int>? = null
    private val handler = Handler(Looper.getMainLooper())
    private val monitor = object : Runnable {
        override fun run() { inspectPage(); if (active) handler.postDelayed(this,1200) }
    }
    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window,false)
        window.statusBarColor = AppColors.background
        window.navigationBarColor = Color.BLACK
        WindowCompat.getInsetsController(window,window.decorView).apply {
            isAppearanceLightStatusBars = false
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            show(WindowInsetsCompat.Type.statusBars());hide(WindowInsetsCompat.Type.navigationBars())
        }
        val root = PullRefreshLayout(this).apply { setBackgroundColor(AppColors.background) }; refreshRoot = root
        web = WebView(this).apply {
            setBackgroundColor(AppColors.background)
            settings.apply {
                javaScriptEnabled = true;domStorageEnabled = true
                allowFileAccess = false;allowContentAccess = false
                javaScriptCanOpenWindowsAutomatically = false;setSupportMultipleWindows(true)
                mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
                mediaPlaybackRequiresUserGesture = true
                builtInZoomControls = false;displayZoomControls = false
                useWideViewPort = true;loadWithOverviewMode = true
            }
        }
        CookieManager.getInstance().setAcceptThirdPartyCookies(web,false)
        progress = ProgressBar(this,null,android.R.attr.progressBarStyleHorizontal).apply {
            max = 100;progressTintList = ColorStateList.valueOf(accent)
        }
        nativePlay = ImageButton(this).apply {
            setImageDrawable(PlayerIcon("play"));scaleType = ImageView.ScaleType.FIT_CENTER
            setPadding(dp(16),dp(16),dp(16),dp(16))
            background = RippleDrawable(ColorStateList.valueOf(0x40ffffff),GradientDrawable().apply {
                cornerRadius = dp(14).toFloat(); setColor(accent);setStroke(dp(1),accent)
            },null)
            imageTintList = ColorStateList.valueOf(AppColors.background); elevation = dp(2).toFloat();contentDescription = "Play in native player"
            visibility = View.GONE;setOnClickListener { launchPlayer() }
        }
        myList = ImageButton(this).apply {
            setImageDrawable(PlayerIcon("list")); scaleType = ImageView.ScaleType.FIT_CENTER
            setPadding(dp(16),dp(16),dp(16),dp(16)); background = surface(AppColors.raised,14,true)
            elevation = dp(2).toFloat(); contentDescription = "My List"
            setOnClickListener {
                showMyList(this@MainActivity,library) { item ->
                    web.evaluateJavascript(BrowserScripts.pauseVideo,null); CookieManager.getInstance().flush()
                    startActivity(Intent(this@MainActivity,PlayerActivity::class.java).putExtra("series",item.url))
                }
            }
        }
        downloads = ImageButton(this).apply {
            setImageDrawable(PlayerIcon("downloads")); setPadding(dp(16),dp(16),dp(16),dp(16))
            background = surface(AppColors.raised,14,true)
            contentDescription = "Downloads"; elevation = dp(2).toFloat()
            setOnClickListener { startActivity(Intent(this@MainActivity,DownloadsActivity::class.java)) }
        }
        history = ImageButton(this).apply {
            setImageDrawable(PlayerIcon("history")); setPadding(dp(16),dp(16),dp(16),dp(16))
            background = surface(AppColors.raised,14,true)
            contentDescription = "History"; elevation = dp(2).toFloat()
            setOnClickListener { startActivity(Intent(this@MainActivity,HistoryActivity::class.java)) }
        }
        root.addView(web,FrameLayout.LayoutParams(-1,-1))
        root.addView(progress,FrameLayout.LayoutParams(-1,dp(2),Gravity.TOP))
        actionRow = BrowserDock(this).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER
            setPadding(dp(8),dp(6),dp(8),dp(6))
            background = GradientDrawable().apply { setColor(AppColors.overlay); cornerRadius = dp(20).toFloat(); setStroke(dp(1),AppColors.stroke) }
            listOf(myList,downloads,history,nativePlay).forEachIndexed { i,button ->
                val cell = LinearLayout(this@MainActivity).apply {
                    orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER
                    addView(button,LinearLayout.LayoutParams(dp(64),dp(64)))
                    addView(label(listOf("My List","Download","History","Play")[i],11f).apply { gravity = Gravity.CENTER; maxLines = 1; ellipsize = android.text.TextUtils.TruncateAt.END; setPadding(0,dp(5),0,0) })
                }
                addView(cell,LinearLayout.LayoutParams(0,-2,1f))
            }
        }
        root.addView(actionRow,FrameLayout.LayoutParams(-1,-2,Gravity.CENTER_HORIZONTAL or Gravity.BOTTOM).apply { bottomMargin = dp(60); marginStart = dp(12); marginEnd = dp(12) })
        val pullHint = label("Pull to refresh",12f).apply {
            gravity = Gravity.CENTER; rounded(0xee211e31.toInt()); visibility = View.GONE
        }
        root.addView(pullHint,FrameLayout.LayoutParams(dp(180),dp(40),Gravity.TOP or Gravity.CENTER_HORIZONTAL).apply { topMargin = dp(12) })
        root.canRefresh = { e -> !keyboardVisible && !web.canScrollVertically(-1) && SitePolicy.siteUrl(web.url.orEmpty()) && e.y < actionRow.top }
        root.onPull = { amount ->
            pullHint.visibility = if (amount > 0) View.VISIBLE else View.GONE
            pullHint.text = if (amount >= 1f) "Release to refresh" else "Pull to refresh"
        }
        root.refresh = { target = null; validatedPage = ""; setPlayVisible(false); web.reload() }
        setPlayVisible(false)
        setContentView(root)
        ViewCompat.setOnApplyWindowInsetsListener(root) { v,insets ->
            val safe = insets.getInsets(WindowInsetsCompat.Type.statusBars() or WindowInsetsCompat.Type.displayCutout())
            val keyboard = insets.getInsets(WindowInsetsCompat.Type.ime())
            keyboardVisible = insets.isVisible(WindowInsetsCompat.Type.ime()) || keyboard.bottom > 0
            actionRow.visibility = if (keyboardVisible) View.GONE else View.VISIBLE
            v.setPadding(safe.left,safe.top,safe.right,keyboard.bottom)
            val navigation = insets.getInsets(WindowInsetsCompat.Type.navigationBars())
            val gestures = insets.getInsets(WindowInsetsCompat.Type.mandatorySystemGestures())
            bottomSafe = maxOf(navigation.bottom,gestures.bottom)
            dockActions()
            WindowInsetsCompat.CONSUMED
        }
        web.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView,value: Int) {
                progress.progress = value;progress.visibility = if (value >= 100) View.GONE else View.VISIBLE
                if (value >= 100) refreshRoot.complete()
            }
            override fun onCreateWindow(v: WebView?,d: Boolean,gesture: Boolean,result: android.os.Message?) = false
            override fun onPermissionRequest(request: PermissionRequest) { request.deny() }
            override fun onJsAlert(v: WebView?,u: String?,m: String?,r: JsResult?): Boolean { r?.cancel();return true }
            override fun onJsConfirm(v: WebView?,u: String?,m: String?,r: JsResult?): Boolean { r?.cancel();return true }
            override fun onJsPrompt(v: WebView?,u: String?,m: String?,d: String?,r: JsPromptResult?): Boolean { r?.cancel();return true }
            override fun onShowCustomView(view: View?,callback: CustomViewCallback?) { callback?.onCustomViewHidden() }
        }
        web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView,request: WebResourceRequest): Boolean {
                val url = request.url.toString()
                if (url == "hdrama-native://play" && SitePolicy.siteUrl(view.url.orEmpty())) {
                    if (request.isForMainFrame && request.hasGesture()) {
                        if (target != null && validatedPage == view.url) launchPlayer()
                        else { launchRequested = true;inspectPage() }
                    };return true
                }
                if (!request.isForMainFrame) return !SitePolicy.verificationResource(url)
                return !SitePolicy.siteUrl(url)
            }
            override fun shouldInterceptRequest(view: WebView,request: WebResourceRequest): WebResourceResponse? {
                val headers = request.requestHeaders
                val accept = headers.entries.firstOrNull { it.key.equals("Accept",true) }?.value.orEmpty()
                val dest = headers.entries.firstOrNull { it.key.equals("Sec-Fetch-Dest",true) }?.value.orEmpty()
                val image = dest.equals("image",true) || accept.contains("image/",true) || (dest.isEmpty() && accept.isEmpty())
                return if (BrowserPolicy.allowResource(request.url.toString(),image)) null
                else WebResourceResponse("text/plain","utf-8",200,"OK",mapOf("Cache-Control" to "no-store"),ByteArrayInputStream(ByteArray(0)))
            }
            override fun onPageStarted(view: WebView,url: String?,favicon: android.graphics.Bitmap?) {
                inspectionEpoch++; inspecting = false; inspectingEpoch = -1; injectedDockCss = ""
                validatedPage = "";target = null;validatedSeries = null;setPlayVisible(false)
                pageChanged(url.orEmpty());progress.visibility = View.VISIBLE
            }
            override fun doUpdateVisitedHistory(view: WebView,url: String?,isReload: Boolean) { pageChanged(url.orEmpty());if (active) inspectPage() }
            override fun onPageCommitVisible(view: WebView,url: String?) { installCleanup();inspectPage() }
            override fun onPageFinished(view: WebView,url: String?) {
                refreshRoot.complete();installCleanup();inspectPage()
                restoreScroll?.let { (x,y) -> web.scrollTo(x,y);restoreScroll = null }
            }
            override fun onReceivedHttpError(view: WebView,request: WebResourceRequest,response: WebResourceResponse) {
                if (request.isForMainFrame) { target = null;setPlayVisible(false);refreshRoot.complete() }
            }
            override fun onReceivedError(view: WebView,request: WebResourceRequest,error: WebResourceError) {
                if (request.isForMainFrame) {
                    target = null;setPlayVisible(false);progress.visibility = View.GONE;refreshRoot.complete()
                    Toast.makeText(this@MainActivity,"Website could not load. Check your connection.",Toast.LENGTH_LONG).show()
                }
            }
            override fun onReceivedSslError(view: WebView,handler: SslErrorHandler,error: SslError) {
                handler.cancel();target = null;setPlayVisible(false);refreshRoot.complete()
                Toast.makeText(this@MainActivity,"Invalid website certificate.",Toast.LENGTH_LONG).show()
            }
            override fun onRenderProcessGone(view: WebView,detail: RenderProcessGoneDetail): Boolean {
                // Rebuild this screen instead of closing the whole app when the web renderer dies.
                handler.removeCallbacksAndMessages(null);inspecting = false;inspectingEpoch = -1;active = false
                recreate();return true
            }
        }
        onBackPressedDispatcher.addCallback(this,object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() { if (web.canGoBack()) web.goBack() else finish() }
        })
        val state = savedInstanceState?.getBundle("browser")
        if (state != null && web.restoreState(state) != null) {
            restoreScroll = ((savedInstanceState?.getInt("scrollX") ?: 0) to (savedInstanceState?.getInt("scrollY") ?: 0));currentPage = web.url.orEmpty()
        } else web.loadUrl(intent.dataString?.takeIf(SitePolicy::siteUrl) ?: SitePolicy.HOME)
    }
    private fun pageChanged(url: String) {
        if (url != currentPage) {
            inspectionEpoch++; inspecting = false; inspectingEpoch = -1; injectedDockCss = ""
            currentPage = url;footerHeight = 0;viewportHeight = 0.0;dockActions();target = null;validatedSeries = null;validatedPage = "";launchRequested = false
            setPlayVisible(false)
        }
    }
    private fun installCleanup() { if (SitePolicy.siteUrl(web.url.orEmpty())) web.evaluateJavascript(BrowserScripts.install,null) }
    private fun inspectPage() {
        if (!active || inspecting || !SitePolicy.siteUrl(web.url.orEmpty())) return
        inspecting = true
        val epoch = inspectionEpoch
        inspectingEpoch = epoch
        web.evaluateJavascript(BrowserScripts.inspect.replace("__KNOWN_PAGE__",JSONObject.quote(validatedPage))) { json ->
            // Release the guard only for the inspection that is still current, and always release it
            // even when the result arrives while the app is in the background.
            if (epoch == inspectingEpoch) inspecting = false
            if (epoch != inspectionEpoch) return@evaluateJavascript
            if (!active || isFinishing) return@evaluateJavascript
            val data = runCatching { JSONObject(JSONTokener(json).nextValue() as String) }.getOrNull() ?: return@evaluateJavascript
            acceptSnapshot(data)
        }
    }
    private fun acceptSnapshot(data: JSONObject) {
        val url = data.optString("url")
        if (!SitePolicy.siteUrl(url) || web.url != url) return
        pageChanged(url)
        val measuredFooter = data.optDouble("footerHeight",0.0)
        val measuredViewport = data.optDouble("viewportHeight",0.0)
        if (measuredFooter.isFinite() && measuredViewport.isFinite() && measuredViewport > 0 && web.height > 0 && !keyboardVisible) {
            footerHeight = (measuredFooter.coerceIn(0.0,measuredViewport * .3) * web.height / measuredViewport).toInt()
            viewportHeight = measuredViewport; dockActions()
        }
        val html = data.optString("html")
        if (data.optBoolean("blocked") || SiteParser.blocked(html)) { target = null;setPlayVisible(false);launchRequested = false;return }
        if (html.isNotEmpty() || validatedPage != url) {
            val candidate = BrowserPolicy.playback(url)
            val parsed = candidate?.let { runCatching { SiteParser.series(html,url) }.getOrNull() }
            target = candidate.takeIf { parsed != null };validatedSeries = parsed
            if (target != null) validatedPage = url
        }
        setPlayVisible(target != null)
        if (target != null) {
            nativePlay.contentDescription = "Play ${validatedSeries?.title.orEmpty()} in native player"
            installCleanup()
            if (launchRequested) { launchRequested = false;launchPlayer() }
        }
    }
    private fun setPlayVisible(visible: Boolean) {
        nativePlay.visibility = if (visible) View.VISIBLE else View.GONE
        (nativePlay.parent as? View)?.visibility = if (visible) View.VISIBLE else View.GONE
    }
    private fun dockActions() {
        if (keyboardVisible) return
        val footer = if (viewportHeight > 0) footerHeight else dp(56)
        (actionRow.layoutParams as FrameLayout.LayoutParams).bottomMargin = footer + bottomSafe + dp(4)
        // Reserve scrollable space for the native dock so the final page cards remain reachable.
        if (SitePolicy.siteUrl(web.url.orEmpty())) {
            val density = if (viewportHeight > 0 && web.height > 0) web.height / viewportHeight else resources.displayMetrics.density.toDouble()
            val space = ((actionRow.height.takeIf { it > 0 } ?: dp(94)) + footer + bottomSafe + dp(12)) / density
            val css = "body{padding-bottom:${space.toInt()}px!important}"
            // Re-inject only when the injected rule actually changes; insets callbacks are frequent.
            if (css != injectedDockCss) {
                injectedDockCss = css
                web.evaluateJavascript("(() => { let s=document.getElementById('native-dock-space'); if(!s){s=document.createElement('style');s.id='native-dock-space';(document.head||document.documentElement).appendChild(s);} const css='$css';if(s.textContent!==css)s.textContent=css; })()",null)
            }
        }
    }
    private fun launchPlayer() {
        val current = target ?: return
        if (!SitePolicy.siteUrl(web.url.orEmpty()) || validatedPage != web.url) return
        validatedSeries?.let(PlaybackHandoff::offer)
        web.evaluateJavascript(BrowserScripts.pauseVideo,null);CookieManager.getInstance().flush()
        startActivity(Intent(this,PlayerActivity::class.java).putExtra("series",current.seriesUrl).putExtra("episode",current.episode))
    }
    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent);setIntent(intent);intent.dataString?.takeIf(SitePolicy::siteUrl)?.let(web::loadUrl) }
    override fun onResume() { super.onResume();active = true;if (::web.isInitialized) { web.onResume();handler.post(monitor) } }
    override fun onPause() { active = false;handler.removeCallbacks(monitor);if (::web.isInitialized) { web.evaluateJavascript(BrowserScripts.pauseVideo,null);web.onPause() };super.onPause() }
    override fun onSaveInstanceState(out: Bundle) {
        if (::web.isInitialized) { out.putBundle("browser",Bundle().also { web.saveState(it) });out.putInt("scrollX",web.scrollX);out.putInt("scrollY",web.scrollY) };super.onSaveInstanceState(out)
    }
    override fun onDestroy() { handler.removeCallbacksAndMessages(null);if (::web.isInitialized) { web.stopLoading();(web.parent as? android.view.ViewGroup)?.removeView(web);web.destroy() };super.onDestroy() }
}
