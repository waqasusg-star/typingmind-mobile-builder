package com.waqas.hdrama

import android.app.AlertDialog
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.*
import androidx.activity.ComponentActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch

/** Recently watched series; hiding history never removes downloads, favorites or resume positions. */
class HistoryActivity : ComponentActivity() {
    private val library by lazy { DramaLibrary(this) }
    private lateinit var rows: LinearLayout
    private lateinit var usage: TextView
    private lateinit var clear: Button
    private val artworkAttempted = mutableSetOf<String>()
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        androidx.core.view.WindowCompat.setDecorFitsSystemWindows(window,false)
        window.statusBarColor = AppColors.background; window.navigationBarColor = Color.BLACK
        val root = column().apply { setBackgroundColor(AppColors.background); pad(16) }
        root.addView(screenHeader("History") { finish() }.first)
        usage = label("",12f).apply { setTextColor(AppColors.muted); setPadding(0,dp(8),0,dp(12)) }; root.addView(usage)
        clear = button("Clear history") { confirmDelete(null) }.apply { contentDescription = "Clear history" }
        root.addView(clear,LinearLayout.LayoutParams(-1,-2))
        root.addView(label("Tap to continue watching · Hold to delete",12f).apply { setTextColor(AppColors.muted); setPadding(0,dp(8),0,dp(12)) })
        rows = column()
        root.addView(ScrollView(this).apply { addView(rows) },LinearLayout.LayoutParams(-1,0,1f))
        setContentView(root)
        ViewCompat.setOnApplyWindowInsetsListener(root) { v,insets ->
            val safe = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
            v.setPadding(dp(16)+safe.left,dp(8)+safe.top,dp(16)+safe.right,dp(16)+safe.bottom); WindowInsetsCompat.CONSUMED
        }
    }
    override fun onResume() { super.onResume(); render() }
    private fun render() {
        val items = library.history()
        usage.text = if (items.size == 1) "1 recently watched series" else "${items.size} recently watched series"
        clear.isEnabled = items.isNotEmpty(); rows.removeAllViews()
        items.forEach { item ->
            val card = seriesCard(item.url,item.title,"Recently watched","EP.${item.episode} · ${time(item.position)}" + if (item.duration > 0) " / ${time(item.duration)}" else "").apply {
                contentDescription = "Continue watching: ${item.title}"
                setOnClickListener { startActivity(Intent(this@HistoryActivity,PlayerActivity::class.java).putExtra("series",item.url)) }
                setOnLongClickListener { confirmDelete(item); true }
            }
            rows.addView(card,LinearLayout.LayoutParams(-1,-2).apply { bottomMargin = dp(12) })
            if (!SeriesArtwork.hasPoster(this,item.url) && artworkAttempted.add(item.url)) lifecycleScope.launch {
                SeriesArtwork.cache(this@HistoryActivity,Series(item.title,item.url,emptyList()))
                if (SeriesArtwork.hasPoster(this@HistoryActivity,item.url)) rows.refreshPosters()
            }
        }
        if (items.isEmpty()) rows.addView(emptyState("history","Your next story starts here","Recently watched series will appear here with your saved episode and time."))
    }
    private fun confirmDelete(item: SavedDrama?) {
        AlertDialog.Builder(this).setTitle(if (item == null) "Clear history?" else "Delete recent history?")
            .setMessage((item?.title ?: "All recently watched series") + "\nFavorites, downloads and episode resume positions are kept.")
            .setNegativeButton("Cancel",null).setPositiveButton(if (item == null) "Clear" else "Delete") { _,_ ->
                if (item == null) library.clearHistory() else library.removeHistory(item.url)
                render()
            }.show().also(::polishDialog)
    }
}
