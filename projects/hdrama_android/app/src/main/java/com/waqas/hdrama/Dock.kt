package com.waqas.hdrama

import android.content.Context
import android.view.Gravity
import android.widget.ImageButton
import android.widget.LinearLayout

/**
 * Floating navigation dock (premium).
 * Glass surface with a compact centred width on tablets and a 48dp minimum target.
 * MainActivity still supplies the buttons so navigation behaviour is unchanged.
 */
class Dock(context: Context) : LinearLayout(context) {

    init {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER
        setPadding(context.dp(10), context.dp(8), context.dp(10), context.dp(8))
        background = Premium.frame(context)
        elevation = context.dp(Premium.DOCK_ELEVATION_DP).toFloat()
        clipToOutline = true
        contentDescription = "Navigation dock"
    }

    /** Keep the dock a compact island instead of stretching across wide windows. */
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = minOf(MeasureSpec.getSize(widthMeasureSpec), context.dp(Premium.DOCK_MAX_WIDTH_DP))
        val visible = (0 until childCount).map { getChildAt(it) }.filter { it.visibility != GONE }
        val usable = (width - paddingLeft - paddingRight).coerceAtLeast(1)
        val target = minOf(context.dp(Premium.TARGET_DP), usable / visible.size.coerceAtLeast(1))
            .coerceAtLeast(context.dp(Premium.MIN_TARGET_DP))
        visible.forEach { cell ->
            ((cell as? LinearLayout)?.getChildAt(0) as? ImageButton)?.let { button ->
                if (button.layoutParams.width != target) {
                    button.layoutParams = (button.layoutParams as LayoutParams).apply { this.width = target; height = target }
                }
            }
        }
        super.onMeasure(MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY), heightMeasureSpec)
    }
}
