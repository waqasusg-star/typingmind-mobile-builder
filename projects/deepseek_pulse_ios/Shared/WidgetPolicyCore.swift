import Foundation

// DeepSeek Pulse — widget refresh policy, deep link and bounded timeline planner (Core).
//
// Shared by the app and the widget extension; Foundation only, so CI executes it with real Swift.
// The deep link uses the scheme actually registered in the generated Info.plist.
// Basename is WidgetPolicyCore.swift to avoid a duplicate-basename compile error with
// Sources/WidgetPolicy.swift, which is now a marker file.

enum WidgetPolicy {

    /// Deep link that opens the app.
    static let deepLink = "com.waqas.deepseekpulse://status"
    static let widgetDeepLinkScheme = "com.waqas.deepseekpulse"
    static let widgetDeepLinkHost = "status"

    /// Shared cache key name used when an App Group is available.
    static let sharedScheduleKey = "deepseekpulse.widget.schedule.v1"
    static let appGroupIdentifier = "group.com.waqas.deepseekpulse"

    /// Smallest gap the app enforces between two refreshes it starts itself.
    static let minimumRefreshInterval: TimeInterval = 60
    /// Upper bound the app asks iOS for when scheduling the next refresh.
    static let maximumRefreshInterval: TimeInterval = 3600
    /// In-app preview tick. Not a widget or Live Activity refresh promise.
    static let liveActivityTickInterval: TimeInterval = 60

    static func secondsUntilSwitch(now: Date, nextSwitchAt: Date?) -> Int {
        guard let target = nextSwitchAt else { return Int(maximumRefreshInterval) }
        return max(1, Int(target.timeIntervalSince(now).rounded()))
    }

    static func refreshDelay(now: Date, nextSwitchAt: Date?) -> TimeInterval {
        let seconds = TimeInterval(secondsUntilSwitch(now: now, nextSwitchAt: nextSwitchAt)) + 5
        return min(max(seconds, minimumRefreshInterval), maximumRefreshInterval)
    }

    static func shouldRefresh(lastRefresh: Date?, now: Date) -> Bool {
        guard let last = lastRefresh else { return true }
        return now.timeIntervalSince(last) >= minimumRefreshInterval
    }

    static func isWidgetDeepLink(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == widgetDeepLinkScheme else { return false }
        return (url.host ?? "").lowercased() == widgetDeepLinkHost
    }

    static func deepLinkURL() -> URL? {
        URL(string: deepLink)
    }
}

/// Builds the timeline dates a widget actually needs.
///
/// Rules, each covered by Tests/WidgetKitTests.swift:
///   * every real transition inside the horizon is planned, not just the nearest one. A trading day
///     has four (01:00, 04:00, 06:00, 10:00 UTC); planning only the first left a stale PEAK badge,
///     because a later midnight entry does not ask iOS for a reload.
///   * the cache-stale boundary is one second PAST the codec threshold, since the codec reports
///     stale only when age > staleAfter.
///   * every UTC midnight inside the horizon is included: the day key and band change there.
///   * both a horizon and an entry cap bound the plan; `now`, the transitions and the stale crossing
///     are collected before optional fill so the cap cannot drop them.
///   * iOS decides when a reload really happens. Nothing here promises an exact instant.
enum WidgetTimelinePlanner {

    /// Hard cap on entries in one timeline.
    static let maximumEntries = 12
    /// Transitions reserved before optional fill, so one trading day fits while a schedule with many
    /// windows still stays bounded.
    static let transitionsBeforeOptionalFill = 6
    /// How far ahead the plan looks for real boundaries.
    static let horizon: TimeInterval = 24 * 60 * 60

    struct Boundary: Equatable {
        var date: Date
        var reason: Reason

        enum Reason: String, Equatable {
            case now
            case peakSwitch
            case cacheStale
            case utcMidnight
            case reloadBound
        }
    }

    /// Ascending, de-duplicated, starting with `now`, at most `maximumEntries` long.
    static func boundaries(now: Date,
                           schedule: PricingSchedule,
                           dataFetchedAt: Date?,
                           staleAfter: TimeInterval = WidgetShared.staleAfter) -> [Boundary] {
        let horizonEnd = now.addingTimeInterval(horizon)
        let nowBoundary = Boundary(date: now, reason: .now)

        // Every real transition inside the horizon. The cursor advances so each step is later.
        var transitionBoundaries: [Boundary] = []
        var cursor = now
        while transitionBoundaries.count < transitionsBeforeOptionalFill {
            guard let step = schedule.nextTransition(after: cursor) else { break }
            guard step.date > cursor else { break }
            guard step.date <= horizonEnd else { break }
            transitionBoundaries.append(Boundary(date: step.date, reason: .peakSwitch))
            cursor = step.date
        }

        // One second past the threshold, so the planned entry really decodes as stale.
        var staleBoundary: Boundary?
        if let fetched = dataFetchedAt {
            let staleAt = fetched.addingTimeInterval(staleAfter + 1)
            if staleAt > now {
                staleBoundary = Boundary(date: staleAt, reason: .cacheStale)
            }
        }

        // Every UTC midnight inside the horizon.
        var midnightBoundaries: [Boundary] = []
        let startOfToday = PricingSchedule.startOfDayUTC(now)
        var dayOffset = 1
        while let midnight = PricingSchedule.utcCalendar.date(byAdding: .day, value: dayOffset, to: startOfToday) {
            guard midnight <= horizonEnd else { break }
            if midnight > now {
                midnightBoundaries.append(Boundary(date: midnight, reason: .utcMidnight))
            }
            dayOffset += 1
            if dayOffset > 3 { break }
        }

        let reloadBound = Boundary(date: min(horizonEnd, reloadDate(now: now)), reason: .reloadBound)

        var reserved: [Boundary] = [nowBoundary]
        reserved.append(contentsOf: transitionBoundaries)
        if let stale = staleBoundary { reserved.append(stale) }

        var combined = reserved
        for candidate in midnightBoundaries + [reloadBound] {
            if combined.count >= maximumEntries { break }
            combined.append(candidate)
        }

        var seen = Set<TimeInterval>()
        var unique: [Boundary] = []
        for boundary in combined.sorted(by: { $0.date < $1.date }) {
            let stamp = boundary.date.timeIntervalSince1970
            if seen.contains(stamp) { continue }
            seen.insert(stamp)
            unique.append(boundary)
            if unique.count >= maximumEntries { break }
        }

        if unique.first?.reason != .now {
            unique.insert(nowBoundary, at: 0)
            if unique.count > maximumEntries {
                unique.removeLast()
            }
        }
        return unique
    }

    /// Dates only, ready for Timeline(entries:policy:).
    static func dates(now: Date,
                      schedule: PricingSchedule,
                      dataFetchedAt: Date?,
                      staleAfter: TimeInterval = WidgetShared.staleAfter) -> [Date] {
        boundaries(now: now,
                   schedule: schedule,
                   dataFetchedAt: dataFetchedAt,
                   staleAfter: staleAfter).map { $0.date }
    }

    /// The next instant the widget should be allowed to ask iOS for fresh data, bounded by the
    /// policy maximum. A request, not a promise.
    static func reloadDate(now: Date) -> Date {
        now.addingTimeInterval(WidgetPolicy.maximumRefreshInterval)
    }
}
