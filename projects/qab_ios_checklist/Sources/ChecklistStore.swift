import Foundation

/// Thin UserDefaults wiring around the tested codec in RequestPolicy.swift.
final class ChecklistStore {

    private enum Key {
        static let items = "qab.checklist.items.v1"
        static let recovery = "qab.checklist.recovery.v1"
        static let draft = "qab.checklist.draft.v1"
        static let theme = "qab.checklist.theme.v1"
    }

    struct LoadResult {
        let items: [ChecklistItem]
        let notice: String?
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> LoadResult {
        guard let payload = defaults.string(forKey: Key.items) else {
            return LoadResult(items: [], notice: nil)
        }
        let decoded = ChecklistPolicy.decode(payload)
        if !decoded.formatOk {
            defaults.set(payload, forKey: Key.recovery)
            defaults.removeObject(forKey: Key.items)
            return LoadResult(
                items: [],
                notice: "The saved checklist could not be read, so a fresh list was started. The unreadable copy was kept for recovery."
            )
        }
        if decoded.skippedLines > 0 {
            defaults.set(payload, forKey: Key.recovery)
            let label = decoded.skippedLines == 1 ? "entry" : "entries"
            return LoadResult(
                items: decoded.items,
                notice: "Recovered the checklist and skipped \(decoded.skippedLines) damaged \(label)."
            )
        }
        return LoadResult(items: decoded.items, notice: nil)
    }

    func save(_ items: [ChecklistItem]) {
        defaults.set(ChecklistPolicy.encode(items), forKey: Key.items)
    }

    func saveDraft(_ text: String) {
        defaults.set(text, forKey: Key.draft)
    }

    func loadDraft() -> String {
        defaults.string(forKey: Key.draft) ?? ""
    }

    func themeChoice() -> ThemeChoice {
        ThemeChoice.parse(defaults.string(forKey: Key.theme))
    }

    func saveTheme(_ choice: ThemeChoice) {
        defaults.set(choice.rawValue, forKey: Key.theme)
    }

    func recoveryCount() -> Int? {
        guard let payload = defaults.string(forKey: Key.recovery) else { return nil }
        let decoded = ChecklistPolicy.decode(payload)
        return (decoded.formatOk && !decoded.items.isEmpty) ? decoded.items.count : nil
    }

    func restoreRecoveryCopy() -> LoadResult {
        guard let payload = defaults.string(forKey: Key.recovery) else {
            return LoadResult(items: [], notice: "There is no recovery copy to restore.")
        }
        let decoded = ChecklistPolicy.decode(payload)
        guard decoded.formatOk, !decoded.items.isEmpty else {
            return LoadResult(items: [], notice: "The recovery copy is unreadable too, so nothing was restored.")
        }
        save(decoded.items)
        defaults.removeObject(forKey: Key.recovery)
        let label = decoded.items.count == 1 ? "task" : "tasks"
        return LoadResult(
            items: decoded.items,
            notice: "Restored \(decoded.items.count) \(label) from the recovery copy."
        )
    }
}
