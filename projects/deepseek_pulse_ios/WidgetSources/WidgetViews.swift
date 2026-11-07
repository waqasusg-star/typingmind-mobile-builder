import Foundation
import WidgetKit
import SwiftUI

// DeepSeek Pulse — the WidgetKit entry point.
//
// It picks the design saved in Widget Studio for the current widget family, resolves the theme, and
// hands everything to that design's view. A saved design that does not belong to the family falls
// back to the family default, so a stale payload cannot produce an empty widget.
//
// 1.0.7 rebuilds the three Lock Screen accessory families. They previously drew a bare gauge with a
// tiny state word, a frozen-looking "--:--" and `entry.balanceText`, which printed "No key" in a
// slot nobody could act on. The accessory views are now:
//   * inline      a compact "OFF-PEAK 3h 12m" sentence using the iOS-rendered timer
//   * circular    a progress ring with the state word and the peak time left
//   * rectangular a two-column card: state + level on the left, live countdown and switch time on the
//                 right
// None of them claims a key is missing: the accessory slot is too small to explain an account, so
// the balance is not shown there at all.

struct WidgetEntryView: View {
    var entry: PulseEntry
    @Environment(\.widgetFamily) private var family

    private var appearance: WidgetAppearance { entry.envelope.appearance }
    private var mood: PulseMood { PulseMood(appearance: appearance) }

    /// The design this size should draw.
    var design: WidgetDesign {
        switch family {
        case .systemSmall:
            let requested = appearance.smallDesign
            return WidgetDesign.smallFamily.contains(requested) ? requested : .aurora
        case .systemMedium:
            let requested = appearance.mediumDesign
            return WidgetDesign.mediumFamily.contains(requested) ? requested : .dashboard
        default:
            return .dashboard
        }
    }

    var state: PricingState {
        guard let schedule = entry.envelope.schedule else { return .standard }
        return schedule.state(at: entry.date)
    }

    var body: some View {
        Group {
            if #available(iOSApplicationExtension 16.0, *) {
                content.containerBackgroundPulse(mood: mood,
                                                 state: state,
                                                 artwork: appearance.artwork,
                                                 overlay: mood.rampOverlay)
            } else {
                content.pulseThemedBackground(mood: mood,
                                              state: state,
                                              artwork: appearance.artwork,
                                              overlay: mood.rampOverlay)
            }
        }
        .widgetURL(WidgetPolicy.deepLinkURL())
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall:
            smallContent
        case .systemMedium:
            mediumContent
        default:
            if #available(iOSApplicationExtension 16.0, *) {
                switch family {
                case .accessoryInline:
                    PulseAccessoryInline(entry: entry, style: appearance.lockScreen.inline)
                case .accessoryCircular:
                    PulseAccessoryCircular(entry: entry, style: appearance.lockScreen.circular)
                case .accessoryRectangular:
                    PulseAccessoryRectangular(entry: entry, style: appearance.lockScreen.rectangular)
                default:
                    mediumContent
                }
            } else {
                mediumContent
            }
        }
    }

    @ViewBuilder
    private var smallContent: some View {
        switch design {
        case .vault:
            PulseVaultView(entry: entry, mood: mood, appearance: appearance)
        case .splitColumn:
            PulseSplitColumnView(entry: entry, mood: mood, appearance: appearance)
        case .ring:
            PulseRingView(entry: entry, mood: mood, appearance: appearance)
        case .timeline:
            PulseTimelineView(entry: entry, mood: mood, appearance: appearance)
        default:
            PulseAuroraView(entry: entry, mood: mood, appearance: appearance)
        }
    }

    @ViewBuilder
    private var mediumContent: some View {
        switch design {
        case .ledger:
            PulseLedgerView(entry: entry, mood: mood, appearance: appearance)
        case .countdownHero:
            PulseCountdownHeroView(entry: entry, mood: mood, appearance: appearance)
        case .bandHero:
            PulseBandHeroView(entry: entry, mood: mood, appearance: appearance)
        case .minimal:
            PulseMinimalView(entry: entry, mood: mood, appearance: appearance)
        default:
            PulseDashboardView(entry: entry, mood: mood, appearance: appearance)
        }
    }
}

// MARK: - Lock Screen accessories (iOS 16+ only)
//
// iOS renders these in its own vibrant, monochrome material. They therefore use primary / secondary
// foreground styles, a single accent for the ring, and no palette colours: a themed gradient here
// would be flattened by the system and would only look muddy.

/// One line beside the Lock Screen clock.
@available(iOSApplicationExtension 16.0, *)
struct PulseInlineView: View {
    var entry: PulseEntry

    var body: some View {
        if let target = entry.nextSwitchAt, target > entry.date {
            // A view that contains a timer Text is never redrawn by WidgetKit mid-interval, so the
            // seconds keep ticking on their own.
            (Text(entry.headline).fontWeight(.bold)
                + Text("  \u{00b7}  ")
                + Text(target, style: .timer))
        } else {
            (Text(entry.headline).fontWeight(.bold)
                + Text("  ")
                + Text(entry.countdownText))
        }
    }
}

/// The ring beside the clock.
@available(iOSApplicationExtension 16.0, *)
struct PulseCircularView: View {
    var entry: PulseEntry

    var body: some View {
        Gauge(value: entry.peakProgress) {
            // The Gauge label is only read by VoiceOver; the visible centre is the state word.
            Text("Peak share of the day")
        } currentValueLabel: {
            VStack(spacing: -1) {
                Text(entry.shortStateWord)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(entry.peakLeftText)
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
        }
        .gaugeStyle(.accessoryCircular)
        .tint(PulseGaugeTint.tint(entry: entry))
        .privacySensitiveIfAvailable()
        .accessibilityLabel(entry.headline + ", " + entry.peakLeftText + " of peak left today")
    }
}

/// The wide card below the clock.
@available(iOSApplicationExtension 16.0, *)
struct PulseRectangularView: View {
    var entry: PulseEntry

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            // Left: the pricing state and what the countdown is counting to.
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.headline)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(entry.countdownLabel.uppercased())
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            // Right: the live countdown, then when the switch lands in local time.
            VStack(alignment: .trailing, spacing: 0) {
                PulseCountdown(entry: entry, size: 19, weight: .bold, ink: .primary)
                Text(entry.switchClockText)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .privacySensitiveIfAvailable()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entry.headline + ". " + entry.countdownLabel + " " + entry.countdownText)
    }
}

/// Tint for the circular gauge: peak and off-peak read differently at a glance, but both stay inside
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
