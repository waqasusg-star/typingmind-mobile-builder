import Foundation

// DeepSeek Pulse — widget refresh and deep-link policy, shared by the app and the extension.
//
// iOS bounds WidgetKit refreshes itself (roughly 15 minutes, 60 in Low Power Mode), so this policy
// states the app's intent and never promises an exact update instant.
// The deep link uses the scheme actually registered in the generated Info.plist:
// com.waqas.deepseekpulse — not the old deepseekpulse shorthand, which iOS would not route.

enum WidgetPolicy {

    /// Deep link that opens the app. Host and path are matched by the app's URL handler.
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
/// Foundation only, so the CI harness executes it with real Swift. The old code used one bounded
/// delay plus a fixed 30-minute follow-up, which could step over real transitions. This planner
/// walks the real pricing schedule and also inserts the moment the cached data turns stale.
/// It only proposes dates; iOS decides when a timeline is actually reloaded.
enum WidgetTimelinePlanner {

    /// Hard cap on entries so a widget can never build an unbounded timeline.
    static let maximumEntries = 8

    /// One point in time the widget needs a fresh view for.
    struct Boundary: Equatable {
        var date: Date
        /// Why this instant matters, used by tests and diagnostics.
        var reason: Reason

        enum Reason: String, Equatable {
            case now
            case peakSwitch
            case cacheStale
            /// End of the current UTC day: the 24-hour band must restart at midnight.
            case utcMidnight
            case safetyFloor
        }
    }

    /// Dates in ascending order, always starting with `now`, at most `maximumEntries`.
    /// - Parameters:
    ///   - now: current instant.
    ///   - schedule: the schedule copied into the shared snapshot.
    ///   - dataWrittenAt: when the balance numbers were fetched, used to find the stale crossing.
    ///   - staleAfter: age at which the widget must show the stale state.
    static func boundaries(now: Date,
                           schedule: PricingSchedule,
                           dataWrittenAt: Date?,
                           staleAfter: TimeInterval = WidgetShared.staleAfter) -> [Boundary] {
        var result: [Boundary] = [Boundary(date: now, reason: .now)]

        // Real peak/off-peak transitions, including weekends and holidays, inside the horizon.
        var cursor = now
        var transitions = 0
        while transitions < maximumEntries, let step = schedule.nextTransition(after: cursor) {
            guard step.date > cursor else { break }
            result.append(Boundary(date: step.date, reason: .peakSwitch))
            cursor = step.date
            transitions += 1
            if result.count >= maximumEntries { break }
        }

        // The instant the cached balance becomes stale.
        if let written = dataWrittenAt {
            let staleAt = written.addingTimeInterval(staleAfter)
            if staleAt > now {
                result.append(Boundary(date: staleAt, reason: .cacheStale))
            }
        }

        // Midnight UTC, because the band and the day key change there.
        let startOfToday = PricingSchedule.startOfDayUTC(now)
        if let midnight = PricingSchedule.utcCalendar.date(byAdding: .day, value: 1, to: startOfToday),
           midnight > now {
            result.append(Boundary(date: midnight, reason: .utcMidnight))
        }

        // A bounded safety entry so a widget is not left undated if every other date is far away.
        let safety = now.addingTimeInterval(WidgetPolicy.maximumRefreshInterval)
        if result.count < 2 {
            result.append(Boundary(date: safety, reason: .safetyFloor))
        }

        // Deduplicate equal instants (keeping the earliest reason), sort, then cap.
        var seen = Set<TimeInterval>()
        var unique: [Boundary] = []
        for boundary in result.sorted(by: { $0.date < $1.date }) {
            let stamp = boundary.date.timeIntervalSince1970
            if seen.contains(stamp) { continue }
            seen.insert(stamp)
            unique.append(boundary)
            if unique.count >= maximumEntries { break }
        }
        return unique
    }

    /// Dates only, ready for Timeline(entries:policy:).
    static func dates(now: Date,
                      schedule: PricingSchedule,
                      dataWrittenAt: Date?,
                      staleAfter: TimeInterval = WidgetShared.staleAfter) -> [Date] {
        boundaries(now: now, schedule: schedule, dataWrittenAt: dataWrittenAt, staleAfter: staleAfter)
            .map { $0.date }
    }
}
