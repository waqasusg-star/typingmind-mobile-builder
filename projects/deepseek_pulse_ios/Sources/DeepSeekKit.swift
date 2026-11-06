import Foundation

// MARK: - Peak / off-peak schedule

/// One contiguous band of the 24 hour UTC day.
struct ScheduleSegment: Equatable {
    var startMinute: Int
    var endMinute: Int
    var isOffPeak: Bool
}

/// The documented DeepSeek off-peak discount window, expressed in UTC minutes.
/// Minutes are counted from 00:00 UTC, `endMinuteUTC` is exclusive.
struct PeakWindow: Codable, Equatable {
    var startMinuteUTC: Int
    var endMinuteUTC: Int
    var discountEnabled: Bool

    static let minutesPerDay = 1440
    static let secondsPerDay = 86400

    /// 16:30 UTC to 00:30 UTC, the published off-peak discount window.
    static let seeded = PeakWindow(startMinuteUTC: 16 * 60 + 30, endMinuteUTC: 30, discountEnabled: true)

    static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone(identifier: "UTC")!
        return calendar
    }

    static func minuteOfDayUTC(_ date: Date) -> Int {
        let parts = utcCalendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    static func secondsOfDayUTC(_ date: Date) -> Int {
        let parts = utcCalendar.dateComponents([.hour, .minute, .second], from: date)
        return (parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60 + (parts.second ?? 0)
    }

    static func isValid(minute: Int) -> Bool {
        minute >= 0 && minute < minutesPerDay
    }

    /// A schedule is only usable when it is switched on and both edges are real times of day.
    var isActive: Bool {
        discountEnabled
            && startMinuteUTC != endMinuteUTC
            && PeakWindow.isValid(minute: startMinuteUTC)
            && PeakWindow.isValid(minute: endMinuteUTC)
    }

    var wrapsMidnight: Bool { startMinuteUTC > endMinuteUTC }

    func isOffPeak(at date: Date) -> Bool {
        guard isActive else { return false }
        let minute = PeakWindow.minuteOfDayUTC(date)
        if wrapsMidnight {
            return minute >= startMinuteUTC || minute < endMinuteUTC
        }
        return minute >= startMinuteUTC && minute < endMinuteUTC
    }

    func stateLabel(at date: Date) -> String {
        guard isActive else { return "STANDARD" }
        return isOffPeak(at: date) ? "OFF-PEAK" : "PEAK"
    }

    /// The next moment the peak/off-peak state flips, strictly in the future.
    func nextTransition(after date: Date) -> (date: Date, becomesOffPeak: Bool)? {
        guard isActive else { return nil }
        let nowSeconds = PeakWindow.secondsOfDayUTC(date)
        var bestSeconds = Int.max
        var best: (date: Date, becomesOffPeak: Bool)?
        for (minute, becomesOffPeak) in [(startMinuteUTC, true), (endMinuteUTC, false)] {
            var delta = minute * 60 - nowSeconds
            if delta <= 0 { delta += PeakWindow.secondsPerDay }
            if delta < bestSeconds {
                bestSeconds = delta
                best = (date.addingTimeInterval(Double(delta)), becomesOffPeak)
            }
        }
        return best
    }

    /// Bands covering the whole day, used by the timeline bar.
    func segments() -> [ScheduleSegment] {
        guard isActive else {
            return [ScheduleSegment(startMinute: 0, endMinute: PeakWindow.minutesPerDay, isOffPeak: false)]
        }
        if wrapsMidnight {
            return [
                ScheduleSegment(startMinute: 0, endMinute: endMinuteUTC, isOffPeak: true),
                ScheduleSegment(startMinute: endMinuteUTC, endMinute: startMinuteUTC, isOffPeak: false),
                ScheduleSegment(startMinute: startMinuteUTC, endMinute: PeakWindow.minutesPerDay, isOffPeak: true)
            ]
        }
        return [
            ScheduleSegment(startMinute: 0, endMinute: startMinuteUTC, isOffPeak: false),
            ScheduleSegment(startMinute: startMinuteUTC, endMinute: endMinuteUTC, isOffPeak: true),
            ScheduleSegment(startMinute: endMinuteUTC, endMinute: PeakWindow.minutesPerDay, isOffPeak: false)
        ]
    }

    func offPeakDurationMinutes() -> Int {
        segments().reduce(0) { $0 + ($1.isOffPeak ? $1.endMinute - $1.startMinute : 0) }
    }
}

// MARK: - Formatting

enum ClockFormat {
    static func countdown(seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remaining = total % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m " + String(format: "%02d", remaining) + "s" }
        return "\(remaining)s"
    }

    static func minuteLabel(_ minute: Int) -> String {
        let clamped = max(0, min(minute, PeakWindow.minutesPerDay))
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    /// Converts a minute-of-day in UTC into the viewer's local wall clock time.
    static func localLabel(minuteUTC: Int, on reference: Date = Date(), timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone(identifier: "UTC")!
        let start = calendar.startOfDay(for: reference)
        guard let shifted = calendar.date(byAdding: .minute, value: max(0, min(minuteUTC, PeakWindow.minutesPerDay)), to: start) else {
            return "--:--"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: shifted)
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
        if delta < 60 { return "\(delta)s ago" }
        if delta < 3600 { return "\(delta / 60)m ago" }
        if delta < 86400 { return "\(delta / 3600)h ago" }
        return "\(delta / 86400)d ago"
    }
}

enum MoneyFormat {
    static func rate(_ value: Double) -> String {
        guard value.isFinite else { return "0.00" }
        let text: String
        if value >= 1 { text = String(format: "%.2f", value) }
        else if value >= 0.1 { text = String(format: "%.3f", value) }
        else { text = String(format: "%.4f", value) }
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
        return TokenRates(cacheHit: cacheHit * safeFactor, cacheMiss: cacheMiss * safeFactor, output: output * safeFactor)
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
    var standard: TokenRates
    var offPeakDiscountPercent: Double

    var clampedDiscount: Double { max(0, min(100, offPeakDiscountPercent)) }

    var offPeak: TokenRates {
        standard.scaled(by: 1 - clampedDiscount / 100)
    }

    func rates(offPeakActive: Bool) -> TokenRates {
        offPeakActive ? offPeak : standard
    }
}

enum RateSeeds {
    /// USD per 1M tokens, taken from DeepSeek's published standard (peak) schedule together with
    /// the 50% / 75% off-peak discounts. Local editable defaults only: confirm on
    /// https://api-docs.deepseek.com/quick_start/pricing and correct them in Settings → Rates.
    static let models: [ModelRate] = [
        ModelRate(id: "deepseek-chat",
                  name: "deepseek-chat",
                  standard: TokenRates(cacheHit: 0.07, cacheMiss: 0.27, output: 1.10),
                  offPeakDiscountPercent: 50),
        ModelRate(id: "deepseek-reasoner",
                  name: "deepseek-reasoner",
                  standard: TokenRates(cacheHit: 0.14, cacheMiss: 0.55, output: 2.19),
                  offPeakDiscountPercent: 75)
    ]

    static let sourceNote = "Seeded defaults — verify on api-docs.deepseek.com/quick_start/pricing"
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
