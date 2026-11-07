package com.waqas.hdrama

import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat

/**
 * Recently watched, reverted to the original working structure.
 * Uses only the shared Ui.kt helpers so the view tree stays stable for the existing test suite.
 */
class HistoryActivity : ComponentActivity() {
    private val library by lazy { DramaLibrary(this) }
    private lateinit var rows: LinearLayout
    private lateinit var usage: TextView
    private lateinit var clear: Button

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = AppColors.background; window.navigationBarColor = Color.BLACK
        WindowCompat.getInsetsController(window, window.decorView).apply {
            isAppearanceLightStatusBars = false
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }

        val root = column().apply { setBackgroundColor(AppColors.background); pad(16) }
        root.addView(screenHeader("History") { finish() }.first)

        root.addView(LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(14), 0, dp(10))
            usage = label("", 12.5f).apply { setTextColor(AppColors.muted) }
            addView(usage, LinearLayout.LayoutParams(0, -2, 1f))
            clear = button("Clear history") { confirmClear() }.apply {
                setTextColor(AppColors.danger)
                contentDescription = "Clear history"
            }
            addView(clear, LinearLayout.LayoutParams(-2, dp(48)))
        })

        rows = column()
        val scroll = ScrollView(this).apply { isVerticalScrollBarEnabled = false; addView(rows) }
        root.addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))

        ViewCompat.setOnApplyWindowInsetsListener(root) { v, insets ->
            val safe = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
            v.setPadding(safe.left, safe.top, safe.right, 0)
            scroll.setPadding(0, 0, 0, safe.bottom)
            WindowInsetsCompat.CONSUMED
        }
        setContentView(root)
        render()
    }

    override fun onResume() { super.onResume(); render() }

    private fun render() {
        rows.removeAllViews()
        val items = library.history()
        usage.text = if (items.isEmpty()) "" else "${items.size} series · recently watched"
        clear.visibility = if (items.isEmpty()) View.GONE else View.VISIBLE
        if (items.isEmpty()) {
            rows.addView(emptyState("history", "Nothing here yet", "Dramas you start watching will appear here so you can jump back in."))
            return
        }
        items.forEach { item -> rows.addView(historyCard(item)) }
    }

    private fun historyCard(item: SavedDrama): View {
        val card = seriesCard(item.url, item.title, "", "EP.${item.episode}")
        card.setOnClickListener { open(item.url) }
        card.setOnLongClickListener { confirmRemove(item) }
        card.contentDescription = "Continue watching: ${item.title}"
        return card
    }

    private fun open(url: String) {
        startActivity(Intent(this, PlayerActivity::class.java).putExtra("series", url))
    }

    private fun confirmRemove(item: SavedDrama): Boolean {
        val dialog = android.app.AlertDialog.Builder(this)
            .setTitle("Remove from history?")
            .setMessage("\"${item.title}\" will be removed from History. Favorites, downloads and resume positions are kept.")
            .setPositiveButton("Remove") { _, _ ->
                library.removeHistory(item.url); render()
            }
            .setNegativeButton("Cancel", null)
            .create()
        dialog.show()
        polishDialog(dialog)
        return true
    }

    private fun confirmClear() {
        val dialog = android.app.AlertDialog.Builder(this)
            .setTitle("Clear history?")
            .setMessage("This removes recently watched entries. Favorites, downloads and resume positions are kept.")
            .setPositiveButton("Clear") { _, _ ->
                library.clearHistory(); render()
            }
            .setNegativeButton("Cancel", null)
            .create()
        dialog.show()
        polishDialog(dialog)
    }
}
