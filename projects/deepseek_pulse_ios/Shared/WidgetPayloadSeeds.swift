import Foundation

// DeepSeek Pulse — the payload the widget extension writes for itself.
//
// Foundation only, compiled into BOTH targets. It contains no secret and no account data:
// the extension has no way to reach the Keychain or the network, so this payload never carries a
// balance, a key flag or a fetch timestamp. It carries exactly what the widget can compute alone:
// the verified pricing schedule, the published rate labels and the last appearance it was given.

extension WidgetSnapshotPayload {

    /// The schedule-only snapshot the extension can build with no help from the app.
    ///
    /// - Parameters:
    ///   - now: the write stamp, so the timeline can label the age honestly.
    ///   - appearance: the appearance already stored in the extension's own tier, if any. Passing it
    ///     keeps the user's chosen theme and design even before the app has written a snapshot.
    static func builtIn(now: Date = Date(),
                        appearance: WidgetAppearance? = nil) -> WidgetSnapshotPayload {
        let rates = RateSeeds.models.map { model in
            WidgetRate(name: WidgetCacheCodec.safe(model.name),
                       label: WidgetCacheCodec.safe(model.label),
                       offPeakDiscountPercent: model.clampedDiscount)
        }
        return WidgetSnapshotPayload.make(writtenAt: now,
                                          balanceFetchedAt: nil,
                                          balance: nil,
                                          schedule: RateSeeds.schedule,
                                          models: rates,
                                          hasAPIKey: false,
                                          appearance: appearance ?? WidgetAppearance.defaultAppearance)
    }
}
