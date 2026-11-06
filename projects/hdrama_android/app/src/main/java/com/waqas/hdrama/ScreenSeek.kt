package com.waqas.hdrama

/** One screen width covers at most 90 seconds; direction and boundaries are stable while preview seeks move playback. */
object ScreenSeek {
    fun target(origin: Long, distance: Float, width: Int, duration: Long): Long {
        if (duration <= 0 || width <= 0 || !distance.isFinite()) return origin.coerceAtLeast(0)
        val delta = (distance.toDouble() / width * minOf(duration,90_000L)).toLong()
        return (origin + delta).coerceIn(0,duration)
    }
}
