package com.waqas.hdrama

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.Request
import org.json.JSONObject
import org.jsoup.nodes.Document
import java.io.File
import java.security.MessageDigest

object SeriesArtwork {
    private val images = object : android.util.LruCache<String,Bitmap>(4 * 1024 * 1024) {
        override fun sizeOf(key: String,value: Bitmap) = value.allocationByteCount
    }
    fun poster(doc: Document, title: String): String {
        fun normalized(value: String) = value.lowercase().filter { it.isLetterOrDigit() }
        val meta = doc.selectFirst("meta[property=og:image],meta[name=twitter:image]")?.absUrl("content").orEmpty()
        val image = doc.selectFirst(".poster img,.series-poster img,img[itemprop=image]")
            ?: doc.select("img[alt]").firstOrNull { normalized(title).isNotEmpty() && normalized(it.attr("alt")).contains(normalized(title)) }
        return listOf(image?.absUrl("data-src").orEmpty(),image?.absUrl("src").orEmpty(),meta).firstOrNull { it.toHttpUrlOrNull()?.scheme == "https" }.orEmpty()
    }
    fun season(title: String): String = Regex("\\b(?:Season\\s*|S)(\\d+)\\b",RegexOption.IGNORE_CASE).find(title)?.let { "Season ${it.groupValues[1]}" }.orEmpty()
    private fun prefs(context: Context) = context.getSharedPreferences("series_artwork",Context.MODE_PRIVATE)
    fun remember(context: Context, series: Series) {
        val prior = enrich(context,series)
        prefs(context).edit().putString(series.url,JSONObject().put("title",series.title)
            .put("poster",series.posterUrl.ifBlank { prior.posterUrl }).put("season",series.seasonLabel.ifBlank { prior.seasonLabel }).toString()).apply()
    }
    fun enrich(context: Context, series: Series): Series {
        val record = runCatching { JSONObject(prefs(context).getString(series.url,"{}").orEmpty()) }.getOrElse { JSONObject() }
        return series.copy(posterUrl = series.posterUrl.ifBlank { record.optString("poster") },seasonLabel = series.seasonLabel.ifBlank { record.optString("season") })
    }
    private val names = android.util.LruCache<String,String>(256)
    fun file(context: Context, url: String): File {
        val name = names.get(url) ?: (MessageDigest.getInstance("SHA-256").digest(url.toByteArray()).joinToString("") { "%02x".format(it) } + ".jpg").also { names.put(url,it) }
        return File(File(context.filesDir,"series-thumbnails"),name)
    }
    fun hasPoster(context: Context, url: String): Boolean = file(context,url).exists() && prefs(context).getString("poster-source:$url",null) != null
    fun bitmap(context: Context, url: String): Bitmap? {
        if (!hasPoster(context,url)) return null
        val source = file(context,url)
        val key = source.path + source.lastModified() + prefs(context).getString("poster-source:$url","")
        images.get(key)?.takeUnless { it.isRecycled }?.let { return it }
        val bitmap = BitmapFactory.decodeFile(source.path)
        if (bitmap == null) {
            source.delete(); prefs(context).edit().remove("poster-source:$url").apply()
            return null
        }
        images.put(key,bitmap); return bitmap
    }
    @Synchronized private fun write(context: Context, url: String, bitmap: Bitmap) {
        val target = file(context,url);target.parentFile?.mkdirs()
        val scale = minOf(1f,240f / maxOf(bitmap.width,bitmap.height))
        val resized = Bitmap.createScaledBitmap(bitmap,(bitmap.width*scale).toInt().coerceAtLeast(1),(bitmap.height*scale).toInt().coerceAtLeast(1),true)
        val temp = File(target.path+".tmp")
        temp.outputStream().use { resized.compress(Bitmap.CompressFormat.JPEG,85,it) }
        if (resized !== bitmap) resized.recycle()
        check(temp.renameTo(target)) { "Poster could not be saved" }
    }
    suspend fun cache(context: Context, series: Series) = withContext(Dispatchers.IO) {
        val enriched = enrich(context,series)
        val u = enriched.posterUrl.toHttpUrlOrNull() ?: return@withContext
        if (u.scheme != "https" || u.username.isNotEmpty() || u.password.isNotEmpty() || (hasPoster(context,series.url) && prefs(context).getString("poster-source:${series.url}",null) == u.toString())) return@withContext
        runCatching {
            Network.mediaClient.newCall(Request.Builder().url(u).header("Referer",series.url).header("User-Agent",android.webkit.WebSettings.getDefaultUserAgent(context)).build()).execute().use { response ->
                if (!response.isSuccessful) return@use
                val bytes = response.body?.byteStream()?.use { input ->
                    val data = java.io.ByteArrayOutputStream();val buffer = ByteArray(8192)
                    while (data.size() <= 2*1024*1024) { val count = input.read(buffer);if (count < 0) break;data.write(buffer,0,count) }
                    data.toByteArray() } ?: return@use
                if (bytes.size > 2*1024*1024) return@use
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true };BitmapFactory.decodeByteArray(bytes,0,bytes.size,bounds)
                if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return@use
                val options = BitmapFactory.Options().apply { inSampleSize = (maxOf(bounds.outWidth,bounds.outHeight)/240).coerceAtLeast(1) }
                BitmapFactory.decodeByteArray(bytes,0,bytes.size,options)?.let { write(context,series.url,it);prefs(context).edit().putString("poster-source:${series.url}",u.toString()).apply();it.recycle() }
            }
        }; Unit
    }
    suspend fun frame(context: Context, url: String, frame: Bitmap) = withContext(Dispatchers.IO) {
        try { if (!file(context,url).exists()) write(context,url,frame) } finally { frame.recycle() }
    }
}

/** The canonical series URL identifies a folder, even if two seasons have the same title. */
object DownloadFolders {
    fun group(items: List<OfflineMetadata>): Map<String,List<OfflineMetadata>> = items.distinctBy { it.id }
        .groupBy { it.series.url }.mapValues { (_,episodes) -> episodes.sortedBy { it.series.episodes[it.index].number } }
}
