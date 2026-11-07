package com.waqas.hdrama

import android.app.Activity
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.SeekBar
import android.widget.TextView

/**
 * Premium building blocks used by every native screen.
 *
 * These helpers only construct views. All colours come from [AppColors]/[Hd] so a theme change
 * applies everywhere instead of drifting per screen.
 */
object Kit {
    /** Section heading with a small amber eyebrow, e.g. "CONTINUE" above "Recently watched". */
    fun section(context: Context, eyebrowText: String, title: String): LinearLayout = context.column().apply {
        setPadding(0, context.dp(18), 0, context.dp(10))
        addView(context.eyebrow(eyebrowText))
        addView(context.label(title, 19f).apply {
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            letterSpacing = -0.01f
            setPadding(0, context.dp(6), 0, 0)
        })
    }

    /** Elevated card container with consistent padding and radius. */
    fun card(context: Context): LinearLayout = context.column().apply {
        background = Hd.card(context, true)
        elevation = context.dp(3).toFloat()
        setPadding(context.dp(16), context.dp(14), context.dp(16), context.dp(14))
    }

    /**
     * Episode / quality choice chip.
     * Selected chips use an amber wash plus amber text; unselected chips stay quiet surfaces.
     */
    fun chip(context: Context, value: String, selected: Boolean, onTap: () -> Unit): TextView =
        context.label(value, 14f).apply {
            gravity = Gravity.CENTER
            includeFontPadding = false
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
            minWidth = context.dp(48)
            minHeight = context.dp(44)
            isFocusable = true
            contentDescription = if (selected) "$value, selected" else value
            background = if (selected) RippleSelected(context) else Hd.card(context)
            setTextColor(if (selected) Hd.gold else Hd.text)
            setPadding(context.dp(12), context.dp(10), context.dp(12), context.dp(10))
            setOnClickListener { onTap() }
        }

    /** Amber wash for a selected chip; kept separate so tests can assert the selection colour. */
    fun RippleSelected(context: Context): GradientDrawable = GradientDrawable().apply {
        setColor(Hd.goldSoft)
        cornerRadius = context.dp(12).toFloat()
        setStroke(context.dp(1), Hd.gold)
    }

    /** Circular glass control for icon-only actions (48dp minimum target). */
    fun iconButton(context: Context, symbol: String, description: String, onTap: (View) -> Unit): ImageButton =
        ImageButton(context).apply {
            setImageDrawable(PlayerIcon(symbol))
            scaleType = ImageView.ScaleType.FIT_CENTER
            setPadding(context.dp(13), context.dp(13), context.dp(13), context.dp(13))
            imageTintList = ColorStateList.valueOf(Hd.text)
            background = Hd.pill(context, Hd.raised)
            contentDescription = description
            minimumWidth = context.dp(48)
            minimumHeight = context.dp(48)
            setOnClickListener { onTap(it) }
        }

    /** Amber progress track matching the player transport styling. */
    fun styleProgress(context: Context, bar: SeekBar) {
        bar.progressTintList = ColorStateList.valueOf(Hd.gold)
        bar.progressBackgroundTintList = ColorStateList.valueOf(0x33ffffff)
        bar.secondaryProgressTintList = ColorStateList.valueOf(Hd.goldSoft)
        bar.thumbTintList = ColorStateList.valueOf(Hd.gold)
    }

    /** Screen scaffolding: deep background plus edge padding that matches the dock rhythm. */
    fun screen(activity: Activity): LinearLayout = activity.column().apply {
        setBackgroundColor(Hd.background)
        setPadding(activity.dp(18), activity.dp(10), activity.dp(18), activity.dp(18))
    }
}
