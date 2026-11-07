import Foundation

// DeepSeek Pulse — executed Foundation checks for the shared widget cache, planner and policy.
//
// Compiled by the widgetkit_v1 profile as its own harness together with ALL Shared/*.swift and
// Sources/RequestPolicy.swift. Foundation only: no WidgetKit, no UIKit, no network, no writes.

enum WidgetKitCheckFailure: Error {
    case failed(String)
}

func widgetKitChecks() throws {
    var checked = 0
    // 1.0.8: a failing check records its label and execution continues, so ONE CI run reports every
    // stale assertion instead of only the first. The function still throws before it prints success,
    // so a failure remains a real non-zero exit. Unexpected encoding/setup throws are not caught here.
    var failures: [String] = []
    func expect(_ condition: Bool, _ label: String) throws {
        checked += 1
        if !condition { failures.append(label) }
    }

    func utc(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: text) ?? Date(timeIntervalSince1970: 0)
    }

    let now = utc("2026-11-10T00:30:00")
    let schedule = RateSeeds.schedule

    // MARK: Payload round trip

    let fetchedAt = now.addingTimeInterval(-120)
    let payload = WidgetSnapshotPayload(
        schemaVersion: WidgetShared.schemaVersion,
        writtenAt: now,
        balanceFetchedAt: fetchedAt,
        balance: WidgetCacheCodec.sanitizedBalance(currency: "usd",
                                                   total: "$12.34",
                                                   granted: "$2.00",
                                                   toppedUp: "$10.34",
                                                   isAvailable: true),
        schedule: schedule,
        models: [WidgetRate(name: "deepseek-flash", label: "V4.1-Flash-1017", offPeakDiscountPercent: 50)],
        hasAPIKey: true)

    let data = try WidgetCacheCodec.encode(payload)
    try expect(!data.isEmpty, "payload encodes to bytes")

    let decoded = WidgetCacheCodec.decode(data, now: now)
    try expect(decoded.state == .fresh, "a fresh payload decodes as fresh")
    try expect(decoded.payload == payload, "round trip is lossless")
    try expect(decoded.balanceLine() == "$12.34", "balance line comes from the sanitised payload")
    try expect(decoded.hasAPIKey, "hasAPIKey survives the round trip as a boolean only")

    // MARK: Secret material

    try expect(!WidgetCacheCodec.containsSecretMaterial(data), "a normal payload contains no secret fragments")
    var leaky = payload
    leaky.models = [WidgetRate(name: "sk-abc123", label: "", offPeakDiscountPercent: 0)]
    let leakyData = try WidgetCacheCodec.encode(leaky)
    try expect(WidgetCacheCodec.containsSecretMaterial(leakyData), "an sk- prefixed value is rejected by the scan")

    let tokenPayload = WidgetSnapshotPayload(schemaVersion: WidgetShared.schemaVersion,
                                            writtenAt: now, balanceFetchedAt: nil, balance: nil,
                                            schedule: schedule, models: [], hasAPIKey: true)
    let tokenData = try WidgetCacheCodec.encode(tokenPayload)
    try expect(!WidgetCacheCodec.containsSecretMaterial(tokenData), "hasAPIKey boolean is not serialised as a token field")

    // MARK: Schema handling

    var newer = payload
    newer.schemaVersion = WidgetShared.schemaVersion + 1
    let newerData = try WidgetCacheCodec.encode(newer)
    try expect(WidgetCacheCodec.decode(newerData, now: now).state == .incompatible, "a newer schema is reported as incompatible")
    try expect(WidgetCacheCodec.decode(newerData, now: now).payload == nil, "an incompatible payload is not half-read")

    var older = payload
    older.schemaVersion = WidgetShared.schemaVersion - 1
    let olderData = try WidgetCacheCodec.encode(older)
    try expect(WidgetCacheCodec.decode(olderData, now: now).state == .incompatible, "an older schema is reported as incompatible")

    // MARK: Corruption and emptiness

    try expect(WidgetCacheCodec.decode(Data(), now: now).state == .empty, "zero bytes is the empty state")
    try expect(WidgetCacheCodec.decode(Data("{".utf8), now: now).state == .corrupt, "truncated JSON is corrupt")
    try expect(WidgetCacheCodec.decode(Data("not json at all".utf8), now: now).state == .corrupt, "non-JSON is corrupt")
    // A body that states the CURRENT version but carries nothing else must be corrupt, not
    // fabricated. The literal is built from the real constant: hard-coding a stale number here turned
    // this into a version-mismatch probe, which the codec correctly reports as .incompatible.
    let versionOnly = Data(("{\"schemaVersion\":" + String(WidgetShared.schemaVersion) + "}").utf8)
    try expect(WidgetCacheCodec.decode(versionOnly, now: now).state == .corrupt, "a version-only body is corrupt, not fabricated")
    try expect(WidgetCacheCodec.decode(versionOnly, now: now).payload == nil, "a corrupt body yields no payload")
    // And the separate rule it accidentally exercised: any other version is incompatible, not corrupt.
    let otherVersion = Data(("{\"schemaVersion\":" + String(WidgetShared.schemaVersion - 2) + "}").utf8)
    try expect(WidgetCacheCodec.decode(otherVersion, now: now).state == .incompatible, "a version-only body for another schema is incompatible")
    try expect(WidgetCacheCodec.decode(Data("{".utf8), now: now).balanceLine() == "--", "corrupt data shows no fake balance")

    // MARK: Staleness threshold, measured from balanceFetchedAt

    let exactlyAtLimit = WidgetCacheCodec.decode(data, now: fetchedAt.addingTimeInterval(WidgetShared.staleAfter))
    try expect(exactlyAtLimit.state == .fresh, "exactly at the threshold is still fresh (codec uses >)")
    let onePastLimit = WidgetCacheCodec.decode(data, now: fetchedAt.addingTimeInterval(WidgetShared.staleAfter + 1))
    try expect(onePastLimit.state == .stale, "one second past the threshold is stale")
    try expect(onePastLimit.balanceCaption(now: fetchedAt.addingTimeInterval(7200)).contains("open the app"), "stale caption tells the user to open the app")

    let noBalancePayload = WidgetSnapshotPayload(schemaVersion: WidgetShared.schemaVersion,
                                                writtenAt: now, balanceFetchedAt: nil, balance: nil,
                                                schedule: schedule, models: [], hasAPIKey: false)
    let noBalanceData = try WidgetCacheCodec.encode(noBalancePayload)
    let noBalance = WidgetCacheCodec.decode(noBalanceData, now: now)
    try expect(noBalance.state == .fresh, "a payload without a balance is still fresh (age uses writtenAt)")
    try expect(noBalance.balanceLine() == "--", "a payload with no balance shows the placeholder, not an invented amount")
    try expect(noBalance.hasUsableBalance == false, "no balance is not a usable balance")
    // Two honest branches, both asserted: a keyless payload must not promise a balance that opening
    // the app cannot produce; a key-present payload must point the user at the app.
    try expect(noBalance.balanceCaption(now: now) == "Saved schedule only - no account data yet", "a keyless payload says only the schedule is saved")
    try expect(!noBalance.balanceCaption(now: now).lowercased().contains("open the app"), "a keyless payload does not point at the app for a balance")

    let keyedNoBalancePayload = WidgetSnapshotPayload(schemaVersion: WidgetShared.schemaVersion,
                                                     writtenAt: now, balanceFetchedAt: nil, balance: nil,
                                                     schedule: schedule, models: [], hasAPIKey: true,
                                                     hasAPIKeyKnown: true)
    let keyedNoBalance = WidgetCacheCodec.decode(try WidgetCacheCodec.encode(keyedNoBalancePayload), now: now)
    try expect(keyedNoBalance.balanceCaption(now: now).contains("open the app"), "a key-present payload asks the user to open the app to load the balance")
    try expect(keyedNoBalance.balanceCaption(now: now) != "Updated", "no freshness claim without a fetch time")

    // MARK: Sanitisation

    try expect(WidgetCacheCodec.safe("  $1.00  ") == "$1.00", "trimming")
    try expect(WidgetCacheCodec.safe(String(repeating: "x", count: 100)).count == 40, "length clamp")
    let injected = WidgetCacheCodec.sanitizedBalance(currency: "USD\n", total: "1.00\u{0007}", granted: "", toppedUp: "", isAvailable: true)
    try expect(injected.currency == "USD", "currency has no control characters")
    try expect(injected.totalText == "1.00", "control characters are stripped from amounts")

    // MARK: Honest state labels

    try expect(WidgetDataState.groupUnavailable.isUsable == false, "group unavailable is not usable")
    try expect(WidgetDataState.groupUnavailable.explainer.contains("Open DeepSeek Pulse"), "group state tells the user to open the app, not to reinstall")
    try expect(WidgetSnapshotEnvelope.failed(.groupUnavailable).balanceLine() == "--", "unavailable shows a placeholder")
    try expect(WidgetDataState.fresh.shortLabel == "UPDATED", "fresh badge says UPDATED, not LIVE")
    try expect(WidgetDataState.stale.shortLabel == "CACHED", "stale badge says CACHED")
    try expect(WidgetDataState.empty.shortLabel == "NO DATA", "empty badge")
    try expect(WidgetDataState.incompatible.shortLabel == "UPDATE", "incompatible badge")
    try expect(WidgetDataState.corrupt.shortLabel == "UNREADABLE", "corrupt badge")

    // MARK: Storage tiers — the widget's own copy keeps it live without an App Group

    try expect(WidgetCacheTier.appGroup.rawValue == "appGroup", "the group tier is named appGroup")
    try expect(WidgetCacheTier.extensionLocal.rawValue == "extensionLocal", "the local tier is named extensionLocal")
    try expect(WidgetSnapshotStore.tiers == [.appGroup, .extensionLocal], "the group tier is preferred, local is the fallback")
    try expect(WidgetShared.localCacheFileName != WidgetShared.cacheFileName, "the two tiers use different file names")

    // An empty location with no App Group container must not make the widget look broken forever.
    let emptyLocation = WidgetCacheLocation(appGroupIdentifier: "group.com.waqas.deepseekpulse.tests.absent")
    let emptyLoad = WidgetSnapshotStore.load(location: emptyLocation, now: now)
    try expect(!emptyLoad.envelope.state.isUsable, "a missing container yields no fake data")
    try expect(emptyLoad.tier == nil, "no tier is reported when nothing decodes")

    // The built-in schedule payload is what the extension writes when the app never did.
    let seeded = WidgetSnapshotPayload.builtIn(now: now)
    try expect(seeded.schemaVersion == WidgetShared.schemaVersion, "the built-in payload uses the current schema")
    try expect(seeded.balance == nil, "the built-in payload carries no balance")
    try expect(seeded.balanceFetchedAt == nil, "the built-in payload carries no fetch time")
    try expect(seeded.hasAPIKey == false, "the built-in payload never claims an API key")
    // 1.0.8: the seed reports the key state as UNKNOWN, not as a positive "no key", unless the
    // caller passes what the extension last knew. Only a known-absent key may say "Add API key".
    try expect(seeded.hasAPIKeyKnown == false, "the built-in payload reports the key state as unknown")
    try expect(PulseBalanceWording.slot(hasBalance: false, hasAPIKey: seeded.hasAPIKey) == "Add API key", "the slot text itself is unchanged")
    let knownNoKey = WidgetSnapshotPayload.builtIn(now: now, appearance: nil, hasAPIKey: false, hasAPIKeyKnown: true)
    try expect(knownNoKey.hasAPIKeyKnown == true, "a carried-over known state survives a reseed")
    try expect(WidgetCacheCodec.envelope(for: knownNoKey, now: now).hasAPIKeyKnown, "the known state round-trips through the envelope")
    let unknownKey = WidgetSnapshotPayload.builtIn(now: now, appearance: nil)
    try expect(!WidgetCacheCodec.envelope(for: unknownKey, now: now).hasAPIKeyKnown, "an unknown state stays unknown through the envelope")
    try expect(seeded.schedule == RateSeeds.schedule, "the built-in payload carries the verified schedule")
    try expect(!seeded.models.isEmpty, "the built-in payload carries the rate labels")
    let seededEnvelope = WidgetCacheCodec.envelope(for: seeded, now: now)
    try expect(seededEnvelope.state == .fresh, "the built-in payload decodes as fresh")
    try expect(seededEnvelope.balanceLine() == "--", "a schedule-only seed shows a placeholder instead of a fake balance")
    try expect(seededEnvelope.hasUsableBalance == false, "the built-in payload has no usable balance")
    try expect(seeded.balance == nil, "the built-in payload invents no account data")
    // The honest wording layer decides the words: an unknown key state must never claim a key is
    // missing, and a known-absent key must offer the next action.
    try expect(PulseBalanceWording.slot(hasBalance: false, hasAPIKey: false) == "Add API key", "a known-absent key asks the user to add one")
    try expect(PulseBalanceWording.slot(hasBalance: true, hasAPIKey: false) == "", "a real balance always wins over the key wording")

    // MARK: Live countdown caption

    let prePeak = WidgetPlanner.snapshot(schedule: schedule, at: utc("2026-11-10T00:30:00"))
    try expect(WidgetPlanner.countdownCaption(snapshot: prePeak, discountsEnabled: true) == "Peak in", "before a peak start the caption says Peak in")
    let preOffPeak = WidgetPlanner.snapshot(schedule: schedule, at: utc("2026-11-10T02:00:00"))
    try expect(WidgetPlanner.countdownCaption(snapshot: preOffPeak, discountsEnabled: true) == "Off-peak in", "inside a peak window the caption says Off-peak in")
    try expect(WidgetPlanner.countdownCaption(snapshot: prePeak, discountsEnabled: false) == "", "with discounts off there is no countdown caption")
    // The caption and the footnote must describe the same switch, or the widget contradicts itself.
    try expect(WidgetPlanner.switchCaption(snapshot: prePeak) == "Peak starts", "the footnote names the same switch as the caption")
    try expect(prePeak.nextSwitchAt == utc("2026-11-10T01:00:00"), "the countdown targets the real next transition")
    try expect(WidgetPlanner.secondsUntil(now: utc("2026-11-10T00:30:00"), target: utc("2026-11-10T01:00:00")) == 1800, "countdown seconds to the switch")
    try expect(WidgetPolicy.deepLinkURL() != nil, "the widget has a tappable link")

    // MARK: Calendar and pricing boundaries

    let inWindow = WidgetPlanner.snapshot(schedule: schedule, at: utc("2026-11-10T02:00:00"))
    try expect(inWindow.state == .peak, "02:00 UTC on a working Tuesday is peak")
    try expect(WidgetPlanner.snapshot(schedule: schedule, at: utc("2026-11-10T01:00:00")).state == .peak, "the peak start is inclusive")
    try expect(WidgetPlanner.snapshot(schedule: schedule, at: utc("2026-11-10T04:00:00")).state == .offPeak, "the peak end is exclusive")
    try expect(WidgetPlanner.snapshot(schedule: schedule, at: utc("2026-10-01T02:00:00")).state == .offPeak, "a listed PRC holiday is off-peak")
    try expect(WidgetPlanner.snapshot(schedule: schedule, at: utc("2026-11-14T02:00:00")).state == .offPeak, "a Saturday is off-peak inside the clock window")
    let unverifiedYear = WidgetPlanner.snapshot(schedule: schedule, at: utc("2028-03-06T02:00:00"))
    try expect(unverifiedYear.uncertain, "an uncovered year is flagged unverified")
    try expect(WidgetPlanner.footnote(snapshot: unverifiedYear, discountsEnabled: true, timeZone: TimeZone(secondsFromGMT: 0)!).contains("unverified"), "the footnote admits the unverified calendar")

    var standardSchedule = schedule
    standardSchedule.discountsEnabled = false
    try expect(standardSchedule.state(at: utc("2026-11-10T02:00:00")) == .standard, "discounts off means STANDARD around the clock")
    try expect(standardSchedule.nextTransition(after: now) == nil, "no transition exists when discounts are off")

    // MARK: Deep link uses the scheme registered in Info.plist

    try expect(WidgetPolicy.deepLink == "com.waqas.deepseekpulse://status", "deep link uses the registered scheme")
    try expect(WidgetPolicy.deepLinkURL()?.absoluteString == "com.waqas.deepseekpulse://status", "deep link URL string")
    if let link = WidgetPolicy.deepLinkURL() {
        try expect(WidgetPolicy.isWidgetDeepLink(link), "the app's own deep link is recognised")
    }
    if let legacy = URL(string: "deepseekpulse://status") {
        try expect(!WidgetPolicy.isWidgetDeepLink(legacy), "the unregistered legacy scheme is rejected")
    }
    if let other = URL(string: "https://example.com/status") {
        try expect(!WidgetPolicy.isWidgetDeepLink(other), "other schemes are rejected")
    }

    // MARK: Timeline planner on the real schedule

    let planStart = utc("2026-11-10T00:30:00")
    let planFetched = planStart.addingTimeInterval(-120)
    let plan = WidgetTimelinePlanner.boundaries(now: planStart,
                                               schedule: schedule,
                                               dataFetchedAt: planFetched)
    try expect(!plan.isEmpty, "the planner produces at least one entry")
    try expect(plan.first?.reason == .now, "the first boundary is now")
    try expect(plan.count <= WidgetTimelinePlanner.maximumEntries, "the plan respects the entry cap")
    try expect(plan == plan.sorted(by: { $0.date < $1.date }), "boundaries are ordered")

    // A trading day has FOUR transitions. Planning only the first left the widget showing PEAK
    // after 04:00, because a later midnight entry does not ask iOS for a reload.
    let switchDates = plan.filter { $0.reason == .peakSwitch }.map { $0.date }
    try expect(switchDates.count == 4, "all four transitions of the trading day are planned")
    try expect(switchDates.contains(utc("2026-11-10T01:00:00")), "01:00 UTC peak start planned")
    try expect(switchDates.contains(utc("2026-11-10T04:00:00")), "04:00 UTC peak end planned")
    try expect(switchDates.contains(utc("2026-11-10T06:00:00")), "06:00 UTC peak start planned")
    try expect(switchDates.contains(utc("2026-11-10T10:00:00")), "10:00 UTC peak end planned")

    // Each planned instant reports the state that actually begins there.
    func state(after date: Date) -> PricingState { schedule.state(at: date.addingTimeInterval(60)) }
    func state(before date: Date) -> PricingState { schedule.state(at: date.addingTimeInterval(-60)) }
    try expect(state(before: utc("2026-11-10T01:00:00")) == .offPeak, "off-peak before 01:00")
    try expect(state(after: utc("2026-11-10T01:00:00")) == .peak, "peak after 01:00")
    try expect(state(after: utc("2026-11-10T04:00:00")) == .offPeak, "off-peak after 04:00")
    try expect(state(after: utc("2026-11-10T06:00:00")) == .peak, "peak after 06:00")
    try expect(state(after: utc("2026-11-10T10:00:00")) == .offPeak, "off-peak after 10:00")

    // The reload request is bounded by the policy maximum, and it is a request, not a promise.
    let reload = WidgetTimelinePlanner.reloadDate(now: planStart)
    try expect(reload <= planStart.addingTimeInterval(WidgetPolicy.maximumRefreshInterval), "reloadDate is within the policy maximum")
    try expect(reload > planStart, "reloadDate is in the future")

    // Horizon bound: nothing may sit further away than one day.
    let horizonLimit = planStart.addingTimeInterval(WidgetTimelinePlanner.horizon)
    try expect(plan.allSatisfy { $0.date <= horizonLimit }, "no entry is beyond the planning horizon")

    // MARK: Integration — the planned cache-stale entry really decodes as stale

    let staleMarks = plan.filter { $0.reason == .cacheStale }
    try expect(staleMarks.count == 1, "the cache-stale crossing is planned exactly once")
    if let mark = staleMarks.first {
        // Just before the mark the SAME bytes must still be fresh.
        let justBefore = mark.date.addingTimeInterval(-1)
        try expect(WidgetCacheCodec.decode(data, now: justBefore).state == .fresh, "an instant before the stale mark still decodes fresh")
        // At the mark they must be stale — this is what the old +0 crossing got wrong.
        try expect(WidgetCacheCodec.decode(data, now: mark.date).state == .stale, "the planned stale entry actually decodes as stale")
        try expect(mark.date > fetchedAt.addingTimeInterval(WidgetShared.staleAfter), "the stale mark is strictly past the codec threshold")
    }

    // MARK: Long holiday run — no transitions, still bounded and still honest

    let holidayPlan = WidgetTimelinePlanner.boundaries(now: utc("2026-10-02T12:00:00"),
                                                       schedule: schedule,
                                                       dataFetchedAt: utc("2026-10-02T11:00:00"))
    try expect(holidayPlan.first?.reason == .now, "a holiday plan starts at now")
    try expect(holidayPlan.count <= WidgetTimelinePlanner.maximumEntries, "a holiday plan is bounded")
    try expect(holidayPlan.contains { $0.reason == .utcMidnight }, "a holiday plan still includes UTC midnight")
    try expect(WidgetPlanner.snapshot(schedule: schedule, at: utc("2026-10-02T12:00:00")).state == .offPeak, "a holiday midday is off-peak")

    // MARK: Every UTC midnight inside the horizon is included

    let nearMidnight = WidgetTimelinePlanner.boundaries(now: utc("2026-11-10T23:50:00"),
                                                       schedule: schedule,
                                                       dataFetchedAt: nil)
    let midnights = nearMidnight.filter { $0.reason == .utcMidnight }
    try expect(!midnights.isEmpty, "a midnight boundary is included near the end of the day")
    if let midnight = midnights.first {
        try expect(midnight.date == utc("2026-11-11T00:00:00"), "the midnight boundary is exactly 00:00 UTC")
    }

    // MARK: No usable cache — planner still bounded, no invented stale entry

    let noCachePlan = WidgetTimelinePlanner.boundaries(now: planStart,
                                                       schedule: schedule,
                                                       dataFetchedAt: nil)
    try expect(noCachePlan.filter { $0.reason == .cacheStale }.isEmpty, "no fetch time means no stale crossing")
    try expect(!noCachePlan.isEmpty, "a plan exists even with no cached balance")
    try expect(noCachePlan.count <= WidgetTimelinePlanner.maximumEntries, "the no-cache plan is bounded")

    // MARK: Non-discount schedule

    let quietPlan = WidgetTimelinePlanner.boundaries(now: planStart,
                                                     schedule: standardSchedule,
                                                     dataFetchedAt: planFetched)
    try expect(quietPlan.filter { $0.reason == .peakSwitch }.isEmpty, "a non-discount schedule has no peak switches")
    try expect(!quietPlan.isEmpty, "a non-discount plan still has entries")
    try expect(quietPlan.first?.reason == .now, "a non-discount plan still starts at now")
    try expect(quietPlan.count <= WidgetTimelinePlanner.maximumEntries, "the non-discount plan is bounded")
    try expect(quietPlan.contains { $0.reason == .cacheStale }, "a non-discount plan still marks the stale crossing")

    // MARK: Explicit key store and removal results

    // A failed write must never look like success, and must never clear the cache.
    let failedSave = KeySaveResult.storeFailed
    try expect(failedSave.isStored == false, "a store failure is not stored")
    try expect(failedSave.shouldClearCachedBalance == false, "a store failure does not clear the cache")
    try expect(KeyStoreDecision.isFailure(failedSave), "a store failure is reported to the caller")
    try expect(KeyStoreDecision.invalidates(failedSave) == false, "a store failure does not invalidate the account")

    let sameKeySave = KeySaveResult.saved(.unchanged)
    try expect(sameKeySave.isStored, "saving the same key is stored")
    try expect(KeyStoreDecision.isFailure(sameKeySave) == false, "saving the same key is not a failure")
    try expect(sameKeySave.shouldClearCachedBalance == false, "saving the same key keeps the cache")

    let changedKeySave = KeySaveResult.saved(.changed)
    try expect(changedKeySave.isStored, "saving a different key is stored")
    try expect(changedKeySave.shouldClearCachedBalance, "saving a different key clears the cache")
    try expect(KeyStoreDecision.invalidates(changedKeySave), "saving a different key invalidates the account")
    try expect(changedKeySave.didChangeAccount, "saving a different key changes the account")

    let deleteFailed = KeyRemovalResult.deleteFailed
    try expect(deleteFailed.isRemoved == false, "a delete failure is not reported as removed")
    try expect(KeyStoreDecision.isFailure(deleteFailed), "a delete failure is reported")
    try expect(KeyStoreDecision.invalidates(deleteFailed) == false, "a delete failure does not invalidate the cache")

    let removed = KeyRemovalResult.removed(.changed)
    try expect(removed.isRemoved, "a successful delete is removed")
    try expect(removed.shouldClearCachedBalance, "a successful delete clears the cache")
    try expect(KeyStoreDecision.invalidates(removed), "a successful delete invalidates")

    // Deleting when no key is loaded must STILL clear an old cached balance.
    let removedAlreadyGone = KeyRemovalResult.removed(.unchanged)
    try expect(removedAlreadyGone.isRemoved, "deleting an already-absent key reports removed")
    try expect(KeyStoreDecision.invalidates(removedAlreadyGone), "an already-absent key still invalidates the cached balance")
    try expect(KeyStoreDecision.isFailure(removedAlreadyGone) == false, "an already-absent key is not a failure")

    // MARK: Keychain mutation routing — saving must never delete the stored item

    let itemMissing: Int32 = -25300  // errSecItemNotFound
    let someOtherError: Int32 = -34018

    let updateRoute = KeyStoreMutationRoute.route(probeStatus: 0, itemMissingStatus: itemMissing)
    try expect(updateRoute == .updateExisting, "a successful update probe routes to updateExisting")
    try expect(updateRoute.isSuccess, "updateExisting is a success")

    let addRoute = KeyStoreMutationRoute.route(probeStatus: itemMissing, itemMissingStatus: itemMissing)
    try expect(addRoute == .addNew, "item-not-found routes to addNew")
    try expect(addRoute.isSuccess, "addNew is a success")

    let failRoute = KeyStoreMutationRoute.route(probeStatus: someOtherError, itemMissingStatus: itemMissing)
    try expect(failRoute == .fail, "an unexpected status routes to fail")
    try expect(failRoute.isSuccess == false, "fail is not a success")

    // The critical regression: no route may delete the existing item.
    try expect(!updateRoute.deletesExistingItem, "updating never deletes the stored item")
    try expect(!addRoute.deletesExistingItem, "adding never deletes the stored item")
    try expect(!failRoute.deletesExistingItem, "failing never deletes the stored item")

    // A failed write must not invalidate the account or clear the cache.
    try expect(KeyStoreDecision.invalidates(KeySaveResult.storeFailed) == false, "a failed write keeps the cached balance")

    // MARK: Account generation — a changed account cannot repopulate the cache

    var generation = AccountGeneration.initial
    let ticket = generation.ticket()
    try expect(generation.accepts(ticket), "a ticket matches its own generation")
    generation.invalidate()
    try expect(!generation.accepts(ticket), "after invalidation the old ticket is rejected")
    try expect(AccountPolicy.acceptance(ticket: ticket, current: generation, hasKey: true) == .discardStaleAccount, "a stale-account response is discarded")
    try expect(AccountPolicy.acceptance(ticket: ticket, current: generation, hasKey: false) == .discardNoKey, "no key discards regardless of generation")
    try expect(AccountPolicy.acceptance(ticket: generation.ticket(), current: generation, hasKey: true) == .accept, "a current ticket is accepted")
    try expect(AccountPolicy.acceptance(ticket: nil, current: generation, hasKey: true) == .discardStaleAccount, "a missing ticket is never accepted")
    try expect(!BalanceAcceptance.discardStaleAccount.shouldCache, "discarded results never cache")

    // MARK: Key change comparison — plain equality, no hashing

    try expect(KeyChange.compare(previous: nil, next: nil) == .unchanged, "no key to no key is unchanged")
    try expect(KeyChange.compare(previous: "", next: "   ") == .unchanged, "whitespace normalises to no key")
    try expect(KeyChange.compare(previous: "sk-a", next: "sk-a") == .unchanged, "the same key is unchanged")
    try expect(KeyChange.compare(previous: " sk-a ", next: "sk-a") == .unchanged, "surrounding whitespace is ignored")
    try expect(KeyChange.compare(previous: nil, next: "sk-a") == .changed, "adding a key is a change")
    try expect(KeyChange.compare(previous: "sk-a", next: nil) == .changed, "removing a key is a change")
    try expect(KeyChange.compare(previous: "sk-a", next: "sk-b") == .changed, "switching account is a change")
    try expect(KeyChange.compare(previous: "sk-a", next: "sk-b").clearsCachedBalance, "switching account clears the cache")
    try expect(!KeyChange.compare(previous: "sk-a", next: "sk-a").clearsCachedBalance, "re-saving the same key keeps the cache")

    // A payload built the way the app builds it never carries the key: the model has no field for it.
    try expect(!WidgetCacheCodec.containsSecretMaterial(data), "a real payload carries no key material")

    // MARK: Identity constants

    try expect(WidgetShared.appGroupIdentifier == "group.com.waqas.deepseekpulse", "App Group identifier")
    try expect(WidgetShared.extensionBundleIdentifier == "com.waqas.deepseekpulse.widgets", "extension bundle identifier")
    try expect(WidgetShared.cacheFileName == "widget-snapshot.json", "cache file name")

    // MARK: 1.0.9 — honest key wording and the widget refresh handshake

    // The widget cannot read the Keychain, so an absent balance must never be reported as a missing
    // key. This is the exact regression the user reported twice.
    try expect(WidgetRefreshHandshakeRules.noBalanceTitle(hasAPIKeyKnown: false, hasAPIKey: false) == "Open app",
               "an unknown key state invites the user to open the app, not to add a key")
    try expect(WidgetRefreshHandshakeRules.noBalanceTitle(hasAPIKeyKnown: true, hasAPIKey: false) == "Add key in app",
               "only a positively reported missing key says Add key")
    try expect(WidgetRefreshHandshakeRules.noBalanceTitle(hasAPIKeyKnown: true, hasAPIKey: true) == "Open app",
               "a known key with no balance is a loading state")
    for known in [true, false] {
        for hasKey in [true, false] {
            let title = PulseBalanceWording.slot(hasBalance: false, hasAPIKey: hasKey, hasAPIKeyKnown: known)
            try expect(!title.lowercased().contains("no key"), "the slot never prints No key")
            let caption = PulseBalanceWording.caption(hasBalance: false,
                                                      hasAPIKeyKnown: known,
                                                      hasAPIKey: hasKey,
                                                      fetchedAtAge: nil,
                                                      isStale: false)
            try expect(!caption.lowercased().contains("no key"), "the caption never prints No key")
            try expect(!caption.lowercased().contains("no api key"), "the caption never prints No API key")
        }
    }
    try expect(PulseBalanceWording.slot(hasBalance: true, hasAPIKey: false) == "",
               "a real balance always wins the slot")

    // Cooldown: the widget cannot spam the app.
    try expect(WidgetRefreshHandshakeRules.shouldRequest(state: .empty,
                                                          hasBalance: false,
                                                          lastRequestAt: nil,
                                                          lastAnswerAt: nil,
                                                          now: now),
               "a widget with no data may ask once")
    try expect(!WidgetRefreshHandshakeRules.shouldRequest(state: .empty,
                                                           hasBalance: false,
                                                           lastRequestAt: now.addingTimeInterval(-30),
                                                           lastAnswerAt: nil,
                                                           now: now),
               "a request inside the cooldown is suppressed")
    try expect(WidgetRefreshHandshakeRules.shouldRequest(state: .empty,
                                                          hasBalance: false,
                                                          lastRequestAt: now.addingTimeInterval(-(WidgetRefreshHandshakeRules.minimumInterval + 5)),
                                                          lastAnswerAt: nil,
                                                          now: now),
               "a request after the cooldown is allowed again")
    try expect(!WidgetRefreshHandshakeRules.shouldRequest(state: .fresh,
                                                           hasBalance: true,
                                                           lastRequestAt: nil,
                                                           lastAnswerAt: nil,
                                                           now: now),
               "fresh data never triggers a request")
    try expect(WidgetRefreshHandshakeRules.shouldRequest(state: .stale,
                                                          hasBalance: true,
                                                          lastRequestAt: nil,
                                                          lastAnswerAt: nil,
                                                          now: now),
               "stale data triggers a request")
    try expect(WidgetRefreshHandshakeRules.reason(state: .stale, hasBalance: true) == .staleBalance,
               "a stale balance is named as such")
    try expect(!WidgetRefreshHandshakeRules.shouldRequest(state: .corrupt,
                                                           hasBalance: false,
                                                           lastRequestAt: nil,
                                                           lastAnswerAt: nil,
                                                           now: now),
               "a corrupt payload is the app's job, not a handshake")

    let freshRequest = WidgetRefreshRequest(requestedAt: now, reason: .missingBalance)
    try expect(!WidgetRefreshHandshakeRules.isExpired(freshRequest, now: now.addingTimeInterval(60)),
               "a request a minute old is still actionable")
    try expect(WidgetRefreshHandshakeRules.isExpired(freshRequest, now: now.addingTimeInterval(60 * 60 * 7)),
               "a request from seven hours ago is ignored")

    // A balance-carrying copy must outrank a newer schedule-only seed. This is the second cause of
    // the permanent "No key": the extension rewrote its own seed on every timeline build.
    let seedNow = WidgetSnapshotPayload.builtIn(now: now, appearance: nil)
    let seedEnvelope = WidgetCacheCodec.decode(try WidgetCacheCodec.encode(seedNow), now: now)
    try expect(!seedEnvelope.hasUsableBalance, "the built-in seed carries no balance")
    try expect(WidgetSnapshotStore.isBetter(decoded, than: seedEnvelope),
               "a copy that holds a balance outranks an empty seed")
    try expect(!WidgetSnapshotStore.isBetter(seedEnvelope, than: decoded),
               "the empty seed never displaces real data")

    // MARK: Themes and designs — every palette reachable, every design assigned to a family

    try expect(PulseThemes.all.count >= 10, "at least ten themes are shipped (found " + String(PulseThemes.all.count) + ")")
    try expect(PulseThemes.count == PulseThemes.all.count, "the advertised theme count matches the catalogue")
    try expect(Set(PulseThemes.all.map { $0.id }).count == PulseThemes.all.count, "theme ids are unique")
    try expect(PulseThemes.isConsistent, "the catalogue is internally consistent")
    for theme in PulseThemes.all {
        try expect(theme.isDisplayable, "every channel of " + theme.id + " is displayable")
        try expect(PulseThemes.contains(id: theme.id), "theme " + theme.id + " resolves by id from the picker")
        try expect(PulseThemes.theme(id: theme.id).name == theme.name, "theme " + theme.id + " keeps its own name, no fallback")
        for state in [PricingState.peak, PricingState.offPeak, PricingState.standard] {
            try expect(theme.ramp(for: state).isDisplayable, "the " + theme.id + " ramp is displayable in every state")
        }
    }
    try expect(PulseThemes.theme(id: "no-such-theme").id == PulseThemes.fallbackID, "an unknown id falls back instead of blanking")
    try expect(WidgetDesign.ordered.count == 10, "ten widget designs are shipped")
    try expect(WidgetDesign.smallFamily.count == 5 && WidgetDesign.mediumFamily.count == 5, "five designs per widget size")
    try expect(Set(WidgetDesign.ordered.map { $0.code }).count == 10, "design codes are unique")
    for design in WidgetDesign.ordered {
        try expect(WidgetDesign.design(code: design.code) == design, "design " + design.code + " resolves from its code")
    }

    // A saved appearance keeps the theme and both designs across a payload round trip.
    let themedAppearance = WidgetAppearance(themeID: "lavender", smallDesign: .ring, mediumDesign: .ledger,
                                            artwork: "rings", showBalance: false, showRefresh: true, showDayBand: false)
    let themedPayload = WidgetSnapshotPayload.make(writtenAt: now, balanceFetchedAt: nil, balance: nil,
                                                   schedule: schedule, models: [], hasAPIKey: true,
                                                   appearance: themedAppearance)
    let themedEnvelope = WidgetCacheCodec.decode(try WidgetCacheCodec.encode(themedPayload), now: now)
    try expect(themedEnvelope.appearance.themeID == "lavender", "the chosen theme survives encode/decode")
    try expect(themedEnvelope.appearance.theme.name == "Lavender", "the chosen theme resolves to its own palette")
    try expect(themedEnvelope.appearance.smallDesign == .ring, "the small design survives encode/decode")
    try expect(themedEnvelope.appearance.mediumDesign == .ledger, "the medium design survives encode/decode")
    try expect(!themedEnvelope.appearance.showBalance, "the balance switch survives encode/decode")

    // Report every failing label from this single execution, then fail. Nothing is printed as a pass.
    if !failures.isEmpty {
        throw WidgetKitCheckFailure.failed("failed " + String(failures.count) + " of " + String(checked) + ": " + failures.joined(separator: " | "))
    }

    print("widget kit checks passed: " + String(checked))
}
