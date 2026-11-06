package com.waqas.hdrama

import kotlinx.coroutines.*

/** Main-thread session cache. In-flight next resolution is shared with a Next press. */
class SessionStreams(
    private val scope: CoroutineScope,
    private val clock: () -> Long,
    private val resolve: suspend (Episode) -> Stream,
    private val ttlMs: Long = 60_000
) {
    private data class Entry(val stream: Stream, val at: Long)
    private val values = LinkedHashMap<String, Entry>()
    private val pending = mutableMapOf<String, Deferred<Stream>>()
    fun peek(episode: Episode): Stream? = values[episode.pageUrl]?.takeIf { clock() - it.at < ttlMs }?.stream
    suspend fun get(episode: Episode, refresh: Boolean = false): Stream {
        val key = episode.pageUrl
        if (refresh) { values.remove(key); pending.remove(key)?.cancel() }
        peek(episode)?.let { return it }
        val task = pending[key] ?: scope.async(start = CoroutineStart.LAZY) {
            resolve(episode).also {
                values[key] = Entry(it, clock())
                while (values.size > 3) values.remove(values.keys.first())
            }
        }.also { pending[key] = it; it.start() }
        return try { task.await() } finally { if (task.isCompleted && pending[key] === task) pending.remove(key) }
    }
    fun cancelExcept(pageUrl: String) {
        pending.keys.filter { it != pageUrl }.forEach { pending.remove(it)?.cancel() }
    }
    fun clear() { pending.values.forEach { it.cancel() }; pending.clear(); values.clear() }
}
