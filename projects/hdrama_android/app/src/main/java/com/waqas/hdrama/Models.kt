package com.waqas.hdrama

import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

data class Drama(val title: String, val url: String)
data class Episode(val number: Int, val pageUrl: String)
data class Series(val title: String, val url: String, val episodes: List<Episode>, val posterUrl: String = "", val seasonLabel: String = "")
data class Stream(val url: String, val referer: String, val userAgent: String, val mimeType: String? = null)

object SitePolicy {
    const val HOME = "https://en.hdrama.net/"
    fun siteUrl(raw: String): Boolean {
        val u = raw.toHttpUrlOrNull() ?: return false
        return u.scheme == "https" && u.host == "en.hdrama.net" && u.port == 443 &&
            u.username.isEmpty() && u.password.isEmpty()
    }
    // Only the website and its documented verification service may run in the user-led access screen.
    fun verificationResource(raw: String): Boolean {
        if (siteUrl(raw)) return true
        val u = raw.toHttpUrlOrNull() ?: return false
        return u.scheme == "https" && u.host == "challenges.cloudflare.com" && u.port == 443 &&
            u.username.isEmpty() && u.password.isEmpty()
    }
    fun seriesUrl(raw: String): String? {
        val u = raw.toHttpUrlOrNull() ?: return null
        if (!siteUrl(raw)) return null
        val parts = u.pathSegments.filter { it.isNotBlank() }
        if (parts.size !in 2..3 || parts[0] != "series") return null
        if (parts.size == 3 && !Regex("episode-\\d+").matches(parts[2])) return null
        return u.newBuilder().encodedPath("/series/${u.encodedPathSegments[1]}")
            .query(null).fragment(null).build().toString()
    }
    fun mediaUrl(raw: String): Boolean {
        val u = raw.toHttpUrlOrNull() ?: return false
        return u.scheme == "https" && u.username.isEmpty() && u.password.isEmpty() &&
            Regex(".*\\.(m3u8|mp4|mpd|webm)$", RegexOption.IGNORE_CASE).matches(u.encodedPath)
    }
}

object EpisodeOrder {
    fun next(index: Int, size: Int): Int? = (index + 1).takeIf { index >= 0 && it < size }
    fun previous(index: Int, size: Int): Int? = (index - 1).takeIf { index < size && it >= 0 }
}
