package com.waqas.hdrama

import android.app.AlertDialog
import android.content.Context
import android.widget.ArrayAdapter
import android.widget.ImageView
import android.view.View
import android.view.ViewGroup
import android.view.Gravity
import androidx.activity.ComponentActivity
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import org.json.JSONArray
import org.json.JSONObject

data class SavedDrama(val url: String, val title: String, val favorite: Boolean = false,
    val episode: Int = 1, val position: Long = 0, val favoriteAt: Long = 0, val duration: Long = 0, val watchedAt: Long = 0)

/** App-private favorites and progress; removing a favorite keeps its watch history. */
class DramaLibrary(context: Context) {
    private val preferences = context.getSharedPreferences("drama_library", Context.MODE_PRIVATE)
    private val legacy = context.getSharedPreferences("playback", Context.MODE_PRIVATE)
    private fun records(): List<SavedDrama> {
        val data = runCatching { JSONArray(preferences.getString("records", "[]")) }.getOrElse { JSONArray() }
        return (0 until data.length()).mapNotNull { i ->
            val item = data.optJSONObject(i) ?: return@mapNotNull null
            val url = SitePolicy.seriesUrl(item.optString("url")) ?: return@mapNotNull null
            SavedDrama(url, item.optString("title").take(200).ifBlank { "Saved drama" }, item.optBoolean("favorite"),
                item.optInt("episode", 1).coerceIn(1, 10_000), item.optLong("position").coerceAtLeast(0), item.optLong("favoriteAt"), item.optLong("duration").coerceAtLeast(0),
                item.optLong("watchedAt",if (item.optLong("position") > 0 || item.optLong("duration") > 0 || item.optInt("episode",1) > 1) 1L else 0L))
        }.distinctBy { it.url }
    }
    fun get(rawUrl: String): SavedDrama? {
        val url = SitePolicy.seriesUrl(rawUrl) ?: return null
        return records().firstOrNull { it.url == url } ?: if (legacy.contains("episode:$url"))
            SavedDrama(url, "Saved drama", episode = legacy.getInt("episode:$url", 1).coerceIn(1, 10_000),
                position = legacy.getLong("position:$url", 0).coerceAtLeast(0), watchedAt = 1) else null
    }
    fun favorites(): List<SavedDrama> = records().filter { it.favorite }.sortedByDescending { it.favoriteAt }
    /** Recent history is separate from favorites and per-episode resume positions. */
    fun history(): List<SavedDrama> {
        val stored = records()
        val migrated = legacy.all.keys.filter { it.startsWith("episode:") }.mapNotNull { key ->
            val url = SitePolicy.seriesUrl(key.removePrefix("episode:")) ?: return@mapNotNull null
            if (stored.any { it.url == url }) null else get(url)
        }
        return (stored + migrated).filter { it.watchedAt > 0 }.sortedByDescending { it.watchedAt }
    }
    fun removeHistory(rawUrl: String) { get(rawUrl)?.let { put(it.copy(watchedAt = 0)) } }
    fun clearHistory() { history().forEach { removeHistory(it.url) } }
    fun episodePosition(rawUrl: String, episode: Int): Long {
        val url = SitePolicy.seriesUrl(rawUrl) ?: return 0
        val key = "episode-position:$url:$episode"
        if (preferences.getBoolean("episode-completed:$url:$episode",false)) return 0
        val saved = get(url)?.takeIf { it.episode == episode }
        val value = if (preferences.contains(key)) preferences.getLong(key,0).coerceAtLeast(0) else saved?.position ?: 0
        val duration = preferences.getLong("episode-duration:$url:$episode",saved?.duration ?: 0)
        return if (duration > 0 && value >= duration) 0 else value
    }
    private fun put(record: SavedDrama) {
        val data = JSONArray()
        (records().filterNot { it.url == record.url } + record).forEach { item ->
            data.put(JSONObject().put("url", item.url).put("title", item.title).put("favorite", item.favorite)
                .put("episode", item.episode).put("position", item.position).put("favoriteAt", item.favoriteAt).put("duration",item.duration).put("watchedAt",item.watchedAt))
        }
        preferences.edit().putString("records", data.toString()).apply()
    }
    fun saveProgress(rawUrl: String, title: String, episode: Int, position: Long, duration: Long = 0, completed: Boolean = false) {
        val url = SitePolicy.seriesUrl(rawUrl) ?: return
        val number = episode.coerceIn(1,10_000)
        val old = get(url) ?: SavedDrama(url, title)
        val edit = preferences.edit()
        val previousKey = "episode-position:$url:${old.episode}"
        if (!preferences.contains(previousKey)) edit.putLong(previousKey,old.position)
        edit.putLong("episode-position:$url:$number",position.coerceAtLeast(0))
            .putBoolean("episode-completed:$url:$number",completed || duration > 0 && position >= duration)
        if (duration > 0) edit.putLong("episode-duration:$url:$number",duration)
        edit.apply()
        put(old.copy(title = title.take(200), episode = number, position = position.coerceAtLeast(0), duration = duration.coerceAtLeast(0), watchedAt = System.currentTimeMillis()))
    }
    fun removeFavorite(rawUrl: String): Boolean {
        val old = get(rawUrl)?.takeIf { it.favorite } ?: return false
        put(old.copy(favorite = false))
        return true
    }
    fun toggleFavorite(rawUrl: String, title: String): Boolean {
        val url = SitePolicy.seriesUrl(rawUrl) ?: return false
        val old = get(url) ?: SavedDrama(url, title)
        val favorite = !old.favorite
        put(old.copy(title = title.take(200), favorite = favorite,
            favoriteAt = if (favorite) System.currentTimeMillis() else old.favoriteAt))
        return favorite
    }
}

fun showMyList(context: Context, library: DramaLibrary,
    onFavoritesChanged: () -> Unit = {}, onSelect: (SavedDrama) -> Unit): AlertDialog {
    val items = library.favorites().toMutableList()
    val builder = AlertDialog.Builder(context).setTitle("My List").setNegativeButton("Close", null)
    if (items.isEmpty()) return builder.setMessage("Tap the heart on a series to keep it in My List.").show().also(::polishDialog)
    val title = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL; setPadding(context.dp(24),context.dp(20),context.dp(24),context.dp(8))
        addView(context.label("My List",20f))
        addView(context.label("Hold a drama to remove from My List",12f).apply { alpha = .7f; setPadding(0,context.dp(6),0,0) })
    }
    fun description(item: SavedDrama) = "${item.title}\nEP. ${item.episode} · ${time(item.position)}" + if (item.duration > 0) " / ${time(item.duration)}" else ""
    val requested = mutableSetOf<String>()
    val adapter = object : ArrayAdapter<String>(context, android.R.layout.simple_list_item_1,items.map(::description).toMutableList()) {
        override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
            val item = items[position]
            return context.seriesCard(item.url,item.title,"Saved series","EP. ${item.episode} · ${time(item.position)}" + if (item.duration > 0) " / ${time(item.duration)}" else "").apply {
                if (!SeriesArtwork.hasPoster(context,item.url) && requested.add(item.url)) {
                    (context as? ComponentActivity)?.lifecycleScope?.launch {
                        SeriesArtwork.cache(context,Series(item.title,item.url,emptyList()))
                        parent.refreshPosters()
                    }
                }
            }
        }
    }
    val dialog = builder.setCustomTitle(title).setAdapter(adapter) { window, index ->
        window.dismiss(); items.getOrNull(index)?.let(onSelect)
    }.show().also(::polishDialog)
    dialog.listView.divider = null; dialog.listView.dividerHeight = context.dp(10)
    dialog.listView.setPadding(context.dp(12),context.dp(4),context.dp(12),context.dp(8))
    dialog.listView.setOnItemLongClickListener { _,_,index,_ ->
        val item = items.getOrNull(index) ?: return@setOnItemLongClickListener true
        library.removeFavorite(item.url)
        // Remove the same listed description before shifting the backing list, so the row count
        // and the displayed card always stay in step.
        val listed = adapter.getItem(index)
        items.removeAt(index); adapter.remove(listed)
        onFavoritesChanged()
        Toast.makeText(context,"Removed from My List",Toast.LENGTH_SHORT).show()
        if (items.isEmpty()) dialog.dismiss()
        true
    }
    return dialog
}
