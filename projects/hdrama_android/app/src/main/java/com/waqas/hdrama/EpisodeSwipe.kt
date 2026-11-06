package com.waqas.hdrama

import kotlin.math.abs

object EpisodeSwipe {
    enum class Axis { NONE, HORIZONTAL, VERTICAL }
    fun axis(dx: Float, dy: Float, threshold: Float): Axis = when {
        abs(dx) < threshold && abs(dy) < threshold -> Axis.NONE
        abs(dy) > abs(dx) * 1.15f -> Axis.VERTICAL
        abs(dx) > abs(dy) * 1.15f -> Axis.HORIZONTAL
        else -> Axis.NONE
    }
    fun target(index: Int, size: Int, dy: Float, height: Int, velocity: Float, density: Float): Int? {
        if (abs(dy) < 24f * density || (abs(dy) < height.coerceAtLeast(1) * .14f && abs(velocity) < 900f * density)) return null
        return if (dy < 0) EpisodeOrder.next(index,size) else EpisodeOrder.previous(index,size)
    }
}
