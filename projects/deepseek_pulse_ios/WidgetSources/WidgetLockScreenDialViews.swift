import Foundation
import SwiftUI
import WidgetKit

// DeepSeek Pulse — the two circular and two inline Lock Screen designs (iOS 16+).
//
// Split from WidgetLockScreenViews.swift only to keep each file small; both files belong to the same
// accessory design set and share LockScreenText and PulseGaugeTint.

/// Circular: gauge (state word + peak time left) or countdown (the timer alone).
@available(iOSApplicationExtension 16.0, *)
struct PulseAccessoryCircular: View {
    var entry: PulseEntry
    var style: LockScreenStyle

    var body: some View {
        switch style {
        case .countdown:
            countdownStyle
        default:
            gaugeStyle
        }
    }

    private var gaugeStyle: some View {
        Gauge(value: progress) {
            // Only VoiceOver reads the label; the visible centre is the state word.
            Text("Peak share of the day")
        } currentValueLabel: {
            VStack(spacing: -1) {
                Text(entry.shortStateWord)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(peakLeftShort)
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
        }
        .gaugeStyle(.accessoryCircular)
        .tint(PulseGaugeTint.tint(entry: entry))
        .privacySensitiveIfAvailable()
        .accessibilityLabel(entry.headline + ", " + LockScreenText.peakLeft(minutes: entry.snapshot?.peakMinutesLeftToday ?? 0))
    }

    private var countdownStyle: some View {
        Gauge(value: progress) {
            Text("Countdown")
        } currentValueLabel: {
            if let target = entry.nextSwitchAt, target > entry.date {
                Text(target, style: .timer)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            } else {
                Text(entry.countdownText)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
        }
        .gaugeStyle(.accessoryCircular)
        .tint(PulseGaugeTint.tint(entry: entry))
        .privacySensitiveIfAvailable()
        .accessibilityLabel(entry.countdownLabel + " " + entry.countdownText)
    }

    private var progress: Double {
        guard let snapshot = entry.snapshot else { return 0 }
        return LockScreenText.peakProgress(minutesLeft: snapshot.peakMinutesLeftToday,
                                           totalMinutes: snapshot.totalPeakMinutesToday)
    }

    private var peakLeftShort: String {
        let minutes = entry.snapshot?.peakMinutesLeftToday ?? 0
        if minutes == 0 { return "none" }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return String(rest) + "m" }
        if rest == 0 { return String(hours) + "h" }
        return String(hours) + "h" + String(rest)
    }
}

/// Inline: one line beside the Lock Screen clock.
@available(iOSApplicationExtension 16.0, *)
struct PulseAccessoryInline: View {
    var entry: PulseEntry
    var style: LockScreenStyle

    var body: some View {
        switch style {
        case .timeOnly:
            timeOnly
        default:
            sentence
        }
    }

    private var sentence: some View {
        Group {
            if let target = entry.nextSwitchAt, target > entry.date {
                Text(entry.headline).fontWeight(.bold) + Text("  \u{00b7}  ") + Text(target, style: .timer)
            } else {
                Text(entry.headline).fontWeight(.bold) + Text("  \u{00b7}  ") + Text(entry.countdownText)
            }
        }
        .privacySensitiveIfAvailable()
    }

    private var timeOnly: some View {
        Group {
            if let target = entry.nextSwitchAt, target > entry.date {
                Text(target, style: .timer).monospacedDigit()
            } else {
                Text(entry.countdownText).monospacedDigit()
            }
        }
        .privacySensitiveIfAvailable()
    }
}

/// Tint for the circular gauges: peak and off-peak read differently at a glance, and both stay inside
/// the system material.
@available(iOSApplicationExtension 16.0, *)
enum PulseGaugeTint {
    static func tint(entry: PulseEntry) -> Color {
        guard let schedule = entry.envelope.schedule else { return .gray }
        switch schedule.state(at: entry.date) {
        case .peak: return .orange
        case .offPeak: return .green
        case .standard: return .gray
        }
    }
}
