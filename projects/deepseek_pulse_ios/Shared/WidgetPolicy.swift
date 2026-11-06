import Foundation

// DeepSeek Pulse — widget refresh and deep-link policy, shared by the app and the extension.
//
// iOS bounds WidgetKit refreshes itself (roughly 15 minutes, 60 in Low Power Mode), so this policy
// states the app's intent and never promises an exact update instant.
// The deep link uses the scheme actually registered in the generated Info.plist:
// com.waqas.deepseekpulse — not the old deepseekpulse shorthand, which iOS would not route.

enum WidgetPolicy {

    /// Deep link that opens the app. Host is matched by the app's URL handler.
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
    /// In-app preview tick. This is not a widget or Live Activity refresh promise.
    static let liveActivityTickInterval: TimeInterval = 60

    static func secondsUntilSwitch(now: Date, nextSwitchAt: Date?) -> Int {
        guard let target = nextSwitchAt else { return Int(maximumRefreshInterval) }
        return max(1, Int(target.timeIntervalSince(now).rounded()))
    }

    /// Delay the app requests for the next refresh: just after the switch, bounded.
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
/// Foundation only, so the CI harness executes it with real Swift.
///
/// Correctness rules, each covered by Tests/WidgetKitTests.swift:
///   * the cache-stale boundary is one second PAST the codec threshold, because the codec only
///     reports .stale when age > staleAfter. Emitting the exact threshold would place an entry that
///     still decodes as fresh, leaving a wrong badge on screen.
///   * the plan is bounded by both a horizon and an entry cap.
///   * every UTC midnight inside the horizon is included, because the day key and the 24-hour band
///     change there.
///   * the cap can never drop `now`, the stale crossing, or a transition within the horizon; those
///     are collected before optional fill and are reserved slots.
///   * the final entry never sits further away than the policy reload bound, so a widget always has
///     a bounded reason to ask for a reload. iOS still decides the real refresh budget.
enum WidgetTimelinePlanner {

    /// Hard cap on entries in one timeline.
    static let maximumEntries = 12
    /// Transitions reserved before optional fill, so one trading day fits (01:00/04:00/06:00/10:00)
    /// while the plan still stays bounded on a schedule with many windows.
    static let transitionsBeforeOptionalFill = 6
    /// How far ahead the plan looks for real boundaries.
    static let horizon: TimeInterval = 24 * 60 * 60

    /// One point in time the widget needs a fresh view for.
    struct Boundary: Equatable {
        var date: Date
        var reason: Reason

        enum Reason: String, Equatable {
            case now
            case peakSwitch
            case cacheStale
            /// End of a UTC day: the band and the day key restart at midnight.
            case utcMidnight
            /// Bounded far entry so the timeline is never open-ended.
            case reloadBound
        }
    }

    /// Ascending, de-duplicated, starting with `now`, at most `maximumEntries` long.
    /// - Parameters:
    ///   - now: current instant.
    ///   - schedule: the schedule copied into the shared snapshot.
    ///   - dataFetchedAt: when the balance numbers were fetched (not when the file was written).
    ///   - staleAfter: age threshold used by WidgetCacheCodec.
    static func boundaries(now: Date,
                           schedule: PricingSchedule,
                           dataFetchedAt: Date?,
                           staleAfter: TimeInterval = WidgetShared.staleAfter) -> [Boundary] {
        let horizonEnd = now.addingTimeInterval(horizon)

        // 1. Always present: the current instant.
        let nowBoundary = Boundary(date: now, reason: .now)

        // 2. Every real transition inside the horizon, not just the first. A trading day has four
        //    (01:00, 04:00, 06:00, 10:00 UTC); planning only the nearest one would leave the widget
        //    showing PEAK long after the window ended, because a later midnight entry does not ask
        //    iOS for a reload. The cursor advances so each step is strictly later.
        var transitionBoundaries: [Boundary] = []
        var cursor = now
        while transitionBoundaries.count < transitionsBeforeOptionalFill {
            guard let step = schedule.nextTransition(after: cursor) else { break }
            guard step.date > cursor else { break }
            guard step.date <= horizonEnd else { break }
            transitionBoundaries.append(Boundary(date: step.date, reason: .peakSwitch))
            cursor = step.date
        }

        // 3. The stale crossing, one second past the threshold so the entry really decodes as stale.
        //    Reserved for the same reason.
        var staleBoundary: Boundary?
        if let fetched = dataFetchedAt {
            let staleAt = fetched.addingTimeInterval(staleAfter + 1)
            if staleAt > now {
                staleBoundary = Boundary(date: staleAt, reason: .cacheStale)
            }
        }

        // 4. Every UTC midnight inside the horizon.
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

        // 5. A bounded far entry so the timeline always terminates on a reload request.
        let reloadBound = Boundary(date: min(horizonEnd, now.addingTimeInterval(WidgetPolicy.maximumRefreshInterval)),
                                   reason: .reloadBound)

        // Assemble: reserved first, then optional fill, then dedupe + sort.
        var reserved: [Boundary] = [nowBoundary]
        reserved.append(contentsOf: transitionBoundaries)
        if let stale = staleBoundary { reserved.append(stale) }

        var optional: [Boundary] = midnightBoundaries
        optional.append(reloadBound)

        var combined = reserved
        for candidate in optional {
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

        // The cap must never remove `now`; it is sorted first because nothing precedes it.
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

    /// The next instant the widget should be allowed to ask iOS for fresh data.
    ///
    /// Bounded by WidgetPolicy.maximumRefreshInterval so a timeline never asks for more than the
    /// policy allows. iOS still applies its own budget and may return the reload later; this is a
    /// request, not a promise.
    static func reloadDate(now: Date) -> Date {
        now.addingTimeInterval(WidgetPolicy.maximumRefreshInterval)
    }
}
