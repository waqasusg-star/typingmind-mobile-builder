import Foundation

var checkCount = 0

func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    checkCount += 1
    if !value() { fatalError("FAILED: " + message) }
}

func item(
    _ id: String,
    _ title: String,
    done: Bool = false,
    priority: TaskPriority = .normal,
    createdAt: Double = 1
) -> ChecklistItem {
    ChecklistItem(id: id, title: title, done: done, priority: priority, createdAt: createdAt)
}

@main struct PolicyTests {

    static func main() {

        // MARK: 1. Title validation
        expect(
            ChecklistPolicy.validateTitle(nil) == .invalid("Enter a task title before adding it."),
            "nil title is rejected with guidance"
        )
        expect(
            ChecklistPolicy.validateTitle("   ") == .invalid("Enter a task title before adding it."),
            "whitespace-only title is rejected"
        )
        expect(
            ChecklistPolicy.validateTitle("\n\t ") == .invalid("Enter a task title before adding it."),
            "tab and newline title is rejected"
        )
        expect(
            ChecklistPolicy.validateTitle("  Review   the\tPR ") == .valid("Review the PR"),
            "title is trimmed and inner whitespace collapsed"
        )
        let atLimit = String(repeating: "a", count: ChecklistPolicy.maxTitleLength)
        expect(ChecklistPolicy.validateTitle(atLimit) == .valid(atLimit), "120 characters is accepted")
        let overLimit = String(repeating: "b", count: ChecklistPolicy.maxTitleLength + 1)
        if case .invalid(let message) = ChecklistPolicy.validateTitle(overLimit) {
            expect(message.contains("120"), "over-length message states the limit")
            expect(message.contains("121"), "over-length message states the current length")
        } else {
            expect(false, "121 characters is rejected")
        }
        expect(
            ChecklistPolicy.validateTitle("مراجعة الملفات — 審査 ✅") == .valid("مراجعة الملفات — 審査 ✅"),
            "unicode title survives validation"
        )
        expect(ChecklistPolicy.validateTitle(atLimit).normalizedTitle == atLimit, "valid result exposes the title")
        expect(
            ChecklistPolicy.validateTitle("   ").errorMessage == "Enter a task title before adding it.",
            "invalid result exposes its message"
        )

        // MARK: 2. Adding tasks
        let added = ChecklistPolicy.add([], rawTitle: "Write acceptance report", priority: .high, now: 500)
        if case .added(let itemsAfterAdd, let newItem) = added {
            expect(itemsAfterAdd.count == 1, "add appends one task")
            expect(newItem.id == "t500", "add derives a deterministic id")
            expect(newItem.title == "Write acceptance report", "add stores the normalized title")
            expect(newItem.done == false, "new tasks start incomplete")
            expect(newItem.priority == .high, "add keeps the chosen priority")
        } else {
            expect(false, "valid title is added")
        }
        if case .rejected(let message) = ChecklistPolicy.add([], rawTitle: "   ", priority: .low, now: 1) {
            expect(message.contains("Enter a task title"), "blank add is rejected with guidance")
        } else {
            expect(false, "blank add is rejected")
        }
        let first = ChecklistPolicy.add([], rawTitle: "One", priority: .normal, now: 42)
        if case .added(let firstItems, _) = first {
            if case .added(let secondItems, let secondItem) = ChecklistPolicy.add(firstItems, rawTitle: "Two", priority: .low, now: 42) {
                expect(secondItems.count == 2, "two tasks with the same timestamp both survive")
                expect(secondItem.id != "t42", "duplicate timestamp ids are disambiguated")
            } else {
                expect(false, "second add succeeds")
            }
        } else {
            expect(false, "first add succeeds")
        }

        // MARK: 3. Ordering
        let ordered = ChecklistPolicy.sortedForDisplay([
            item("a", "Done urgent", done: true, priority: .high, createdAt: 1),
            item("b", "Low pending", priority: .low, createdAt: 2),
            item("c", "High pending newer", priority: .high, createdAt: 9),
            item("d", "High pending older", priority: .high, createdAt: 3)
        ])
        expect(ordered.map { $0.id } == ["d", "c", "b", "a"], "incomplete first, then priority, then age")

        // MARK: 4. Summary
        let summary = ChecklistPolicy.summarize([
            item("a", "A", done: true), item("b", "B"), item("c", "C"), item("d", "D")
        ])
        expect(summary.total == 4, "summary counts all tasks")
        expect(summary.done == 1, "summary counts completed tasks")
        expect(summary.remaining == 3, "summary counts remaining tasks")
        expect(summary.percentDone == 25, "summary computes percent complete")
        expect(summary.headline == "1 of 4 done", "summary headline is readable")
        let emptySummary = ChecklistPolicy.summarize([])
        expect(emptySummary.headline == "No tasks yet", "empty summary headline")
        expect(emptySummary.percentDone == 0, "empty summary reports zero percent")
        let completeSummary = ChecklistPolicy.summarize([item("a", "A", done: true), item("b", "B", done: true)])
        expect(completeSummary.percentDone == 100, "complete list reports 100 percent")
        expect(completeSummary.headline == "All 2 done", "complete summary headline")
        expect(ChecklistPolicy.summarize([item("a", "A", done: true), item("b", "B"), item("c", "C")]).percentDone == 33,
               "percent complete truncates instead of rounding up")

        // MARK: 5. Mutations
        let base = [item("a", "A"), item("b", "B")]
        let toggled = ChecklistPolicy.setDone(base, id: "b", done: true)
        expect(toggled[0].done == false, "setDone leaves other tasks untouched")
        expect(toggled[1].done == true, "setDone updates the target")
        expect(ChecklistPolicy.setDone(toggled, id: "b", done: false)[1].done == false, "setDone can reopen a task")
        expect(ChecklistPolicy.remove(base, id: "a").map { $0.id } == ["b"], "remove drops only the target")
        expect(
            ChecklistPolicy.clearCompleted([item("a", "A", done: true), item("b", "B")]).map { $0.id } == ["b"],
            "clearCompleted keeps incomplete tasks"
        )
        expect(ChecklistPolicy.remove([], id: "missing").isEmpty, "remove on an empty list is safe")

        // MARK: 6. Persistence codec round trip
        let tricky = [
            item("t1", "Quotes \"here\" and \\ backslash and \n newline", done: true, priority: .high, createdAt: 111),
            item("t2", "مراجعة — 審査 ✅", priority: .low, createdAt: 222)
        ]
        let encoded = ChecklistPolicy.encode(tricky)
        expect(encoded.hasPrefix(ChecklistPolicy.headerLine), "encoded payload starts with the versioned header")
        let decoded = ChecklistPolicy.decode(encoded)
        expect(decoded.formatOk, "encoded payload decodes as valid")
        expect(decoded.skippedLines == 0, "valid payload skips nothing")
        expect(decoded.items == tricky, "round trip preserves every field")
        expect(decoded.needsRecoveryCopy == false, "clean payload needs no recovery copy")

        // MARK: 7. Decode tolerance and corruption
        let blank = ChecklistPolicy.decode(nil)
        expect(blank.formatOk && blank.items.isEmpty && blank.skippedLines == 0, "nil payload is an empty checklist")
        let whitespace = ChecklistPolicy.decode("   \n  ")
        expect(whitespace.formatOk && whitespace.items.isEmpty, "whitespace payload is an empty checklist")
        let garbage = ChecklistPolicy.decode("definitely not our format")
        expect(garbage.formatOk == false, "unknown payload is flagged as unreadable")
        expect(garbage.items.isEmpty, "unreadable payload yields no tasks")
        expect(garbage.needsRecoveryCopy, "unreadable payload asks for a recovery copy")
        let wrongSchema = ChecklistPolicy.decode("{\"app\":\"qab-checklist\",\"schema\":2}")
        expect(wrongSchema.formatOk == false, "future schema versions are refused instead of misread")
        let damaged = ChecklistPolicy.encode([item("t1", "Survivor", priority: .high, createdAt: 9)])
            + "\n{\"broken\":"
            + "\n{\"id\":\"t9\",\"title\":\"   \",\"done\":false,\"priority\":\"high\",\"createdAt\":1}"
        let recovered = ChecklistPolicy.decode(damaged)
        expect(recovered.formatOk, "single damaged lines do not invalidate the checklist")
        expect(recovered.items.count == 1, "good tasks survive damaged lines")
        expect(recovered.items.first?.title == "Survivor", "surviving task keeps its title")
        expect(recovered.skippedLines == 2, "both the broken JSON and the blank title are skipped")
        expect(recovered.needsRecoveryCopy, "partial damage requests a recovery copy")

        // MARK: 8. Priority and theme parsing
        expect(TaskPriority.parse(" high ") == .high, "priority parsing trims and lowercases")
        expect(TaskPriority.parse("urgent-ish") == .normal, "unknown priority falls back to normal")
        expect(TaskPriority.parse(nil) == .normal, "missing priority falls back to normal")
        expect(TaskPriority.allCases.map { $0.label } == ["High", "Normal", "Low"], "priority labels are stable")
        expect(TaskPriority.high.sortRank < TaskPriority.normal.sortRank, "high priority sorts first")
        expect(ThemeChoice.parse(nil) == .system, "missing appearance follows the system")
        expect(ThemeChoice.parse(" DARK ") == .dark, "appearance parsing trims and lowercases")
        expect(ThemeChoice.parse("neon") == .system, "unknown appearance falls back to system")
        expect(ThemeChoice.allCases.map { $0.label } == ["System", "Light", "Dark"], "appearance labels are stable")

        print("PolicyTests passed: \(checkCount) checks")
    }
}
