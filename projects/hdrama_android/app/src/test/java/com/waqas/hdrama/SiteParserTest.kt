package com.waqas.hdrama

import org.junit.Assert.*
import org.junit.Test

class SiteParserTest {
    private val base = "https://en.hdrama.net/series/story"
    @Test fun episodesSortedNumericallyAndDeduplicated() {
        val html = """<h1>Story</h1>
            <a href="/series/story/episode-10">10</a>
            <a href="/series/story/episode-2">2</a>
            <a href="/series/story/episode-1">1</a>
            <a href="/series/story/episode-2">Next</a>
            <a href="/series/other/episode-1">Recommendation</a>"""
        assertEquals(listOf(1, 2, 10), SiteParser.series(html, base).episodes.map { it.number })
    }
    @Test fun rejectsExternalEpisodeLinks() {
        val html = """<a href="https://ads.example/series/story/episode-1">ad</a>
            <a href="/series/story/episode-2">2</a>"""
        assertEquals(listOf(2), SiteParser.series(html, base).episodes.map { it.number })
    }
    @Test fun catalogueUsesTitlesNotRatings() {
        val html = """<a href="/series/story">9.9</a><h3><a href="/series/story">Story</a></h3>
            <h3><a href="/series/story">Story</a></h3><h3><a href="https://ads.example/x">Ad</a></h3>"""
        assertEquals(listOf(Drama("Story", base)), SiteParser.catalog(html))
    }
    @Test fun readsVideoElementAndIgnoresScriptAds() {
        val html = """<script>const ad="https://ads.example/ad.mp4"</script>
            <video><source src="https://cdn.example/a.m3u8?token=a&amp;b=2"></video>"""
        assertEquals("https://cdn.example/a.m3u8?token=a&b=2", SiteParser.directStream(html, base))
    }
    @Test fun encryptedBootstrapDoesNotBecomeFakeStream() {
        val html = """<script>self.__next_f.push([1,"{\"enc\":\"abc\",\"type\":\"hls\"}"])</script>"""
        assertNull(SiteParser.directStream(html, base))
    }
    @Test fun noEpisodesIsAnExplicitFailure() {
        assertThrows(IllegalStateException::class.java) { SiteParser.series("<h1>Story</h1>", base) }
    }
    @Test fun rejectsLookalikeHostsAndHttp() {
        assertFalse(SitePolicy.siteUrl("https://en.hdrama.net.evil.example/series/story"))
        assertFalse(SitePolicy.siteUrl("http://en.hdrama.net/series/story"))
        assertFalse(SitePolicy.siteUrl("https://user:pass@en.hdrama.net/"))
        assertFalse(SitePolicy.siteUrl("https://en.hdrama.net:8443/"))
    }
    @Test fun canonicalizesEpisodeUrl() {
        assertEquals(base, SitePolicy.seriesUrl("$base/episode-2?tracking=x#fragment"))
        assertNull(SitePolicy.seriesUrl("https://en.hdrama.net/category/action"))
        assertNull(SitePolicy.seriesUrl("$base/not-an-episode"))
    }
    @Test fun mediaMustBeHttpsAndHaveSupportedExtension() {
        assertTrue(SitePolicy.mediaUrl("https://cdn.example/video.m3u8?token=x"))
        assertFalse(SitePolicy.mediaUrl("blob:https://en.hdrama.net/id"))
        assertFalse(SitePolicy.mediaUrl("https://ads.example/path?file=ad.mp4"))
        assertFalse(SitePolicy.mediaUrl("https://cdn.example/poster.jpg"))
    }
    @Test fun detectsVerificationPage() {
        assertTrue(SiteParser.blocked("<title>Attention Required! | Cloudflare</title>"))
        assertFalse(SiteParser.blocked("<title>A story</title>"))
    }
    @Test fun autoNextStopsAtLastEpisode() {
        assertEquals(1, EpisodeOrder.next(0, 3))
        assertNull(EpisodeOrder.next(2, 3))
        assertNull(EpisodeOrder.next(-1, 3))
        assertNull(EpisodeOrder.next(0, 0))
    }
    @Test fun previousStopsAtFirstEpisode() {
        assertNull(EpisodeOrder.previous(0, 3))
        assertEquals(0, EpisodeOrder.previous(1, 3))
        assertNull(EpisodeOrder.previous(3, 3))
    }

    @Test fun accessScreenOnlyAllowsWebsiteAndDocumentedVerificationHost() {
        assertTrue(SitePolicy.verificationResource("https://en.hdrama.net/cdn-cgi/challenge-platform/test"))
        assertTrue(SitePolicy.verificationResource("https://challenges.cloudflare.com/turnstile/v0/api.js"))
        assertFalse(SitePolicy.verificationResource("https://challenges.cloudflare.com.evil.example/api.js"))
        assertFalse(SitePolicy.verificationResource("http://challenges.cloudflare.com/api.js"))
        assertFalse(SitePolicy.verificationResource("https://ads.example/banner.js"))
    }
    @Test fun deniedAccessIsNotReportedAsSuccessfulPlayback() {
        val denied = SiteAccessException(base, 403)
        assertEquals(403, denied.statusCode)
        assertFalse(denied.challenged)
        assertTrue(denied.message!!.contains("denied app access"))
    }
    @Test fun challengedAccessRequestsUserLedCheck() {
        val challenged = SiteAccessException(base, 403, true)
        assertTrue(challenged.challenged)
        assertTrue(challenged.message!!.contains("Check website access"))
    }
}
