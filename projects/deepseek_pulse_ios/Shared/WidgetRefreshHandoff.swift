import Foundation
import WidgetKit

// DeepSeek Pulse — the link a widget can use to make the extension write its own snapshot.
//
// A widget extension cannot be opened or messaged directly from the app. The one supported
// direction that exists is the widget's own URL: the app can ask WidgetKit to reload, and a
// user tap can reach the extension's `.widgetURL` handling through `onOpenURL` in the app.
//
// Because the App Group may be unavailable on this signing identity, the extension's timeline
// provider keeps a local copy (PulseWidgetLocalStore) and re-reads both tiers on every reload.
// This file holds the shared vocabulary for that handoff so the app and the widget cannot drift:
// it names the reload link and the reload reasons Widget Studio reports.

enum WidgetRefreshHandoff {

    /// Deep link that simply opens the app. Registered in the generated Info.plist.
    static var appLink: URL? { WidgetPolicy.deepLinkURL() }

    /// Amount of time Widget Studio waits before telling the user the widget may still be catching
    /// up. WidgetKit gives no callback, so this is a hint, not a guarantee.
    static let expectedRefreshDelay: TimeInterval = 3

    /// One line for Widget Studio describing what will actually happen after a write.
    static func summary(for result: WidgetBridge.WriteResult) -> String {
        switch result {
        case .written:
            return "Saved. iOS will redraw the widget soon; it normally redraws within a minute."
        case .stagedForExtension:
            return "Saved for the widget extension. Opening a Pulse widget lets it keep the copy."
        case .groupUnavailable:
            return "Not saved yet. Open a Pulse widget once; it starts from the built-in schedule."
        case .encodingFailed:
            return "Not saved: the snapshot could not be encoded."
        case .secretRejected:
            return "Not saved: the secret scan rejected the payload."
        case .ioFailure(let detail):
            return "Not saved: " + detail
        }
    }

    /// Requests a redraw without writing anything, used when settings change while the widget
    /// already holds a usable copy.
    static func requestRedraw() {
        WidgetCenter.shared.reloadTimelines(ofKind: "DeepSeekPulseWidget")
    }
}
