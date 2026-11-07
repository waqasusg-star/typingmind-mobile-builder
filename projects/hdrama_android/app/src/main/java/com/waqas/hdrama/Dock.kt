package com.waqas.hdrama

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Floating navigation dock (premium).
 * Glass surface, amber primary Play target, and a compact centred width on tablets.
 */
class Dock : LinearLayout {
    constructor(context: Context) : super(context) { build() }

    private lateinit var cells: List<Pair<String, ImageButton>>

    private fun build() {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER
        setPadding(context.dp(10), context.dp(8), context.dp(10), context.dp(8))
        background = Hd.glassFrame(context)
        elevation = context.dp(12).toFloat()
        clipToOutline = true
        contentDescription = "Navigation dock"
    }

    companion object {
        /** Reference width so the dock stays a compact island on wide windows. */
        fun maxWidth(context: Context): Int = context.dp(440)
    }
}

/** Amber-tinted status pill used above the dock to reflect page state. */
class DockPill(context: Context) : TextView(context) {
    init {
        gravity = Gravity.CENTER
        textSize = 11f
        letterSpacing = 0.08f
        setTextColor(Hd.muted)
        includeFontPadding = false
        background = Hd.pill(context, 0xd90b0d13.toInt())
        setPadding(context.dp(14), context.dp(8), context.dp(14), context.dp(8))
    }
}
