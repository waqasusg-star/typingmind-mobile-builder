import Foundation

// DeepSeek Pulse — the in-app widget diagnostics.
//
// Answers the question the widget cannot answer about itself: where is the data, how old is it, is a
// refresh pending, and has the app ever been able to reach the API from this build. It is read-only
// and shows no key material - only whether a key exists.
extension WidgetStudioStatus {

    /// A short list of facts Widget Studio prints under the previews.
    static func lines(now: Date = Date()) -> [String] {
        var lines: [String] = []
        let ledger = WidgetRefreshLedger.read()
        let loaded = WidgetSnapshotStore.load(now: now)

        switch loaded.tier {
        case .appGroup?:
            lines.append("Snapshot tier: App Group (shared with the widget).")
        case .extensionLocal?:
            lines.append("Snapshot tier: extension-only copy. Sign both bundles with the same team so the App Group works.")
        case nil:
            lines.append("Snapshot tier: none readable yet.")
        }

        if let payload = loaded.envelope.payload {
            lines.append("Snapshot written " + ClockFormat.relative(payload.writtenAt, now: now) + ".")
            if let fetched = payload.balanceFetchedAt {
                lines.append("Balance fetched " + ClockFormat.relative(fetched, now: now) + ".")
            } else {
                lines.append("No balance in the snapshot yet.")
            }
        }

        if let requested = ledger.requestedAt {
            lines.append("Widget asked for a refresh " + ClockFormat.relative(requested, now: now) + ".")
        }
        if let answered = ledger.answeredAt {
            lines.append("Last answered request " + ClockFormat.relative(answered, now: now) + ".")
        }
        return lines
    }
}

/// Namespace placeholder kept so the extension above has a stable home.
enum WidgetStudioStatus {}
