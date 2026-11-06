import Foundation

// DeepSeek Pulse — shared widget snapshot types.
//
// Foundation only, compiled into BOTH targets: the app (Sources/ + Shared/) and the WidgetKit
// extension (WidgetSources/ + Shared/ + Sources/RequestPolicy.swift).
//
// It declares no type that already exists in Sources/RequestPolicy.swift. The API key never
// reaches this file: only display-safe values are encoded.

/// App Group shared by the app and the widget extension.
enum WidgetShared {
    /// Must match the App Group entitlement on both targets.
    static let appGroupIdentifier = "group.com.waqas.deepseekpulse"
    /// File written by the app, read by the extension.
    static let cacheFileName = "widget-snapshot.json"
    /// Current on-disk payload version. Bumping this makes older payloads unreadable by design.
    static let schemaVersion = 2
    /// Dates older than this are labelled as stale instead of being presented as current.
    static let staleAfter: TimeInterval = 60 * 60
    /// Extension bundle identifier, used for diagnostics and the setup state.
    static let extensionBundleIdentifier = "com.waqas.deepseekpulse.widgets"
}

/// Why the widget cannot show live numbers. Every case has a visible, honest string.
enum WidgetDataState: String, Codable, Equatable {
    case fresh
    case stale
    /// The App Group container is unavailable (entitlement missing on one or both targets).
    case groupUnavailable
    case empty
    case incompatible
    case corrupt

    var isUsable: Bool {
        self == .fresh || self == .stale
    }

    /// One short sentence a user can act on. Never contains fake values.
    var explainer: String {
        switch self {
        case .fresh:
            return "Balance from the DeepSeek Pulse app."
        case .stale:
            return "Showing the last balance the app saved. Open the app to refresh."
        case .groupUnavailable:
            return "Widget data access is unavailable. Open the app, then reinstall this build with the App Group enabled for both bundles."
        case .empty:
            return "No data yet. Open DeepSeek Pulse once to save your balance and schedule."
        case .incompatible:
            return "Saved widget data is from a different app version. Open the app to rewrite it."
        case .corrupt:
            return "Saved widget data could not be read. Open the app to rewrite it."
        }
    }

    var shortLabel: String {
        switch self {
        case .fresh: return "RECENT"
        case .stale: return "CACHED"
        case .groupUnavailable: return "SETUP"
        case .empty: return "NO DATA"
        case .incompatible: return "UPDATE"
        case .corrupt: return "UNREADABLE"
        }
    }
}

/// Display-only balance for the widget. Sanitised: no key, no token, no request headers.
struct WidgetBalance: Codable, Equatable {
    var currency: String
    /// Pre-formatted by the app, for example "$12.34"
    var totalText: String
    var grantedText: String
    var toppedUpText: String
    var isAvailable: Bool
}

/// One model rate as the widget needs it: display text only.
struct WidgetRate: Codable, Equatable {
    var name: String
    var label: String
    var offPeakDiscountPercent: Double
}

/// The complete, self-contained payload the extension needs to draw itself offline.
///
/// The schedule is embedded rather than shared by reference so the extension can compute state,
/// countdown and timeline boundaries with no app running and no network.
struct WidgetSnapshotPayload: Codable, Equatable {
    var schemaVersion: Int
    /// When the app wrote this payload.
    var writtenAt: Date
    /// When the balance numbers inside it were fetched. Nil when no balance is known.
    var balanceFetchedAt: Date?
    var balance: WidgetBalance?
    var schedule: PricingSchedule
    var models: [WidgetRate]
    var hasAPIKey: Bool
}

/// Decoded result handed to the timeline provider and the views.
struct WidgetSnapshotEnvelope: Equatable {
    var payload: WidgetSnapshotPayload?
    var state: WidgetDataState
    /// Seconds between the app write and "now"; 0 when unknown.
    var age: TimeInterval

    static func failed(_ state: WidgetDataState) -> WidgetSnapshotEnvelope {
        WidgetSnapshotEnvelope(payload: nil, state: state, age: 0)
    }

    var schedule: PricingSchedule? { payload?.schedule }
    var balance: WidgetBalance? { payload?.balance }
    var hasAPIKey: Bool { payload?.hasAPIKey ?? false }

    /// Balance line, or an explicit placeholder when there is nothing trustworthy to show.
    func balanceLine() -> String {
        if let balance = payload?.balance {
            return balance.totalText
        }
        if state == .fresh || state == .stale {
            return hasAPIKey ? "—" : "No key"
        }
        return "--"
    }

    /// Balance caption that never claims freshness the data does not have.
    func balanceCaption(now: Date) -> String {
        if state == .groupUnavailable || state == .empty || state == .corrupt || state == .incompatible {
            return state.explainer
        }
        guard let fetched = payload?.balanceFetchedAt else {
            return hasAPIKey ? "Balance not loaded yet" : "No API key saved"
        }
        let relative = ClockFormat.relative(fetched, now: now)
        if state == .stale {
            return "Last saved " + relative + " · open the app"
        }
        return "Updated " + relative
    }
}
