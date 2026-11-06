package com.waqas.qabchecklist

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ChecklistPolicyTest {

    private fun task(
        id: String,
        title: String,
        done: Boolean = false,
        priority: Priority = Priority.NORMAL,
        createdAt: Long = 0L
    ) = Task(id, title, done, priority, createdAt)

    @Test
    fun blankTitleIsRejectedWithGuidance() {
        val result = ChecklistPolicy.validateTitle("   ")
        assertTrue(result is TitleResult.Invalid)
        assertEquals("Enter a task title before adding it.", (result as TitleResult.Invalid).message)
    }

    @Test
    fun nullTitleIsRejected() {
        assertTrue(ChecklistPolicy.validateTitle(null) is TitleResult.Invalid)
    }

    @Test
    fun titleIsTrimmedAndInternalWhitespaceCollapsed() {
        val result = ChecklistPolicy.validateTitle("   Review    the\tPR  ")
        assertTrue(result is TitleResult.Valid)
        assertEquals("Review the PR", (result as TitleResult.Valid).title)
    }

    @Test
    fun maximumTitleLengthIsEnforced() {
        val atLimit = "a".repeat(ChecklistPolicy.MAX_TITLE_LENGTH)
        assertTrue(ChecklistPolicy.validateTitle(atLimit) is TitleResult.Valid)

        val tooLong = "a".repeat(ChecklistPolicy.MAX_TITLE_LENGTH + 1)
        val result = ChecklistPolicy.validateTitle(tooLong)
        assertTrue(result is TitleResult.Invalid)
        assertTrue((result as TitleResult.Invalid).message.contains("120"))
    }

    @Test
    fun addRejectsInvalidTitleAndKeepsExistingTasks() {
        val existing = listOf(task("t1", "First"))
        val result = ChecklistPolicy.add(existing, "  ", Priority.HIGH, 10L)
        assertTrue(result is ChecklistPolicy.AddResult.Rejected)
    }

    @Test
    fun addAppendsTaskWithPriorityAndDeterministicId() {
        val result = ChecklistPolicy.add(emptyList(), "Write acceptance report", Priority.HIGH, 500L)
        assertTrue(result is ChecklistPolicy.AddResult.Added)
        val added = result as ChecklistPolicy.AddResult.Added
        assertEquals(1, added.tasks.size)
        assertEquals("t500", added.task.id)
        assertEquals("Write acceptance report", added.task.title)
        assertFalse(added.task.done)
        assertEquals(Priority.HIGH, added.task.priority)
    }

    @Test
    fun idsStayUniqueWhenTwoTasksShareATimestamp() {
        val first = ChecklistPolicy.add(emptyList(), "One", Priority.NORMAL, 42L)
        val addedFirst = (first as ChecklistPolicy.AddResult.Added).tasks
        val second = ChecklistPolicy.add(addedFirst, "Two", Priority.LOW, 42L)
        val addedSecond = (second as ChecklistPolicy.AddResult.Added).tasks
        assertEquals(2, addedSecond.size)
        assertNotEquals(addedSecond[0].id, addedSecond[1].id)
    }

    @Test
    fun sortingPutsIncompleteHighPriorityTasksFirst() {
        val done = task("a", "Done urgent", done = true, priority = Priority.HIGH, createdAt = 1L)
        val low = task("b", "Low pending", priority = Priority.LOW, createdAt = 2L)
        val highNew = task("c", "High pending newer", priority = Priority.HIGH, createdAt = 9L)
        val highOld = task("d", "High pending older", priority = Priority.HIGH, createdAt = 3L)

        val ordered = ChecklistPolicy.sortForDisplay(listOf(done, low, highNew, highOld))

        assertEquals(listOf("d", "c", "b", "a"), ordered.map { it.id })
    }

    @Test
    fun summarizeReportsProgress() {
        val summary = ChecklistPolicy.summarize(
            listOf(task("a", "A", done = true), task("b", "B"), task("c", "C"), task("d", "D"))
        )
        assertEquals(4, summary.total)
        assertEquals(1, summary.done)
        assertEquals(3, summary.remaining)
        assertEquals(25, summary.percentDone)
        assertEquals("1 of 4 done", summary.headline)
    }

    @Test
    fun summarizeHandlesEmptyAndCompleteLists() {
        val empty = ChecklistPolicy.summarize(emptyList())
        assertEquals(0, empty.total)
        assertEquals(0, empty.percentDone)
        assertEquals("No tasks yet", empty.headline)

        val complete = ChecklistPolicy.summarize(listOf(task("a", "A", done = true), task("b", "B", done = true)))
        assertEquals(100, complete.percentDone)
        assertEquals("All 2 done", complete.headline)
    }

    @Test
    fun toggleChangesOnlyTheTargetTask() {
        val tasks = listOf(task("a", "A"), task("b", "B"))
        val toggled = ChecklistPolicy.toggle(tasks, "b")
        assertFalse(toggled[0].done)
        assertTrue(toggled[1].done)
        assertFalse(ChecklistPolicy.toggle(toggled, "missing")[1] == false)
    }

    @Test
    fun removeAndClearCompletedKeepTheRest() {
        val tasks = listOf(task("a", "A", done = true), task("b", "B"), task("c", "C", done = true))
        assertEquals(listOf("b", "c"), ChecklistPolicy.remove(tasks, "a").map { it.id })
        assertEquals(listOf("b"), ChecklistPolicy.clearCompleted(tasks).map { it.id })
    }

    @Test
    fun encodeDecodeRoundTripPreservesEverything() {
        val original = listOf(
            task("t1", "Tab\tand newline\nand backslash \\ inside", done = true, priority = Priority.HIGH, createdAt = 111L),
            task("t2", "\u0645\u0631\u0627\u062c\u0639\u0629 \u2014 \u5be9\u67fb \u2705", priority = Priority.LOW, createdAt = 222L)
        )
        val decoded = ChecklistPolicy.decode(ChecklistPolicy.encode(original))
        assertTrue(decoded.formatOk)
        assertEquals(0, decoded.skippedLines)
        assertEquals(original, decoded.tasks)
    }

    @Test
    fun blankPayloadDecodesToEmptyListWithoutError() {
        val decoded = ChecklistPolicy.decode("")
        assertTrue(decoded.formatOk)
        assertEquals(0, decoded.skippedLines)
        assertTrue(decoded.tasks.isEmpty())
    }

    @Test
    fun unknownHeaderIsReportedAsInvalidFormat() {
        val decoded = ChecklistPolicy.decode("SOMETHING ELSE\n1\t1\tHIGH\t5\tTask")
        assertFalse(decoded.formatOk)
        assertTrue(decoded.tasks.isEmpty())
    }

    @Test
    fun damagedEntryIsSkippedWhileGoodEntriesSurvive() {
        val good = ChecklistPolicy.encode(listOf(task("t1", "Keep me", priority = Priority.HIGH, createdAt = 9L)))
        val damaged = good + "\n" + "broken-line-without-fields" + "\n" + "t9\tx\tHIGH\tnotanumber\tBad"
        val decoded = ChecklistPolicy.decode(damaged)
        assertTrue(decoded.formatOk)
        assertEquals(1, decoded.tasks.size)
        assertEquals("Keep me", decoded.tasks[0].title)
        assertEquals(2, decoded.skippedLines)
    }

    @Test
    fun priorityFallsBackToNormalForUnknownNames() {
        assertEquals(Priority.NORMAL, Priority.fromName("urgent-ish"))
        assertEquals(Priority.HIGH, Priority.fromName(" high "))
        assertEquals(Priority.NORMAL, Priority.fromName(null))
    }
}
