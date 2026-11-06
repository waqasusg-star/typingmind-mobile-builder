import Foundation

// DeepSeek Pulse — executed Foundation checks for the shared widget cache and widget logic.
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

    var newer = payload
    newer.schemaVersion = WidgetShared.schemaVersion + 1
    let newerData = try WidgetCacheCodec.encode(newer)
    try expect(WidgetCacheCodec.decode(newerData, now: now).state == .incompatible, "a newer schema is reported as incompatible")
    try expect(WidgetCacheCodec.decode(newerData, now: now).payload == nil, "an incompatible payload is not half-read")

    var older = payload
    older.schemaVersion = WidgetShared.schemaVersion - 1
    let olderData = try WidgetCacheCodec.encode(older)
    try expect(WidgetCacheCodec.decode(olderData, now: now).state == .incompatible, "an older schema is reported as incompatible")

    try expect(WidgetCacheCodec.decode(Data(), now: now).state == .empty, "zero bytes is the empty state")
    try expect(WidgetCacheCodec.decode(Data("{".utf8), now: now).state == .corrupt, "truncated JSON is corrupt")
    try expect(WidgetCacheCodec.decode(Data("not json at all".utf8), now: now).state == .corrupt, "non-JSON is corrupt")
    try expect(WidgetCacheCodec.decode(Data("{\"schemaVersion\":2}".utf8), now: now).state == .corrupt, "a version-only body is corrupt, not fabricated")
    try expect(WidgetCacheCodec.decode(Data("{".utf8), now: now).balanceLine() == "--", "corrupt data shows no fake balance")

    let exactlyAtLimit = WidgetCacheCodec.decode(data, now: now.addingTimeInterval(WidgetShared.staleAfter))
    try expect(exactlyAtLimit.state == .fresh, "exactly at the stale limit is still fresh")
    let justOver = WidgetCacheCodec.decode(data, now: now.addingTimeInterval(WidgetShared.staleAfter + 1))
    try expect(justOver.state == .stale, "one second past the limit is stale")
    try expect(justOver.balanceCaption(now: now.addingTimeInterval(7200)).contains("open the app"), "stale caption tells the user to open the app")

    let noBalancePayload = WidgetSnapshotPayload(schemaVersion: WidgetShared.schemaVersion,
                                                writtenAt: now, balanceFetchedAt: nil, balance: nil,
                                                schedule: schedule, models: [], hasAPIKey: false)
    let noBalanceData = try WidgetCacheCodec.encode(noBalancePayload)
    let noBalance = WidgetCacheCodec.decode(noBalanceData, now: now)
    try expect(noBalance.state == .fresh, "a payload without a balance is still fresh (age uses writtenAt)")
    try expect(noBalance.balanceLine() == "No key", "no key is stated, not faked")
    try expect(noBalance.balanceCaption(now: now) == "No API key saved", "no-key caption")

    try expect(WidgetCacheCodec.safe("  $1.00  ") == "$1.00", "trimming")
    try expect(WidgetCacheCodec.safe(String(repeating: "x", count: 100)).count == 40, "length clamp")
    let injected = WidgetCacheCodec.sanitizedBalance(currency: "USD\n", total: "1.00\u{0007}", granted: "", toppedUp: "", isAvailable: true)
    try expect(injected.currency == "USD", "currency has no control characters")
    try expect(injected.totalText == "1.00", "control characters are stripped from amounts")

    try expect(WidgetDataState.groupUnavailable.isUsable == false, "group unavailable is not usable")
    try expect(WidgetDataState.groupUnavailable.explainer.contains("App Group"), "group state explains the entitlement")
    try expect(WidgetSnapshotEnvelope.failed(.groupUnavailable).balanceLine() == "--", "unavailable shows a placeholder")
    try expect(WidgetDataState.fresh.shortLabel == "LIVE", "fresh badge")
    try expect(WidgetDataState.stale.shortLabel == "STALE", "stale badge")
    try expect(WidgetDataState.empty.shortLabel == "NO DATA", "empty badge")

    let inWindow = WidgetPlanner.snapshot(schedule: schedule, at: utc("2026-11-10T02:00:00"))
    try expect(inWindow.state == .peak, "02:00 UTC on a working Tuesday is peak")
    let atEnd = WidgetPlanner.snapshot(schedule: schedule, at: utc("2026-11-10T04:00:00"))
    try expect(atEnd.state == .offPeak, "the peak window end is exclusive")
    let holiday = WidgetPlanner.snapshot(schedule: schedule, at: utc("2026-10-01T02:00:00"))
    try expect(holiday.state == .offPeak, "a listed PRC holiday is off-peak in the widget too")
    let unverifiedYear = WidgetPlanner.snapshot(schedule: schedule, at: utc("2028-03-06T02:00:00"))
    try expect(unverifiedYear.uncertain, "an uncovered year is flagged unverified")
    try expect(WidgetPlanner.footnote(snapshot: unverifiedYear, discountsEnabled: true, timeZone: TimeZone(secondsFromGMT: 0)!).contains("unverified"), "the footnote admits the unverified calendar")

    let switchTarget = utc("2026-11-10T01:00:00")
    try expect(WidgetPlanner.countdown(from: now, to: switchTarget) == "30m 00s", "countdown text at a boundary")
    try expect(WidgetPolicy.refreshDelay(now: now, nextSwitchAt: switchTarget) == 1805, "refresh delay is the switch plus 5s")
    try expect(WidgetPolicy.deepLinkURL()?.absoluteString == "deepseekpulse://status", "widget deep link")

    try expect(WidgetShared.appGroupIdentifier == "group.com.waqas.deepseekpulse", "App Group identifier")
    try expect(WidgetShared.extensionBundleIdentifier == "com.waqas.deepseekpulse.widgets", "extension bundle identifier")
    try expect(WidgetShared.cacheFileName == "widget-snapshot.json", "cache file name")

    print("widget kit checks passed: " + String(checked))
}
