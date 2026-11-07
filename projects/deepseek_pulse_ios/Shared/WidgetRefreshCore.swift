import Foundation

// DeepSeek Pulse — the widget-to-app refresh handoff.
//
// Foundation only, compiled into BOTH targets, and executed by the widgetkit_v1 harness.
//
// Why this exists
// ---------------
// A widget extension cannot read the app's Keychain item and cannot make a network request, so it can
// never fetch a balance. In 1.0.8 the widget therefore printed "No key" / "No API key saved"
// whenever its snapshot had no balance, even on a phone where the app held a valid key and had simply
// not been opened since the last timeline refresh. That message was wrong and unactionable.
//
// The rules implemented here:
//   1. A widget never claims the key is missing. The absence of a balance means "open the app", not
//      "you have no key" - the widget has no way to know the difference.
//   2. The widget writes a small request file into the shared container when it needs fresh numbers.
//   3. The app consumes that request on launch and on foreground, refreshes once, then answers it.
//      The answer is stamped so the widget does not re-ask in a loop.
//
// Nothing secret is written: the request is a timestamp plus a reason code.

enum WidgetRefreshReason: String, Codable, Equatable {
    /// The widget had no balance at all.
    case missingBalance
    /// The widget held a balance but it was older than the stale threshold.
    case staleBalance
    /// The key state was never reported by the app.
    case unknownKey
}

struct WidgetRefreshRequest: Codable, Equatable {
    /// Schema of this small file, independent of the snapshot schema.
    static let schema = 1
    var schemaVersion: Int
    var requestedAt: Date
    var reason: String

    init(requestedAt: Date, reason: WidgetRefreshReason) {
        self.schemaVersion = WidgetRefreshRequest.schema
        self.requestedAt = requestedAt
        self.reason = reason.rawValue
    }

    var typedReason: WidgetRefreshReason {
        WidgetRefreshReason(rawValue: reason) ?? .missingBalance
    }
}

/// The rule layer. Pure functions, so the tests exercise exactly the policy the extension and the app
/// use at runtime.
enum WidgetRefreshHandshakeRules {

    /// File name inside the App Group container.
    static let fileName = "widget-refresh-request.json"

    /// Minimum gap between two requests the widget is allowed to write.
    static let minimumInterval: TimeInterval = 90

    /// Whether the widget should ask the app to refresh now.
    ///
    /// - Parameters:
    ///   - state: the snapshot state the widget just decoded.
    ///   - hasBalance: whether a displayable balance exists.
    ///   - lastRequestAt: when the widget last wrote a request, if ever.
    ///   - lastAnswerAt: when the app last answered a request.
    ///   - now: the current instant.
    static func shouldRequest(state: WidgetDataState,
                              hasBalance: Bool,
                              lastRequestAt: Date?,
                              lastAnswerAt: Date?,
                              now: Date) -> Bool {
        // A snapshot the app has not written yet is worth one request; a corrupt or incompatible one
        // is the app's job to rewrite, and it will do that on its next launch anyway.
        if state == .corrupt || state == .incompatible { return false }

        if hasBalance && state == .fresh { return false }

        // Do not spam: honour the cooldown against both the last request and the last answer.
        let reference = [lastRequestAt, lastAnswerAt].compactMap { $0 }.max()
        if let reference = reference, now.timeIntervalSince(reference) < minimumInterval {
            return false
        }
        return true
    }

    /// Why the widget is asking, so the app can log it in the session and the tests can assert it.
    static func reason(state: WidgetDataState, hasBalance: Bool) -> WidgetRefreshReason {
        if hasBalance && state == .stale { return .staleBalance }
        return .missingBalance
    }

    /// The text the widget shows in place of a balance when it has none.
    ///
    /// Never "No key": the extension cannot prove that, and on a phone with a stored key it was a
    /// lie. It points at the action that actually fixes it.
    static func noBalanceTitle(hasAPIKeyKnown: Bool, hasAPIKey: Bool) -> String {
        if hasAPIKeyKnown && !hasAPIKey { return "Add key in app" }
        return "Open app"
    }

    /// The caption under that slot.
    static func noBalanceCaption(hasAPIKeyKnown: Bool, hasAPIKey: Bool) -> String {
        if hasAPIKeyKnown && !hasAPIKey {
            return "Tap to add your DeepSeek API key"
        }
        return "Tap to load your balance"
    }

    /// True when the request file is old enough that the app should ignore it rather than act on a
    /// stale tap from hours ago.
    static func isExpired(_ request: WidgetRefreshRequest, now: Date) -> Bool {
        now.timeIntervalSince(request.requestedAt) > 60 * 60 * 6
    }
}
