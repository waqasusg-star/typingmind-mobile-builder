package com.waqas.hdrama

import android.webkit.CookieManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.IOException
import okhttp3.Call
import okhttp3.Callback
import okhttp3.Response
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resumeWithException
import java.util.concurrent.TimeUnit

object Network {
    val client = OkHttpClient.Builder().connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(25, TimeUnit.SECONDS).callTimeout(35, TimeUnit.SECONDS)
        .followRedirects(false).build()
    // Cookies are looked up per destination; no site cookies are copied to a media CDN.
    val mediaClient = OkHttpClient.Builder().connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS).addNetworkInterceptor { chain ->
            val original = chain.request()
            val request = original.newBuilder().removeHeader("Cookie")
            CookieManager.getInstance().getCookie(original.url.toString())
                ?.takeIf { it.isNotBlank() }?.let { request.header("Cookie", it) }
            chain.proceed(request.build())
        }.build()

    /** Cancellation closes the in-flight socket instead of waiting for the read timeout. */
    @OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
    internal suspend fun response(call: Call): Response = suspendCancellableCoroutine { continuation ->
        continuation.invokeOnCancellation { call.cancel() }
        call.enqueue(object : Callback {
            override fun onFailure(call: Call, error: IOException) {
                if (continuation.isActive) continuation.resumeWithException(error)
            }
            override fun onResponse(call: Call, response: Response) {
                if (continuation.isActive) continuation.resume(response) { response.close() }
                else response.close()
            }
        })
    }

    suspend fun html(url: String, userAgent: String): String = withContext(Dispatchers.IO) {
        require(SitePolicy.siteUrl(url)) { "Only en.hdrama.net pages are supported." }
        var current = url
        repeat(4) {
            val request = Request.Builder().url(current).header("User-Agent", userAgent)
                .header("Accept", "text/html").apply {
                    CookieManager.getInstance().getCookie(current)?.let { header("Cookie", it) }
                }.build()
            response(client.newCall(request)).use { response ->
                if (response.isRedirect) {
                    val next = response.header("Location")?.let { response.request.url.resolve(it) }?.toString()
                    if (next == null || !SitePolicy.siteUrl(next)) throw IOException("Unexpected site redirect.")
                    current = next
                } else {
                    if (response.header("cf-mitigated").equals("challenge", true))
                        throw SiteAccessException(current, response.code, challenged = true)
                    if (response.code == 401 || response.code == 403)
                        throw SiteAccessException(current, response.code)
                    if (!response.isSuccessful) throw IOException("Site request failed: HTTP ${response.code}.")
                    val body = response.body ?: throw IOException("Empty site response.")
                    val bytes = body.byteStream().use { input ->
                        val output = java.io.ByteArrayOutputStream()
                        val buffer = ByteArray(8192)
                        while (output.size() <= 6 * 1024 * 1024) {
                            val read = input.read(buffer)
                            if (read < 0) break
                            output.write(buffer, 0, read)
                        }
                        output.toByteArray()
                    }
                    if (bytes.size > 6 * 1024 * 1024) throw IOException("Page exceeded size limit.")
                    val html = bytes.toString(Charsets.UTF_8)
                    if (SiteParser.blocked(html)) throw SiteAccessException(current, response.code, challenged = true)
                    return@withContext html
                }
            }
        }
        throw IOException("Too many redirects.")
    }
}
