package com.waqas.hdrama

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

/** Cinematic component library: glass panels, hero fades, stat tiles, tabs and badges. */
object Visual {
    const val RADIUS_LG = 24
    const val RADIUS_MD = 16
    const val RADIUS_SM = 12

    /** Deep glass panel: translucent fill plus a hairline light edge. */
    fun glass(context: Context, alpha: Int = 0xd9): GradientDrawable = GradientDrawable().apply {
        setColor((alpha shl 24) or 0x14161f)
        cornerRadius = context.dp(RADIUS_LG).toFloat()
        setStroke(context.dp(1), 0x26ffffff)
    }

    /** Elevated amber call-to-action. */
    fun cta(context: Context): RippleDrawable = RippleDrawable(
        ColorStateList.valueOf(0x40ffffff),
        GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT, intArrayOf(Hd.gold, 0xffffd98a.toInt())).apply {
            cornerRadius = context.dp(RADIUS_MD).toFloat()
        }, null)

    /** Top fade used behind hero headers. */
    fun heroFade(): GradientDrawable = GradientDrawable(
        GradientDrawable.Orientation.TOP_BOTTOM,
        intArrayOf(0xcc07080d.toInt(), 0x0007080d))

    /** Rounded portrait poster frame with a subtle outline. */
    fun posterFrame(context: Context): GradientDrawable = GradientDrawable().apply {
        setColor(Hd.raised)
        cornerRadius = context.dp(RADIUS_MD).toFloat()
        setStroke(context.dp(1), 0x1affffff)
    }

    /** Feature tile: large value above a quiet caption. */
    fun stat(context: Context, value: String, caption: String): LinearLayout = context.column().apply {
        gravity = Gravity.CENTER
        setPadding(context.dp(12), context.dp(14), context.dp(12), context.dp(14))
        background = glass(context, 0xcc)
        addView(context.label(value, 20f).apply {
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            gravity = Gravity.CENTER
        })
        addView(context.label(caption, 10.5f).apply {
            setTextColor(Hd.muted)
            letterSpacing = 0.08f
            gravity = Gravity.CENTER
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
            setPadding(0, context.dp(4), 0, 0)
        })
    }

    /** Selectable pill used for section switching. */
    fun tab(context: Context, value: String, selected: Boolean, onTap: () -> Unit): TextView =
        context.label(value, 13.5f).apply {
            gravity = Gravity.CENTER
            isFocusable = true
            includeFontPadding = false
            minHeight = context.dp(40)
            setPadding(context.dp(16), context.dp(8), context.dp(16), context.dp(8))
            contentDescription = if (selected) "$value, selected" else value
            setTextColor(if (selected) Hd.background else Hd.muted)
            background = if (selected) cta(context) else glass(context, 0x99)
            setOnClickListener { onTap() }
        }

    /** Screen body: aurora behind, transparent content column on top. */
    fun auroraScreen(context: Context): Pair<FrameLayout, LinearLayout> {
        val root = FrameLayout(context)
        root.addView(AuroraView(context), FrameLayout.LayoutParams(-1, -1))
        val content = context.column().apply { setBackgroundColor(0x00000000) }
        root.addView(content, FrameLayout.LayoutParams(-1, -1))
        return root to content
    }

    /** Thin accent rule under headings. */
    fun accentRule(context: Context): View = View(context).apply {
        background = GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT, intArrayOf(Hd.gold, 0x00f5b544)).apply {
            cornerRadius = context.dp(2).toFloat()
        }
    }

    /** State badge such as OFFLINE, NEW or HD. */
    fun badge(context: Context, value: String, color: Int = Hd.gold): TextView =
        context.label(value.uppercase(java.util.Locale.US), 9.5f).apply {
            letterSpacing = 0.1f
            includeFontPadding = false
            setTextColor(color)
            setPadding(context.dp(8), context.dp(4), context.dp(8), context.dp(4))
            background = GradientDrawable().apply {
                setColor(0x24ffffff)
                cornerRadius = context.dp(RADIUS_SM).toFloat()
                setStroke(context.dp(1), 0x33ffffff)
            }
        }
}
