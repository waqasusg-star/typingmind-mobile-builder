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

// MARK: - Old accessory views removed in 1.0.9
//
// PulseInlineView, PulseCircularView, PulseRectangularView and PulseGaugeTint used to live below this
// line. The redesigned Lock Screen lives in WidgetLockScreenViews.swift and
// WidgetLockScreenDialViews.swift, and keeping both copies would duplicate the type names in one
// target. Nothing else referenced the old views.

// MARK: - Old rectangular accessory view removed in 1.0.9
//
// PulseRectangularView and the PulseGaugeTint enum were defined here. The redesigned accessory views
// now live in WidgetLockScreenViews.swift and WidgetLockScreenDialViews.swift; keeping the old copy
// would duplicate those type names inside the extension target.

