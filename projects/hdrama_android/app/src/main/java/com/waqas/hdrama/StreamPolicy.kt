package com.waqas.hdrama

import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

/** Only public HTTPS media metadata is accepted; blob URLs never leave WebView. */
object StreamPolicy {
    fun mime(raw: String): String? = when (raw.substringBefore(';').trim().lowercase()) {
        "application/vnd.apple.mpegurl", "application/x-mpegurl", "audio/mpegurl", "audio/x-mpegurl" -> "application/x-mpegURL"
        "application/dash+xml" -> "application/dash+xml"
        "video/mp4" -> "video/mp4"
        "video/webm" -> "video/webm"
        else -> null
    }
    fun candidate(raw: String, contentType: String = ""): Boolean {
        val u = raw.toHttpUrlOrNull() ?: return false
        return u.scheme == "https" && u.username.isEmpty() && u.password.isEmpty() &&
            !BrowserPolicy.blockedHost(u.host) && (SitePolicy.mediaUrl(raw) || mime(contentType) != null)
    }
    // Let the site's CORS fetch/XHR requests discover extensionless manifests.
    // Third-party executable scripts, frames, images and advertising remain blocked.
    fun resolverResource(raw: String, headers: Map<String, String>): Boolean {
        val u = raw.toHttpUrlOrNull() ?: return false
        if (u.scheme != "https" || u.username.isNotEmpty() || u.password.isNotEmpty() || BrowserPolicy.blockedHost(u.host)) return false
        if (SitePolicy.siteUrl(raw)) return true
        fun header(key: String) = headers.entries.firstOrNull { it.key.equals(key, true) }?.value.orEmpty()
        val destination = header("Sec-Fetch-Dest")
        return destination.isEmpty() && header("Origin") == "https://en.hdrama.net"
    }
}
