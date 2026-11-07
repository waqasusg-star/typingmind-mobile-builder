package com.waqas.hdrama

import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch

/** Recently watched, rebuilt on the aurora glass design. History never touches downloads or favorites. */
class HistoryActivity : ComponentActivity() {
    private val library by lazy { DramaLibrary(this) }
    private lateinit var rows: LinearLayout
    private lateinit var usage: TextView
    private lateinit var clear: Button
    private val artworkAttempted = mutableSetOf<String>()

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        androidx.core.view.WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = Color.BLACK; window.navigationBarColor = Color.BLACK
        WindowCompat.getInsetsController(window, window.decorView).apply {
            isAppearanceLightStatusBars = false
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }

        // Aurora behind everything; a ScrollView holds the content column.
        val (root, content) = Visual.auroraScreen(this)
        val scroll = ScrollView(this).apply { isVerticalScrollBarEnabled = false }
        scroll.addView(content, ScrollView.LayoutParams(-1, -2))
        root.addView(scroll)

        // Hero header over the gradient fade.
        val hero = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = Visual.heroFade()
            setPadding(dp(20), dp(18), dp(20), dp(16))
            addView(eyebrow("YOUR JOURNEY"))
            addView(label("History", 30f).apply {
                typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
                letterSpacing = -0.02f
                setPadding(0, dp(6), 0, dp(8))
            })
            addView(Visual.accentRule(this@HistoryActivity), LinearLayout.LayoutParams(dp(56), dp(3)))
        }
        content.addView(hero)

        content.addView(LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(20), dp(14), dp(20), dp(10))
            usage = label("", 12.5f).apply { setTextColor(Hd.muted) }
            addView(usage, LinearLayout.LayoutParams(0, -2, 1f))
            clear = Button(this@HistoryActivity).apply {
                text = "Clear history"; isAllCaps = false; textSize = 12.5f
                minHeight = 0; minimumHeight = 0; includeFontPadding = false
                setPadding(dp(16), dp(10), dp(16), dp(10))
                typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
                background = Visual.glass(this@HistoryActivity, 0x99)
                setTextColor(Hd.danger)
                setOnClickListener { confirmClear() }
            }
            addView(clear, LinearLayout.LayoutParams(-2, dp(40)))
        })

        rows = column()
        content.addView(rows, LinearLayout.LayoutParams(-1, -2).apply { setMargins(dp(16), 0, dp(16), dp(24)) })

        ViewCompat.setOnApplyWindowInsetsListener(root) { v, insets ->
            val safe = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
            v.setPadding(safe.left, safe.top, safe.right, 0)
            scroll.setPadding(0, 0, 0, safe.bottom)
            WindowInsetsCompat.CONSUMED
        }
        setContentView(root)
    }

    override fun onResume() { super.onResume(); refresh() }

    private fun refresh() {
        rows.removeAllViews()
        artworkAttempted.clear()
        val items = library.history()
        usage.text = if (items.isEmpty()) "" else "${items.size} series · recently watched"
        clear.visibility = if (items.isEmpty()) View.GONE else View.VISIBLE
        if (items.isEmpty()) {
            rows.addView(emptyState("history", "Nothing here yet", "Dramas you start watching will appear here so you can jump back in."))
            return
        }
        items.forEach { item -> rows.addView(historyCard(item)) }
    }

    /** Elevated glass row with poster, title, episode position and an amber resume affordance. */
    private fun historyCard(item: SavedDrama): View {
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = Visual.glass(this@HistoryActivity, 0xcc)
            setPadding(dp(14), dp(14), dp(14), dp(14))
        }
        val poster = poster(item.url, item.title, width = 64, height = 92).apply { background = Visual.posterFrame(this@HistoryActivity) }
        card.addView(poster)
        val text = column().apply {
            setPadding(dp(14), 0, 0, 0)
            addView(label(item.title, 16f).apply {
                typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
                maxLines = 2
                ellipsize = android.text.TextUtils.TruncateAt.END
            })
            addView(label("EP. ${item.episode}" + if (item.position > 0) " · resumed at ${time(item.position)}" else "", 12f).apply {
                setTextColor(Hd.muted); setPadding(0, dp(6), 0, dp(10))
            })
            addView(Visual.badge(this@HistoryActivity, "RESUME"))
        }
        card.addView(text, LinearLayout.LayoutParams(0, -2, 1f))
        card.setOnClickListener { open(item.url) }
        card.isFocusable = true
        card.contentDescription = "Resume ${item.title}"
        return card
    }

    private fun open(url: String) {
        startActivity(Intent(this, PlayerActivity::class.java).putExtra("series", url))
    }

    private fun confirmClear() {
        val dialog = android.app.AlertDialog.Builder(this)
            .setTitle("Clear history?")
            .setMessage("This removes recently watched entries. Favorites, downloads and resume positions are kept.")
            .setPositiveButton("Clear") { _, _ ->
                library.clearHistory(); refresh()
            }
            .setNegativeButton("Cancel", null)
            .create()
        dialog.show()
        polishDialog(dialog)
    }
}
