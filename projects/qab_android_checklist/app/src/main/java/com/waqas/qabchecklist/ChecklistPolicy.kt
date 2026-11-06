package com.waqas.qabchecklist

/**
 * Platform-neutral checklist rules shared by the UI and the plain-JVM unit tests.
 * This file deliberately has no Android imports so it can be tested off-device.
 */
enum class Priority(val label: String, val rank: Int) {
    HIGH("High", 0),
    NORMAL("Normal", 1),
    LOW("Low", 2);

    companion object {
        fun fromName(raw: String?): Priority =
            entries.firstOrNull { it.name.equals(raw?.trim(), ignoreCase = true) } ?: NORMAL
    }
}

data class Task(
    val id: String,
    val title: String,
    val done: Boolean,
    val priority: Priority,
    val createdAt: Long
)

data class Summary(
    val total: Int,
    val done: Int,
    val remaining: Int,
    val percentDone: Int,
    val headline: String
)

sealed class TitleResult {
    data class Valid(val title: String) : TitleResult()
    data class Invalid(val message: String) : TitleResult()
}

object ChecklistPolicy {

    const val MAX_TITLE_LENGTH = 120
    private const val HEADER = "QABCHECKLIST\t1"

    fun validateTitle(raw: String?): TitleResult {
        val normalized = raw?.trim()?.replace(Regex("\\s+"), " ").orEmpty()
        return when {
            normalized.isEmpty() -> TitleResult.Invalid("Enter a task title before adding it.")
            normalized.length > MAX_TITLE_LENGTH -> TitleResult.Invalid(
                "Keep the title to " + MAX_TITLE_LENGTH + " characters or fewer (currently " + normalized.length + ")."
            )
            else -> TitleResult.Valid(normalized)
        }
    }

    sealed class AddResult {
        data class Added(val tasks: List<Task>, val task: Task) : AddResult()
        data class Rejected(val message: String) : AddResult()
    }

    fun add(existing: List<Task>, rawTitle: String?, priority: Priority, now: Long): AddResult =
        when (val validation = validateTitle(rawTitle)) {
            is TitleResult.Invalid -> AddResult.Rejected(validation.message)
            is TitleResult.Valid -> {
                val task = Task(nextId(existing, now), validation.title, false, priority, now)
                AddResult.Added(existing + task, task)
            }
        }

    fun nextId(existing: List<Task>, now: Long): String {
        var suffix = 0
        var candidate = "t" + now
        while (existing.any { it.id == candidate }) {
            suffix += 1
            candidate = "t" + now + "-" + suffix
        }
        return candidate
    }

    fun setDone(tasks: List<Task>, id: String, done: Boolean): List<Task> =
        tasks.map { if (it.id == id) it.copy(done = done) else it }

    fun toggle(tasks: List<Task>, id: String): List<Task> =
        tasks.map { if (it.id == id) it.copy(done = !it.done) else it }

    fun remove(tasks: List<Task>, id: String): List<Task> = tasks.filterNot { it.id == id }

    fun clearCompleted(tasks: List<Task>): List<Task> = tasks.filterNot { it.done }

    /** Incomplete first, then highest priority, then oldest, then alphabetical. */
    fun sortForDisplay(tasks: List<Task>): List<Task> = tasks.sortedWith(
        compareBy<Task> { it.done }
            .thenBy { it.priority.rank }
            .thenBy { it.createdAt }
            .thenBy { it.title.lowercase() }
    )

    fun summarize(tasks: List<Task>): Summary {
        val total = tasks.size
        val done = tasks.count { it.done }
        val percent = if (total == 0) 0 else (done * 100) / total
        val headline = when {
            total == 0 -> "No tasks yet"
            done == total -> "All " + total + " done"
            else -> done.toString() + " of " + total + " done"
        }
        return Summary(total, done, total - done, percent, headline)
    }

    data class DecodeResult(val tasks: List<Task>, val skippedLines: Int, val formatOk: Boolean)

    fun encode(tasks: List<Task>): String {
        val builder = StringBuilder(HEADER)
        tasks.forEach { task ->
            builder.append('\n')
            builder.append(task.id).append('\t')
            builder.append(if (task.done) "1" else "0").append('\t')
            builder.append(task.priority.name).append('\t')
            builder.append(task.createdAt).append('\t')
            builder.append(escape(task.title))
        }
        return builder.toString()
    }

    fun decode(payload: String?): DecodeResult {
        val text = payload.orEmpty()
        if (text.isBlank()) return DecodeResult(emptyList(), 0, true)
        val lines = text.split('\n')
        if (lines.first().trim() != HEADER) {
            return DecodeResult(emptyList(), lines.count { it.isNotBlank() }, false)
        }
        val tasks = mutableListOf<Task>()
        var skipped = 0
        lines.drop(1).forEach { line ->
            if (line.isNotBlank()) {
                val fields = line.split('\t')
                val createdAt = if (fields.size >= 5) fields[3].toLongOrNull() else null
                val done = when {
                    fields.size < 2 -> null
                    fields[1] == "1" -> true
                    fields[1] == "0" -> false
                    else -> null
                }
                if (fields.size < 5 || createdAt == null || done == null) {
                    skipped += 1
                } else {
                    val title = unescape(fields.drop(4).joinToString("\t"))
                    if (title.isBlank()) {
                        skipped += 1
                    } else {
                        tasks.add(Task(fields[0], title, done, Priority.fromName(fields[2]), createdAt))
                    }
                }
            }
        }
        return DecodeResult(tasks, skipped, true)
    }

    private fun escape(value: String): String {
        val out = StringBuilder(value.length)
        value.forEach { c ->
            when (c) {
                '\\' -> out.append("\\\\")
                '\t' -> out.append("\\t")
                '\n' -> out.append("\\n")
                '\r' -> out.append("\\r")
                else -> out.append(c)
            }
        }
        return out.toString()
    }

    private fun unescape(value: String): String {
        val out = StringBuilder(value.length)
        var index = 0
        while (index < value.length) {
            val c = value[index]
            if (c == '\\' && index + 1 < value.length) {
                when (value[index + 1]) {
                    '\\' -> { out.append('\\'); index += 2 }
                    't' -> { out.append('\t'); index += 2 }
                    'n' -> { out.append('\n'); index += 2 }
                    'r' -> { out.append('\r'); index += 2 }
                    else -> { out.append(c); index += 1 }
                }
            } else {
                out.append(c)
                index += 1
            }
        }
        return out.toString()
    }
}
