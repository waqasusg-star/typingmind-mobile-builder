import Foundation
import WidgetKit
import SwiftUI

// DeepSeek Pulse — real WidgetKit SwiftUI views.
//
// These are WidgetKit views, not the UIKit preview cards in Sources/Widget*CardView.swift.
// The UIKit cards stay in the app as Widget Studio previews; this file is the Home Screen and
// Lock Screen UI that iOS actually renders.

struct WidgetEntryView: View {
    var entry: PulseEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                PulseSmallView(entry: entry)
            case .systemMedium:
                PulseMediumView(entry: entry)
            case .accessoryInline:
                PulseInlineView(entry: entry)
            case .accessoryCircular:
                PulseCircularView(entry: entry)
            case .accessoryRectangular:
                PulseRectangularView(entry: entry)
            default:
                PulseMediumView(entry: entry)
            }
        }
        .widgetURL(WidgetPolicy.deepLinkURL())
    }

    /// Gradient per pricing state, shared with the timeline provider.
    static func palette(for state: PricingState) -> [Color] {
        switch state {
        case .peak:
            return [Color(red: 0.98, green: 0.58, blue: 0.13), Color(red: 0.32, green: 0.16, blue: 0.06)]
        case .offPeak:
            return [Color(red: 0.18, green: 0.72, blue: 0.50), Color(red: 0.05, green: 0.24, blue: 0.20)]
        case .standard:
            return [Color(red: 0.30, green: 0.42, blue: 0.99), Color(red: 0.07, green: 0.10, blue: 0.18)]
        }
    }

    static func currentState(_ entry: PulseEntry) -> PricingState {
        guard let schedule = entry.envelope.schedule else { return .standard }
        return schedule.state(at: entry.date)
    }
}

// MARK: - Small

struct PulseSmallView: View {
    var entry: PulseEntry

    var body: some View {
        let state = WidgetEntryView.currentState(entry)
        VStack(alignment: .leading, spacing: 4) {
            Text("DeepSeek")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.85))
            Text(entry.headline)
                .font(.system(size: 15, weight: .heavy))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(entry.countdownText)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            Text(entry.envelope.balanceLine())
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.92))
                .lineLimit(1)
            StatusBadge(envelope: entry.envelope)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .pulseBackground(state: state)
    }
}

// MARK: - Medium

struct PulseMediumView: View {
    var entry: PulseEntry

    var body: some View {
        let state = WidgetEntryView.currentState(entry)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("DEEPSEEK PULSE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                Text(entry.headline)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.18))
                    .clipShape(Capsule())
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(entry.countdownText)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(entry.envelope.balanceLine())
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(1)
            }
            if let schedule = entry.envelope.schedule {
                PulseDayBand(schedule: schedule, date: entry.date)
                    .frame(height: 10)
            }
            Text(entry.footnote)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.72))
                .lineLimit(2)
            Spacer(minLength: 0)
            HStack {
                Text(entry.envelope.balanceCaption(now: entry.date))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
                Spacer()
                StatusBadge(envelope: entry.envelope)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .pulseBackground(state: state)
    }
}

// MARK: - Lock Screen accessories (iOS 16+; deployment target stays iOS 15)

struct PulseInlineView: View {
    var entry: PulseEntry

    var body: some View {
        // Inline text on the Lock Screen. iOS renders this in its own monochrome style.
        Text(entry.headline + " " + entry.countdownText)
    }
}

struct PulseCircularView: View {
    var entry: PulseEntry

    var body: some View {
        Gauge(value: progress) {
            Text("Peak")
        } currentValueLabel: {
            Text(entry.envelope.state.isUsable ? entry.countdownText : "--")
                .font(.system(size: 9, weight: .bold))
                .minimumScaleFactor(0.5)
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccessible(envelope: entry.envelope)
    }

    private var progress: Double {
        guard let snapshot = entry.snapshot, snapshot.totalPeakMinutesToday > 0 else { return 0 }
        let elapsed = snapshot.totalPeakMinutesToday - snapshot.peakMinutesLeftToday
        return min(1, max(0, Double(elapsed) / Double(snapshot.totalPeakMinutesToday)))
    }
}

struct PulseRectangularView: View {
    var entry: PulseEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.headline)
                .font(.system(size: 12, weight: .heavy))
            Text(entry.countdownText)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(entry.envelope.balanceCaption(now: entry.date))
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetAccessible(envelope: entry.envelope)
    }
}

// MARK: - Shared pieces

struct StatusBadge: View {
    var envelope: WidgetSnapshotEnvelope

    var body: some View {
        if envelope.state == .fresh {
            EmptyView()
        } else {
            Text(envelope.state.shortLabel)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.35))
                .clipShape(Capsule())
                .widgetAccessible(envelope: envelope)
        }
    }
}

/// The 24-hour band, drawn from the same intervals the app uses.
struct PulseDayBand: View {
    var schedule: PricingSchedule
    var date: Date

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { pair in
                    Rectangle()
                        .fill(color(for: pair.element.state))
                        .frame(width: width(for: pair.element, total: geometry.size.width))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay(
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 1.5)
                    .offset(x: nowOffset(total: geometry.size.width))
                , alignment: .leading
            )
        }
    }

    private var segments: [ScheduleSegment] {
        schedule.segments(for: date)
    }

    private func color(for state: PricingState) -> Color {
        switch state {
        case .peak: return Color(red: 0.98, green: 0.58, blue: 0.13)
        case .offPeak: return Color(red: 0.18, green: 0.72, blue: 0.50)
        case .standard: return Color.white.opacity(0.25)
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

// MARK: - Helpers

extension View {
    /// Applies a state gradient inside the widget container.
    func pulseBackground(state: PricingState) -> some View {
        self.background(
            LinearGradient(colors: WidgetEntryView.palette(for: state),
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
        )
    }

    /// Marks the whole accessory view as privacy sensitive so a locked device hides balance text.
    @ViewBuilder
    func widgetAccessible(envelope: WidgetSnapshotEnvelope) -> some View {
        if #available(iOSApplicationExtension 16.0, *) {
            self.privacySensitive(true)
        } else {
            self
        }
    }
}
