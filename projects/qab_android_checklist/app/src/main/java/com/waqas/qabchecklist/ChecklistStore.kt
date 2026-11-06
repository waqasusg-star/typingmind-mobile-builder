package com.waqas.qabchecklist

import android.content.Context

/** Minimal key/value seam so persistence logic is testable without Android. */
interface KeyValueStore {
    fun read(key: String): String?
    fun write(key: String, value: String)
    fun remove(key: String)
}

class SharedPreferencesStore(context: Context) : KeyValueStore {

    private val prefs = context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    override fun read(key: String): String? = prefs.getString(key, null)

    override fun write(key: String, value: String) {
        prefs.edit().putString(key, value).apply()
    }

    override fun remove(key: String) {
        prefs.edit().remove(key).apply()
    }

    companion object {
        private const val FILE = "qab_checklist"
    }
}

/**
 * Local-only checklist persistence with corruption recovery:
 * unreadable payloads are moved to a recovery key instead of being destroyed.
 */
class ChecklistStore(private val kv: KeyValueStore) {

    data class LoadResult(val tasks: List<Task>, val notice: String? = null)

    fun load(): LoadResult {
        val payload = kv.read(KEY_TASKS) ?: return LoadResult(emptyList())
        val decoded = ChecklistPolicy.decode(payload)
        if (!decoded.formatOk) {
            kv.write(KEY_RECOVERY, payload)
            kv.remove(KEY_TASKS)
            return LoadResult(
                emptyList(),
                "The saved checklist could not be read, so a fresh list was started. The unreadable copy was kept for recovery."
            )
        }
        if (decoded.skippedLines > 0) {
            kv.write(KEY_RECOVERY, payload)
            val label = if (decoded.skippedLines == 1) "entry" else "entries"
            return LoadResult(
                decoded.tasks,
                "Recovered the checklist and skipped " + decoded.skippedLines + " damaged " + label + "."
            )
        }
        return LoadResult(decoded.tasks)
    }

    fun save(tasks: List<Task>) {
        kv.write(KEY_TASKS, ChecklistPolicy.encode(tasks))
    }

    fun saveDraft(text: String) {
        kv.write(KEY_DRAFT, text)
    }

    fun loadDraft(): String = kv.read(KEY_DRAFT).orEmpty()

    fun recoveryCopy(): String? = kv.read(KEY_RECOVERY)

    /** Number of tasks recoverable from the kept copy, or null when there is nothing usable. */
    fun recoveryTaskCount(): Int? {
        val copy = recoveryCopy() ?: return null
        val decoded = ChecklistPolicy.decode(copy)
        return if (decoded.formatOk && decoded.tasks.isNotEmpty()) decoded.tasks.size else null
    }

    fun restoreRecoveryCopy(): LoadResult {
        val copy = recoveryCopy() ?: return LoadResult(emptyList(), "There is no recovery copy to restore.")
        val decoded = ChecklistPolicy.decode(copy)
        if (!decoded.formatOk || decoded.tasks.isEmpty()) {
            return LoadResult(emptyList(), "The recovery copy is unreadable too, so nothing was restored.")
        }
        save(decoded.tasks)
        kv.remove(KEY_RECOVERY)
        val count = decoded.tasks.size
        val label = if (count == 1) "task" else "tasks"
        return LoadResult(decoded.tasks, "Restored " + count + " " + label + " from the recovery copy.")
    }

    companion object {
        const val KEY_TASKS = "tasks_v1"
        const val KEY_RECOVERY = "tasks_v1_recovery"
        const val KEY_DRAFT = "draft_v1"
    }
}
