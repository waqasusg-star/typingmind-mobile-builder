package com.waqas.hdrama

import android.annotation.SuppressLint
import android.content.Context
import android.net.http.SslError
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.webkit.*
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import org.json.JSONTokener
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.IOException
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** Resolves the site's normal public player initialization; playback stays in ExoPlayer.
 * No JS bridge, popup windows, third-party scripts, external navigation or SSL overrides.
 * Does not solve challenges, decrypt DRM, or bypass login/access restrictions.
 */
class BrowserResolver(private val activity: Context, private val host: ViewGroup) {
    val userAgent: String = WebSettings.getDefaultUserAgent(activity)
    suspend fun page(url: String): String = run(url, false)
    suspend fun stream(url: String): Stream {
        val result = JSONObject(run(url, true))
        return Stream(result.getString("url"), url, userAgent, StreamPolicy.mime(result.optString("mimeType")))
    }

    // This invisible resolver is deliberately excluded from accessibility and consumes touches.
    @SuppressLint("SetJavaScriptEnabled", "ClickableViewAccessibility")
    private suspend fun run(url: String, media: Boolean): String = withContext(Dispatchers.Main.immediate) {
        require(SitePolicy.siteUrl(url))
        suspendCancellableCoroutine { continuation ->
            val handler = Handler(Looper.getMainLooper())
            val closed = AtomicBoolean(false)
            val web = WebView(activity)
            val tasks = Any()
            fun clean() {
                handler.removeCallbacksAndMessages(tasks)
                web.stopLoading()
                host.removeView(web)
                web.removeAllViews()
                web.destroy()
            }
            fun finish(value: String? = null, error: String? = null, failure: Exception? = null) {
                handler.post {
                    if (closed.compareAndSet(false, true)) {
                        clean()
                        if (continuation.isActive) {
                            if (value != null) continuation.resume(value)
                            else continuation.resumeWithException(failure ?: IOException(error ?: "Source could not be resolved."))
                        }
                    }
                }
            }
            fun later(delay: Long, action: () -> Unit) {
                handler.postAtTime({ if (!closed.get()) action() }, tasks, android.os.SystemClock.uptimeMillis() + delay)
            }
            fun empty() = WebResourceResponse("text/plain", "utf-8", 200, "OK",
                mapOf("Cache-Control" to "no-store"), ByteArrayInputStream(ByteArray(0)))
            web.alpha = 0f
            web.isFocusable = false
            web.setOnTouchListener { _, _ -> true }
            web.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            web.settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                allowFileAccess = false
                allowContentAccess = false
                javaScriptCanOpenWindowsAutomatically = false
                setSupportMultipleWindows(false)
                mediaPlaybackRequiresUserGesture = false
                mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
                blockNetworkImage = true
                // Reuse Next.js assets between episodes. Intercepted media is always no-store.
                cacheMode = WebSettings.LOAD_DEFAULT
            }
            CookieManager.getInstance().setAcceptThirdPartyCookies(web, false)
            web.webChromeClient = object : WebChromeClient() {
                override fun onPermissionRequest(request: PermissionRequest) { request.deny() }
                override fun onJsAlert(v: WebView?, u: String?, m: String?, r: JsResult?): Boolean {
                    r?.cancel(); return true
                }
                override fun onJsConfirm(v: WebView?, u: String?, m: String?, r: JsResult?): Boolean {
                    r?.cancel(); return true
                }
                override fun onJsPrompt(v: WebView?, u: String?, m: String?, d: String?, r: JsPromptResult?): Boolean {
                    r?.cancel(); return true
                }
            }
            web.webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(v: WebView, r: WebResourceRequest): Boolean =
                    !SitePolicy.siteUrl(r.url.toString()) || r.url.path != android.net.Uri.parse(url).path

                override fun shouldInterceptRequest(v: WebView, r: WebResourceRequest): WebResourceResponse? {
                    val source = r.url.toString()
                    if (closed.get()) return empty()
                    if (media && StreamPolicy.candidate(source)) {
                        // Capture the public stream request BEFORE WebView downloads the video.
                        finish(JSONObject().put("url", source).toString())
                        return empty()
                    }
                    // First-party bootstrap and media CORS only. Never load external scripts/iframes.
                    return if (if (media) StreamPolicy.resolverResource(source, r.requestHeaders) else SitePolicy.siteUrl(source)) null else empty()
                }
                override fun onReceivedSslError(v: WebView, h: SslErrorHandler, e: SslError) {
                    h.cancel(); finish(error = "The site returned an invalid TLS certificate.")
                }
                override fun onReceivedError(v: WebView, r: WebResourceRequest, e: WebResourceError) {
                    if (r.isForMainFrame) finish(error = "Could not load the episode page. Check your connection.")
                }
                override fun onReceivedHttpError(v: WebView, r: WebResourceRequest, e: WebResourceResponse) {
                    if (r.isForMainFrame) {
                        val challenged = e.responseHeaders?.entries?.any {
                            it.key.equals("cf-mitigated", true) && it.value.equals("challenge", true)
                        } == true
                        if (e.statusCode == 401 || e.statusCode == 403 || challenged)
                            finish(failure = SiteAccessException(url, e.statusCode, challenged))
                        else finish(error = "Site returned HTTP ${e.statusCode}.")
                    }
                }
                override fun onPageFinished(v: WebView, loaded: String) {
                    if (closed.get()) return
                    if (media) v.evaluateJavascript(ResolverScripts.observe, null)
                    if (!media) {
                        v.evaluateJavascript("document.documentElement.outerHTML") { json ->
                            if (!closed.get()) {
                                val html = runCatching { JSONTokener(json).nextValue() as String }.getOrNull()
                                if (html == null || SiteParser.blocked(html)) finish(failure = SiteAccessException(url, challenged = true))
                                else finish(html)
                            }
                        }
                    }
                }
                override fun onPageCommitVisible(v: WebView, loaded: String?) {
                    if (media && !closed.get()) v.evaluateJavascript(ResolverScripts.observe, null)
                }
                override fun onRenderProcessGone(v: WebView, d: RenderProcessGoneDetail): Boolean {
                    finish(error = "The source resolver stopped. Please retry."); return true
                }
            }
            host.addView(web, 0, ViewGroup.LayoutParams(-1, -1))
            web.onResume()
            if (media && WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
                WebViewCompat.addDocumentStartJavaScript(web, ResolverScripts.observe, setOf("https://en.hdrama.net"))
            }
            // Avoid running any page in the visible player surface. Poll for at most 30 seconds.
            fun tick() {
                if (closed.get()) return
                web.evaluateJavascript(ResolverScripts.observe, null)
                web.evaluateJavascript(ResolverScripts.inspect) { json ->
                    if (!closed.get()) {
                        val value = runCatching { JSONTokener(json).nextValue() as String }.getOrDefault("")
                        val data = runCatching { JSONObject(value) }.getOrNull()
                        val sources = data?.optJSONArray("sources")
                        val found = (0 until (sources?.length() ?: 0)).mapNotNull { sources?.optJSONObject(it) }
                            .firstOrNull { StreamPolicy.candidate(it.optString("url"), it.optString("mimeType")) }
                        when {
                            data?.optBoolean("blocked") == true -> finish(failure = SiteAccessException(url, challenged = true))
                            found != null -> finish(found.toString())
                            else -> later(250) { tick() }
                        }
                    }
                }
            }
            continuation.invokeOnCancellation {
                handler.post { if (closed.compareAndSet(false, true)) clean() }
            }
            later(30_000) { finish(error = "The episode did not provide a supported video within 30 seconds. Tap Retry source, or return to the website and check this episode.") }
            if (media) later(150) { tick() }
            web.loadUrl(url)
        }
    }
}
