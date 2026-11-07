package com.waqas.hdrama

import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat

/** Recently watched, rebuilt on the aurora glass design. History never touches downloads or favorites. */
class HistoryActivity : ComponentActivity() {
    private val library by lazy { DramaLibrary(this) }
    private lateinit var rows: LinearLayout
    private lateinit var usage: TextView
    private lateinit var clear: Button

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = Color.BLACK; window.navigationBarColor = Color.BLACK
        WindowCompat.getInsetsController(window, window.decorView).apply {
            isAppearanceLightStatusBars = false
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }

        val (root, content) = Visual.auroraScreen(this)
        val scroll = ScrollView(this).apply { isVerticalScrollBarEnabled = false; addView(content) }
        root.addView(scroll)

        val hero = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = Visual.heroFade()
            setPadding(dp(20), dp(18), dp(20), dp(16))
            // The back control carries an exact contentDescription so the design review
            // test can locate it without depending on the layout order.
            addView(LinearLayout(this@HistoryActivity).apply {
                orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
                addView(ImageButton(this@HistoryActivity).apply {
                    setImageDrawable(PlayerIcon("back"))
                    background = Visual.glass(this@HistoryActivity, 0x99)
                    imageTintList = android.content.res.ColorStateList.valueOf(Hd.text)
                    setPadding(dp(12), dp(12), dp(12), dp(12))
                    contentDescription = "Back"
                    setOnClickListener { finish() }
                }, LinearLayout.LayoutParams(dp(48), dp(48)))
                addView(LinearLayout(this@HistoryActivity).apply {
                    orientation = LinearLayout.VERTICAL
                    setPadding(dp(14), 0, 0, 0)
                    addView(eyebrow("YOUR JOURNEY"))
                    addView(label("History", 30f).apply {
                        typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
                        letterSpacing = -0.02f
                        setPadding(0, dp(4), 0, dp(6))
                    })
                }, LinearLayout.LayoutParams(0, -2, 1f))
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
                setTextColor(AppColors.danger)
                contentDescription = "Clear history"
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
        render()
    }

    override fun onResume() { super.onResume(); render() }

    /** Rebuild the row list. Called by lifecycle and directly by the design review test. */
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
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = Visual.glass(this@HistoryActivity, 0xcc)
            setPadding(dp(14), dp(14), dp(14), dp(14))
        }
        val poster = poster(item.url, item.title, width = 64, height = 92).apply { background = Visual.posterFrame(this@HistoryActivity) }
        card.addView(poster)
        val timing = "${time(item.position)}" + if (item.duration > 0) " / ${time(item.duration)}" else ""
        val text = column().apply {
            setPadding(dp(14), 0, 0, 0)
            addView(label(item.title, 16f).apply {
                typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
                maxLines = 2
                ellipsize = TextUtils.TruncateAt.END
            })
            addView(label("EP.${item.episode} · $timing", 12f).apply {
                setTextColor(Hd.muted); setPadding(0, dp(6), 0, dp(10))
            })
            addView(Visual.badge(this@HistoryActivity, "RESUME"))
        }
        card.addView(text, LinearLayout.LayoutParams(0, -2, 1f))
        card.setOnClickListener { open(item.url) }
        card.setOnLongClickListener { confirmRemove(item) }
        card.isFocusable = true
        card.contentDescription = "Continue watching: ${item.title}"
        return card
    }

    private fun open(url: String) {
        startActivity(Intent(this, PlayerActivity::class.java).putExtra("series", url))
    }

    /** Long-press removes this one entry with confirmation; the record's resume data survives. */
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
