package com.waqas.hdrama

import android.app.AlertDialog
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.*
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.widget.*

val accent = Color.rgb(164,145,255)
object AppColors {
    val background = 0xff101016.toInt()
    val surface = 0xff1d1d28.toInt()
    val raised = 0xff272735.toInt()
    val stroke = 0xff393948.toInt()
    val muted = 0xffb6b5c8.toInt()
    /** Opaque card surface used by the browser dock and list rows. */
    val card = 0xff16161f.toInt()
    /** Translucent dock/pill surface above the website. */
    val overlay = 0xf0161620.toInt()
    /** Destructive confirmation actions. */
    val danger = 0xffff627d.toInt()
    /** Saved (filled) favorite heart. */
    val heart = 0xffff304f.toInt()
}
fun Context.dp(n: Int) = (n * resources.displayMetrics.density).toInt()
fun Context.label(value: String, size: Float = 16f) = TextView(this).apply {
    text = value; textSize = size; setTextColor(0xfff6f5fa.toInt()); includeFontPadding = false
}
fun Context.surface(color: Int = AppColors.surface, radius: Int = 16, interactive: Boolean = false): android.graphics.drawable.Drawable {
    val shape = GradientDrawable().apply { setColor(color); cornerRadius = dp(radius).toFloat(); setStroke(dp(1),AppColors.stroke) }
    return if (interactive) RippleDrawable(ColorStateList.valueOf(0x33ffffff),shape,null) else shape
}
fun Context.button(value: String, action: () -> Unit) = Button(this).apply {
    text = value; isAllCaps = false; textSize = 13f; minWidth = 0; minimumWidth = 0
    minHeight = dp(48); minimumHeight = dp(48); includeFontPadding = false
    typeface = Typeface.create("sans-serif-medium",Typeface.NORMAL)
    setPadding(dp(12),dp(10),dp(12),dp(10)); maxLines = 2
    background = android.graphics.drawable.StateListDrawable().apply {
        addState(intArrayOf(-android.R.attr.state_enabled),surface(AppColors.background,12))
        addState(intArrayOf(),surface(AppColors.raised,12,true))
    }
    setTextColor(ColorStateList(arrayOf(intArrayOf(-android.R.attr.state_enabled),intArrayOf()),intArrayOf(0xff747487.toInt(),Color.WHITE)))
    setOnClickListener { action() }; contentDescription = value
}
fun Button.primary(context: Context) {
    background = StateListDrawable().apply {
        addState(intArrayOf(-android.R.attr.state_enabled),context.surface(AppColors.raised,12))
        addState(intArrayOf(),context.surface(accent,12,true))
    }
    setTextColor(ColorStateList(arrayOf(intArrayOf(-android.R.attr.state_enabled),intArrayOf()),intArrayOf(AppColors.muted,AppColors.background)))
}
fun Context.column() = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
fun Context.row() = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
fun View.pad(n: Int) { val d = context.dp(n); setPadding(d,d,d,d) }
fun View.rounded(color: Int) { background = GradientDrawable().apply { setColor(color); cornerRadius = context.dp(16).toFloat() } }
fun LinearLayout.weight(view: View) { addView(view,LinearLayout.LayoutParams(0,-2,1f).apply { if (childCount > 0) marginStart = context.dp(8) }) }
fun Context.screenHeader(value: String,onBack: () -> Unit): Pair<LinearLayout,TextView> {
    val title = label(value,24f).apply { typeface = Typeface.DEFAULT_BOLD; maxLines = 1; ellipsize = TextUtils.TruncateAt.END }
    val header = row().apply {
        setPadding(0,dp(4),0,dp(12))
        addView(ImageButton(this@screenHeader).apply {
            setImageDrawable(PlayerIcon("back")); background = surface(AppColors.raised,14,true)
            setPadding(dp(12),dp(12),dp(12),dp(12)); contentDescription = "Back"; setOnClickListener { onBack() }
        },LinearLayout.LayoutParams(dp(48),dp(48)))
        addView(title,LinearLayout.LayoutParams(0,-2,1f).apply { marginStart = dp(14) })
    }
    return header to title
}
fun Context.poster(url: String,title: String,width: Int = 72,height: Int = 104,description: String = "$title poster") = ImageView(this).apply {
    tag = "poster:$url"; contentDescription = description; background = surface(AppColors.raised,12); clipToOutline = true
    val image = SeriesArtwork.bitmap(this@poster,url)
    if (image == null) { setImageDrawable(PlayerIcon("film")); scaleType = ImageView.ScaleType.FIT_CENTER; setPadding(dp(18),dp(18),dp(18),dp(18)) }
    else { scaleType = ImageView.ScaleType.CENTER_CROP; setImageBitmap(image) }
    layoutParams = LinearLayout.LayoutParams(dp(width),dp(height))
}
/** Replace only visible artwork, preserving scrolling, focus and in-progress long presses. */
fun View.refreshPosters() {
    if (this is ImageView && tag?.toString()?.startsWith("poster:") == true) {
        SeriesArtwork.bitmap(context,tag.toString().removePrefix("poster:"))?.let {
            scaleType = ImageView.ScaleType.CENTER_CROP; setPadding(0,0,0,0); setImageBitmap(it)
        }
    }
    if (this is android.view.ViewGroup) for (i in 0 until childCount) getChildAt(i).refreshPosters()
}
fun Context.seriesCard(url: String,title: String,subtitle: String,detail: String,description: String = "$title poster") = row().apply {
    setPadding(dp(14),dp(14),dp(14),dp(14)); background = surface(interactive = true)
    addView(poster(url,title,description = description))
    addView(column().apply {
        addView(label(title,17f).apply { maxLines = 3; ellipsize = TextUtils.TruncateAt.END; typeface = Typeface.DEFAULT_BOLD })
        addView(label(subtitle,12f).apply { setTextColor(AppColors.muted); setPadding(0,dp(8),0,dp(8)) })
        addView(label(detail,13f).apply { setTextColor(accent); maxLines = 2; ellipsize = TextUtils.TruncateAt.END })
    },LinearLayout.LayoutParams(0,-2,1f).apply { marginStart = dp(14) })
}
fun Context.emptyState(symbol: String,title: String,message: String) = column().apply {
    gravity = Gravity.CENTER; setPadding(dp(24),dp(40),dp(24),dp(40))
    addView(ImageView(this@emptyState).apply { setImageDrawable(PlayerIcon(symbol)); imageTintList = ColorStateList.valueOf(accent); contentDescription = null },LinearLayout.LayoutParams(dp(44),dp(44)))
    addView(label(title,18f).apply { typeface = Typeface.DEFAULT_BOLD; gravity = Gravity.CENTER },LinearLayout.LayoutParams(-1,-2).apply { topMargin = dp(18) })
    addView(label(message,14f).apply { setTextColor(AppColors.muted); gravity = Gravity.CENTER; setLineSpacing(dp(3).toFloat(),1f) },LinearLayout.LayoutParams(-1,-2).apply { topMargin = dp(10) })
}
fun polishDialog(dialog: AlertDialog): AlertDialog {
    val context = dialog.context
    dialog.window?.setBackgroundDrawable(context.surface(AppColors.surface,20))
    listOf(AlertDialog.BUTTON_POSITIVE,AlertDialog.BUTTON_NEGATIVE,AlertDialog.BUTTON_NEUTRAL).forEach { id ->
        dialog.getButton(id)?.apply { isAllCaps = false; setTextColor(if (text.toString() in listOf("Delete","Clear")) AppColors.danger else accent); minHeight = context.dp(48) }
    }
    return dialog
}
/** Center the browser dock on large screens and shrink its square targets only when necessary. */
class BrowserDock(context: Context) : LinearLayout(context) {
    override fun onMeasure(widthMeasureSpec: Int,heightMeasureSpec: Int) {
        val width = minOf(MeasureSpec.getSize(widthMeasureSpec),context.dp(440))
        val visible = (0 until childCount).map { getChildAt(it) }.filter { it.visibility != GONE }
        val target = minOf(context.dp(64),(width-paddingLeft-paddingRight)/visible.size.coerceAtLeast(1)).coerceAtLeast(context.dp(48))
        visible.forEach { cell ->
            ((cell as? LinearLayout)?.getChildAt(0) as? ImageButton)?.let { button ->
                if (button.layoutParams.width != target) button.layoutParams = (button.layoutParams as LayoutParams).apply { this.width = target; height = target }
            }
        }
        super.onMeasure(MeasureSpec.makeMeasureSpec(width,MeasureSpec.EXACTLY),heightMeasureSpec)
    }
}
fun time(ms: Long): String {
    val sec = ms.coerceAtLeast(0)/1000
    // Fixed locale keeps timestamps in Latin digits on every device language.
    return if (sec >= 3600) String.format(java.util.Locale.US,"%d:%02d:%02d",sec/3600,sec/60%60,sec%60) else String.format(java.util.Locale.US,"%d:%02d",sec/60,sec%60)
}
