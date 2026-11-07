import Foundation

// DeepSeek Pulse — shared widget snapshot types.
//
// Foundation only, compiled into BOTH targets: the app (Sources/ + Shared/) and the WidgetKit
// extension (WidgetSources/ + Shared/ + Sources/RequestPolicy.swift).
//
// It declares no type that already exists in Sources/RequestPolicy.swift or in the other Shared
// Core files. The API key never reaches this file: only display-safe values are encoded.

/// App Group shared by the app and the widget extension.
enum WidgetShared {
    /// Must match the App Group entitlement on both targets.
    static let appGroupIdentifier = "group.com.waqas.deepseekpulse"
    /// File written by the app, read by the extension.
    static let cacheFileName = "widget-snapshot.json"
    /// The extension's own copy, used when the App Group container is unavailable.
    static let localCacheFileName = "pulse-widget-local.json"
    /// Current on-disk payload version. Bumping this makes older payloads unreadable by design.
    static let schemaVersion = 3
    /// Dates older than this are labelled as stale instead of being presented as current.
    static let staleAfter: TimeInterval = 60 * 60
    /// Extension bundle identifier, used for diagnostics and the setup state.
    static let extensionBundleIdentifier = "com.waqas.deepseekpulse.widgets"
}

/// Why the widget cannot show live numbers. Every case has a visible, honest string.
enum WidgetDataState: String, Codable, Equatable {
    case fresh
    case stale
    /// No storage tier could be opened at all (entitlement missing AND the local tier unusable).
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
            return "Showing the last balance the app saved. Tap the refresh icon to update."
        case .groupUnavailable:
            return "No saved snapshot yet. Open DeepSeek Pulse once; the widget saves its own copy from then on."
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
        case .fresh: return "UPDATED"
        case .stale: return "CACHED"
        case .groupUnavailable: return "FIRST RUN"
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
/// countdown and timeline boundaries with no app running and no network. `appearance` is optional
/// so a payload written by an older build still decodes.
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
    /// Theme, widget design and display switches chosen in Widget Studio.
    var appearance: WidgetAppearance?

    /// Builds a payload from raw pieces without touching the file system, so the same construction
    /// is reused by the app bridge and by widget-only fallback states. Never carries key material.
    static func make(schemaVersion: Int = WidgetShared.schemaVersion,
                     writtenAt: Date,
                     balanceFetchedAt: Date?,
                     balance: WidgetBalance?,
                     schedule: PricingSchedule,
                     models: [WidgetRate],
                     hasAPIKey: Bool,
                     appearance: WidgetAppearance? = nil) -> WidgetSnapshotPayload {
        WidgetSnapshotPayload(schemaVersion: schemaVersion,
                              writtenAt: writtenAt,
                              balanceFetchedAt: balanceFetchedAt,
                              balance: balance,
                              schedule: schedule,
                              models: models,
                              hasAPIKey: hasAPIKey,
                              appearance: appearance)
    }
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

    /// The saved appearance, or the default one. Never nil, so views always have a theme.
    var appearance: WidgetAppearance {
        (payload?.appearance ?? WidgetAppearance.defaultAppearance).normalised()
    }

    /// True when a real, available balance is known and should be shown.
    var hasUsableBalance: Bool {
        guard let balance = payload?.balance else { return false }
        return balance.isAvailable || !balance.totalText.isEmpty
    }

    /// The available balance, formatted by the app. "--" when there is nothing trustworthy.
    func balanceLine() -> String {
        if let balance = payload?.balance, !balance.totalText.isEmpty {
            return balance.totalText
        }
        if state == .fresh || state == .stale {
            return hasAPIKey ? "--" : "No key"
        }
        return "--"
    }

    /// Whether the API says the account can actually make calls right now.
    /// Nil means "unknown", so the widget must not claim either way.
    var availabilityText: String? {
        guard let balance = payload?.balance else { return nil }
        return balance.isAvailable ? "Available" : "Not available"
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
            return "Last saved " + relative + " - tap to refresh"
        }
        return "Updated " + relative
    }

    /// Short caption used by the compact designs.
    func shortBalanceCaption(now: Date) -> String {
        guard let fetched = payload?.balanceFetchedAt else {
            return hasAPIKey ? "Not loaded" : "No key"
        }
        return ClockFormat.relative(fetched, now: now)
    }
}
