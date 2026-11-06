package com.waqas.hdrama

import kotlinx.coroutines.CancellationException

class Repository(private val resolver: BrowserResolver) {
    private suspend fun html(url: String): String = try {
        Network.html(url, resolver.userAgent)
    } catch (e: CancellationException) { throw e }
      catch (_: Exception) { resolver.page(url) }

    suspend fun catalog(): List<Drama> = SiteParser.catalog(html(SitePolicy.HOME)).also {
        check(it.isNotEmpty()) { "No titles were found. Retry or paste a series link." }
    }
    suspend fun series(url: String): Series = SiteParser.series(html(url), url)
    suspend fun stream(episode: Episode): Stream {
        // The site initializes encrypted public URLs in JavaScript. Use the normal page
        // immediately rather than waiting up to 35 seconds for a separate HTML request.
        return resolver.stream(episode.pageUrl)
    }
}
