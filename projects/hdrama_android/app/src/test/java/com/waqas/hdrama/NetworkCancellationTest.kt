package com.waqas.hdrama

import kotlinx.coroutines.*
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.SocketPolicy
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.TimeUnit

class NetworkCancellationTest {
    @Test fun cancellationCancelsTheActualHttpCall() = runBlocking {
        val server = MockWebServer()
        server.enqueue(MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE))
        server.start()
        val client = OkHttpClient()
        val call = client.newCall(Request.Builder().url(server.url("/slow")).build())
        try {
            val task = launch(Dispatchers.IO) { Network.response(call).close() }
            assertNotNull(server.takeRequest(5, TimeUnit.SECONDS))
            task.cancelAndJoin()
            assertTrue(call.isCanceled())
        } finally { client.dispatcher.executorService.shutdown(); client.connectionPool.evictAll(); server.shutdown() }
    }
    @Test fun responseRemainsReadableOnSuccess() = runBlocking {
        val server = MockWebServer(); server.enqueue(MockResponse().setBody("actual response")); server.start()
        val client = OkHttpClient()
        try { Network.response(client.newCall(Request.Builder().url(server.url("/")).build())).use { assertEquals("actual response",it.body!!.string()) } }
        finally { client.dispatcher.executorService.shutdown(); client.connectionPool.evictAll(); server.shutdown() }
    }
    @Test fun completionAndCancellationReleaseOnlyOnce() {
        val calls=java.util.concurrent.atomic.AtomicInteger();val cleanup=ReleaseOnce { calls.incrementAndGet() }
        val threads=(1..20).map { Thread { repeat(20) { cleanup.release() } }.apply { start() } };threads.forEach { it.join() }
        assertEquals(1,calls.get())
    }
}
