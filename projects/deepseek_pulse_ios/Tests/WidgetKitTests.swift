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
    func expect(_ condition: Bool, _ label: String) throws {
        checked += 1
        if !condition { throw WidgetKitCheckFailure.failed(label) }
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
    try expect(WidgetCacheCodec.decode(Data("{\"schemaVersion\":2}".utf8), now: now).state == .corrupt, "a version-only body is corrupt, not fabricated")
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
    try expect(noBalance.balanceLine() == "No key", "no key is stated, not faked")
    try expect(noBalance.balanceCaption(now: now) == "No API key saved", "no-key caption")

    // MARK: Sanitisation

    try expect(WidgetCacheCodec.safe("  $1.00  ") == "$1.00", "trimming")
    try expect(WidgetCacheCodec.safe(String(repeating: "x", count: 100)).count == 40, "length clamp")
    let injected = WidgetCacheCodec.sanitizedBalance(currency: "USD\n", total: "1.00\u{0007}", granted: "", toppedUp: "", isAvailable: true)
    try expect(injected.currency == "USD", "currency has no control characters")
    try expect(injected.totalText == "1.00", "control characters are stripped from amounts")

    // MARK: Honest state labels

    try expect(WidgetDataState.groupUnavailable.isUsable == false, "group unavailable is not usable")
    try expect(WidgetDataState.groupUnavailable.explainer.contains("App Group"), "group state explains the entitlement")
    try expect(WidgetSnapshotEnvelope.failed(.groupUnavailable).balanceLine() == "--", "unavailable shows a placeholder")
    try expect(WidgetDataState.fresh.shortLabel == "RECENT", "fresh badge says RECENT, not LIVE")
    try expect(WidgetDataState.stale.shortLabel == "CACHED", "stale badge says CACHED")
    try expect(WidgetDataState.empty.shortLabel == "NO DATA", "empty badge")
    try expect(WidgetDataState.incompatible.shortLabel == "UPDATE", "incompatible badge")
    try expect(WidgetDataState.corrupt.shortLabel == "UNREADABLE", "corrupt badge")

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
    try expect(quietPlan.count <= WidgetTimelinePlanner.maximumEntries, "the non-discount plan is bounded")

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

    print("widget kit checks passed: " + String(checked))
}
