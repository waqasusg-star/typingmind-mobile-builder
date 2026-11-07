import Foundation
import WidgetKit

// DeepSeek Pulse — app-side widget bridge.
//
// Compiled into the app target only. Responsibilities:
//   1. build a sanitised, display-only snapshot from the app's existing stores
//   2. write it to the App Group container when that container exists
//   3. mirror it into the extension's own tier when the App Group is unavailable
//   4. ask WidgetKit to reload the timelines
//
// The API key is never copied here: SettingsStore reads it from the Keychain for network calls only.
//
// 1.0.7 fixes two reasons the widget said "No key" / "No API key saved":
//   * the payload never carried `appearance`, so the extension always drew the default theme and
//     design even after Widget Studio saved a choice;
//   * when the App Group container was missing, the app only reported groupUnavailable and wrote
//     nothing, so the extension kept its own stale seed with `hasAPIKey: false` forever.
// The bridge now carries the appearance, marks the key state as known, and writes the extension tier
// directly when the group container is not available.

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

        return WidgetSnapshotPayload.make(writtenAt: now,
                                          balanceFetchedAt: fetchedAt,
                                          balance: balance,
                                          schedule: store.schedule,
                                          models: rates,
                                          hasAPIKey: store.hasAPIKey,
                                          hasAPIKeyKnown: true,
                                          appearance: store.widgetAppearance.normalised())
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
                return "The App Group is unavailable, so the snapshot was written into the widget extension's own copy."
            case .groupUnavailable:
                return "The snapshot could not be written: no writable location was available."
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
    ///
    /// The App Group is tried first. Writing the group file additionally mirrors the payload into the
    /// extension's own tier, because a signer that grants the group to one bundle only would otherwise
    /// leave the widget reading a stale local copy. When the group is unavailable the local tier is
    /// written directly, which is what makes the balance and the theme reach the widget on builds that
    /// were signed without an App Group at all.
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

        let location = WidgetCacheLocation.shared
        if let fileURL = location.fileURL {
            do {
                try data.write(to: fileURL, options: [.atomic])
                // Keep the extension tier in step as well; a mismatch between the two is the state
                // that produced a widget showing older numbers than the app.
                WidgetSnapshotStore.write(payload: payload, to: .extensionLocal, location: location)
                return .written(fileURL)
            } catch {
                // Fall through to the extension tier rather than giving up.
                if WidgetSnapshotStore.write(payload: payload, to: .extensionLocal, location: location) != nil {
                    return .stagedForExtension
                }
                return .ioFailure(error.localizedDescription)
            }
        }

        if WidgetSnapshotStore.write(payload: payload, to: .extensionLocal, location: location) != nil {
            return .stagedForExtension
        }
        return .groupUnavailable
    }

    /// Writes the snapshot then asks iOS to refresh the widget. Timings are iOS-controlled.
    @discardableResult
    static func refresh(store: SettingsStore, now: Date = Date()) -> WriteResult {
        let result = write(store: store, now: now)
        if result.isWritten {
            reloadWidgets()
        }
        return result
    }

    /// Requests a timeline reload. Outside iOS 14+ WidgetKit this is a no-op.
    static func reloadWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: "DeepSeekPulseWidget")
    }
}
