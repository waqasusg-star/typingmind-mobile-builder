import Foundation

/// Executed component checks for the widget planner.
///
/// Compiled with `Sources/RequestPolicy.swift` and `Sources/WidgetPlanner.swift` through the
/// pipeline's `foundation_policy` test profile. Foundation only: no UIKit, no network.

enum WidgetPlannerCheckFailure: Error {
    case failed(String)
}

func widgetPlannerChecks() throws {
    let schedule = RateSeeds.schedule
    var checked = 0

    func expect(_ condition: Bool, _ label: String) throws {
        checked += 1
        if !condition { throw WidgetPlannerCheckFailure.failed(label) }
    }

    func utc(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: text) ?? Date(timeIntervalSince1970: 0)
    }

    let beforeWindow = WidgetPlanner.snapshot(schedule: schedule, at: utc("2026-11-10T00:30:00"))
    try expect(beforeWindow.state == .offPeak, "00:30 UTC is off-peak")
    try expect(beforeWindow.peakMinutesLeftToday == 420, "420 peak minutes remain before the first window")
    try expect(beforeWindow.totalPeakMinutesToday == 420, "a working day has 420 peak minutes")

    let insideFirst = WidgetPlanner.snapshot(schedule: schedule, at: utc("2026-11-10T03:59:00"))
    try expect(insideFirst.state == .peak, "03:59 UTC is peak")
    try expect(insideFirst.peakMinutesLeftToday == 241, "241 peak minutes remain at 03:59")

    let atWindowEnd = WidgetPlanner.snapshot(schedule: schedule, at: utc("2026-11-10T04:00:00"))
    try expect(atWindowEnd.state == .offPeak, "the window end is exclusive")
    try expect(atWindowEnd.peakMinutesLeftToday == 240, "240 peak minutes remain at 04:00")

    let afterWindows = WidgetPlanner.snapshot(schedule: schedule, at: utc("2026-11-10T10:00:00"))
    try expect(afterWindows.state == .offPeak, "10:00 UTC is off-peak")
    try expect(afterWindows.peakMinutesLeftToday == 0, "no peak minutes remain after the second window")

    let weekend = WidgetPlanner.snapshot(schedule: schedule, at: utc("2026-11-14T02:00:00"))
    try expect(weekend.state == .offPeak, "Saturday is off-peak")
    try expect(weekend.isWeekend, "Saturday is flagged as a weekend")
    try expect(weekend.totalPeakMinutesToday == 0, "a weekend has no peak minutes")

    let holiday = WidgetPlanner.snapshot(schedule: schedule, at: utc("2026-10-01T02:00:00"))
    try expect(holiday.state == .offPeak, "a listed PRC holiday is off-peak")

    let unverified = WidgetPlanner.snapshot(schedule: schedule, at: utc("2028-03-06T02:00:00"))
    try expect(unverified.uncertain, "a 2028 weekday is flagged unverified")

    let now = utc("2026-11-10T00:30:00")
    if let target = beforeWindow.nextSwitchAt {
        try expect(WidgetPlanner.countdown(from: now, to: target) == "30m 00s", "30-minute countdown text")
        try expect(WidgetPlanner.secondsUntil(now: now, target: target) == 1800, "30 minutes in seconds")
    } else {
        throw WidgetPlannerCheckFailure.failed("expected a next switch before the first window")
    }
    try expect(WidgetPlanner.countdown(from: now, to: now.addingTimeInterval(-60)) == "0s", "past targets clamp to zero")
    try expect(WidgetPlanner.headline(snapshot: insideFirst, discountsEnabled: true) == "PEAK", "peak headline")
    try expect(WidgetPlanner.headline(snapshot: insideFirst, discountsEnabled: false) == "STANDARD", "standard headline")
    try expect(WidgetPlanner.peakLeftLabel(minutes: 0) == "Off-peak all day", "zero minutes label")
    try expect(WidgetPlanner.peakLeftLabel(minutes: 160) == "2h 40m peak left today", "hours and minutes label")
    try expect(WidgetPlanner.peakLeftLabel(minutes: 120) == "2h peak left today", "whole hours label")
    try expect(WidgetPlanner.dayTag(daysAhead: 0) == "today", "today tag")
    try expect(WidgetPlanner.dayTag(daysAhead: 1) == "tomorrow", "tomorrow tag")
    try expect(WidgetPlanner.dayTag(daysAhead: 3) == "in 3 days", "in-N-days tag")
    try expect(WidgetPlanner.nextSwitchLabel(snapshot: beforeWindow, timeZone: TimeZone(secondsFromGMT: 0)!) == "Tue 01:00", "UTC next-switch label")

    try expect(WidgetPolicy.shouldRefresh(lastRefresh: nil, now: now), "first refresh is allowed")
    try expect(!WidgetPolicy.shouldRefresh(lastRefresh: now, now: now.addingTimeInterval(30)), "30 seconds is too soon")
    try expect(WidgetPolicy.shouldRefresh(lastRefresh: now, now: now.addingTimeInterval(61)), "61 seconds is allowed")
    try expect(WidgetPolicy.refreshDelay(now: now, nextSwitchAt: now.addingTimeInterval(10)) == 60, "short gaps clamp to the floor")
    try expect(WidgetPolicy.refreshDelay(now: now, nextSwitchAt: now.addingTimeInterval(7200)) == 3600, "long gaps clamp to the ceiling")

    if let link = WidgetPolicy.deepLinkURL() {
        try expect(WidgetPolicy.isWidgetDeepLink(link), "the status deep link is recognised")
        if let other = URL(string: "https://example.com/status") {
            try expect(!WidgetPolicy.isWidgetDeepLink(other), "other schemes are rejected")
        }
    } else {
        throw WidgetPlannerCheckFailure.failed("deep link URL could not be built")
    }

    print("widget planner checks passed: " + String(checked))
}
