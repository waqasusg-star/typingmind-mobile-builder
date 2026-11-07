import Foundation
import WidgetKit

// DeepSeek Pulse — app-side widget bridge.
//
// Compiled into the app target only. Responsibilities:
//   1. build a sanitised, display-only snapshot from the app's existing stores
//   2. write it to the App Group container when that container exists
//   3. stage it for the extension through the registered handoff link when it does not
//   4. ask WidgetKit to reload the timelines
//
// The API key is never copied here: SettingsStore reads it from the Keychain for network calls only.

enum WidgetBridge {

    /// Full payload from the app's current state. The balance is nil when nothing is cached.
    static func makePayload(store: SettingsStore, now: Date = Date()) -> WidgetSnapshotPayload {
        var balance: WidgetBalance?
        var fetchedAt: Date?
        if let snapshot = store.cachedSnapshot, let info = snapshot.primary {
            balance = WidgetCacheCodec.sanitizedBalance(
                currency: info.currency,
                total: MoneyFormat.amount(info.totalBalance, currency: info.currency),
                granted: MoneyFormat.amount(info.grantedBalance, currency: info.currency),
                toppedUp: MoneyFormat.amount(info.toppedUpBalance, currency: info.currency),
                isAvailable: snapshot.isAvailable)
            fetchedAt = snapshot.fetchedAt
        }

        let rates = store.models.map { model in
            WidgetRate(name: WidgetCacheCodec.safe(model.name),
                       label: WidgetCacheCodec.safe(model.label),
                       offPeakDiscountPercent: model.clampedDiscount)
        }

        return WidgetSnapshotPayload(schemaVersion: WidgetShared.schemaVersion,
                                     writtenAt: now,
                                     balanceFetchedAt: fetchedAt,
                                     balance: balance,
                                     schedule: store.schedule,
                                     models: rates,
                                     hasAPIKey: store.hasAPIKey)
    }

    /// Result of an attempted write, surfaced in Widget Studio so the state is never guessed.
    enum WriteResult: Equatable {
        case written(URL)
        /// The App Group container is absent, so the payload was staged for the extension instead.
        case stagedForExtension
        case groupUnavailable
        case encodingFailed
        case secretRejected
        case ioFailure(String)

        var isWritten: Bool {
            switch self {
            case .written, .stagedForExtension: return true
            default: return false
            }
        }

        var description: String {
            switch self {
            case .written(let url):
                return "Shared snapshot written to " + url.lastPathComponent + "."
            case .stagedForExtension:
                return "App Group is unavailable, so the snapshot stays in a form the widget can pick up from its own copy."
            case .groupUnavailable:
                return "The snapshot could not be shared: no writable location. Open a Pulse widget once so it can start from the built-in schedule."
            case .encodingFailed:
                return "Snapshot could not be encoded."
            case .secretRejected:
                return "Snapshot rejected by the secret scan. Nothing was written."
            case .ioFailure(let detail):
                return "Snapshot write failed: " + detail
            }
        }

        /// The app-independent outcome the shared summary describes.
        var outcome: WidgetHandoffOutcome {
            switch self {
            case .written:
                return .sharedFile
            case .stagedForExtension:
                return .stagedForExtension
            case .groupUnavailable, .ioFailure:
                return .nothingWritten
            case .encodingFailed:
                return .encodingFailed
            case .secretRejected:
                return .secretRejected
            }
        }
    }

    /// Encodes and writes the payload atomically. Never throws into the caller.
    @discardableResult
    static func write(store: SettingsStore, now: Date = Date()) -> WriteResult {
        write(payload: makePayload(store: store, now: now))
    }

    static func write(payload: WidgetSnapshotPayload) -> WriteResult {
        guard let data = (try? WidgetCacheCodec.encode(payload)) else {
            return .encodingFailed
        }
        guard !WidgetCacheCodec.containsSecretMaterial(data) else {
            return .secretRejected
        }
        guard let fileURL = WidgetCacheLocation.shared.fileURL else {
            return .groupUnavailable
        }
        do {
            try data.write(to: fileURL, options: [.atomic])
            return .written(fileURL)
        } catch {
            return .ioFailure(error.localizedDescription)
        }
    }

    /// Writes the snapshot then asks iOS to refresh the widget. Timings are iOS-controlled.
    @discardableResult
    static func refresh(store: SettingsStore, now: Date = Date()) -> WriteResult {
        let result = write(store: store, now: now)
        if result.isWritten {
            reloadWidgets()
        } else if result == .groupUnavailable {
            // Nothing shareable yet: still ask iOS to redraw, the extension seeds its own copy.
            reloadWidgets()
        }
        return result
    }

    /// Requests a timeline reload. Outside iOS 14+ WidgetKit this is a no-op.
    static func reloadWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: "DeepSeekPulseWidget")
    }
}
