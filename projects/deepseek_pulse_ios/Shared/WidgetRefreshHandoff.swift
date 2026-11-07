import Foundation
import WidgetKit

// DeepSeek Pulse — widget redraw vocabulary shared by the app and the extension.
//
// This file is compiled into BOTH targets, including the Foundation test harness that knows nothing
// about the app's UIKit classes. It therefore must not name any app-only type (WidgetBridge,
// SettingsStore, …): it takes a plain outcome value instead.

/// The outcome of an attempted snapshot write, independent of who performed it.
enum WidgetHandoffOutcome: Equatable {
    /// A shared file was written in the App Group container.
    case sharedFile
    /// The App Group container was absent, so the payload is left for the extension's own copy.
    case stagedForExtension
    /// Nothing writable existed.
    case nothingWritten
    case encodingFailed
    case secretRejected
}

enum WidgetRefreshHandoff {

    /// Deep link that opens the app straight on the dashboard.
    /// Assembled from WidgetPolicy's constants so the scheme cannot drift from Info.plist.
    static var appLink: URL? { WidgetPolicy.deepLinkURL() }

    /// Deep link that opens the app and asks it to refresh the balance immediately.
    /// Info.plist registers the `com.waqas.deepseekpulse` scheme, so this is the same URL plus a flag.
    static let refreshQueryItem = "refresh=1"
    static let refreshPath = "status"

    /// Widget tap target. The widget cannot run code on tap, so it opens the app with refresh=1 and
    /// the dashboard performs the balance request. Honest, and the only behaviour WidgetKit allows.
    static var refreshLink: URL? {
        URL(string: WidgetPolicy.widgetDeepLinkScheme + "://" + refreshPath + "?" + refreshQueryItem)
    }

    /// True when the app was opened by a widget tap that asked for a refresh.
    static func wantsRefresh(_ url: URL) -> Bool {
        guard WidgetPolicy.isWidgetDeepLink(url) else { return false }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return items.contains { $0.name == "refresh" && ($0.value ?? "1") == "1" }
    }

    /// How long Widget Studio waits before asking for a second redraw. WidgetKit gives no callback,
    /// so this is a hint, not a guarantee.
    static let expectedRefreshDelay: TimeInterval = 3

    /// One line for Widget Studio describing what will actually happen after a write.
    static func summary(for outcome: WidgetHandoffOutcome) -> String {
        switch outcome {
        case .sharedFile:
            return "Saved to the shared App Group. iOS will redraw the widget soon, normally within a minute."
        case .stagedForExtension:
            return "Saved for the widget extension: it keeps its own copy of the schedule and countdown."
        case .nothingWritten:
            return "Nothing written yet. Open a Pulse widget once; it starts from the built-in schedule."
        case .encodingFailed:
            return "Not saved: the snapshot could not be encoded."
        case .secretRejected:
            return "Not saved: the secret scan rejected the payload."
        }
    }

    /// Requests a redraw without writing anything.
    static func requestRedraw() {
        WidgetCenter.shared.reloadTimelines(ofKind: "DeepSeekPulseWidget")
    }
}
