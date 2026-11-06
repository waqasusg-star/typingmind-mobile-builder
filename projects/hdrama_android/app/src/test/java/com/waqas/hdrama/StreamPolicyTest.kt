package com.waqas.hdrama

import org.junit.Assert.*
import org.junit.Test

class StreamPolicyTest {
    @Test fun extensionlessManifestsUseResponseMime() {
        assertTrue(StreamPolicy.candidate("https://video.example/play?id=1", "application/vnd.apple.mpegurl; charset=utf-8"))
        assertTrue(StreamPolicy.candidate("https://video.example/play", "application/dash+xml"))
        assertEquals("application/x-mpegURL", StreamPolicy.mime("Audio/X-MPEGURL"))
    }
    @Test fun directFileLinksStillWork() {
        assertTrue(StreamPolicy.candidate("https://video.example/episode.M3U8?token=public"))
        assertTrue(StreamPolicy.candidate("https://video.example/episode.mp4"))
    }
    @Test fun blobAndUnsafeMediaNeverReachExoPlayer() {
        assertFalse(StreamPolicy.candidate("blob:https://en.hdrama.net/temporary", "video/mp4"))
        assertFalse(StreamPolicy.candidate("http://video.example/test.mp4"))
        assertFalse(StreamPolicy.candidate("https://user:secret@video.example/test.mp4"))
    }
    @Test fun adSourcesAndNonMediaResponsesAreRejected() {
        assertFalse(StreamPolicy.candidate("https://ads.doubleclick.net/ad.mp4"))
        assertFalse(StreamPolicy.candidate("https://video.example/api", "application/json"))
        assertFalse(StreamPolicy.candidate("https://video.example/chunk", "video/mp2t"))
        assertNull(StreamPolicy.mime("text/html"))
    }
    @Test fun corsManifestDiscoveryIsAllowed() {
        assertTrue(StreamPolicy.resolverResource("https://video.example/play", mapOf("Origin" to "https://en.hdrama.net", "Sec-Fetch-Dest" to "")))
        assertTrue(StreamPolicy.resolverResource("https://en.hdrama.net/_next/chunk.js", emptyMap()))
    }
    @Test fun externalExecutionAndOtherOriginsAreBlocked() {
        val origin = mapOf("Origin" to "https://en.hdrama.net")
        for (destination in listOf("script", "iframe", "document", "image")) {
            assertFalse(StreamPolicy.resolverResource("https://video.example/asset", origin + ("Sec-Fetch-Dest" to destination)))
        }
        assertFalse(StreamPolicy.resolverResource("https://video.example/play", emptyMap()))
        assertFalse(StreamPolicy.resolverResource("https://video.example/play", mapOf("Origin" to "https://untrusted.example")))
        assertFalse(StreamPolicy.resolverResource("https://ads.doubleclick.net/api", origin))
    }
}
