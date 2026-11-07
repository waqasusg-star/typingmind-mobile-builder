import Foundation
import WidgetKit
import SwiftUI

// DeepSeek Pulse — the WidgetKit entry point.
//
// Chooses one of the ten designs from the appearance stored in the payload, applies the theme
// gradient, and attaches the deep link. A design that does not belong to the rendered family falls
// back to that family's default, so a stale or hand-edited payload cannot produce a blank widget.

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
        default:
            let requested = appearance.mediumDesign
            return WidgetDesign.mediumFamily.contains(requested) ? requested : .dashboard
        }
    }

    var state: PricingState {
        guard let schedule = entry.envelope.schedule else { return .standard }
        return schedule.state(at: entry.date)
    }

    var body: some View {
        Group {
            if #available(iOSApplicationExtension 16.0, *) {
                content.containerBackgroundPulse(mood: mood, state: state, overlay: mood.rampOverlay)
            } else {
                content.pulseBackground(mood: mood, state: state, overlay: mood.rampOverlay)
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
                    PulseInlineView(entry: entry)
                case .accessoryCircular:
                    PulseCircularView(entry: entry)
                case .accessoryRectangular:
                    PulseRectangularView(entry: entry)
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

@available(iOSApplicationExtension 16.0, *)
struct PulseInlineView: View {
    var entry: PulseEntry

    var body: some View {
        if let target = entry.nextSwitchAt, target > entry.date {
            Text(entry.headline) + Text(" ") + Text(target, style: .timer)
        } else {
            Text(entry.headline + " " + entry.countdownText)
        }
    }
}

@available(iOSApplicationExtension 16.0, *)
struct PulseCircularView: View {
    var entry: PulseEntry

    var body: some View {
        Gauge(value: progress) {
            Text("Peak")
        } currentValueLabel: {
            // A gauge cannot host a ticking Text, so the centre shows the state word rather than a
            // frozen number that would look like a live countdown.
            Text(entry.headline)
                .font(.system(size: 9, weight: .bold))
                .minimumScaleFactor(0.5)
        }
        .gaugeStyle(.accessoryCircular)
        .privacySensitive(true)
    }

    private var progress: Double {
        guard let snapshot = entry.snapshot, snapshot.totalPeakMinutesToday > 0 else { return 0 }
        let elapsed = snapshot.totalPeakMinutesToday - snapshot.peakMinutesLeftToday
        return min(1, max(0, Double(elapsed) / Double(snapshot.totalPeakMinutesToday)))
    }
}

@available(iOSApplicationExtension 16.0, *)
struct PulseRectangularView: View {
    var entry: PulseEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.headline)
                .font(.system(size: 12, weight: .heavy))
            PulseCountdown(entry: entry, size: 17)
            Text(entry.balanceText)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .privacySensitive(true)
    }
}
