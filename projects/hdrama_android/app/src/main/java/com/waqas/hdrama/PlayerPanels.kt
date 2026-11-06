@file:androidx.annotation.OptIn(markerClass = [androidx.media3.common.util.UnstableApi::class])

package com.waqas.hdrama

import android.app.Activity
import android.app.Dialog
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.*
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.media3.common.*
import androidx.media3.exoplayer.ExoPlayer

data class VideoQuality(val pixels: Int, val group: TrackGroup, val track: Int)
object QualityOptions {
    fun pixels(format: Format): Int = if (format.width > 0 && format.height > 0) minOf(format.width, format.height) else 0
    fun available(tracks: Tracks): List<VideoQuality> = tracks.groups.filter { it.type == C.TRACK_TYPE_VIDEO }.flatMap { group ->
        (0 until group.length).filter { group.isTrackSupported(it) && pixels(group.getTrackFormat(it)) > 0 }
            .map { VideoQuality(pixels(group.getTrackFormat(it)), group.mediaTrackGroup, it) }
    }.distinctBy { it.pixels }.sortedByDescending { it.pixels }
    fun nearest(values: List<Int>, preferred: Int): Int? = values.filter { it <= preferred }.maxOrNull() ?: values.minOrNull()
    fun apply(player: ExoPlayer, preferred: Int) {
        val builder = player.trackSelectionParameters.buildUpon().clearOverridesOfType(C.TRACK_TYPE_VIDEO)
        if (preferred > 0) {
            val options = available(player.currentTracks)
            val target = nearest(options.map { it.pixels }, preferred)
            options.firstOrNull { it.pixels == target }?.let { builder.addOverride(TrackSelectionOverride(it.group, it.track)) }
        }
        val parameters = builder.build()
        if (parameters != player.trackSelectionParameters) player.trackSelectionParameters = parameters
    }
}

/** Keep the sheet within the current app window when the device rotates. */
class PlayerSheetDialog(private val owner: Activity) : Dialog(owner) {
    var preferredHeight: Int? = null
    private val changes = object : android.content.ComponentCallbacks {
        override fun onConfigurationChanged(configuration: android.content.res.Configuration) {
            window?.decorView?.post { fitWindow() }
        }
        override fun onLowMemory() {}
    }
    override fun onStart() { super.onStart(); owner.applicationContext.registerComponentCallbacks(changes) }
    override fun onStop() { owner.applicationContext.unregisterComponentCallbacks(changes); super.onStop() }
    fun fitWindow() {
        val metrics = owner.resources.displayMetrics
        val wide = metrics.widthPixels > metrics.heightPixels
        val limit = minOf((metrics.heightPixels * if (wide) .90f else .72f).toInt(),owner.dp(620))
        window?.setLayout(minOf(metrics.widthPixels,owner.dp(640)),minOf(preferredHeight ?: limit,limit))
    }
}
/** Prioritize the episode grid over repeated metadata in short windows. */
class SheetContent(context: android.content.Context) : LinearLayout(context) {
    private var body: LinearLayout? = null
    private var original = emptyList<View>()
    private var compact: Boolean? = null
    fun body(column: LinearLayout) { body = column; original = (0 until column.childCount).map { column.getChildAt(it) } }
    override fun onMeasure(widthMeasureSpec: Int,heightMeasureSpec: Int) {
        val wide = MeasureSpec.getSize(widthMeasureSpec) > MeasureSpec.getSize(heightMeasureSpec)
        if (compact != wide) {
            compact = wide
            val ordered = if (wide && original.any { it.tag == "sheet-grid" })
                original.filter { it.tag == "sheet-ranges" || it.tag == "sheet-grid" } + original.filterNot { it.tag == "sheet-ranges" || it.tag == "sheet-grid" }
                else original
            body?.removeAllViews()
            ordered.forEach { view ->
                if (view.tag == "sheet-secondary") view.visibility = if (wide) View.GONE else View.VISIBLE
                body?.addView(view)
            }
        }
        super.onMeasure(widthMeasureSpec,heightMeasureSpec)
    }
}

/** Bottom sheets leave the video visible above them and keep long episode lists inside the sheet. */
fun playerSheet(activity: Activity, title: String, body: LinearLayout.() -> Unit): Dialog {
    val dialog = PlayerSheetDialog(activity)
    val content = SheetContent(activity).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(activity.dp(16),activity.dp(10),activity.dp(16),activity.dp(16))
        background = GradientDrawable().apply {
            setColor(AppColors.background)
            cornerRadii = floatArrayOf(24f,24f,24f,24f,0f,0f,0f,0f).map { it * resources.displayMetrics.density }.toFloatArray()
        }
        addView(View(activity).apply { rounded(AppColors.stroke) },LinearLayout.LayoutParams(activity.dp(40),activity.dp(4)).apply { gravity = Gravity.CENTER_HORIZONTAL; bottomMargin = activity.dp(12) })
        addView(activity.row().apply {
            addView(activity.label(title,21f).apply { typeface = Typeface.DEFAULT_BOLD; maxLines = 2 },LinearLayout.LayoutParams(0,-2,1f))
            addView(ImageButton(activity).apply {
                setImageDrawable(PlayerIcon("close")); background = activity.surface(AppColors.raised,12,true)
                setPadding(activity.dp(13),activity.dp(13),activity.dp(13),activity.dp(13)); contentDescription = "Close $title"
                setOnClickListener { dialog.dismiss() }
            },LinearLayout.LayoutParams(activity.dp(48),activity.dp(48)))
        },LinearLayout.LayoutParams(-1,-2).apply { bottomMargin = activity.dp(12) })
    }
    val bodyContent = activity.column().apply { body() }
    // Scroll all controls in short windows instead of allowing fixed headers to squeeze the episode grid to zero.
    val children = (0 until bodyContent.childCount).map { bodyContent.getChildAt(it) }
    children.forEach { child ->
        if (child is ScrollView && child.childCount == 1) {
            val index = bodyContent.indexOfChild(child); val nested = child.getChildAt(0)
            child.removeView(nested); bodyContent.removeViewAt(index)
            bodyContent.addView(nested,index,LinearLayout.LayoutParams(-1,-2))
        } else (child.layoutParams as? LinearLayout.LayoutParams)?.let { params ->
            if (params.height == 0 && params.weight > 0) { params.height = -2; params.weight = 0f }
        }
    }
    val footer = (bodyContent.getChildAt(bodyContent.childCount-1) as? Button)?.takeIf { it.text == "Download selected" }
    footer?.let { bodyContent.removeView(it); it.primary(activity) }
    content.body(bodyContent)
    content.addView(ScrollView(activity).apply { isVerticalScrollBarEnabled = false; addView(bodyContent) },LinearLayout.LayoutParams(-1,0,1f))
    footer?.let { content.addView(it,LinearLayout.LayoutParams(-1,activity.dp(48)).apply { topMargin = activity.dp(12) }) }
    androidx.core.view.ViewCompat.setOnApplyWindowInsetsListener(content) { v,insets ->
        val safe = insets.getInsets(WindowInsetsCompat.Type.navigationBars() or WindowInsetsCompat.Type.displayCutout())
        val gestures = insets.getInsets(WindowInsetsCompat.Type.mandatorySystemGestures())
        v.setPadding(activity.dp(16)+safe.left,activity.dp(10),activity.dp(16)+safe.right,activity.dp(16)+maxOf(safe.bottom,gestures.bottom))
        WindowInsetsCompat.CONSUMED
    }
    dialog.setContentView(content)
    dialog.window?.apply {
        setBackgroundDrawableResource(android.R.color.transparent)
        addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
        setDimAmount(.15f); setGravity(Gravity.BOTTOM)
    }
    dialog.show()
    dialog.window?.apply {
        dialog.fitWindow()
        WindowCompat.setDecorFitsSystemWindows(this,false)
        WindowCompat.getInsetsController(this,decorView).apply {
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_DEFAULT
            show(WindowInsetsCompat.Type.systemBars())
        }
    }
    return dialog
}

fun qualitySheet(activity: Activity, player: ExoPlayer, preferred: Int, onSelect: (Int) -> Unit): Dialog {
    var dialog: Dialog? = null
    val choices = QualityOptions.available(player.currentTracks)
    val selected = if (preferred > 0) QualityOptions.nearest(choices.map { it.pixels },preferred) ?: 0 else 0
    dialog = playerSheet(activity,"Quality") {
        val list = activity.column()
        fun option(value: String, pixels: Int) {
            list.addView(activity.label(value + if (selected == pixels) "    ✓" else "",18f).apply {
                gravity = Gravity.CENTER_VERTICAL; setPadding(activity.dp(16),0,activity.dp(16),0)
                setTextColor(if (selected == pixels) accent else Color.WHITE)
                if (selected == pixels) background = activity.surface(AppColors.raised,12,true)
                isFocusable = true; contentDescription = value + if (selected == pixels) ", selected" else ""
                setOnClickListener { onSelect(pixels); dialog?.dismiss() }
            },LinearLayout.LayoutParams(-1,activity.dp(56)).apply { topMargin = activity.dp(6) })
        }
        option("Auto",0)
        choices.forEach { option("${it.pixels}P",it.pixels) }
        if (choices.size <= 1) list.addView(activity.label(if (choices.isEmpty()) "Quality options appear when the video is ready." else "This source offers one video quality.",12f).apply { alpha = .6f; pad(16) })
        addView(ScrollView(activity).apply { addView(list) },LinearLayout.LayoutParams(-1,0,1f))
    }
    (dialog as? PlayerSheetDialog)?.apply { preferredHeight = activity.dp(120 + (choices.size + 1) * 62 + if (choices.size <= 1) 48 else 0); fitWindow() }
    return dialog
}

fun episodeSheet(activity: Activity, series: Series, current: Int, downloadMode: Boolean = false,
    onEpisode: (Int) -> Unit = {}, onDownload: (List<Int>) -> Unit = {},
    downloadQualities: List<Int> = emptyList(), downloadQuality: Int = 0, onDownloadQuality: (Int) -> Unit = {}): Dialog {
    var dialog: Dialog? = null
    val picked = linkedSetOf(current)
    var downloadButton: Button? = null
    var selectionInfo: TextView? = null
    dialog = playerSheet(activity,if (downloadMode) "Download episodes" else "Episodes") {
        addView(activity.label(series.title,18f).apply { tag = "sheet-secondary"; maxLines = 2; ellipsize = android.text.TextUtils.TruncateAt.END; pad(8) })
        selectionInfo = activity.label("${series.episodes.size} episodes · " + if (downloadMode) "Choose episodes to save" else "Tap an episode to play",12f).apply { tag = "sheet-secondary"; setTextColor(AppColors.muted); pad(8) }
        addView(selectionInfo)
        if (downloadMode) {
            val values = (listOf(0) + downloadQualities + listOf(downloadQuality)).distinct()
            addView(activity.label("Download quality",12f).apply { tag = "sheet-secondary"; setTextColor(AppColors.muted); pad(8) })
            addView(Spinner(activity).apply {
                contentDescription = "Download quality"
                adapter = ArrayAdapter(activity,android.R.layout.simple_spinner_dropdown_item,values.map { if (it == 0) "Best available" else "Up to ${it}P" })
                setSelection(values.indexOf(downloadQuality).coerceAtLeast(0))
                onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
                    override fun onItemSelected(parent: AdapterView<*>?,view: View?,position: Int,id: Long) { onDownloadQuality(values[position]) }
                    override fun onNothingSelected(parent: AdapterView<*>?) {}
                }
            },LinearLayout.LayoutParams(-1,activity.dp(48)))
        }
        val tabs = activity.row()
        val grid = GridLayout(activity).apply { tag = "sheet-grid"; columnCount = 5 }
        val scroller = ScrollView(activity).apply { addView(grid) }
        var activeRange = current / 30
        fun populate(range: Int) {
            activeRange = range; grid.removeAllViews()
            if (downloadMode) { selectionInfo?.text = "${picked.size} selected · ${series.episodes.size} episodes"; downloadButton?.isEnabled = picked.isNotEmpty() }
            val entries = series.episodes.indices.filter { it / 30 == range }
            entries.forEachIndexed { cell, i ->
                val downloaded = OfflineStore.completed(activity,series.episodes[i].pageUrl) != null
                val selected = if (downloadMode) i in picked else i == current
                val label = series.episodes[i].number.toString()
                grid.addView(activity.label(label + if (downloaded) "\n✓" else "",17f).apply {
                    gravity = Gravity.CENTER
                    setTextColor(if (selected) accent else Color.WHITE); typeface = Typeface.DEFAULT_BOLD
                    background = activity.surface(if (selected) 0xff322b40.toInt() else AppColors.surface,12,true); isFocusable = true
                    contentDescription = "Episode ${series.episodes[i].number}" + (if (downloaded) ", downloaded" else "") + (if (selected) ", selected" else "")
                    setOnClickListener {
                        if (downloadMode) { if (!picked.add(i)) picked.remove(i); populate(activeRange) }
                        else { dialog?.dismiss(); onEpisode(i) }
                    }
                },GridLayout.LayoutParams(GridLayout.spec(cell / 5),GridLayout.spec(cell % 5,1f)).apply {
                    width = 0; height = activity.dp(54); setMargins(activity.dp(3),activity.dp(3),activity.dp(3),activity.dp(3))
                })
            }
            repeat((5 - entries.size % 5) % 5) { offset ->
                val cell = entries.size + offset
                grid.addView(View(activity),GridLayout.LayoutParams(GridLayout.spec(cell / 5),GridLayout.spec(cell % 5,1f)).apply { width = 0; height = activity.dp(54); setMargins(activity.dp(3),activity.dp(3),activity.dp(3),activity.dp(3)) })
            }
            for (i in 0 until tabs.childCount) (tabs.getChildAt(i) as TextView).apply {
                setTextColor(if (i == range) accent else AppColors.muted)
                background = activity.surface(if (i == range) AppColors.raised else AppColors.background,12,true)
                isSelected = i == range
            }
        }
        val ranges = series.episodes.indices.chunked(30)
        ranges.forEachIndexed { range, values ->
            tabs.addView(activity.label("${series.episodes[values.first()].number}–${series.episodes[values.last()].number}",15f).apply {
                pad(12); minHeight = activity.dp(48); gravity = Gravity.CENTER; isFocusable = true; setOnClickListener { populate(range) }
            },LinearLayout.LayoutParams(-2,-2).apply { marginEnd = activity.dp(8) })
        }
        addView(HorizontalScrollView(activity).apply { tag = "sheet-ranges"; isHorizontalScrollBarEnabled = false; addView(tabs) })
        if (downloadMode) addView(activity.row().apply {
            weight(activity.button("Select all") { picked.addAll(series.episodes.indices); populate(activeRange) })
            weight(activity.button("Clear") { picked.clear(); populate(activeRange) })
        })
        addView(scroller,LinearLayout.LayoutParams(-1,0,1f))
        if (downloadMode) {
            downloadButton = activity.button("Download selected") {
            if (picked.isNotEmpty()) { onDownload(picked.sorted()); dialog?.dismiss() }
            else Toast.makeText(activity,"Select at least one episode",Toast.LENGTH_SHORT).show()
            }
            addView(downloadButton,LinearLayout.LayoutParams(-1,activity.dp(48)))
        }
        populate(activeRange)
    }
    return dialog
}
