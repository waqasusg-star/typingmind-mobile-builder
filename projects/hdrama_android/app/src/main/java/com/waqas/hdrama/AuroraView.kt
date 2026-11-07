package com.waqas.hdrama

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.Shader
import android.os.SystemClock
import android.view.View
import kotlin.math.cos
import kotlin.math.sin

/**
 * Living backdrop: three drifting radial blooms over a vertical cinematic gradient.
 * Drawing only, no per-frame allocation. Pauses when detached.
 */
class AuroraView(context: Context) : View(context) {
    private val core = Paint(Paint.ANTI_ALIAS_FLAG)
    private val base = Paint(Paint.ANTI_ALIAS_FLAG)
    private val bloom = Paint(Paint.ANTI_ALIAS_FLAG)
    private var baseShader: Shader? = null
    private var bloomA: Shader? = null
    private var bloomB: Shader? = null
    private var bloomC: Shader? = null
    private var cachedW = 0f
    private var cachedH = 0f
    private var start = 0L

    private val tick = object : Runnable {
        override fun run() {
            if (!isAttachedToWindow) return
            invalidate()
            postDelayed(this, FRAME_MS)
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (start == 0L) start = SystemClock.uptimeMillis()
        removeCallbacks(tick)
        postDelayed(tick, FRAME_MS)
    }

    override fun onDetachedFromWindow() {
        removeCallbacks(tick)
        super.onDetachedFromWindow()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        rebuild(w.toFloat(), h.toFloat())
    }

    private fun rebuild(w: Float, h: Float) {
        if (w <= 0f || h <= 0f) return
        cachedW = w; cachedH = h
        baseShader = LinearGradient(0f, 0f, w * 0.35f, h, intArrayOf(
            0xff07080d.toInt(), 0xff0b0d15.toInt(), 0xff0a0b11.toInt()
        ), floatArrayOf(0f, 0.55f, 1f), Shader.TileMode.CLAMP)
        val radius = maxOf(w, h) * 0.78f
        bloomA = RadialGradient(w * 0.18f, h * 0.14f, radius, intArrayOf(withAlpha(TINT_A, 0x66), withAlpha(TINT_A, 0x14), 0x00000000), floatArrayOf(0f, 0.5f, 1f), Shader.TileMode.CLAMP)
        bloomB = RadialGradient(w * 0.92f, h * 0.34f, radius * 0.8f, intArrayOf(withAlpha(TINT_B, 0x4d), withAlpha(TINT_B, 0x10), 0x00000000), floatArrayOf(0f, 0.5f, 1f), Shader.TileMode.CLAMP)
        bloomC = RadialGradient(w * 0.55f, h * 0.92f, radius * 0.72f, intArrayOf(withAlpha(TINT_C, 0x40), withAlpha(TINT_C, 0x0d), 0x00000000), floatArrayOf(0f, 0.5f, 1f), Shader.TileMode.CLAMP)
    }

    /** Keep the hue and replace the alpha channel. */
    private fun withAlpha(color: Int, alpha: Int): Int =
        Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color))

    override fun onDraw(canvas: Canvas) {
        val w = width.toFloat(); val h = height.toFloat()
        if (w <= 0f || h <= 0f) return
        if (baseShader == null || cachedW != w || cachedH != h) rebuild(w, h)
        base.shader = baseShader
        canvas.drawRect(0f, 0f, w, h, base)

        val t = (SystemClock.uptimeMillis() - start) / 1000f
        canvas.save(); canvas.translate(cos(t * 0.23f) * w * 0.055f, sin(t * 0.31f) * h * 0.035f)
        bloom.shader = bloomA; canvas.drawRect(0f, 0f, w, h, bloom); canvas.restore()
        canvas.save(); canvas.translate(sin(t * 0.19f) * w * 0.06f, cos(t * 0.27f) * h * 0.045f)
        bloom.shader = bloomB; canvas.drawRect(0f, 0f, w, h, bloom); canvas.restore()
        canvas.save(); canvas.translate(cos(t * 0.15f + 1.2f) * w * 0.05f, sin(t * 0.21f + 0.6f) * h * 0.04f)
        bloom.shader = bloomC; canvas.drawRect(0f, 0f, w, h, bloom); canvas.restore()

        core.shader = LinearGradient(0f, 0f, w, 0f, intArrayOf(0x00ffffff, 0x1fffffff, 0x00ffffff), null, Shader.TileMode.CLAMP)
        canvas.drawRect(0f, 0f, w, resources.displayMetrics.density.coerceAtLeast(1f), core)
    }

    private companion object {
        const val FRAME_MS = 33L
        const val TINT_A = 0xff5b3df5.toInt()
        const val TINT_B = 0xff1f7ae0.toInt()
        const val TINT_C = 0xffb8347a.toInt()
    }
}
