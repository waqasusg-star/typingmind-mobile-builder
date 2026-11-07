package com.waqas.hdrama

import android.graphics.Typeface
import android.view.Gravity

/**
 * Premium visual constants shared by the native screens.
 *
 * The dock keeps a glass look, the primary play target is the only amber-filled control,
 * and every other control stays a quiet raised surface so the hierarchy is obvious.
 */
object Premium {
    const val DOCK_MAX_WIDTH_DP = 440
    const val DOCK_CORNER_DP = 26
    const val DOCK_ELEVATION_DP = 12
    const val TARGET_DP = 64
    const val MIN_TARGET_DP = 48
    const val LABEL_ALPHA = 0.78f

    fun dockBackground(): Int = 0xe60d1016.toInt()
    fun dockStroke(): Int = 0x33ffffff

    /** Rebuild the dock's glass frame at the current density. */
    fun frame(context: android.content.Context) = android.graphics.drawable.GradientDrawable().apply {
        setColor(dockBackground())
        cornerRadius = context.dp(DOCK_CORNER_DP).toFloat()
        setStroke(context.dp(1), dockStroke())
    }

    fun label(text: android.widget.TextView) {
        text.textSize = 10.5f
        text.letterSpacing = 0.06f
        text.gravity = Gravity.CENTER
        text.setTextColor(0xffe8e6ef.toInt())
        text.typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
        text.alpha = LABEL_ALPHA
    }
}
