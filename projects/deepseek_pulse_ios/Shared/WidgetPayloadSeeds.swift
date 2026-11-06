import Foundation

// DeepSeek Pulse — the payload the widget extension writes for itself.
//
// Foundation only, compiled into BOTH targets. It contains no secret and no account data:
// the extension has no way to reach the Keychain or the network, so this payload never carries a
// balance, a key flag or a fetch timestamp. It carries exactly what the widget can compute alone:
// the verified pricing schedule and the published rate labels.

extension WidgetSnapshotPayload {

    /// The schedule-only snapshot the extension can build with no help from the app.
    ///
    /// - Parameter now: the write stamp, so the timeline can label the age honestly.
    static func builtIn(now: Date = Date()) -> WidgetSnapshotPayload {
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
                                          hasAPIKey: false)
    }
}
