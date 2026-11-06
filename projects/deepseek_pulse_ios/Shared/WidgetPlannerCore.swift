import Foundation

// DeepSeek Pulse — shared widget state planner (Core).
//
// Moved to Shared/ for profile widgetkit_v1: the extension compiles WidgetSources + Shared +
// Sources/RequestPolicy.swift and needs this type. Pure Foundation (no UIKit, no network).
//
// File basename is WidgetPlannerCore.swift, not WidgetPlanner.swift, because Swift rejects two files
// with the same basename inside one app target. The old Sources/WidgetPlanner.swift was removed in
// 1.0.3 (build 4), so this is the only implementation of WidgetPlanner in the project.

enum WidgetPlanner {

    static let minutesPerDay = 1440

    /// One instant of widget state plus the facts the layouts display.
    struct Snapshot: Equatable {
        var state: PricingState
        var dayKey: String
        var weekdayLabel: String
        var peakMinutesLeftToday: Int
        var totalPeakMinutesToday: Int
        var nextSwitchAt: Date?
        var nextSwitchBecomesPeak: Bool
        var nextSwitchDaysAhead: Int
        var uncertain: Bool
        var isWeekend: Bool
    }

    static func snapshot(schedule: PricingSchedule, at date: Date) -> Snapshot {
        let today = schedule.daySchedule(for: date)
        let transition = schedule.nextTransition(after: date)
        let minute = PricingSchedule.minuteOfDayUTC(date)

        var minutesLeft = 0
        if schedule.discountsEnabled {
            for interval in today.intervals {
                let from = max(interval.startMinuteUTC, minute)
                if interval.endMinuteUTC > from {
                    minutesLeft += interval.endMinuteUTC - from
                }
            }
        }

        var total = 0
        for interval in today.intervals {
            total += interval.durationMinutes
        }

        return Snapshot(state: schedule.state(at: date),
                        dayKey: today.key,
                        weekdayLabel: PricingSchedule.weekdayShort(today.weekday),
                        peakMinutesLeftToday: clampMinutes(minutesLeft),
                        totalPeakMinutesToday: clampMinutes(total),
                        nextSwitchAt: transition?.date,
                        nextSwitchBecomesPeak: transition?.becomesPeak ?? false,
                        nextSwitchDaysAhead: transition?.daysAhead ?? 0,
                        uncertain: schedule.isUncertain(at: date),
                        isWeekend: today.weekday >= 6)
    }

    private static func clampMinutes(_ value: Int) -> Int {
        min(max(0, value), minutesPerDay)
    }

    static func countdown(from now: Date, to target: Date) -> String {
        ClockFormat.countdown(seconds: secondsUntil(now: now, target: target))
    }

    static func secondsUntil(now: Date, target: Date) -> Int {
        max(0, Int(target.timeIntervalSince(now).rounded()))
    }

    /// Short label for the next switch in the device time zone, for example "Wed 06:00".
    static func nextSwitchLabel(snapshot value: Snapshot, timeZone: TimeZone = .current) -> String {
        guard let date = value.nextSwitchAt else { return "No peak window" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEE HH:mm"
        return formatter.string(from: date)
    }

    static func dayTag(daysAhead: Int) -> String {
        if daysAhead <= 0 { return "today" }
        if daysAhead == 1 { return "tomorrow" }
        return "in " + String(daysAhead) + " days"
    }

    static func headline(snapshot value: Snapshot, discountsEnabled: Bool) -> String {
        guard discountsEnabled else { return "STANDARD" }
        switch value.state {
        case .peak: return "PEAK"
        case .offPeak: return "OFF-PEAK"
        case .standard: return "STANDARD"
        }
    }

    static func switchCaption(snapshot value: Snapshot) -> String {
        value.nextSwitchBecomesPeak ? "Peak starts" : "Off-peak starts"
    }

    static func footnote(snapshot value: Snapshot, discountsEnabled: Bool, timeZone: TimeZone = .current) -> String {
        guard discountsEnabled else { return "Off-peak discounts are off" }
        guard value.nextSwitchAt != nil else { return "No peak window configured" }
        var text = switchCaption(snapshot: value) + " " + nextSwitchLabel(snapshot: value, timeZone: timeZone)
        if value.uncertain { text += " · calendar unverified" }
        return text
    }

    static func peakLeftLabel(minutes: Int) -> String {
        let total = clampMinutes(minutes)
        if total == 0 { return "Off-peak all day" }
        let hours = total / 60
        let rest = total % 60
        if hours == 0 { return String(rest) + "m peak left today" }
        if rest == 0 { return String(hours) + "h peak left today" }
        return String(hours) + "h " + String(rest) + "m peak left today"
    }
}
