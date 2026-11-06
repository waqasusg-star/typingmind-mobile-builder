// UIKit-free checklist core for the native iPhone acceptance app.
//
// This file is compiled alone with Tests/PolicyTests.swift through the reviewed
// "foundation_policy" test profile, so it must not reference app-only symbols.

import Foundation

enum TaskPriority: String, Codable, CaseIterable {
    case high
    case normal
    case low

    var label: String {
        switch self {
        case .high: return "High"
        case .normal: return "Normal"
        case .low: return "Low"
        }
    }

    var sortRank: Int {
        switch self {
        case .high: return 0
        case .normal: return 1
        case .low: return 2
        }
    }

    static func parse(_ raw: String?) -> TaskPriority {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              let parsed = TaskPriority(rawValue: trimmed) else {
            return .normal
        }
        return parsed
    }
}

struct ChecklistItem: Codable, Equatable {
    var id: String
    var title: String
    var done: Bool
    var priority: TaskPriority
    var createdAt: Double
}

enum TitleValidation: Equatable {
    case valid(String)
    case invalid(String)

    var normalizedTitle: String? {
        if case .valid(let title) = self { return title }
        return nil
    }

    var errorMessage: String? {
        if case .invalid(let message) = self { return message }
        return nil
    }
}

struct ChecklistSummary: Equatable {
    let total: Int
    let done: Int
    let remaining: Int
    let percentDone: Int
    let headline: String
}

enum AddOutcome: Equatable {
    case added(items: [ChecklistItem], item: ChecklistItem)
    case rejected(String)
}

struct ChecklistDecode: Equatable {
    let items: [ChecklistItem]
    let skippedLines: Int
    let formatOk: Bool

    var needsRecoveryCopy: Bool { !formatOk || skippedLines > 0 }
}

enum ThemeChoice: String, CaseIterable {
    case system
    case light
    case dark

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    static func parse(_ raw: String?) -> ThemeChoice {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              let parsed = ThemeChoice(rawValue: trimmed) else {
            return .system
        }
        return parsed
    }
}

enum ChecklistPolicy {

    static let maxTitleLength = 120
    static let schemaVersion = 1
    static let headerLine = "{\"app\":\"qab-checklist\",\"schema\":1}"

    // MARK: Validation and mutation

    static func validateTitle(_ raw: String?) -> TitleValidation {
        let collapsed = (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        if collapsed.isEmpty {
            return .invalid("Enter a task title before adding it.")
        }
        if collapsed.count > maxTitleLength {
            return .invalid("Keep the title to \(maxTitleLength) characters or fewer (currently \(collapsed.count)).")
        }
        return .valid(collapsed)
    }

    static func nextID(existing: [ChecklistItem], now: Double) -> String {
        let base = "t" + String(Int(now.rounded()))
        var candidate = base
        var suffix = 2
        while existing.contains(where: { $0.id == candidate }) {
            candidate = base + "-" + String(suffix)
            suffix += 1
        }
        return candidate
    }

    static func add(_ existing: [ChecklistItem], rawTitle: String?, priority: TaskPriority, now: Double) -> AddOutcome {
        switch validateTitle(rawTitle) {
        case .invalid(let message):
            return .rejected(message)
        case .valid(let title):
            let item = ChecklistItem(
                id: nextID(existing: existing, now: now),
                title: title,
                done: false,
                priority: priority,
                createdAt: now
            )
            return .added(items: existing + [item], item: item)
        }
    }

    static func setDone(_ items: [ChecklistItem], id: String, done: Bool) -> [ChecklistItem] {
        items.map { item in
            guard item.id == id else { return item }
            var copy = item
            copy.done = done
            return copy
        }
    }

    static func remove(_ items: [ChecklistItem], id: String) -> [ChecklistItem] {
        items.filter { $0.id != id }
    }

    static func clearCompleted(_ items: [ChecklistItem]) -> [ChecklistItem] {
        items.filter { !$0.done }
    }

    /// Incomplete first, then highest priority, then oldest, then alphabetical.
    static func sortedForDisplay(_ items: [ChecklistItem]) -> [ChecklistItem] {
        items.sorted { lhs, rhs in
            if lhs.done != rhs.done { return !lhs.done }
            if lhs.priority.sortRank != rhs.priority.sortRank {
                return lhs.priority.sortRank < rhs.priority.sortRank
            }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.title.lowercased() < rhs.title.lowercased()
        }
    }

    static func summarize(_ items: [ChecklistItem]) -> ChecklistSummary {
        let total = items.count
        let done = items.filter { $0.done }.count
        let percent = total == 0 ? 0 : (done * 100) / total
        let headline: String
        if total == 0 {
            headline = "No tasks yet"
        } else if done == total {
            headline = "All \(total) done"
        } else {
            headline = "\(done) of \(total) done"
        }
        return ChecklistSummary(
            total: total,
            done: done,
            remaining: total - done,
            percentDone: percent,
            headline: headline
        )
    }

    // MARK: Persistence codec — strict header line plus one JSON object per item line.
    // A damaged item line is skipped instead of discarding the whole checklist.

    static func encode(_ items: [ChecklistItem]) -> String {
        var lines: [String] = [headerLine]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for item in items {
            if let data = try? encoder.encode(item), let text = String(data: data, encoding: .utf8) {
                lines.append(text)
            }
        }
        return lines.joined(separator: "\n")
    }

    static func decode(_ payload: String?) -> ChecklistDecode {
        guard let payload = payload,
              !payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ChecklistDecode(items: [], skippedLines: 0, formatOk: true)
        }
        let lines = payload
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let header = lines.first,
              let headerData = header.data(using: .utf8),
              let headerObject = (try? JSONSerialization.jsonObject(with: headerData)) as? [String: Any],
              let schema = headerObject["schema"] as? Int,
              schema == schemaVersion else {
            return ChecklistDecode(items: [], skippedLines: 0, formatOk: false)
        }

        let decoder = JSONDecoder()
        var items: [ChecklistItem] = []
        var skipped = 0
        for line in lines.dropFirst() {
            guard let data = line.data(using: .utf8),
                  let decoded = try? decoder.decode(ChecklistItem.self, from: data) else {
                skipped += 1
                continue
            }
            var item = decoded
            let trimmedTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty, trimmedTitle.count <= maxTitleLength else {
                skipped += 1
                continue
            }
            item.title = trimmedTitle
            items.append(item)
        }
        return ChecklistDecode(items: items, skippedLines: skipped, formatOk: true)
    }
}
