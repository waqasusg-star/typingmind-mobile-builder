import Foundation

// DeepSeek Pulse — the payload the widget extension writes for itself.
//
// Foundation only, compiled into BOTH targets. It contains no secret and no account data:
// the extension has no way to reach the Keychain or the network, so this payload never carries a
// balance, a key value or a fetch timestamp. It carries exactly what the widget can compute alone:
// the verified pricing schedule, the published rate labels and the last appearance it was given.
//
// 1.0.7 changes the key flag. It used to be hard-coded `false`, so a seed the extension wrote before
// the app had ever saved a snapshot told the widget "No API key saved" forever, even though the app
// held a key in the Keychain. The seed now carries whatever the extension last knew: nil means
// unknown, and the shared wording layer refuses to claim a key is missing on unknown state.
extension WidgetSnapshotPayload {

    /// The schedule-only snapshot the extension can build with no help from the app.
    ///
    /// - Parameters:
    ///   - now: the write stamp, so the timeline can label the age honestly.
    ///   - appearance: the appearance already stored in the extension's own tier, if any. Passing it
    ///     keeps the user's chosen theme and design even before the app has written a snapshot.
    ///   - hasAPIKey: the key state the extension last saw. Nil (the default) means "unknown", which
    ///     is rendered as "Add key" only after the app has actually reported no key.
    static func builtIn(now: Date = Date(),
                        appearance: WidgetAppearance? = nil,
                        hasAPIKey: Bool? = nil) -> WidgetSnapshotPayload {
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
                                          hasAPIKey: hasAPIKey ?? false,
                                          hasAPIKeyKnown: hasAPIKey != nil,
                                          appearance: appearance ?? WidgetAppearance.defaultAppearance)
    }
}
