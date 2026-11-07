import Foundation
import WidgetKit
import SwiftUI

// DeepSeek Pulse — shared WidgetKit pieces: theme colours, countdown, balance, refresh, band.
//
// Ten designs are built from these parts. Colours come from the theme inside the payload, so the
// widget follows the palette chosen in Widget Studio.
//
// 1.0.7 changes:
//   * the band colours come from the palette and the current state instead of two hard-coded values;
//   * the balance line renders the honest wording from PulseBalanceWording rather than a raw
//     "No key", and keeps the number visible whenever a real balance exists;
//   * the status badge exposes an explanation to VoiceOver instead of only a CACHED tag.

// MARK: - Theme

/// SwiftUI colours for one theme, plus the on-colour for text over the gradient.
struct PulseMood {
    let theme: PulseTheme

    init(appearance: WidgetAppearance) {
        self.theme = appearance.theme
    }

    static func colour(_ value: PulseRGB) -> Color {
        Color(red: value.r, green: value.g, blue: value.b)
    }

    func stop(_ ramp: PulseRamp) -> [Color] {
        [PulseMood.colour(ramp.top), PulseMood.colour(ramp.middle), PulseMood.colour(ramp.bottom)]
    }

    func gradient(for state: PricingState) -> LinearGradient {
        LinearGradient(colors: stop(theme.ramp(for: state)),
                       startPoint: .topLeading,
                       endPoint: .bottomTrailing)
    }

    /// White ink on every dark ramp; the light ramps get a darkening overlay first.
    var ink: Color { Color.white }

    /// Darkening applied over a light ramp so white text keeps contrast.
    var rampOverlay: Double {
        PulseThemes.luminance(theme.background) > 0.55 ? 0.34 : 0.0
    }

    /// Band colour for a pricing state, taken from the palette so every theme colours its own band.
    func bandColour(for state: PricingState) -> Color {
        switch state {
        case .peak: return PulseMood.colour(theme.peak).opacity(0.95)
        case .offPeak: return PulseMood.colour(theme.offPeak).opacity(0.95)
        case .standard: return Color.white.opacity(0.28)
        }
    }
}

// MARK: - Shared pieces

/// Self-updating countdown. Falls back to a static, honest label when there is no target.
struct PulseCountdown: View {
    var entry: PulseEntry
    var size: CGFloat
    var weight: Font.Weight = .bold
    var ink: Color = .white

    var body: some View {
        if let target = entry.nextSwitchAt, target > entry.date {
            Text(target, style: .timer)
                .font(.system(size: size, weight: weight, design: .rounded))
                .foregroundColor(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        } else {
            Text(entry.countdownText)
                .font(.system(size: size, weight: weight, design: .rounded))
                .foregroundColor(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }
}

/// The caption above the countdown: "Off-peak in", "Peak in", or nothing.
struct PulseCountdownCaption: View {
    var entry: PulseEntry
    var size: CGFloat = 9
    var ink: Color = .white

    var body: some View {
        let label = entry.countdownLabel
        if !label.isEmpty {
            Text(label.uppercased())
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(ink.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

/// The balance slot plus how old it is, or what to do next when there is no balance.
///
/// This is the one place the Home Screen widgets word the account. `entry.balanceText` already
/// routes through PulseBalanceWording, so a widget can never print "No key" for a snapshot whose key
/// state is simply unknown.
struct PulseBalanceLine: View {
    var entry: PulseEntry
    var size: CGFloat = 13
    var captionSize: CGFloat = 9
    var showCaption: Bool = true
    var ink: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.balanceText)
                .font(.system(size: entry.hasBalance ? size : size * 0.85,
                              weight: .semibold,
                              design: .rounded))
                .foregroundColor(ink.opacity(entry.hasBalance ? 0.94 : 0.80))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityLabel(entry.hasBalance
                                    ? "Available balance " + entry.balanceText
                                    : entry.balanceText)
            if showCaption {
                Text(entry.balanceCaption)
                    .font(.system(size: captionSize, weight: .medium))
                    .foregroundColor(ink.opacity(0.62))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

/// The refresh affordance.
///
/// A WidgetKit widget cannot run code on tap, but iOS does open the widgetURL. This pill therefore
/// says exactly what it does: tapping anywhere on the widget opens DeepSeek Pulse, which refreshes
/// the balance and rewrites the snapshot. No request is invented on the Home Screen.
struct PulseRefreshAffordance: View {
    var size: CGFloat = 15
    var ink: Color = .white

    var body: some View {
        Image(systemName: "arrow.clockwise")
            .font(.system(size: size, weight: .bold))
            .foregroundColor(ink.opacity(0.9))
            .padding(4)
            .background(ink.opacity(0.16))
            .clipShape(Circle())
            .accessibilityLabel("Tap the widget to open DeepSeek Pulse and refresh the balance")
    }
}

/// Small honest badge for a data state that is not simply fresh.
struct PulseStatusBadge: View {
    var entry: PulseEntry
    var ink: Color = .white

    var body: some View {
        if entry.envelope.state == .fresh {
            EmptyView()
        } else {
            Text(entry.envelope.state.shortLabel)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(ink)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.32))
                .clipShape(Capsule())
                .privacySensitiveIfAvailable()
                .accessibilityLabel(entry.envelope.state.explainer)
        }
    }
}

/// The 24-hour band, drawn from the same intervals the app uses.
struct PulseDayBand: View {
    var schedule: PricingSchedule
    var date: Date
    var barHeight: CGFloat = 8
    var mood: PulseMood?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { pair in
                        Rectangle()
                            .fill(colour(for: pair.element.state))
                            .frame(width: width(for: pair.element, total: geometry.size.width))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: barHeight / 2, style: .continuous))
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 1.5, height: barHeight)
                    .offset(x: nowOffset(total: geometry.size.width))
            }
            .frame(height: barHeight)
        }
        .frame(height: barHeight)
    }

    private var segments: [ScheduleSegment] {
        schedule.segments(for: date)
    }

    private func colour(for state: PricingState) -> Color {
        if let mood = mood {
            return mood.bandColour(for: state)
        }
        switch state {
        case .peak: return Color(red: 0.98, green: 0.58, blue: 0.13)
        case .offPeak: return Color(red: 0.18, green: 0.72, blue: 0.50)
        case .standard: return Color.white.opacity(0.28)
        }
    }

    private func width(for segment: ScheduleSegment, total: CGFloat) -> CGFloat {
        let fraction = CGFloat(max(0, segment.endMinute - segment.startMinute)) / CGFloat(PricingSchedule.minutesPerDay)
        return max(0.5, total * fraction)
    }

    private func nowOffset(total: CGFloat) -> CGFloat {
        let minute = PricingSchedule.minuteOfDayUTC(date)
        return total * CGFloat(minute) / CGFloat(PricingSchedule.minutesPerDay)
    }
}

/// A tiny statistic for the layouts that summarise more than one number.
struct PulseStat: View {
    var title: String
    var value: String
    var ink: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(ink.opacity(0.6))
                .lineLimit(1)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(ink.opacity(0.94))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

// MARK: - Backgrounds

extension View {
    /// Pre-iOS 17 background for Home Screen widget containers.
    func pulseBackground(mood: PulseMood, state: PricingState, overlay: Double) -> some View {
        self.background(PulseWidgetBackdrop(mood: mood,
                                           state: state,
                                           artwork: "gradient",
                                           overlay: overlay))
    }

    /// 1.0.9: the themed background, including the artwork layer chosen in Widget Studio.
    func pulseThemedBackground(mood: PulseMood, state: PricingState, artwork: String, overlay: Double) -> some View {
        self.background(PulseWidgetBackdrop(mood: mood, state: state, artwork: artwork, overlay: overlay))
    }

    /// iOS 17+ wants the container background declared through the modifier; without it the gallery
    /// shows an "adopt container background" placeholder instead of the widget.
    @ViewBuilder
    func containerBackgroundPulse(mood: PulseMood, state: PricingState, overlay: Double) -> some View {
        containerBackgroundPulse(mood: mood, state: state, artwork: "gradient", overlay: overlay)
    }

    /// 1.0.9: themed container background, with the artwork layer.
    @ViewBuilder
    func containerBackgroundPulse(mood: PulseMood,
                                  state: PricingState,
                                  artwork: String,
                                  overlay: Double) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            self.containerBackground(for: .widget) {
                PulseWidgetBackdrop(mood: mood, state: state, artwork: artwork, overlay: overlay)
            }
        } else {
            self.pulseThemedBackground(mood: mood, state: state, artwork: artwork, overlay: overlay)
        }
    }

    /// Marks content privacy sensitive from iOS 16 on; a no-op on iOS 15 so the target stays 15.
    @ViewBuilder
    func privacySensitiveIfAvailable() -> some View {
        if #available(iOSApplicationExtension 16.0, *) {
            self.privacySensitive(true)
        } else {
            self
        }
    }
}

// MARK: - Entry helpers used by the Lock Screen views

extension PulseEntry {

    /// "PEAK", "OFF" or "STD" - short enough for a circular complication.
    var shortStateWord: String {
        switch headline {
        case "OFF-PEAK": return "OFF"
        default: return headline
        }
    }
}
