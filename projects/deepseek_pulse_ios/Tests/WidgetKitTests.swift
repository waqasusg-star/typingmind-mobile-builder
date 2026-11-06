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

    let payload = WidgetSnapshotPayload(
        schemaVersion: WidgetShared.schemaVersion,
        writtenAt: now,
        balanceFetchedAt: now.addingTimeInterval(-120),
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

    // MARK: Staleness — measured from balanceFetchedAt (now - 120), not from writtenAt.

    let reference = now.addingTimeInterval(-120)
    let atLimit = WidgetCacheCodec.decode(data, now: reference.addingTimeInterval(WidgetShared.staleAfter))
    try expect(atLimit.state == .fresh, "exactly at the stale limit is still fresh")
    let pastLimit = WidgetCacheCodec.decode(data, now: reference.addingTimeInterval(WidgetShared.staleAfter + 1))
    try expect(pastLimit.state == .stale, "one second past the limit is stale")
    try expect(pastLimit.balanceCaption(now: reference.addingTimeInterval(7200)).contains("open the app"), "stale caption tells the user to open the app")

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

    // MARK: Honest state labels — the widget shows cached data, so no LIVE claim.

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
    let atEnd = WidgetPlanner.snapshot(schedule: schedule, at: utc("2026-11-10T04:00:00"))
    try expect(atEnd.state == .offPeak, "the peak window end is exclusive")
    let atStart = WidgetPlanner.snapshot(schedule: schedule, at: utc("2026-11-10T01:00:00"))
    try expect(atStart.state == .peak, "the peak window start is inclusive")
    let holiday = WidgetPlanner.snapshot(schedule: schedule, at: utc("2026-10-01T02:00:00"))
    try expect(holiday.state == .offPeak, "a listed PRC holiday is off-peak in the widget too")
    let weekend = WidgetPlanner.snapshot(schedule: schedule, at: utc("2026-11-14T02:00:00"))
    try expect(weekend.state == .offPeak, "a Saturday is off-peak even inside the clock window")
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

    // MARK: Bounded timeline planner — real transitions, not a fixed +30 minute step

    let planStart = utc("2026-11-10T00:30:00")
    let plan = WidgetTimelinePlanner.boundaries(now: planStart,
                                               schedule: schedule,
                                               dataWrittenAt: planStart.addingTimeInterval(-120))
    try expect(!plan.isEmpty, "the planner produces at least one entry")
    try expect(plan.first?.reason == .now, "the first boundary is now")
    try expect(plan.count <= WidgetTimelinePlanner.maximumEntries, "the planner is bounded")
    try expect(plan == plan.sorted(by: { $0.date < $1.date }), "boundaries are strictly ordered")

    let switches = plan.filter { $0.reason == .peakSwitch }
    try expect(!switches.isEmpty, "the plan contains real pricing transitions")
    if let firstSwitch = switches.first {
        try expect(firstSwitch.date == utc("2026-11-10T01:00:00"), "the first transition is the real 01:00 UTC peak start")
    }
    if switches.count > 1 {
        try expect(switches[1].date == utc("2026-11-10T04:00:00"), "the second transition is the real 04:00 UTC peak end")
    }

    // Exact midnight UTC boundary: the band and day key change there.
    let midnightPlan = WidgetTimelinePlanner.boundaries(now: utc("2026-11-10T23:58:00"),
                                                       schedule: schedule,
                                                       dataWrittenAt: nil)
    let midnights = midnightPlan.filter { $0.reason == .utcMidnight }
    try expect(!midnights.isEmpty, "a midnight boundary is included near the end of the day")
    if let midnight = midnights.first {
        try expect(midnight.date == utc("2026-11-11T00:00:00"), "the midnight boundary is exactly 00:00 UTC")
    }

    // Cache-stale crossing must be planned so the badge flips without a reload loop.
    let stalePlan = WidgetTimelinePlanner.boundaries(now: planStart,
                                                     schedule: schedule,
                                                     dataWrittenAt: planStart.addingTimeInterval(-120))
    let staleMarks = stalePlan.filter { $0.reason == .cacheStale }
    try expect(!staleMarks.isEmpty, "the cache-stale crossing is planned")
    if let mark = staleMarks.first {
        let expected = planStart.addingTimeInterval(-120).addingTimeInterval(WidgetShared.staleAfter)
        try expect(mark.date == expected, "the stale crossing is exactly fetch time plus staleAfter")
    }

    // A schedule that never transitions still yields a bounded plan.
    let quietPlan = WidgetTimelinePlanner.boundaries(now: planStart,
                                                     schedule: standardSchedule,
                                                     dataWrittenAt: nil)
    try expect(!quietPlan.isEmpty, "a non-discount schedule still produces a plan")
    try expect(quietPlan.filter { $0.reason == .peakSwitch }.isEmpty, "a non-discount schedule has no peak switches")
    try expect(quietPlan.count <= WidgetTimelinePlanner.maximumEntries, "the quiet plan is bounded")

    // MARK: Account generation — a changed account cannot repopulate the cache

    var generation = AccountGeneration.initial
    let ticket = generation.ticket()
    try expect(generation.accepts(ticket), "a ticket matches its own generation")
    generation.invalidate()
    try expect(!generation.accepts(ticket), "after invalidation the old ticket is rejected")
    try expect(AccountPolicy.acceptance(ticket: ticket, current: generation, hasKey: true) == .discardStaleAccount, "a stale-account response is discarded")
    try expect(AccountPolicy.acceptance(ticket: ticket, current: generation, hasKey: false) == .discardNoKey, "no key discards regardless of generation")
    let freshTicket = generation.ticket()
    try expect(AccountPolicy.acceptance(ticket: freshTicket, current: generation, hasKey: true) == .accept, "a current ticket is accepted")
    try expect(AccountPolicy.acceptance(ticket: nil, current: generation, hasKey: true) == .discardStaleAccount, "a missing ticket is never accepted")
    try expect(!BalanceAcceptance.discardStaleAccount.shouldCache, "discarded results never cache")

    try expect(AccountPolicy.clearsCache(previousKeyHash: nil, newKeyHash: nil) == false, "no key to no key does not clear")
    try expect(AccountPolicy.clearsCache(previousKeyHash: 1, newKeyHash: nil), "removing a key clears the cache")
    try expect(AccountPolicy.clearsCache(previousKeyHash: 1, newKeyHash: 2), "changing the key clears the cache")
    try expect(AccountPolicy.clearsCache(previousKeyHash: 1, newKeyHash: 1) == false, "re-saving the same key keeps the cache")

    try expect(AccountPolicy.keyFingerprint("   ") == nil, "an empty key has no fingerprint")
    try expect(AccountPolicy.keyFingerprint("sk-test-1234") != nil, "a real key has a fingerprint")
    try expect(AccountPolicy.keyFingerprint("sk-test-1234") == AccountPolicy.keyFingerprint("sk-test-1234"), "the fingerprint is stable")
    try expect(AccountPolicy.keyFingerprint("sk-test-1234") != AccountPolicy.keyFingerprint("sk-test-5678"), "different keys have different fingerprints")
    // The fingerprint is an integer only; no key text can appear in a shared payload built from it.
    let fingerprintPayload = WidgetSnapshotPayload(schemaVersion: WidgetShared.schemaVersion,
                                                   writtenAt: now, balanceFetchedAt: nil, balance: nil,
                                                   schedule: schedule,
                                                   models: [WidgetRate(name: "deepseek-flash", label: "V4.1", offPeakDiscountPercent: 50)],
                                                   hasAPIKey: AccountPolicy.keyFingerprint("sk-test-1234") != nil)
    let fingerprintData = try WidgetCacheCodec.encode(fingerprintPayload)
    try expect(!WidgetCacheCodec.containsSecretMaterial(fingerprintData), "a payload derived from the fingerprint carries no secret")

    // MARK: Identity constants

    try expect(WidgetShared.appGroupIdentifier == "group.com.waqas.deepseekpulse", "App Group identifier")
    try expect(WidgetShared.extensionBundleIdentifier == "com.waqas.deepseekpulse.widgets", "extension bundle identifier")
    try expect(WidgetShared.cacheFileName == "widget-snapshot.json", "cache file name")

    print("widget kit checks passed: " + String(checked))
}
