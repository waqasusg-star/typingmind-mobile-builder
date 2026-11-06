package com.waqas.hdrama

import android.annotation.SuppressLint
import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.net.http.SslError
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.webkit.*
import android.widget.*
import androidx.activity.ComponentActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import org.json.JSONTokener
import java.io.ByteArrayInputStream

/** A user-led website check. Never clicks, solves, fabricates or exports a challenge token. */
class AccessActivity : ComponentActivity() {
    private lateinit var web: WebView
    private lateinit var status: TextView
    private lateinit var spinner: ProgressBar
    private lateinit var pageUrl: String
    private val handler = Handler(Looper.getMainLooper())
    private var checking = false
    private var completed = false
    private var responseCode: Int? = null
    private val monitor = object : Runnable {
        override fun run() {
            inspectPage()
            if (!completed) handler.postDelayed(this, 1500)
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        androidx.core.view.WindowCompat.setDecorFitsSystemWindows(window,false)
        pageUrl = intent.getStringExtra("page").orEmpty()
        if (!SitePolicy.siteUrl(pageUrl)) { finish(); return }
        setResult(RESULT_CANCELED)
        val root = column().apply { pad(16); setBackgroundColor(AppColors.background) }
        root.addView(screenHeader("Check website access") { finish() }.first)
        root.addView(label("en.hdrama.net", 12f).apply { setTextColor(accent); setPadding(0,0,0,dp(8)) })
        status = label("Opening the website’s access check…",13f).apply { setTextColor(AppColors.muted); setPadding(0,0,0,dp(8)) }
        root.addView(status)
        // Two comfortable 48dp targets instead of three cramped buttons competing for one row.
        root.addView(row().apply {
            weight(button("Reload check") {
                responseCode = null; web.alpha = 0f; spinner.visibility = View.VISIBLE
                status.text = "Opening the website’s access check…"; web.loadUrl(pageUrl)
            })
            weight(button("Open in browser") {
                try { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(pageUrl))) }
                catch (_: ActivityNotFoundException) { Toast.makeText(this@AccessActivity, "No browser is installed.", Toast.LENGTH_SHORT).show() }
            })
        })
        root.addView(label("Complete any check yourself. A browser session is separate from this app’s session.", 12f).apply { setTextColor(AppColors.muted); setPadding(0,dp(10),0,0) })
        val body = FrameLayout(this)
        web = WebView(this).apply {
            alpha = 0f
            settings.apply {
                javaScriptEnabled = true; domStorageEnabled = true
                allowFileAccess = false; allowContentAccess = false
                javaScriptCanOpenWindowsAutomatically = false
                setSupportMultipleWindows(false)
                mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
                mediaPlaybackRequiresUserGesture = true
            }
        }
        CookieManager.getInstance().setAcceptThirdPartyCookies(web, false)
        web.webChromeClient = object : WebChromeClient() {
            override fun onPermissionRequest(request: PermissionRequest) { request.deny() }
            override fun onJsAlert(v: WebView?, u: String?, m: String?, r: JsResult?): Boolean { r?.cancel(); return true }
            override fun onJsConfirm(v: WebView?, u: String?, m: String?, r: JsResult?): Boolean { r?.cancel(); return true }
            override fun onJsPrompt(v: WebView?, u: String?, m: String?, d: String?, r: JsPromptResult?): Boolean { r?.cancel(); return true }
        }
        web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(v: WebView, r: WebResourceRequest): Boolean {
                val path = r.url.path.orEmpty()
                return !SitePolicy.siteUrl(r.url.toString()) ||
                    (path != Uri.parse(pageUrl).path && !path.startsWith("/cdn-cgi/"))
            }
            override fun shouldInterceptRequest(v: WebView, r: WebResourceRequest): WebResourceResponse? {
                if (SitePolicy.verificationResource(r.url.toString())) return null
                return WebResourceResponse("text/plain", "utf-8", ByteArrayInputStream(ByteArray(0)))
            }
            override fun onPageStarted(v: WebView, url: String?, favicon: android.graphics.Bitmap?) {
                responseCode = null
                web.alpha = 0f
                spinner.visibility = View.VISIBLE
            }
            override fun onReceivedHttpError(v: WebView, r: WebResourceRequest, response: WebResourceResponse) {
                // A challenge can use HTTP 403: let its page render for the user to inspect.
                if (r.isForMainFrame) responseCode = response.statusCode
            }
            override fun onReceivedError(v: WebView, r: WebResourceRequest, error: WebResourceError) {
                if (r.isForMainFrame) { spinner.visibility = View.GONE; status.text = "The website could not be reached. Use Reload check." }
            }
            override fun onReceivedSslError(v: WebView, h: SslErrorHandler, error: SslError) {
                h.cancel(); spinner.visibility = View.GONE; status.text = "Invalid website certificate. Access was stopped."
            }
            override fun onPageFinished(v: WebView, url: String?) { inspectPage() }
            override fun onRenderProcessGone(v: WebView, detail: RenderProcessGoneDetail): Boolean {
                handler.removeCallbacksAndMessages(null)
                Toast.makeText(this@AccessActivity, "The access screen stopped. Please reopen it.", Toast.LENGTH_LONG).show()
                finish(); return true
            }
        }
        body.addView(web, FrameLayout.LayoutParams(-1, -1))
        spinner = ProgressBar(this)
        body.addView(spinner, FrameLayout.LayoutParams(dp(40), dp(40), android.view.Gravity.CENTER))
        root.addView(body, LinearLayout.LayoutParams(-1, 0, 1f))
        setContentView(root)
        ViewCompat.setOnApplyWindowInsetsListener(root) { v, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
            v.setPadding(dp(16) + bars.left, dp(16) + bars.top, dp(16) + bars.right, dp(16) + bars.bottom)
            WindowInsetsCompat.CONSUMED
        }
        web.loadUrl(pageUrl)
    }

    private fun inspectPage() {
        if (!::web.isInitialized || checking || completed || isFinishing) return
        checking = true
        web.evaluateJavascript("document.documentElement.outerHTML") { json ->
            checking = false
            if (completed || isFinishing) return@evaluateJavascript
            val html = runCatching { JSONTokener(json).nextValue() as String }.getOrNull() ?: return@evaluateJavascript
            val allowed = responseCode == null && !SiteParser.blocked(html) &&
                (if (SitePolicy.seriesUrl(pageUrl) != null) runCatching { SiteParser.series(html, pageUrl) }.isSuccess
                 else SiteParser.catalog(html, pageUrl).isNotEmpty())
            if (allowed) {
                completed = true
                handler.removeCallbacksAndMessages(null)
                // Keep only normal WebView cookies; no cookies or challenge values leave the app.
                CookieManager.getInstance().flush()
                setResult(RESULT_OK); finish()
            } else {
                spinner.visibility = View.GONE
                web.alpha = 1f
                status.text = if (responseCode == 403 && !html.contains("cf-chl", true) && !html.contains("turnstile", true))
                    "The website is still denying app access (403). There may be no check you can complete."
                else "Complete any website check below. This screen closes when the episode list is accessible."
            }
        }
    }
    override fun onStart() { super.onStart(); if (::web.isInitialized) handler.postDelayed(monitor, 1500) }
    override fun onStop() { handler.removeCallbacks(monitor); super.onStop() }
    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        if (::web.isInitialized) {
            web.stopLoading(); (web.parent as? android.view.ViewGroup)?.removeView(web); web.destroy()
        }
        super.onDestroy()
    }
}
