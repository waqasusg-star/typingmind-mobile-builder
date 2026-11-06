package com.waqas.hdrama

/** Reuse the series the browser already validated. No repeated HTML request on Play. */
object PlaybackHandoff {
    private var pending: Series? = null
    fun offer(series: Series) { pending = series }
    fun take(url: String): Series? = pending?.takeIf { it.url == url }.also { pending = null }
}
