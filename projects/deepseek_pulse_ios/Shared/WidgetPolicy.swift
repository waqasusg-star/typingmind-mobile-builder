import Foundation

// DeepSeek Pulse — widget refresh and deep-link policy, shared by the app and the extension.
//
// iOS bounds WidgetKit refreshes itself (roughly 15 minutes, 60 in Low Power Mode), so this policy
// states the app's own intent and never promises an exact update instant.
// Sources/WidgetPolicy.swift is now a comment-only stub.

enum WidgetPolicy {

    /// Deep link that opens the app.
    static let deepLink = "deepseekpulse://status"
    static let widgetDeepLinkScheme = "deepseekpulse"
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
