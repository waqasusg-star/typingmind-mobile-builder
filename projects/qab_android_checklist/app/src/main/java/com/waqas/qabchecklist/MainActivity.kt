package com.waqas.qabchecklist

import android.app.Activity
import android.app.AlertDialog
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.text.InputFilter
import android.text.InputType
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView

/**
 * Single-screen local-only checklist for builder acceptance testing.
 * Framework views only: no networking, no accounts, no analytics, no ads.
 */
class MainActivity : Activity() {

    private lateinit var store: ChecklistStore
    private var tasks: List<Task> = emptyList()
    private var priority: Priority = Priority.NORMAL
    private var statusMessage: String = ""

    private lateinit var column: LinearLayout
    private lateinit var taskContainer: LinearLayout
    private lateinit var input: EditText
    private lateinit var errorLabel: TextView
    private lateinit var statusLabel: TextView
    private lateinit var summaryLabel: TextView
    private lateinit var progress: ProgressBar
    private lateinit var emptyState: TextView
    private lateinit var clearCompletedButton: Button
    private lateinit var recoveryButton: Button
    private val priorityButtons = mutableMapOf<Priority, Button>()

    private val isNight: Boolean
        get() = (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES

    private val bg get() = if (isNight) Color.parseColor("#101319") else Color.parseColor("#F4F6FB")
    private val surface get() = if (isNight) Color.parseColor("#1A1F29") else Color.parseColor("#FFFFFF")
    private val border get() = if (isNight) Color.parseColor("#2A3140") else Color.parseColor("#DCE1EC")
    private val textPrimary get() = if (isNight) Color.parseColor("#F2F5FA") else Color.parseColor("#161A22")
    private val textSecondary get() = if (isNight) Color.parseColor("#A7B0C0") else Color.parseColor("#5B6474")
    private val accent get() = if (isNight) Color.parseColor("#7AA2FF") else Color.parseColor("#2F5FE0")
    private val danger get() = if (isNight) Color.parseColor("#FF8A8A") else Color.parseColor("#B3261E")

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        store = ChecklistStore(SharedPreferencesStore(this))

        val loaded = store.load()
        tasks = loaded.tasks
        loaded.notice?.let { statusMessage = it }

        setContentView(buildScreen())
        priority = Priority.fromName(savedInstanceState?.getString(STATE_PRIORITY))
        input.setText(savedInstanceState?.getString(STATE_DRAFT) ?: store.loadDraft())
        render()
    }

    private fun buildScreen(): View {
        val scroll = ScrollView(this).apply {
            isFillViewport = true
            setBackgroundColor(bg)
        }
        column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(20), dp(20), dp(24))
        }
        scroll.addView(
            column,
            ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        )
        scroll.setOnApplyWindowInsetsListener { _, insets ->
            @Suppress("DEPRECATION")
            column.setPadding(
                dp(20),
                dp(20) + insets.systemWindowInsetTop,
                dp(20),
                dp(20) + insets.systemWindowInsetBottom
            )
            insets
        }

        column.addView(heading("QA Checklist", 26f, Typeface.BOLD, textPrimary))
        column.addView(label("Local-only task checklist \u00b7 v1.0.0 \u00b7 nothing leaves this device", 13f, textSecondary))

        summaryLabel = label("", 14f, textSecondary).apply {
            setPadding(0, dp(14), 0, dp(8))
            accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
        }
        column.addView(summaryLabel)

        progress = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 100
            minHeight = dp(8)
            progressTintList = ColorStateList.valueOf(accent)
            progressBackgroundTintList = ColorStateList.valueOf(border)
            contentDescription = "0 percent complete"
        }
        column.addView(progress, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(8)))
        column.addView(space(18))

        input = EditText(this).apply {
            hint = "New task title"
            textSize = 16f
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
            filters = arrayOf<InputFilter>(InputFilter.LengthFilter(INPUT_LIMIT))
            imeOptions = EditorInfo.IME_ACTION_DONE
            maxLines = 3
            minHeight = dp(48)
            setTextColor(textPrimary)
            setHintTextColor(textSecondary)
            setPadding(dp(14), dp(12), dp(14), dp(12))
            background = rounded(surface, border, 12)
            contentDescription = "Task title"
            setOnEditorActionListener { _, actionId, _ ->
                if (actionId == EditorInfo.IME_ACTION_DONE) {
                    addTask()
                    true
                } else {
                    false
                }
            }
        }

        val addButton = Button(this).apply {
            text = "Add task"
            isAllCaps = false
            textSize = 16f
            minHeight = dp(48)
            minWidth = dp(96)
            setTextColor(Color.WHITE)
            background = rounded(accent, accent, 12)
            contentDescription = "Add task"
            setOnClickListener { addTask() }
        }

        val inputRow = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        inputRow.addView(
            input,
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply { marginEnd = dp(10) }
        )
        inputRow.addView(addButton)
        column.addView(inputRow)

        errorLabel = label("", 13f, danger).apply {
            setPadding(0, dp(8), 0, 0)
            visibility = View.GONE
            accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_ASSERTIVE
        }
        column.addView(errorLabel)

        column.addView(space(14))
        column.addView(label("Priority", 13f, textSecondary))
        val priorityRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, dp(8), 0, 0)
        }
        Priority.entries.forEach { option ->
            val button = Button(this).apply {
                text = option.label
                isAllCaps = false
                textSize = 14f
                minHeight = dp(48)
                setOnClickListener {
                    priority = option
                    statusMessage = "Priority set to " + option.label + "."
                    renderPriority()
                    renderStatus()
                }
            }
            priorityButtons[option] = button
            priorityRow.addView(
                button,
                LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply { marginEnd = dp(8) }
            )
        }
        column.addView(priorityRow)
        column.addView(space(18))

        taskContainer = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        column.addView(
            taskContainer,
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        )

        emptyState = label(
            "No tasks yet.\nAdd your first task above. Incomplete tasks stay on top, highest priority first.",
            14f,
            textSecondary
        ).apply {
            setPadding(dp(16), dp(24), dp(16), dp(24))
            gravity = Gravity.CENTER
            background = rounded(surface, border, 14)
        }
        column.addView(
            emptyState,
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        )

        column.addView(space(18))
        clearCompletedButton = Button(this).apply {
            text = "Clear completed"
            isAllCaps = false
            textSize = 14f
            minHeight = dp(48)
            setTextColor(textPrimary)
            background = rounded(surface, border, 12)
            contentDescription = "Clear completed tasks"
            setOnClickListener { clearCompleted() }
        }
        column.addView(
            clearCompletedButton,
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        )

        recoveryButton = Button(this).apply {
            text = "Restore recovery copy"
            isAllCaps = false
            textSize = 14f
            minHeight = dp(48)
            setTextColor(accent)
            background = rounded(surface, accent, 12)
            setOnClickListener { confirmRestore() }
        }
        column.addView(
            recoveryButton,
            LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        )

        statusLabel = label("", 13f, textSecondary).apply {
            setPadding(0, dp(14), 0, 0)
            accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
        }
        column.addView(statusLabel)

        return scroll
    }

    private fun render() {
        renderPriority()
        renderSummary()
        renderRecovery()
        renderStatus()

        taskContainer.removeAllViews()
        val ordered = ChecklistPolicy.sortForDisplay(tasks)
        emptyState.visibility = if (ordered.isEmpty()) View.VISIBLE else View.GONE
        taskContainer.visibility = if (ordered.isEmpty()) View.GONE else View.VISIBLE
        ordered.forEach { taskContainer.addView(buildRow(it), rowParams()) }

        val hasCompleted = tasks.any { it.done }
        clearCompletedButton.isEnabled = hasCompleted
        clearCompletedButton.alpha = if (hasCompleted) 1f else 0.45f
    }

    private fun renderPriority() {
        priorityButtons.forEach { (option, button) ->
            val selected = option == priority
            button.background = if (selected) rounded(accent, accent, 12) else rounded(surface, border, 12)
            button.setTextColor(if (selected) Color.WHITE else textPrimary)
            button.isSelected = selected
            button.contentDescription =
                option.label + " priority" + if (selected) ", selected" else ""
        }
    }

    private fun renderSummary() {
        val summary = ChecklistPolicy.summarize(tasks)
        summaryLabel.text = summary.headline
        progress.progress = summary.percentDone
        progress.contentDescription = summary.percentDone.toString() + " percent complete"
    }

    private fun renderRecovery() {
        val count = store.recoveryTaskCount()
        if (count == null) {
            recoveryButton.visibility = View.GONE
        } else {
            recoveryButton.visibility = View.VISIBLE
            recoveryButton.text = "Restore recovery copy (" + count + ")"
            recoveryButton.contentDescription =
                "Restore " + count + " " + (if (count == 1) "task" else "tasks") + " from the recovery copy"
        }
    }

    private fun renderStatus() {
        statusLabel.text = statusMessage
        statusLabel.visibility = if (statusMessage.isBlank()) View.GONE else View.VISIBLE
        if (statusMessage.isNotBlank()) {
            statusLabel.announceForAccessibility(statusMessage)
        }
    }

    private fun buildRow(task: Task): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(10), dp(8), dp(8), dp(8))
            minimumHeight = dp(56)
            background = rounded(surface, border, 14)
        }

        val check = CheckBox(this).apply {
            isChecked = task.done
            contentDescription = "Mark " + task.title + (if (task.done) " as not done" else " as done")
            setOnCheckedChangeListener { _, checked -> setDone(task.id, checked) }
        }

        val title = label(task.title, 16f, if (task.done) textSecondary else textPrimary).apply {
            maxLines = 2
            ellipsize = TextUtils.TruncateAt.END
            setPadding(dp(2), 0, dp(8), 0)
            if (task.done) paintFlags = paintFlags or Paint.STRIKE_THRU_TEXT_FLAG
        }

        val pill = label(task.priority.label, 11f, priorityColor(task.priority)).apply {
            setPadding(dp(8), dp(4), dp(8), dp(4))
            background = rounded(Color.TRANSPARENT, priorityColor(task.priority), 20)
        }

        val delete = Button(this).apply {
            text = "Delete"
            isAllCaps = false
            textSize = 13f
            minWidth = dp(48)
            minHeight = dp(48)
            setTextColor(danger)
            background = rounded(Color.TRANSPARENT, danger, 12)
            contentDescription = "Delete " + task.title
            setOnClickListener { deleteTask(task.id) }
        }

        row.addView(check)
        row.addView(title, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        row.addView(pill)
        row.addView(delete)
        return row
    }

    private fun addTask() {
        when (val result = ChecklistPolicy.add(tasks, input.text.toString(), priority, System.currentTimeMillis())) {
            is ChecklistPolicy.AddResult.Rejected -> showError(result.message)
            is ChecklistPolicy.AddResult.Added -> {
                tasks = result.tasks
                input.setText("")
                store.saveDraft("")
                showError(null)
                persist()
                statusMessage = "Added \u201c" + result.task.title + "\u201d as " + result.task.priority.label + " priority."
                render()
                input.requestFocus()
            }
        }
    }

    private fun setDone(id: String, done: Boolean) {
        val target = tasks.firstOrNull { it.id == id } ?: return
        tasks = ChecklistPolicy.setDone(tasks, id, done)
        persist()
        statusMessage = (if (done) "Completed \u201c" else "Reopened \u201c") + target.title + "\u201d."
        render()
    }

    private fun deleteTask(id: String) {
        val target = tasks.firstOrNull { it.id == id } ?: return
        tasks = ChecklistPolicy.remove(tasks, id)
        persist()
        statusMessage = "Deleted \u201c" + target.title + "\u201d."
        render()
    }

    private fun clearCompleted() {
        val removed = tasks.count { it.done }
        if (removed == 0) {
            statusMessage = "No completed tasks to clear."
            renderStatus()
            return
        }
        tasks = ChecklistPolicy.clearCompleted(tasks)
        persist()
        statusMessage = "Cleared " + removed + " completed " + (if (removed == 1) "task" else "tasks") + "."
        render()
    }

    private fun confirmRestore() {
        val count = store.recoveryTaskCount() ?: return
        AlertDialog.Builder(this)
            .setTitle("Restore recovery copy")
            .setMessage(
                "Replace the current list with the " + count + " " +
                    (if (count == 1) "task" else "tasks") + " kept from unreadable saved data?"
            )
            .setNegativeButton("Cancel", null)
            .setPositiveButton("Restore") { _, _ ->
                val restored = store.restoreRecoveryCopy()
                if (restored.tasks.isNotEmpty()) {
                    tasks = restored.tasks
                }
                statusMessage = restored.notice ?: "Recovery copy restored."
                render()
            }
            .show()
    }

    private fun showError(message: String?) {
        if (message == null) {
            errorLabel.text = ""
            errorLabel.visibility = View.GONE
        } else {
            errorLabel.text = message
            errorLabel.visibility = View.VISIBLE
            errorLabel.announceForAccessibility(message)
            input.requestFocus()
        }
    }

    private fun persist() {
        store.save(tasks)
    }

    private fun priorityColor(option: Priority): Int = when (option) {
        Priority.HIGH -> danger
        Priority.NORMAL -> accent
        Priority.LOW -> textSecondary
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private fun rounded(fill: Int, stroke: Int, radiusDp: Int): GradientDrawable =
        GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(radiusDp).toFloat()
            setColor(fill)
            setStroke(dp(1), stroke)
        }

    private fun label(text: String, size: Float, color: Int): TextView =
        TextView(this).apply {
            this.text = text
            textSize = size
            setTextColor(color)
            includeFontPadding = false
        }

    private fun heading(text: String, size: Float, style: Int, color: Int): TextView =
        label(text, size, color).apply { typeface = Typeface.create("sans-serif", style) }

    private fun space(heightDp: Int): View = View(this).apply {
        layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(heightDp))
    }

    private fun rowParams(): LinearLayout.LayoutParams =
        LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
            .apply { bottomMargin = dp(8) }

    override fun onPause() {
        super.onPause()
        store.save(tasks)
        store.saveDraft(input.text.toString())
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putString(STATE_DRAFT, input.text.toString())
        outState.putString(STATE_PRIORITY, priority.name)
    }

    companion object {
        private const val STATE_DRAFT = "state_draft"
        private const val STATE_PRIORITY = "state_priority"
        private const val INPUT_LIMIT = 200
    }
}
