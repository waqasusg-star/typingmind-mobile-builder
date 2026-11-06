package com.waqas.qabchecklist

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ChecklistStoreTest {

    private class FakeKeyValueStore : KeyValueStore {
        val values = mutableMapOf<String, String>()
        override fun read(key: String): String? = values[key]
        override fun write(key: String, value: String) {
            values[key] = value
        }

        override fun remove(key: String) {
            values.remove(key)
        }
    }

    private fun task(id: String, title: String, done: Boolean = false) =
        Task(id, title, done, Priority.NORMAL, 1L)

    @Test
    fun firstRunReturnsEmptyListWithoutNotice() {
        val store = ChecklistStore(FakeKeyValueStore())
        val loaded = store.load()
        assertTrue(loaded.tasks.isEmpty())
        assertNull(loaded.notice)
    }

    @Test
    fun saveThenLoadRoundTrips() {
        val kv = FakeKeyValueStore()
        val store = ChecklistStore(kv)
        val tasks = listOf(task("t1", "Ship build", done = true), task("t2", "Write notes"))
        store.save(tasks)

        val reloaded = ChecklistStore(kv).load()
        assertEquals(tasks, reloaded.tasks)
        assertNull(reloaded.notice)
    }

    @Test
    fun unreadablePayloadIsBackedUpAndReset() {
        val kv = FakeKeyValueStore()
        kv.write(ChecklistStore.KEY_TASKS, "definitely not our format")
        val loaded = ChecklistStore(kv).load()

        assertTrue(loaded.tasks.isEmpty())
        assertNotNull(loaded.notice)
        assertTrue(loaded.notice!!.contains("could not be read"))
        assertEquals("definitely not our format", kv.read(ChecklistStore.KEY_RECOVERY))
        assertNull(kv.read(ChecklistStore.KEY_TASKS))
    }

    @Test
    fun partiallyDamagedPayloadKeepsGoodTasks() {
        val kv = FakeKeyValueStore()
        val good = ChecklistPolicy.encode(listOf(task("t1", "Survivor")))
        kv.write(ChecklistStore.KEY_TASKS, good + "\nnot-a-task-row")

        val loaded = ChecklistStore(kv).load()
        assertEquals(1, loaded.tasks.size)
        assertEquals("Survivor", loaded.tasks[0].title)
        assertTrue(loaded.notice!!.contains("1 damaged entry"))
        assertEquals(good + "\nnot-a-task-row", kv.read(ChecklistStore.KEY_RECOVERY))
    }

    @Test
    fun recoveryTaskCountIsNullWhenNothingIsBackedUp() {
        assertNull(ChecklistStore(FakeKeyValueStore()).recoveryTaskCount())
    }

    @Test
    fun restoreRecoveryCopyReplaysBackedUpTasks() {
        val kv = FakeKeyValueStore()
        val backup = ChecklistPolicy.encode(listOf(task("t1", "Alpha"), task("t2", "Beta", done = true)))
        kv.write(ChecklistStore.KEY_RECOVERY, backup)

        val store = ChecklistStore(kv)
        assertEquals(2, store.recoveryTaskCount())

        val restored = store.restoreRecoveryCopy()
        assertEquals(2, restored.tasks.size)
        assertEquals("Restored 2 tasks from the recovery copy.", restored.notice)
        assertNull(kv.read(ChecklistStore.KEY_RECOVERY))
        assertEquals(2, ChecklistStore(kv).load().tasks.size)
    }

    @Test
    fun unreadableRecoveryCopyIsReportedWithoutTouchingTasks() {
        val kv = FakeKeyValueStore()
        kv.write(ChecklistStore.KEY_RECOVERY, "garbage")
        val store = ChecklistStore(kv)

        assertNull(store.recoveryTaskCount())
        val restored = store.restoreRecoveryCopy()
        assertTrue(restored.tasks.isEmpty())
        assertTrue(restored.notice!!.contains("unreadable"))
    }

    @Test
    fun draftRoundTripsAndCanBeCleared() {
        val store = ChecklistStore(FakeKeyValueStore())
        assertEquals("", store.loadDraft())
        store.saveDraft("half typed title")
        assertEquals("half typed title", store.loadDraft())
        store.saveDraft("")
        assertEquals("", store.loadDraft())
    }
}
