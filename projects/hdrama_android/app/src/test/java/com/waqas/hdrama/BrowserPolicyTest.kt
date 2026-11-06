package com.waqas.hdrama

import org.junit.Assert.*
import org.junit.Test

class BrowserPolicyTest {
    @Test fun acceptsPastedHDramaAddressAndRejectsUnrelatedSites() {
        assertEquals("https://en.hdrama.net/series/story", BrowserPolicy.normalizeAddress("en.hdrama.net/series/story"))
        assertNull(BrowserPolicy.normalizeAddress("https://ads.example/banner"))
        assertNull(BrowserPolicy.normalizeAddress("http://en.hdrama.net/"))
        assertNull(BrowserPolicy.normalizeAddress("file:///data/private"))
    }
    @Test fun seriesOpensNativePlayerWithResumeSelection() {
        assertEquals(PlaybackTarget("https://en.hdrama.net/series/story", 0), BrowserPolicy.playback("https://en.hdrama.net/series/story"))
    }
    @Test fun episodePreservesNumberAndCanonicalSeries() {
        assertEquals(PlaybackTarget("https://en.hdrama.net/series/story", 2), BrowserPolicy.playback("https://en.hdrama.net/series/story/episode-2?ref=x#player"))
    }
    @Test fun rejectsInvalidOrUnrelatedEpisodeTargets() {
        assertNull(BrowserPolicy.playback("https://en.hdrama.net/category/romance"))
        assertNull(BrowserPolicy.playback("https://en.hdrama.net/series/story/episode-0"))
        assertNull(BrowserPolicy.playback("https://ads.example/series/story/episode-2"))
        assertNull(BrowserPolicy.playback("https://en.hdrama.net/series/story/episode-99999999999999999999"))
    }
    @Test fun firstPartyPagesScriptsAndVerificationRemainAvailable() {
        assertTrue(BrowserPolicy.allowResource("https://en.hdrama.net/_next/static/chunks/player.js"))
        assertTrue(BrowserPolicy.allowResource("https://en.hdrama.net/api/search?q=story"))
        assertTrue(BrowserPolicy.allowResource("https://challenges.cloudflare.com/turnstile/v0/api.js"))
    }
    @Test fun thirdPartyScriptsAndFramesAreBlocked() {
        assertFalse(BrowserPolicy.allowResource("https://external.example/player.js"))
        assertFalse(BrowserPolicy.allowResource("https://external.example/embed"))
        assertFalse(BrowserPolicy.allowResource("https://challenges.cloudflare.com.evil.example/api.js"))
    }
    @Test fun legitimatePostersRequireImageRequestClassification() {
        assertTrue(BrowserPolicy.allowResource("https://cdn.example/poster.jpg?resize=400", true))
        assertFalse(BrowserPolicy.allowResource("https://cdn.example/poster.jpg", false))
        assertFalse(BrowserPolicy.allowResource("https://cdn.example/script.js", true))
    }
    @Test fun knownAdImagesAndTrackersAreBlocked() {
        assertFalse(BrowserPolicy.allowResource("https://cdn.doubleclick.net/banner.jpg", true))
        assertFalse(BrowserPolicy.allowResource("https://www.googletagmanager.com/gtm.js"))
        assertFalse(BrowserPolicy.allowResource("https://popads.net/banner.png", true))
    }
    @Test fun domainMatchingRespectsBoundaries() {
        assertTrue(BrowserPolicy.blockedHost("ads.doubleclick.net"))
        assertFalse(BrowserPolicy.blockedHost("notdoubleclick.net"))
        assertFalse(BrowserPolicy.blockedHost("doubleclick.net.good.example"))
    }
    @Test fun browserDoesNotDownloadVideosAlongsideNativePlayer() {
        assertFalse(BrowserPolicy.allowResource("https://cdn.example/video.m3u8", true))
        assertFalse(BrowserPolicy.allowResource("https://en.hdrama.net/video.mp4"))
        assertFalse(BrowserPolicy.allowResource("http://cdn.example/poster.png", true))
    }
}
