import Foundation

// DeepSeek Pulse — the Lock Screen / accessory design model.
//
// Foundation only, compiled into BOTH targets and executed by the widgetkit_v1 harness.
//
// 1.0.9 redesigns the Lock Screen. The old accessory views were a bare gauge, a frozen "--:--" and a
// balance label that could read "No key". The new set is deliberately chosen per accessory family and
// is persisted like the Home Screen designs, so the in-app preview and the real Lock Screen widget
// always agree:
//
//   rectangular  ribbon | ring | compact
//   circular     gauge  | countdown
//   inline       sentence | timeOnly
//
// Every design is described from the same WidgetPlanner snapshot, and none of them can say anything
// about the API key: the accessory slot cannot explain an account, and the wording layer refuses.

enum LockScreenStyle: String, Codable, CaseIterable, Equatable {
    // rectangular
    case ribbon
    case ring
    case compact
    // circular
    case gauge
    case countdown
    // inline
    case sentence
    case timeOnly

    /// Rectangular designs, in picker order.
    static let rectangularFamily: [LockScreenStyle] = [.ribbon, .ring, .compact]
    /// Circular designs, in picker order.
    static let circularFamily: [LockScreenStyle] = [.gauge, .countdown]
    /// Inline designs, in picker order.
    static let inlineFamily: [LockScreenStyle] = [.sentence, .timeOnly]

    static var all: [LockScreenStyle] { rectangularFamily + circularFamily + inlineFamily }

    var family: String {
        if LockScreenStyle.rectangularFamily.contains(self) { return "rectangular" }
        if LockScreenStyle.circularFamily.contains(self) { return "circular" }
        return "inline"
    }

    /// Human name, shown in Widget Studio and in the picker.
    var title: String {
        switch self {
        case .ribbon: return "Ribbon"
        case .ring: return "Ring"
        case .compact: return "Compact"
        case .gauge: return "Gauge"
        case .countdown: return "Countdown"
        case .sentence: return "Sentence"
        case .timeOnly: return "Time only"
        }
    }

    var summary: String {
        switch self {
        case .ribbon: return "State chip, live countdown and a 24-hour band."
        case .ring: return "A progress ring beside the countdown and switch time."
        case .compact: return "Two short lines: state and countdown."
        case .gauge: return "A progress ring with the state word and peak time left."
        case .countdown: return "The countdown alone, as large as the dial allows."
        case .sentence: return "A single line: state, bullet, live countdown."
        case .timeOnly: return "A single line with just the countdown."
        }
    }

    /// Stable two-letter code, used by the in-app previews and the tests.
    var code: String {
        switch self {
        case .ribbon: return "rb"
        case .ring: return "rg"
        case .compact: return "cp"
        case .gauge: return "ga"
        case .countdown: return "cd"
        case .sentence: return "se"
        case .timeOnly: return "to"
        }
    }

    static func style(code: String) -> LockScreenStyle? {
        all.first { $0.code == code }
    }

    static func defaultStyle(forFamily family: String) -> LockScreenStyle {
        switch family {
        case "circular": return .gauge
        case "inline": return .sentence
        default: return .ribbon
        }
    }
}

/// Resolved Lock Screen choices. Stored inside WidgetAppearance, decoded tolerantly, and clamped to
/// the design that belongs to each family so a stale payload cannot blank an accessory slot.
struct LockScreenAppearance: Codable, Equatable {
    var rectangular: LockScreenStyle
    var circular: LockScreenStyle
    var inline: LockScreenStyle

    static let defaultAppearance = LockScreenAppearance(rectangular: .ribbon,
                                                        circular: .gauge,
                                                        inline: .sentence)

    func style(forFamily family: String) -> LockScreenStyle {
        switch family {
        case "circular": return circular
        case "inline": return inline
        default: return rectangular
        }
    }

    mutating func set(_ style: LockScreenStyle) {
        switch style.family {
        case "circular": circular = style
        case "inline": inline = style
        default: rectangular = style
        }
    }

    /// The design currently comparable to `picked`, or nil when the picked design is another family.
    func selected(forFamily family: String) -> LockScreenStyle? {
        let value = style(forFamily: family)
        return value.family == family ? value : nil
    }

    enum CodingKeys: String, CodingKey {
        case rectangular, circular, inline
    }

    init(rectangular: LockScreenStyle, circular: LockScreenStyle, inline: LockScreenStyle) {
        self.rectangular = rectangular.family == "rectangular" ? rectangular : .ribbon
        self.circular = circular.family == "circular" ? circular : .gauge
        self.inline = inline.family == "inline" ? inline : .sentence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = LockScreenAppearance.defaultAppearance
        let rect = (try? container.decodeIfPresent(LockScreenStyle.self, forKey: .rectangular)) ?? defaults.rectangular
        let circ = (try? container.decodeIfPresent(LockScreenStyle.self, forKey: .circular)) ?? defaults.circular
        let line = (try? container.decodeIfPresent(LockScreenStyle.self, forKey: .inline)) ?? defaults.inline
        self.init(rectangular: rect, circular: circ, inline: line)
    }
}

// MARK: - Display strings

/// The exact strings the accessory widgets show. Foundation-only so the app's UIKit preview uses the
/// same words as the real Lock Screen widget instead of an approximation.
enum LockScreenText {

    /// What the live timer is counting down to: "PEAK IN" / "OFF-PEAK IN".
    static func countdownLabel(snapshot: WidgetPlanner.Snapshot, discountsEnabled: Bool) -> String {
        guard discountsEnabled, snapshot.nextSwitchAt != nil else { return "" }
        return snapshot.nextSwitchBecomesPeak ? "PEAK IN" : "OFF-PEAK IN"
    }

    /// The state word for the chip: PEAK / OFF-PEAK / STANDARD.
    static func stateWord(snapshot: WidgetPlanner.Snapshot, discountsEnabled: Bool) -> String {
        WidgetPlanner.headline(snapshot: snapshot, discountsEnabled: discountsEnabled)
    }

    /// Peak time left today, e.g. "3h 20m peak left" or "Peak all day".
    static func peakLeft(minutes: Int) -> String {
        let total = max(0, min(1440, minutes))
        if total == 0 { return "No peak left today" }
        if total == 1440 { return "Peak all day" }
        let hours = total / 60
        let rest = total % 60
        if hours == 0 { return String(rest) + "m peak left" }
        if rest == 0 { return String(hours) + "h peak left" }
        return String(hours) + "h " + String(rest) + "m peak left"
    }

    /// 0...1 share of today's peak minutes that are still ahead.
    static func peakProgress(minutesLeft: Int, totalMinutes: Int) -> Double {
        guard totalMinutes > 0 else { return 0 }
        let clamped = max(0, min(totalMinutes, minutesLeft))
        return Double(clamped) / Double(totalMinutes)
    }

    /// Fallback countdown text when no live timer can be shown.
    static func staticCountdown(snapshot: WidgetPlanner.Snapshot,
                                discountsEnabled: Bool,
                                now: Date) -> String {
        guard discountsEnabled, let target = snapshot.nextSwitchAt else { return "STD" }
        return WidgetPlanner.countdown(from: now, to: target)
    }

    /// Local switch time, e.g. "04:00".
    static func switchTime(snapshot: WidgetPlanner.Snapshot, timeZone: TimeZone = .current) -> String {
        guard let target = snapshot.nextSwitchAt else { return "" }
        return ClockFormat.localTimeLabel(target, timeZone: timeZone)
    }

    /// Whether the data behind the accessory widget is old enough to matter on the Lock Screen.
    static func dataFlag(state: WidgetDataState) -> String? {
        switch state {
        case .fresh: return nil
        case .stale: return "CACHED"
        case .empty, .groupUnavailable: return "OPEN APP"
        case .incompatible, .corrupt: return "OPEN APP"
        }
    }
}
