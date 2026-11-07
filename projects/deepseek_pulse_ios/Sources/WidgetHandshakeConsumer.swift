import Foundation
import WidgetKit

// DeepSeek Pulse — the app side of the widget refresh handoff.
//
// Called on launch and on every return to the foreground. It answers a request the widget left in the
// App Group container by writing a fresh snapshot and telling WidgetKit to reload. This is the piece
// that turns the widget's "Open app" tap into an actual balance load, instead of the widget sitting on
// "No key" forever.
//
// Guard rails:
//   * a request older than six hours is ignored, so a tap from this morning cannot trigger a surprise
//     network call;
//   * at most one consume per launch/foreground pass, so the handshake cannot loop;
//   * the widget's answer file carries only timestamps and a counter - no account data, no key.

enum WidgetHandshakeConsumer {

    /// Reads any pending widget request.
    ///
    /// - Returns: the reason code when a usable request is waiting, otherwise nil.
    static func pendingReason(now: Date = Date()) -> WidgetRefreshReason? {
        guard let data = WidgetRefreshStore.read(.request),
              let request = WidgetRefreshStore.decodeRequest(data) else { return nil }
        guard !WidgetRefreshHandshakeRules.isExpired(request, now: now) else {
            WidgetRefreshStore.clearRequest()
            return nil
        }
        return request.typedReason
    }

    /// Removes the pending request and records the answer. Safe to call when no request exists.
    ///
    /// - Parameter count: how many requests this installation has answered, so the widget can tell
    ///   two answers apart even within the same second. The caller passes the previous value plus one.
    @discardableResult
    static func completeRequest(previousCount: Int, now: Date = Date()) -> Bool {
        WidgetRefreshStore.clearRequest()
        let answer = WidgetRefreshAnswer(answeredAt: now, answeredCount: previousCount + 1)
        return WidgetRefreshStore.writeAnswer(answer)
    }

    /// The last answer the app wrote, used to keep the counter monotonic.
    static func lastAnswer() -> WidgetRefreshAnswer? {
        guard let data = WidgetRefreshStore.read(.answer) else { return nil }
        return WidgetRefreshStore.decodeAnswer(data)
    }
}
