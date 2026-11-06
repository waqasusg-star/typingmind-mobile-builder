package com.waqas.hdrama

import org.jsoup.Jsoup

/** HTML only: scripts are read as data, never evaluated here. */
object SiteParser {
    fun catalog(html: String, base: String = SitePolicy.HOME): List<Drama> {
        val doc = Jsoup.parse(html, base)
        // Heading links avoid rating/poster-only anchors. Preserve server ordering.
        return doc.select("h2 a[href], h3 a[href], a[aria-label][href]").mapNotNull { a ->
            val raw = a.absUrl("href")
            val url = SitePolicy.seriesUrl(raw) ?: return@mapNotNull null
            if (raw.contains("/episode-")) return@mapNotNull null
            val title = a.text().ifBlank { a.attr("aria-label") }.trim()
            title.takeIf { it.isNotBlank() }?.let { Drama(it, url) }
        }.distinctBy { it.url }
    }

    fun series(html: String, url: String): Series {
        val canonical = requireNotNull(SitePolicy.seriesUrl(url)) { "Use an HDrama series URL." }
        val doc = Jsoup.parse(html, canonical)
        val title = doc.selectFirst("h1")?.text()?.replace(Regex("\\s+Episode\\s*\\d+.*$"), "")
            ?: canonical.substringAfterLast('/').replace('-', ' ')
        val episodes = doc.select("a[href]").mapNotNull { a ->
            val href = a.absUrl("href").substringBefore('?').substringBefore('#').trimEnd('/')
            if (SitePolicy.seriesUrl(href) != canonical) return@mapNotNull null
            val number = Regex("/episode-(\\d+)$").find(href)?.groupValues?.get(1)?.toIntOrNull()
            number?.takeIf { it > 0 }?.let { Episode(it, href) }
        }.distinctBy { it.number }.sortedBy { it.number }
        if (episodes.isEmpty()) error("No episode links found. The site layout may have changed.")
        return Series(title, canonical, episodes,SeriesArtwork.poster(doc,title),SeriesArtwork.season(title))
    }

    fun directStream(html: String, page: String): String? {
        val doc = Jsoup.parse(html, page)
        // Never select arbitrary URLs from scripts: ad sources and recommendation videos can occur there.
        return doc.select("video[src], video source[src]").map { it.absUrl("src") }
            .firstOrNull(SitePolicy::mediaUrl)
    }

    fun blocked(html: String): Boolean {
        val text = Jsoup.parse(html).title().lowercase()
        return text.contains("just a moment") || text.contains("attention required") ||
            text.contains("access denied")
    }
}
