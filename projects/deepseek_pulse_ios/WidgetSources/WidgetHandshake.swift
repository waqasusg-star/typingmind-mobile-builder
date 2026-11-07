import Foundation
import WidgetKit

// DeepSeek Pulse — the extension side of the refresh handoff.
//
// The widget cannot read the Keychain and cannot open a socket, so it asks the containing app to do
// the work: it writes a request file, and the app answers it on launch or foreground. This file is
// extension-only (it touches WidgetKit for the timeline reload), while the rules and the file format
// stay in Shared/ so the Foundation harness can test them.

enum PulseWidgetHandshake {

    /// Writes the request the timeline provider left for the app. Diagnostics only: the provider already
    /// records requests, so this just guarantees one exists while the studio is open.
    @discardableResult
    static func requestRefresh(reason: WidgetRefreshReason, at date: Date = Date()) -> WidgetRefreshReason? {
        let request = WidgetRefreshRequest(requestedAt: date, reason: reason)
        guard WidgetRefreshStore.writeRequest(request) else { return nil }
        return request.typedReason
    }

    /// True when the app has answered since the widget last looked. The timeline provider uses it to
    /// ask WidgetKit for one new entry instead of waiting for the OS budget.
    static func answerIsNewerThan(requestedAt: Date?, answeredAt: Date?) -> Bool {
        guard let answeredAt = answeredAt else { return false }
        guard let requestedAt = requestedAt else { return true }
        return answeredAt >= requestedAt
    }

    /// Asks WidgetKit to rebuild the timeline soon after the app wrote a fresh snapshot. The system
    /// still decides when that actually happens.
    static func reloadTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: "DeepSeekPulseWidget")
    }
}
