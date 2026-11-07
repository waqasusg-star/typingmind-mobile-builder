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

    /// Deep link that simply opens the app. Registered in the generated Info.plist.
    static var appLink: URL? { WidgetPolicy.deepLinkURL() }

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
