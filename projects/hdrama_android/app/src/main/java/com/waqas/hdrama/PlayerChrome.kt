package com.waqas.hdrama

import android.content.Context
import android.content.res.ColorStateList
import android.graphics.*
import android.graphics.drawable.*
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.widget.*

/** Native, non-scrolling chrome; the center is reserved for tapping/gestures. */
class PlayerChrome(context: Context, val actions: Actions) : FrameLayout(context) {
    data class Actions(
        val back: () -> Unit,
        val episodes: () -> Unit, val speed: () -> Unit,
        val rotate: () -> Unit, val fit: () -> Unit,
        val toggle: () -> Unit, val retry: () -> Unit, val access: () -> Unit,
        val favorite: () -> Unit = {}, val myList: () -> Unit = {}, val removeFavorite: () -> Unit = {},
        val quality: () -> Unit = {}, val download: () -> Unit = {}, val downloads: () -> Unit = {},
        val pip: () -> Unit = {}
    )
    val heading = text("Loading story…", 15f).apply {
        typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
        maxLines = 1; ellipsize = TextUtils.TruncateAt.END
    }
    val episode = text("", 13f).apply {
        gravity = Gravity.CENTER_VERTICAL; setPadding(context.dp(16),0,context.dp(16),0)
        background = GradientDrawable().apply { setColor(AppColors.card); cornerRadius = context.dp(10).toFloat() }
        val start = PlayerIcon("episodes").apply { setBounds(0,0,context.dp(20),context.dp(20)) }
        val end = PlayerIcon("chevron-up").apply { setBounds(0,0,context.dp(20),context.dp(20)) }
        setCompoundDrawables(start,null,end,null); compoundDrawablePadding = context.dp(8)
        contentDescription = "Episodes"; isFocusable = true; setOnClickListener { actions.episodes() }
    }
    val position = text("0:00 / --:--", 11f).apply { typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL) }
    val remaining = text("", 11f).apply { setTextColor(0xffbbb7c8.toInt()); gravity = Gravity.END }
    private val speedControl = sideAction("speed", "Playback speed", actions.speed)
    val speed = (speedControl.getChildAt(1) as TextView).apply { text = "Speed" }
    val runningEpisode = text("",13f).apply { setTextColor(0xffddd9e9.toInt()); maxLines = 1 }
    val seek = SeekBar(context).apply {
        max = 10_000; splitTrack = false
        progressTintList = ColorStateList.valueOf(accent)
        progressBackgroundTintList = ColorStateList.valueOf(0x66ffffff)
        secondaryProgressTintList = ColorStateList.valueOf(0xff9991af.toInt())
        thumbTintList = ColorStateList.valueOf(Color.WHITE)
        val track = { color: Int -> GradientDrawable().apply { setColor(color); cornerRadius = context.dp(2).toFloat() } }
        progressDrawable = LayerDrawable(arrayOf(
            track(0x66ffffff),
            ClipDrawable(track(0xff9991af.toInt()),Gravity.LEFT,ClipDrawable.HORIZONTAL),
            ClipDrawable(track(accent),Gravity.LEFT,ClipDrawable.HORIZONTAL)
        )).apply {
            setId(0,android.R.id.background); setId(1,android.R.id.secondaryProgress); setId(2,android.R.id.progress)
            for (i in 0..2) { setLayerHeight(i,context.dp(3)); setLayerGravity(i,Gravity.CENTER_VERTICAL) }
        }
        thumb = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(Color.WHITE); setSize(context.dp(10),context.dp(10)) }
        contentDescription = "Episode progress"
        setPadding(context.dp(4), 0, context.dp(4), 0)
    }
    val status = text("", 12f).apply { maxLines = 4 }
    val retry = actionText("Retry source", actions.retry)
    val access = actionText("Check website access", actions.access)
    val spinner = ProgressBar(context).apply { indeterminateTintList = ColorStateList.valueOf(accent); visibility = GONE }
    private val qualityControl = sideAction("quality", "Quality", actions.quality)
    private val downloadControl = sideAction("download", "Download", actions.download)
    val favoriteControl = sideAction("heart", "Favorite", actions.favorite)
    val myListControl = sideAction("list", "My List", actions.myList)
    val playPause = icon("pause", "Pause video") { actions.toggle() }
    var controlsVisible = true
        private set
    private val top = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER_VERTICAL
        background = GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, intArrayOf(0xb8000000.toInt(), 0x00000000))
    }
    private val progressPanel = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        background = GradientDrawable(GradientDrawable.Orientation.BOTTOM_TOP, intArrayOf(0xa6000000.toInt(), 0x00000000))
    }
    private val rail = GridLayout(context)
    private val errorPanel = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL; setPadding(context.dp(14),context.dp(12),context.dp(14),context.dp(12))
        background = GradientDrawable().apply { setColor(0xe51a1723.toInt()); cornerRadius = context.dp(18).toFloat() }
        visibility = GONE
    }
    private val feedback = text("", 14f).apply {
        gravity = Gravity.CENTER; setPadding(context.dp(20),context.dp(12),context.dp(20),context.dp(12))
        background = pill(); visibility = GONE; isClickable = false; isFocusable = false
    }
    private val clearFeedback = Runnable { feedback.animate().alpha(0f).setDuration(180).withEndAction { feedback.visibility = GONE }.start() }
    private var landscape = false
    private var compact = false
    private var safeLeft = 0; private var safeRight = 0; private var safeTop = 0; private var safeBottom = 0
    init {
        isClickable = false
        top.addView(LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.TOP
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                addView(heading,LinearLayout.LayoutParams(-1,-2))
                addView(runningEpisode,LinearLayout.LayoutParams(-1,-2).apply { topMargin = context.dp(6) })
            },LinearLayout.LayoutParams(0,-2,1f).apply { marginEnd = context.dp(12) })
            addView(icon("more", "Player options") { anchor -> showOptions(anchor) }, LinearLayout.LayoutParams(context.dp(48),context.dp(48)))
        })
        addView(top, LayoutParams(-1,context.dp(88),Gravity.TOP))
        addView(rail, LayoutParams(-2,-2,Gravity.END or Gravity.CENTER_VERTICAL))
        progressPanel.addView(LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL; addView(position,LinearLayout.LayoutParams(0,-2,1f)); addView(remaining,LinearLayout.LayoutParams(-2,-2))
        })
        progressPanel.addView(seek,LinearLayout.LayoutParams(-1,context.dp(36)))
        progressPanel.addView(episode,LinearLayout.LayoutParams(-1,context.dp(48)).apply { topMargin = context.dp(4) })
        addView(progressPanel,LayoutParams(-1,-2,Gravity.BOTTOM))
        errorPanel.addView(status); errorPanel.addView(retry); errorPanel.addView(access)
        retry.visibility = GONE; access.visibility = GONE
        addView(errorPanel,LayoutParams(-1,-2,Gravity.TOP))
        addView(spinner,LayoutParams(context.dp(40),context.dp(40),Gravity.CENTER))
        addView(playPause,LayoutParams(context.dp(64),context.dp(64),Gravity.CENTER))
        addView(feedback,LayoutParams(-2,-2,Gravity.CENTER).apply { topMargin = context.dp(128) })
        favoriteControl.setOnLongClickListener { actions.removeFavorite(); true }
        favoriteControl.getChildAt(0).setOnLongClickListener { actions.removeFavorite(); true }
        rebuildRail(false); applyInsets(0,0,0,0)
    }
    private fun text(value: String, size: Float) = context.label(value,size)
    private fun pill() = RippleDrawable(ColorStateList.valueOf(0x40ffffff), GradientDrawable().apply {
        setColor(0x800d0b14.toInt()); cornerRadius = context.dp(28).toFloat(); setStroke(context.dp(1),0x33ffffff)
    }, null)
    private fun icon(symbol: String, description: String, action: (View) -> Unit) = ImageButton(context).apply {
        setImageDrawable(PlayerIcon(symbol)); background = pill(); scaleType = ImageView.ScaleType.FIT_CENTER
        contentDescription = description; setPadding(context.dp(11),context.dp(11),context.dp(11),context.dp(11)); setOnClickListener { action(it) }
        minimumWidth = context.dp(48); minimumHeight = context.dp(48)
    }
    private fun sideAction(symbol: String, description: String, action: () -> Unit) = sideControl(symbol,description) { _: View -> action() }
    private fun sideControl(symbol: String, description: String, action: (View) -> Unit): LinearLayout = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER; contentDescription = description
        isClickable = true; isFocusable = true; setOnClickListener { action(it) }
        addView(icon(symbol,description,action).apply {
            background = RippleDrawable(ColorStateList.valueOf(0x40ffffff),GradientDrawable().apply {
                setColor(0x990e0f16.toInt()); cornerRadius = context.dp(16).toFloat(); setStroke(context.dp(1),0x40ffffff)
            },null)
        },LinearLayout.LayoutParams(context.dp(50),context.dp(50)))
        addView(text(description,10f).apply { gravity = Gravity.CENTER; setPadding(0,context.dp(5),0,0) })
    }
    private fun actionText(value: String, action: () -> Unit) = text(value,13f).apply {
        gravity = Gravity.CENTER; setTextColor(accent); minHeight = context.dp(48)
        background = pill(); setOnClickListener { action() }; isFocusable = true
    }
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val wide = View.MeasureSpec.getSize(widthMeasureSpec) > View.MeasureSpec.getSize(heightMeasureSpec)
        val small = View.MeasureSpec.getSize(heightMeasureSpec) < context.dp(700)
        if (wide != landscape || small != compact) { landscape = wide; compact = small; rebuildRail(wide); applyInsets(safeLeft,safeTop,safeRight,safeBottom) }
        if (!wide) {
            val height = View.MeasureSpec.getSize(heightMeasureSpec)
            val railHeight = context.dp(if (small) 290 else 390)
            (rail.layoutParams as LayoutParams).topMargin = minOf((height - railHeight)/2 + context.dp(56) + safeTop/2,
                height - safeBottom - context.dp(160) - railHeight).coerceAtLeast(safeTop + context.dp(90))
        }
        super.onMeasure(widthMeasureSpec,heightMeasureSpec)
    }
    private fun rebuildRail(wide: Boolean) {
        rail.removeAllViews(); rail.columnCount = if (wide) 2 else 1; rail.rowCount = if (wide) 3 else 5
        listOf(favoriteControl,myListControl,downloadControl,qualityControl,speedControl).forEachIndexed { i,v ->
            (v.getChildAt(0).layoutParams as LinearLayout.LayoutParams).apply { width = context.dp(if (wide) 40 else if (compact) 36 else 50); height = width }
            (v.getChildAt(0) as ImageButton).setPadding(context.dp(if (wide) 9 else if (compact) 8 else 11),context.dp(if (wide) 9 else if (compact) 8 else 11),context.dp(if (wide) 9 else if (compact) 8 else 11),context.dp(if (wide) 9 else if (compact) 8 else 11))
            (v.getChildAt(1) as TextView).apply { textSize = 10f; maxLines = 1; ellipsize = TextUtils.TruncateAt.END; setPadding(0,context.dp(5),0,0) }
            v.layoutParams = GridLayout.LayoutParams(GridLayout.spec(i / rail.columnCount),GridLayout.spec(if (wide && i == 4) 1 else i % rail.columnCount)).apply {
                width = context.dp(68); height = context.dp(if (wide) 58 else if (compact) 56 else 72)
                setMargins(0,context.dp(if (wide || compact) 1 else 3),0,context.dp(if (wide || compact) 1 else 3))
            }; rail.addView(v)
        }
    }
    fun applyInsets(left: Int, topInset: Int, right: Int, bottom: Int) {
        safeLeft = left; safeTop = topInset; safeRight = right; safeBottom = bottom
        top.setPadding(context.dp(14)+left,context.dp(12)+topInset,context.dp(14)+right,context.dp(16))
        (top.layoutParams as LayoutParams).height = context.dp(88)+topInset
        (rail.layoutParams as LayoutParams).apply { gravity = Gravity.END or if (landscape) Gravity.BOTTOM else Gravity.TOP; marginEnd = context.dp(12)+right; topMargin = topInset; bottomMargin = bottom + if (landscape) context.dp(12) else 0 }
        progressPanel.setPadding(context.dp(22)+left,context.dp(16),context.dp(22)+right,context.dp(10))
        (progressPanel.layoutParams as LayoutParams).apply {
            bottomMargin = context.dp(24)+bottom
            // Keep the raised landscape timeline beside the action rail.
            marginEnd = if (landscape) context.dp(156)+right else 0
            resolveLayoutDirection(this@PlayerChrome.layoutDirection)
        }
        (errorPanel.layoutParams as LayoutParams).apply {
            topMargin = context.dp(108)+topInset; marginStart = context.dp(18)+left
            marginEnd = context.dp(if (landscape) 156 else 94)+right
            resolveLayoutDirection(this@PlayerChrome.layoutDirection)
        }
        requestLayout()
    }
    fun setEpisode(current: Int, total: Int) {
        val currentText = "EP$current"
        val value = android.text.SpannableString("$currentText / EP$total")
        value.setSpan(android.text.style.StyleSpan(Typeface.BOLD),0,currentText.length,android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        runningEpisode.text = value; episode.text = value
        runningEpisode.contentDescription = "Episode $current of $total"
    }
    fun showControls(visible: Boolean) {
        val value = if (visible) VISIBLE else GONE
        controlsVisible = visible
        top.visibility = value; rail.visibility = value; progressPanel.visibility = value; playPause.visibility = value
    }
    fun showStatus(message: String, retryVisible: Boolean = false, accessVisible: Boolean = false) {
        status.text = message; errorPanel.visibility = if (message.isEmpty()) GONE else VISIBLE
        retry.visibility = if (retryVisible) VISIBLE else GONE; access.visibility = if (accessVisible) VISIBLE else GONE
    }
    fun setPlayback(playing: Boolean, enabled: Boolean) {
        playPause.setImageDrawable(PlayerIcon(if (playing) "pause" else "play"))
        playPause.contentDescription = if (playing) "Pause video" else "Play video"
        playPause.isEnabled = enabled; playPause.alpha = if (enabled) 1f else .4f
    }
    fun setFavorite(saved: Boolean) {
        val icon = favoriteControl.getChildAt(0) as ImageButton
        icon.setImageDrawable(PlayerIcon(if (saved) "heart-filled" else "heart"))
        icon.imageTintList = ColorStateList.valueOf(if (saved) AppColors.heart else Color.WHITE)
        icon.contentDescription = if (saved) "Remove from favorites" else "Add to favorites"
        favoriteControl.contentDescription = icon.contentDescription
        (favoriteControl.getChildAt(1) as TextView).text = if (saved) "Saved" else "Favorite"
    }
    private fun showOptions(anchor: View) {
        PopupMenu(context,anchor).apply {
            menu.add("Fit / Fill").setOnMenuItemClickListener { actions.fit(); true }
            menu.add("Rotate").setOnMenuItemClickListener { actions.rotate(); true }
            // These two destinations were wired by the player but had no visible entry point.
            menu.add("Downloads").setOnMenuItemClickListener { actions.downloads(); true }
            menu.add("Picture in picture").setOnMenuItemClickListener { actions.pip(); true }
            show()
        }
    }
    fun showSeeking(visible: Boolean) {
        if (visible) { top.visibility = GONE; rail.visibility = GONE; playPause.visibility = GONE }
        else showControls(controlsVisible)
    }
    fun feedback(message: String, persistent: Boolean = false) {
        removeCallbacks(clearFeedback); feedback.animate().cancel(); feedback.text = message
        feedback.alpha = 1f; feedback.visibility = VISIBLE
        if (!persistent) postDelayed(clearFeedback,650)
    }
    fun clearFeedback() { removeCallbacks(clearFeedback); feedback.animate().cancel(); feedback.visibility = GONE }
    fun pip(hidden: Boolean) { visibility = if (hidden) GONE else VISIBLE }
    override fun onDetachedFromWindow() { removeCallbacks(clearFeedback); super.onDetachedFromWindow() }
}

/** Crisp vector glyphs, independent of fonts or bitmap assets. */
class PlayerIcon(private val symbol: String) : Drawable() {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE; strokeWidth = 2f; strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND }
    override fun getIntrinsicWidth() = 28
    override fun getIntrinsicHeight() = 28
    override fun draw(canvas: Canvas) {
        canvas.save(); canvas.translate(bounds.left.toFloat(),bounds.top.toFloat()); canvas.scale(bounds.width()/28f,bounds.height()/28f)
        paint.style = Paint.Style.STROKE
        fun path(vararg points: Float) { val p = Path(); p.moveTo(points[0],points[1]); var i = 2; while (i < points.size) { p.lineTo(points[i],points[i+1]); i += 2 }; canvas.drawPath(p,paint) }
        when (symbol) {
            "close" -> { path(7f,7f,21f,21f);path(21f,7f,7f,21f) }
            "film" -> { canvas.drawRoundRect(4f,3f,24f,25f,2f,2f,paint);path(9f,3f,9f,25f);path(19f,3f,19f,25f); for (y in listOf(8f,14f,20f)) { path(4f,y,9f,y);path(19f,y,24f,y) };path(12f,10f,16f,14f,12f,18f) }
            "back" -> path(18f,5f,9f,14f,18f,23f)
            "play" -> { paint.style = Paint.Style.FILL; val p = Path();p.moveTo(9f,5f);p.lineTo(23f,14f);p.lineTo(9f,23f);p.close();canvas.drawPath(p,paint) }
            "pause" -> { paint.style = Paint.Style.FILL;canvas.drawRoundRect(7f,5f,11f,23f,1f,1f,paint);canvas.drawRoundRect(17f,5f,21f,23f,1f,1f,paint) }
            "speed" -> { canvas.drawArc(3f,5f,25f,27f,180f,180f,false,paint);path(14f,16f,21f,8f);canvas.drawCircle(14f,16f,2f,paint);path(5f,23f,23f,23f) }
            "history" -> { canvas.drawArc(5f,4f,25f,24f,210f,310f,false,paint);path(3f,4f,3f,11f,10f,11f);path(15f,8f,15f,15f,20f,18f) }
            "rotate" -> { canvas.drawArc(4f,4f,24f,24f,30f,270f,false,paint);path(24f,4f,24f,10f,18f,10f) }
            "fit" -> { canvas.drawRoundRect(3f,6f,25f,22f,2f,2f,paint);path(10f,14f,18f,14f);path(10f,10f,6f,14f,10f,18f);path(18f,10f,22f,14f,18f,18f) }
            "pip" -> { canvas.drawRoundRect(3f,5f,25f,23f,2f,2f,paint);paint.style = Paint.Style.FILL;canvas.drawRoundRect(14f,14f,23f,21f,1f,1f,paint) }
            "auto" -> { canvas.drawArc(4f,4f,24f,24f,30f,135f,false,paint);canvas.drawArc(4f,4f,24f,24f,210f,135f,false,paint);path(3f,10f,3f,16f,9f,16f);path(25f,18f,25f,12f,19f,12f) }
            "previous", "next" -> {
                val backwards = symbol == "previous"
                paint.style = Paint.Style.FILL
                val p = Path(); if (backwards) { p.moveTo(19f,6f);p.lineTo(9f,14f);p.lineTo(19f,22f) }
                else { p.moveTo(9f,6f);p.lineTo(19f,14f);p.lineTo(9f,22f) }; p.close();canvas.drawPath(p,paint)
                paint.style = Paint.Style.STROKE; val x = if (backwards) 6f else 22f; canvas.drawLine(x,6f,x,22f,paint)
            }
            "heart", "heart-filled" -> {
                val p = Path(); p.moveTo(14f,24f); p.cubicTo(10f,20f,3f,15f,3f,9f)
                p.cubicTo(3f,2f,11f,1f,14f,7f); p.cubicTo(17f,1f,25f,2f,25f,9f)
                p.cubicTo(25f,15f,18f,20f,14f,24f); p.close()
                if (symbol == "heart-filled") paint.style = Paint.Style.FILL
                canvas.drawPath(p,paint)
            }
            "list" -> { canvas.drawRoundRect(4f,3f,24f,25f,2f,2f,paint); path(9f,9f,19f,9f); path(9f,14f,19f,14f); path(9f,19f,16f,19f) }
            "quality" -> { canvas.drawRoundRect(3f,6f,25f,22f,2f,2f,paint); paint.textSize = 9f;paint.style = Paint.Style.FILL;canvas.drawText("HD",6f,17f,paint) }
            "download", "downloads" -> { path(14f,3f,14f,18f);path(8f,12f,14f,18f,20f,12f);path(4f,20f,4f,25f,24f,25f,24f,20f) }
            "episodes" -> { path(5f,6f,23f,6f);path(5f,12f,23f,12f);path(5f,18f,17f,18f);path(5f,24f,14f,24f) }
            "fullscreen" -> { path(10f,4f,4f,4f,4f,10f);path(18f,4f,24f,4f,24f,10f);path(4f,18f,4f,24f,10f,24f);path(24f,18f,24f,24f,18f,24f) }
            "chevron-up" -> path(6f,18f,14f,10f,22f,18f)
            "more" -> { paint.style = Paint.Style.FILL; for (y in listOf(6f,14f,22f)) canvas.drawCircle(14f,y,1.9f,paint) }
        }
        canvas.restore()
    }
    override fun setAlpha(alpha: Int) { paint.alpha = alpha; invalidateSelf() }
    override fun setColorFilter(colorFilter: ColorFilter?) { paint.colorFilter = colorFilter; invalidateSelf() }
    @Deprecated("Drawable opacity") override fun getOpacity() = PixelFormat.TRANSLUCENT
}
