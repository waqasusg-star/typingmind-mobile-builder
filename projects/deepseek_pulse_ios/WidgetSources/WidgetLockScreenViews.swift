import Foundation
import SwiftUI
import WidgetKit

// DeepSeek Pulse — the trio of Lock Screen accessory designs (iOS 16+).
//
// iOS renders accessory widgets in its own vibrant, monochrome material: palette colours are
// flattened, so these views use primary/secondary styles plus one accent for the progress ring, and
// they deliberately never mention the API key or the balance. The chosen design comes from
// LockScreenAppearance in the saved appearance, so the in-app preview and the real widget agree.

@available(iOSApplicationExtension 16.0, *)
struct PulseAccessoryRectangular: View {
    var entry: PulseEntry
    var style: LockScreenStyle

    private var snapshot: WidgetPlanner.Snapshot? { entry.snapshot }

    var body: some View {
        switch style {
        case .ring:
            ringStyle
        case .compact:
            compactStyle
        default:
            ribbonStyle
        }
    }

    /// Ribbon: state on the left, live countdown on the right, the day band underneath.
    private var ribbonStyle: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(entry.headline)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Text(entry.countdownLabel.uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                accessoryCountdown(size: 21)
                Spacer(minLength: 0)
                if let flag = LockScreenText.dataFlag(state: entry.envelope.state) {
                    Text(flag)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                } else {
                    Text(entry.switchClockText)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            if let schedule = entry.envelope.schedule {
                AccessoryBand(schedule: schedule, date: entry.date)
                    .frame(height: 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .privacySensitiveIfAvailable()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    /// Ring: a progress ring beside the state, countdown and switch time.
    private var ringStyle: some View {
        HStack(spacing: 8) {
            accessoryGauge(diameter: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.headline)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                accessoryCountdown(size: 18)
                Text(entry.switchClockText)
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .privacySensitiveIfAvailable()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    /// Compact: two short lines, for a busy Lock Screen.
    private var compactStyle: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                Text(entry.headline)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let flag = LockScreenText.dataFlag(state: entry.envelope.state) {
                    Text(flag)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
            }
            accessoryCountdown(size: 19)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .privacySensitiveIfAvailable()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    @ViewBuilder
    private func accessoryCountdown(size: CGFloat) -> some View {
        // A Text(.timer) keeps ticking without a new timeline entry, which is what makes the Lock
        // Screen widget feel live between refreshes.
        if let target = entry.nextSwitchAt, target > entry.date {
            Text(target, style: .timer)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        } else {
            Text(entry.countdownText)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    @ViewBuilder
    private func accessoryGauge(diameter: CGFloat) -> some View {
        if let snapshot = snapshot {
            Gauge(value: LockScreenText.peakProgress(minutesLeft: snapshot.peakMinutesLeftToday,
                                                     totalMinutes: snapshot.totalPeakMinutesToday)) {
                EmptyView()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(PulseGaugeTint.tint(entry: entry))
            .frame(width: diameter, height: diameter)
        } else {
            Image(systemName: "dial.medium")
                .font(.system(size: diameter * 0.7, weight: .semibold))
        }
    }

    private var accessibilitySummary: String {
        var parts = [entry.headline]
        if !entry.countdownLabel.isEmpty { parts.append(entry.countdownLabel) }
        parts.append(entry.countdownText)
        if !entry.switchClockText.isEmpty { parts.append("Switch at " + entry.switchClockText) }
        if let snapshot = snapshot {
            parts.append(LockScreenText.peakLeft(minutes: snapshot.peakMinutesLeftToday))
        }
        return parts.joined(separator: ", ")
    }
}

/// The 24-hour band in monochrome, sized for an accessory slot.
@available(iOSApplicationExtension 16.0, *)
struct AccessoryBand: View {
    var schedule: PricingSchedule
    var date: Date

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.16))
                HStack(spacing: 0) {
                    ForEach(Array(schedule.segments(for: date).enumerated()), id: \.offset) { pair in
                        Rectangle()
                            .fill(colour(for: pair.element.state))
                            .frame(width: width(for: pair.element, total: geometry.size.width))
                    }
                }
                .clipShape(Capsule())
                Capsule()
                    .fill(Color.primary)
                    .frame(width: 2)
                    .offset(x: min(max(0, geometry.size.width - 2), nowOffset(total: geometry.size.width)))
            }
        }
    }

    private func colour(for state: PricingState) -> Color {
        switch state {
        case .peak: return Color.primary.opacity(0.85)
        case .offPeak: return Color.primary.opacity(0.5)
        case .standard: return Color.primary.opacity(0.28)
        }
    }

    private func width(for segment: ScheduleSegment, total: CGFloat) -> CGFloat {
        let fraction = CGFloat(max(0, segment.endMinute - segment.startMinute)) / CGFloat(PricingSchedule.minutesPerDay)
        return max(0.5, total * fraction)
    }

    private func nowOffset(total: CGFloat) -> CGFloat {
        total * CGFloat(PricingSchedule.minuteOfDayUTC(date)) / CGFloat(PricingSchedule.minutesPerDay)
    }
}
