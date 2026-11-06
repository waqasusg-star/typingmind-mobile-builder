// DeepSeek Pulse — platform-neutral pricing, schedule and balance logic.
//
// This file is UIKit-free so the native pipeline can compile it together with
// Tests/PolicyTests.swift through the "foundation_policy" test profile.
// It must not reference symbols from other files in Sources/.

import Foundation

// MARK: - Pricing state

enum PricingState: String, Equatable {
    case peak
    case offPeak
    case standard

    var label: String {
        switch self {
        case .peak: return "PEAK"
        case .offPeak: return "OFF-PEAK"
        case .standard: return "STANDARD"
        }
    }
}

// MARK: - Schedule model

/// One peak window inside a single UTC day. `endMinuteUTC` is exclusive.
struct PeakInterval: Codable, Equatable, Hashable {
    var startMinuteUTC: Int
    var endMinuteUTC: Int

    var isValid: Bool {
        startMinuteUTC >= 0
            && endMinuteUTC <= PricingSchedule.minutesPerDay
            && startMinuteUTC < endMinuteUTC
    }

    var durationMinutes: Int { max(0, endMinuteUTC - startMinuteUTC) }

    func contains(minute: Int) -> Bool {
        minute >= startMinuteUTC && minute < endMinuteUTC
    }

    var utcLabel: String {
        ClockFormat.minuteLabel(startMinuteUTC) + "–" + ClockFormat.minuteLabel(endMinuteUTC)
    }
}

/// How a single UTC day relates to the PRC public holiday calendar.
enum DayKind: String, Codable, Equatable {
    /// Explicitly listed as a PRC public holiday.
    case holiday
    /// Inside the date range covered by a verified list, and not a holiday.
    case workingDay
    /// No verified holiday information for this day; weekday peaks are assumed.
    case unverified
}

struct HolidayCalendar: Codable, Equatable {
    /// PRC calendar dates, yyyy-MM-dd. Peak windows fall inside 09:00–18:00 CST, so the PRC
    /// date and the UTC date of a peak window carry the same yyyy-MM-dd.
    var dates: Set<String>
    /// First and last yyyy-MM-dd covered by a list the user actually checked.
    var coverageStart: String?
    var coverageEnd: String?
    /// The date the human confirmed the list, as words. Never set automatically by the app.
    var verifiedAsOf: String?
    /// Where the list came from.
    var source: String? = nil

    static let empty = HolidayCalendar(dates: [], coverageStart: nil, coverageEnd: nil, verifiedAsOf: nil, source: nil)

    /// A calendar is verified when a coverage range has been declared; dates alone are not enough,
    /// because a partial list would silently treat missing holidays as working days.
    var isVerified: Bool {
        guard let start = coverageStart, let end = coverageEnd else { return false }
        return start <= end
    }

    /// ISO date strings compare lexicographically, which is chronological for yyyy-MM-dd.
    func covers(_ dayKey: String) -> Bool {
        guard let start = coverageStart, let end = coverageEnd else { return false }
        return dayKey >= start && dayKey <= end
    }

    func kind(forDay dayKey: String) -> DayKind {
        if dates.contains(dayKey) { return .holiday }
        if covers(dayKey) { return .workingDay }
        return .unverified
    }

    var coverageLabel: String? {
        guard let start = coverageStart, let end = coverageEnd else { return nil }
        return start + "…" + end
    }

    var sourceHost: String {
        guard let source = source, let url = URL(string: source), let host = url.host else {
            return source ?? ""
        }
        return host
    }

    var summary: String {
        if dates.isEmpty && coverageStart == nil { return "PRC public holidays not loaded" }
        var parts: [String] = [String(dates.count) + " PRC holiday date(s)"]
        if let coverage = coverageLabel { parts.append("checked " + coverage) }
        if let stamp = verifiedAsOf {
            parts.append("verified " + stamp)
        } else {
            parts.append("unverified")
        }
        let host = sourceHost
        if !host.isEmpty { parts.append("source " + host) }
        return parts.joined(separator: " · ")
    }
}

/// The resolved peak/off-peak shape of one UTC day.
struct DaySchedule: Equatable {
    var key: String
    var weekday: Int
    var kind: DayKind
    var intervals: [PeakInterval]

    var isPeakDay: Bool { !intervals.isEmpty }
}

/// One band of the 24 hour UTC day, used by the timeline bar.
struct ScheduleSegment: Equatable {
    var startMinute: Int
    var endMinute: Int
    var state: PricingState
}

/// The published DeepSeek price schedule: a set of UTC weekday peak windows plus the PRC public
/// holiday calendar. Off-peak covers every other hour, every weekend and every PRC public holiday.
struct PricingSchedule: Codable, Equatable {

    /// ISO weekdays with peak windows: 1 = Monday … 7 = Sunday.
    var peakWeekdays: Set<Int>
    /// Peak windows in UTC minutes from 00:00, applied on `peakWeekdays`.
    var intervals: [PeakInterval]
    var holidays: HolidayCalendar
    /// false means "discounts withdrawn": one standard price around the clock.
    var discountsEnabled: Bool
    var sourceURL: String
    var verifiedAsOf: String

    static let minutesPerDay = 1440
    static let secondsPerDay = 86400

    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone(identifier: "UTC")!
        return calendar
    }()

    // MARK: UTC helpers

    static func dayKey(_ date: Date) -> String {
        let parts = utcCalendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(fromDayKey key: String) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }
        return utcCalendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    static func startOfDayUTC(_ date: Date) -> Date {
        utcCalendar.startOfDay(for: date)
    }

    /// ISO weekday: 1 = Monday … 7 = Sunday.
    static func isoWeekday(_ date: Date) -> Int {
        let weekday = utcCalendar.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }

    static func weekdayShort(_ iso: Int) -> String {
        let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        guard iso >= 1, iso <= names.count else { return "?" }
        return names[iso - 1]
    }

    static func minuteOfDayUTC(_ date: Date) -> Int {
        let parts = utcCalendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    static func secondsOfDayUTC(_ date: Date) -> Int {
        let parts = utcCalendar.dateComponents([.hour, .minute, .second], from: date)
        return (parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60 + (parts.second ?? 0)
    }

    // MARK: Shape

    var intervalsAreValid: Bool {
        !peakWeekdays.isEmpty && !intervals.isEmpty && intervals.allSatisfy { $0.isValid }
    }

    var isActive: Bool { discountsEnabled && intervalsAreValid }

    var sortedIntervals: [PeakInterval] {
        intervals.sorted { $0.startMinuteUTC < $1.startMinuteUTC }
    }

    var weekdaySummary: String {
        let sorted = peakWeekdays.sorted()
        if sorted == [1, 2, 3, 4, 5] { return "Mon–Fri" }
        if sorted == [1, 2, 3, 4, 5, 6, 7] { return "every day" }
        if sorted.isEmpty { return "no days" }
        return sorted.map { PricingSchedule.weekdayShort($0) }.joined(separator: " ")
    }

    var intervalSummaryUTC: String {
        sortedIntervals.map { $0.utcLabel }.joined(separator: ", ") + " UTC"
    }

    func intervalSummaryLocal(on reference: Date = Date(), timeZone: TimeZone = .current) -> String {
        let parts = sortedIntervals.map { interval in
            ClockFormat.localLabel(minuteUTC: interval.startMinuteUTC, on: reference, timeZone: timeZone)
                + "–"
                + ClockFormat.localLabel(minuteUTC: interval.endMinuteUTC, on: reference, timeZone: timeZone)
        }
        return parts.joined(separator: ", ")
    }

    // MARK: Queries

    func daySchedule(for date: Date) -> DaySchedule {
        let key = PricingSchedule.dayKey(date)
        let weekday = PricingSchedule.isoWeekday(date)
        let kind = holidays.kind(forDay: key)
        // DeepSeek charges every Saturday and Sunday as off-peak, so a PRC make-up working
        // weekend never becomes peak here: only `peakWeekdays` can carry peak windows.
        let peakDay = isActive && peakWeekdays.contains(weekday) && kind != .holiday
        return DaySchedule(key: key,
                           weekday: weekday,
                           kind: kind,
                           intervals: peakDay ? sortedIntervals : [])
    }

    func isPeak(at date: Date) -> Bool {
        let day = daySchedule(for: date)
        guard !day.intervals.isEmpty else { return false }
        let minute = PricingSchedule.minuteOfDayUTC(date)
        return day.intervals.contains { $0.contains(minute: minute) }
    }

    func state(at date: Date) -> PricingState {
        guard discountsEnabled else { return .standard }
        return isPeak(at: date) ? .peak : .offPeak
    }

    /// True when today's answer depends on a holiday that is not on file.
    func isUncertain(at date: Date) -> Bool {
        guard discountsEnabled, intervalsAreValid else { return false }
        let day = daySchedule(for: date)
        return day.kind == .unverified && peakWeekdays.contains(day.weekday)
    }

    /// A plain-language warning when the verified holiday list does not cover this day.
    func calendarWarning(at date: Date) -> String? {
        let key = PricingSchedule.dayKey(date)
        guard !holidays.dates.contains(key), !holidays.covers(key) else { return nil }
        let year = String(key.prefix(4))
        return "Calendar update needed: no verified PRC holiday list covers " + year
            + ", so weekday peaks assume no public holiday."
    }

    struct Transition: Equatable {
        var date: Date
        var becomesPeak: Bool
        var dayKind: DayKind
        var daysAhead: Int
        /// The target day is a weekday whose holiday status is not on file.
        var uncertain: Bool
    }

    /// Next moment the peak/off-peak state flips, searching across days, weekends and holidays.
    func nextTransition(after date: Date, horizonDays: Int = 400) -> Transition? {
        guard isActive else { return nil }
        let todayStart = PricingSchedule.startOfDayUTC(date)
        let limit = max(1, horizonDays)
        for offset in 0...limit {
            guard let dayStart = PricingSchedule.utcCalendar.date(byAdding: .day, value: offset, to: todayStart) else { continue }
            let day = daySchedule(for: dayStart)
            for interval in day.intervals {
                let startCandidate = dayStart.addingTimeInterval(Double(interval.startMinuteUTC * 60))
                if startCandidate > date {
                    return Transition(date: startCandidate,
                                      becomesPeak: true,
                                      dayKind: day.kind,
                                      daysAhead: offset,
                                      uncertain: day.kind == .unverified)
                }
                let endCandidate = dayStart.addingTimeInterval(Double(interval.endMinuteUTC * 60))
                if endCandidate > date {
                    return Transition(date: endCandidate,
                                      becomesPeak: false,
                                      dayKind: day.kind,
                                      daysAhead: offset,
                                      uncertain: day.kind == .unverified)
                }
            }
        }
        return nil
    }

    func segments(for date: Date) -> [ScheduleSegment] {
        guard discountsEnabled else {
            return [ScheduleSegment(startMinute: 0, endMinute: PricingSchedule.minutesPerDay, state: .standard)]
        }
        let day = daySchedule(for: date)
        guard !day.intervals.isEmpty else {
            return [ScheduleSegment(startMinute: 0, endMinute: PricingSchedule.minutesPerDay, state: .offPeak)]
        }
        var result: [ScheduleSegment] = []
        var cursor = 0
        for interval in day.intervals {
            if interval.startMinuteUTC > cursor {
                result.append(ScheduleSegment(startMinute: cursor, endMinute: interval.startMinuteUTC, state: .offPeak))
            }
            result.append(ScheduleSegment(startMinute: interval.startMinuteUTC, endMinute: interval.endMinuteUTC, state: .peak))
            cursor = interval.endMinuteUTC
        }
        if cursor < PricingSchedule.minutesPerDay {
            result.append(ScheduleSegment(startMinute: cursor, endMinute: PricingSchedule.minutesPerDay, state: .offPeak))
        }
        return result
    }

    func outlook(from date: Date, days: Int = 7) -> [DaySchedule] {
        let start = PricingSchedule.startOfDayUTC(date)
        var result: [DaySchedule] = []
        let count = max(0, days)
        for offset in 0..<count {
            guard let day = PricingSchedule.utcCalendar.date(byAdding: .day, value: offset, to: start) else { continue }
            result.append(daySchedule(for: day))
        }
        return result
    }
}

// MARK: - Formatting

enum ClockFormat {
    static func countdown(seconds: Int) -> String {
        let total = max(0, seconds)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        let remaining = total % 60
        if days > 0 {
            return String(days) + "d " + String(hours) + "h " + String(minutes) + "m"
        }
        if hours > 0 {
            return String(hours) + "h " + String(minutes) + "m"
        }
        if minutes > 0 {
            return String(minutes) + "m " + String(format: "%02d", remaining) + "s"
        }
        return String(remaining) + "s"
    }

    static func minuteLabel(_ minute: Int) -> String {
        let clamped = max(0, min(minute, PricingSchedule.minutesPerDay))
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    /// Converts a minute-of-day in UTC into the viewer's local wall clock time.
    static func localLabel(minuteUTC: Int, on reference: Date = Date(), timeZone: TimeZone = .current) -> String {
        let start = PricingSchedule.startOfDayUTC(reference)
        let clamped = max(0, min(minuteUTC, PricingSchedule.minutesPerDay))
        guard let shifted = PricingSchedule.utcCalendar.date(byAdding: .minute, value: clamped, to: start) else {
            return "--:--"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: shifted)
    }

    static func utcStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE d MMM HH:mm"
        return formatter.string(from: date) + " UTC"
    }

    static func localStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "EEE d MMM HH:mm"
        return formatter.string(from: date)
    }

    static func utcDayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: date)
    }

    static func utcTimeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date) + " UTC"
    }

    static func localTimeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func relative(_ date: Date, now: Date = Date()) -> String {
        let delta = max(0, Int(now.timeIntervalSince(date)))
        if delta < 10 { return "just now" }
        if delta < 60 { return String(delta) + "s ago" }
        if delta < 3600 { return String(delta / 60) + "m ago" }
        if delta < 86400 { return String(delta / 3600) + "h ago" }
        return String(delta / 86400) + "d ago"
    }
}

enum MoneyFormat {
    static func rate(_ value: Double) -> String {
        guard value.isFinite else { return "0.00" }
        let text: String
        if value >= 1 {
            text = String(format: "%.2f", value)
        } else if value >= 0.1 {
            text = String(format: "%.3f", value)
        } else {
            text = String(format: "%.4f", value)
        }
        return trim(text)
    }

    static func amount(_ text: String, currency: String) -> String {
        guard let value = decimal(text) else { return text.isEmpty ? "—" : text }
        return symbol(for: currency) + String(format: "%.2f", value)
    }

    static func symbol(for currency: String) -> String {
        switch currency.uppercased() {
        case "CNY", "RMB": return "¥"
        case "USD": return "$"
        default: return currency.uppercased() + " "
        }
    }

    static func decimal(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "")
        return Double(cleaned)
    }

    private static func trim(_ text: String) -> String {
        var result = text
        while result.contains(".") && result.hasSuffix("0") { result.removeLast() }
        if result.hasSuffix(".") { result.append("00") }
        if let dot = result.firstIndex(of: ".") {
            let fraction = result.distance(from: result.index(after: dot), to: result.endIndex)
            if fraction < 2 { result += String(repeating: "0", count: 2 - fraction) }
        } else {
            result += ".00"
        }
        return result
    }
}

// MARK: - Rates

struct TokenRates: Codable, Equatable {
    var cacheHit: Double
    var cacheMiss: Double
    var output: Double

    static let zero = TokenRates(cacheHit: 0, cacheMiss: 0, output: 0)

    func scaled(by factor: Double) -> TokenRates {
        let safeFactor = max(0, factor)
        return TokenRates(cacheHit: cacheHit * safeFactor,
                          cacheMiss: cacheMiss * safeFactor,
                          output: output * safeFactor)
    }
}

enum RateComponent: String, CaseIterable {
    case cacheHit
    case cacheMiss
    case output

    var title: String {
        switch self {
        case .cacheHit: return "Input · cache hit"
        case .cacheMiss: return "Input · cache miss"
        case .output: return "Output"
        }
    }

    func value(in rates: TokenRates) -> Double {
        switch self {
        case .cacheHit: return rates.cacheHit
        case .cacheMiss: return rates.cacheMiss
        case .output: return rates.output
        }
    }
}

struct ModelRate: Codable, Equatable {
    var id: String
    var name: String
    /// Published model build label, for example V4.1-Flash-1017.
    var label: String
    var standard: TokenRates
    var offPeakDiscountPercent: Double

    var clampedDiscount: Double { max(0, min(100, offPeakDiscountPercent)) }

    var offPeak: TokenRates {
        standard.scaled(by: 1 - clampedDiscount / 100)
    }

    func rates(offPeakActive: Bool) -> TokenRates {
        offPeakActive ? offPeak : standard
    }

    var displayName: String {
        label.isEmpty ? name : name + " · " + label
    }
}

enum RateSeeds {

    /// Human-verified against the official pricing page on this date. The app never downloads prices.
    static let verifiedAsOf = "2026-11-06"
    static let sourceURL = "https://api-docs.deepseek.com/quick_start/pricing/"
    static let holidayVerifiedAsOf = "2026-11-06"
    static let holidaySource = "https://english.www.gov.cn/policies/latestreleases/202611/06/content_WS6aed74dcc6d00ca5f9a0e22e.html"
    static let holidaySourceNotes = "PRC State Council holiday notices of 2025-11-04 and 2026-11-05; English official table opened 2026-11-06"

    /// PRC public holidays, inclusive ranges, verified for 2026 and 2027.
    /// 2026: 01-01…01-03, 02-15…02-23, 04-04…04-06, 05-01…05-05, 06-19…06-21, 09-25…09-27, 10-01…10-07.
    /// 2027: 01-01…01-03, 02-05…02-13, 04-03…04-05, 05-01…05-05, 06-09, 09-15, 10-01…10-07.
    static let prcHolidays2026to2027: Set<String> = [
        "2026-01-01", "2026-01-02", "2026-01-03", "2026-02-15", "2026-02-16", "2026-02-17", "2026-02-18", "2026-02-19",
        "2026-02-20", "2026-02-21", "2026-02-22", "2026-02-23", "2026-04-04", "2026-04-05", "2026-04-06", "2026-05-01",
        "2026-05-02", "2026-05-03", "2026-05-04", "2026-05-05", "2026-06-19", "2026-06-20", "2026-06-21", "2026-09-25",
        "2026-09-26", "2026-09-27", "2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04", "2026-10-05", "2026-10-06",
        "2026-10-07", "2027-01-01", "2027-01-02", "2027-01-03", "2027-02-05", "2027-02-06", "2027-02-07", "2027-02-08",
        "2027-02-09", "2027-02-10", "2027-02-11", "2027-02-12", "2027-02-13", "2027-04-03", "2027-04-04", "2027-04-05",
        "2027-05-01", "2027-05-02", "2027-05-03", "2027-05-04", "2027-05-05", "2027-06-09", "2027-09-15", "2027-10-01",
        "2027-10-02", "2027-10-03", "2027-10-04", "2027-10-05", "2027-10-06", "2027-10-07"
    ]

    static let holidays = HolidayCalendar(dates: prcHolidays2026to2027,
                                         coverageStart: "2026-01-01",
                                         coverageEnd: "2027-12-31",
                                         verifiedAsOf: holidayVerifiedAsOf,
                                         source: holidaySource)

    /// USD per 1M tokens. Published standard (peak) prices; the published off-peak prices are
    /// exactly 50% of these for both models.
    static let models: [ModelRate] = [
        ModelRate(id: "deepseek-flash",
                  name: "deepseek-flash",
                  label: "V4.1-Flash-1017",
                  standard: TokenRates(cacheHit: 0.006, cacheMiss: 0.30, output: 1.20),
                  offPeakDiscountPercent: 50),
        ModelRate(id: "deepseek-v4-pro",
                  name: "deepseek-v4-pro",
                  label: "V4-Pro-0813",
                  standard: TokenRates(cacheHit: 0.044, cacheMiss: 1.32, output: 3.96),
                  offPeakDiscountPercent: 50)
    ]

    /// Peak = Monday–Friday 01:00–04:00 and 06:00–10:00 UTC, excluding PRC public holidays.
    static let schedule = PricingSchedule(
        peakWeekdays: [1, 2, 3, 4, 5],
        intervals: [
            PeakInterval(startMinuteUTC: 60, endMinuteUTC: 240),
            PeakInterval(startMinuteUTC: 360, endMinuteUTC: 600)
        ],
        holidays: holidays,
        discountsEnabled: true,
        sourceURL: sourceURL,
        verifiedAsOf: verifiedAsOf)

    static let sourceNote = "Official schedule and prices verified " + verifiedAsOf + " · " + sourceURL
}

// MARK: - Account balance

struct BalanceInfo: Codable, Equatable {
    var currency: String
    var totalBalance: String
    var grantedBalance: String
    var toppedUpBalance: String

    enum CodingKeys: String, CodingKey {
        case currency
        case totalBalance = "total_balance"
        case grantedBalance = "granted_balance"
        case toppedUpBalance = "topped_up_balance"
    }

    var total: Double { MoneyFormat.decimal(totalBalance) ?? 0 }
    var granted: Double { MoneyFormat.decimal(grantedBalance) ?? 0 }
    var toppedUp: Double { MoneyFormat.decimal(toppedUpBalance) ?? 0 }
}

struct BalanceSnapshot: Codable, Equatable {
    var isAvailable: Bool
    var balanceInfos: [BalanceInfo]
    var fetchedAt: Date

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
        case fetchedAt = "fetched_at"
    }

    /// DeepSeek may return more than one currency; USD is preferred, then the first entry.
    var primary: BalanceInfo? {
        balanceInfos.first(where: { $0.currency.uppercased() == "USD" }) ?? balanceInfos.first
    }
}

enum BalanceParser {
    struct LenientText: Decodable, Equatable {
        var text: String

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                text = string
            } else if let number = try? container.decode(Double.self) {
                text = String(number)
            } else {
                text = ""
            }
        }

        init(text: String) { self.text = text }
    }

    private struct RawInfo: Decodable {
        var currency: String?
        var totalBalance: LenientText?
        var grantedBalance: LenientText?
        var toppedUpBalance: LenientText?

        enum CodingKeys: String, CodingKey {
            case currency
            case totalBalance = "total_balance"
            case grantedBalance = "granted_balance"
            case toppedUpBalance = "topped_up_balance"
        }
    }

    private struct RawResponse: Decodable {
        var isAvailable: Bool?
        var balanceInfos: [RawInfo]?

        enum CodingKeys: String, CodingKey {
            case isAvailable = "is_available"
            case balanceInfos = "balance_infos"
        }
    }

    static func snapshot(from data: Data, at date: Date = Date()) -> BalanceSnapshot? {
        guard let raw = try? JSONDecoder().decode(RawResponse.self, from: data) else { return nil }
        let infos = (raw.balanceInfos ?? []).map { info in
            BalanceInfo(currency: (info.currency ?? "").uppercased(),
                        totalBalance: info.totalBalance?.text ?? "",
                        grantedBalance: info.grantedBalance?.text ?? "",
                        toppedUpBalance: info.toppedUpBalance?.text ?? "")
        }
        return BalanceSnapshot(isAvailable: raw.isAvailable ?? false, balanceInfos: infos, fetchedAt: date)
    }
}

// MARK: - Request policy

enum BalanceFetchError: Equatable {
    case missingKey
    case unauthorized
    case rateLimited
    case http(Int)
    case offline(String)
    case invalidResponse(String)

    var message: String {
        switch self {
        case .missingKey:
            return "Add your DeepSeek API key in Settings to load the account balance."
        case .unauthorized:
            return "The API key was rejected (401/403). Check the key in Settings and try again."
        case .rateLimited:
            return "DeepSeek is rate limiting requests (429). Wait a moment, then refresh."
        case .http(let code):
            return "api.deepseek.com returned HTTP " + String(code) + "."
        case .offline(let detail):
            return "Network error: " + detail
        case .invalidResponse(let detail):
            return "Unexpected response: " + detail
        }
    }
}

/// Only this endpoint may receive the API key.
enum RequestPolicy {

    static let balanceEndpoint = "https://api.deepseek.com/user/balance"

    static var balanceURL: URL {
        URL(string: balanceEndpoint)!
    }

    static func normalizedKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isAllowed(url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" else { return false }
        guard let host = url.host?.lowercased(), host == "api.deepseek.com" else { return false }
        return url.path == "/user/balance"
    }

    static func request(apiKey: String, timeout: TimeInterval = 20) -> URLRequest {
        var request = URLRequest(url: balanceURL)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("Bearer " + normalizedKey(apiKey), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// nil when there is no usable key or the endpoint is not the reviewed one.
    static func requestIfValid(apiKey: String) -> URLRequest? {
        let key = normalizedKey(apiKey)
        guard !key.isEmpty, isAllowed(url: balanceURL) else { return nil }
        return request(apiKey: key)
    }

    static func error(forStatus status: Int) -> BalanceFetchError? {
        switch status {
        case 200: return nil
        case 401, 403: return .unauthorized
        case 429: return .rateLimited
        default: return .http(status)
        }
    }
}
