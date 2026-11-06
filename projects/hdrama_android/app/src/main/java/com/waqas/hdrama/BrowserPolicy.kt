package com.waqas.hdrama

import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

data class PlaybackTarget(val seriesUrl: String, val episode: Int)

/** Browser navigation stays on HDrama. Only its verification provider and poster images are external. */
object BrowserPolicy {
    private val adHosts = setOf(
        "doubleclick.net", "googlesyndication.com", "googleadservices.com", "googletagmanager.com",
        "google-analytics.com", "adservice.google.com", "adnxs.com", "adsrvr.org", "adroll.com",
        "taboola.com", "outbrain.com", "popads.net", "popcash.net", "propellerads.com",
        "adsterra.com", "exoclick.com", "onclickads.net", "hilltopads.net", "trafficjunky.net",
        "juicyads.com", "adcash.com", "clickadu.com", "monetag.com", "a-ads.com"
    )
    fun blockedHost(host: String): Boolean = adHosts.any { host.equals(it, true) || host.endsWith(".$it", true) }
    fun allowResource(raw: String, imageRequest: Boolean = false): Boolean {
        val url = raw.toHttpUrlOrNull() ?: return false
        if (url.scheme != "https" || url.username.isNotEmpty() || url.password.isNotEmpty()) return false
        if (blockedHost(url.host) || SitePolicy.mediaUrl(raw)) return false
        if (SitePolicy.verificationResource(raw)) return true
        return imageRequest && Regex(".*\\.(png|jpe?g|webp|gif|avif|svg|ico)$", RegexOption.IGNORE_CASE).matches(url.encodedPath)
    }
    fun normalizeAddress(raw: String): String? {
        val value = raw.trim()
        if (value.isEmpty()) return null
        val candidate = if (value.contains("://")) value else "https://$value"
        return candidate.takeIf(SitePolicy::siteUrl)
    }
    fun playback(raw: String): PlaybackTarget? {
        val canonical = SitePolicy.seriesUrl(raw) ?: return null
        val url = raw.toHttpUrlOrNull() ?: return null
        val segment = url.pathSegments.lastOrNull().orEmpty()
        val episode = Regex("episode-(\\d+)").matchEntire(segment)?.groupValues?.get(1)?.toIntOrNull() ?: 0
        if (segment.startsWith("episode-") && episode <= 0) return null
        return PlaybackTarget(canonical, episode)
    }
}
