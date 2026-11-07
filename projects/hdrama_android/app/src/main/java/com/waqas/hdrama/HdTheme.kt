package com.waqas.hdrama

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.*
import android.graphics.drawable.*
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.TextView

/**
 * HDrama premium design system (obsidian + amber).
 * Pure drawing/measure code so it can be exercised in Robolectric without a screen.
 */
object Hd {
    val background = 0xff08090d.toInt()
    val deep = 0xff0b0d13.toInt()
    val surface = 0xff11141c.toInt()
    val raised = 0xff171b25.toInt()
    val stroke = 0xff262b38.toInt()
    val gold = 0xfff5b544.toInt()
    val goldSoft = 0xff2a2114.toInt()
    val text = 0xfff7f8fb.toInt()
    val muted = 0xff9ba3b4.toInt()
    val success = 0xff4ade85.toInt()

    /** Reference corner radius in dp. */
    fun radius(compact: Boolean = false): Float = if (compact) 12f else 18f

    /** Corner radii for a 48dp control, sized for the device density. */
    fun cornerPx(context: Context, compact: Boolean = false): Float = context.dp(radius(compact).toInt()).toFloat()

    fun gradient(): LinearGradient = LinearGradient(0f, 0f, 1f, 1f, intArrayOf(gold, 0xffffd166.toInt()), null, Shader.TileMode.CLAMP)

    fun card(context: Context, elevated: Boolean = false): Drawable = GradientDrawable().apply {
        setColor(if (elevated) raised else surface)
        cornerRadius = context.dp(if (elevated) 20 else 16).toFloat()
        setStroke(context.dp(1), if (elevated) 0xff2e3444.toInt() else stroke)
    }

    fun pill(context: Context, color: Int = surface): Drawable = GradientDrawable().apply {
        setColor(color); cornerRadius = context.dp(28).toFloat(); setStroke(context.dp(1), stroke)
    }

    fun primaryButton(context: Context): Drawable = RippleDrawable(ColorStateList.valueOf(0x40ffffff), GradientDrawable().apply {
        setColor(gold); cornerRadius = context.dp(14).toFloat()
    }, null)

    /** Only render the four safest status-bar icons; letterbox devices with cutouts are skipped. */
    fun immersive(context: Context): Boolean = context.resources.displayMetrics.widthPixels > 0
}

/** Faint radial glow behind hero content; cheap to draw and never allocates per frame. */
class AuroraGlow(context: Context) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { shader = null }
    private var shaderCache: Shader? = null
    private var shadeW = 0f
    private var shadeH = 0f
    override fun onDraw(canvas: Canvas) {
        val w = width.toFloat(); val h = height.toFloat()
        if (w <= 0f || h <= 0f) return
        if (shaderCache == null || shadeW != w || shadeH != h) {
            shaderCache = RadialGradient(w * 0.22f, h * 0.18f, maxOf(w, h) * 0.85f,
                intArrayOf(0x4d7c5cff, 0x246b48ff, 0x00000000), floatArrayOf(0f, 0.45f, 1f), Shader.TileMode.CLAMP)
            shadeW = w; shadeH = h
        }
        paint.shader = shaderCache
        canvas.drawRect(0f, 0f, w, h, paint)
    }
}

/** Small uppercase label used above section headlines. */
fun Context.eyebrow(value: String) = TextView(this).apply {
    text = value.uppercase(java.util.Locale.US)
    textSize = 10f
    letterSpacing = 0.18f
    setTextColor(Hd.gold)
    includeFontPadding = false
    typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
}

/** Premium primary action: amber fill, dark label, 48dp target. */
fun ImageButton.premium(context: Context) {
    background = Hd.primaryButton(context)
    imageTintList = ColorStateList.valueOf(Hd.background)
    contentDescription = contentDescription ?: "Action"
    minimumWidth = context.dp(48); minimumHeight = context.dp(48)
}

/** Rounded glass frame for the floating dock. */
fun glassDock(context: Context): Drawable = GradientDrawable().apply {
    setColor(0xe60d1016.toInt())
    cornerRadius = context.dp(26).toFloat()
    setStroke(context.dp(1), 0x33ffffff)
}
