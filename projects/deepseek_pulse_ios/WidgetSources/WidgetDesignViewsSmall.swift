import Foundation
import SwiftUI
import WidgetKit

// DeepSeek Pulse — the five small-family designs.
//
//   aurora      state pill, countdown, balance
//   vault       balance first, countdown underneath
//   splitColumn countdown and peak time left side by side
//   ring        progress ring around the state word
//   timeline    today's 24-hour band with state and countdown
//
// Every design honours the balance and refresh switches from Widget Studio.

struct PulseAuroraView: View {
    var entry: PulseEntry
    var mood: PulseMood
    var appearance: WidgetAppearance

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text("DeepSeek")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(mood.ink.opacity(0.85))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if appearance.showRefresh { PulseRefreshAffordance(size: 12, ink: mood.ink) }
            }
            Text(entry.headline)
                .font(.system(size: 14, weight: .heavy))
                .foregroundColor(mood.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            PulseCountdownCaption(entry: entry, ink: mood.ink)
            PulseCountdown(entry: entry, size: 20, ink: mood.ink)
            Spacer(minLength: 0)
            if appearance.showBalance {
                PulseBalanceLine(entry: entry, size: 12, captionSize: 8, ink: mood.ink)
            } else {
                PulseStatusBadge(entry: entry, ink: mood.ink)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct PulseVaultView: View {
    var entry: PulseEntry
    var mood: PulseMood
    var appearance: WidgetAppearance

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(entry.headline)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(mood.ink.opacity(0.9))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if appearance.showRefresh { PulseRefreshAffordance(size: 12, ink: mood.ink) }
            }
            Spacer(minLength: 0)
            if appearance.showBalance {
                Text(entry.balanceText)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(mood.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .accessibilityLabel("Available balance " + entry.balanceText)
                Text(entry.envelope.availabilityText ?? entry.balanceCaption)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(mood.ink.opacity(0.66))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text(entry.footnote)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(mood.ink.opacity(0.7))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                PulseCountdown(entry: entry, size: 15, ink: mood.ink)
                Spacer(minLength: 0)
                PulseStatusBadge(entry: entry, ink: mood.ink)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct PulseSplitColumnView: View {
    var entry: PulseEntry
    var mood: PulseMood
    var appearance: WidgetAppearance

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text("PULSE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(mood.ink.opacity(0.8))
                Spacer(minLength: 0)
                if appearance.showRefresh { PulseRefreshAffordance(size: 12, ink: mood.ink) }
            }
            Rectangle()
                .fill(mood.ink.opacity(0.2))
                .frame(height: 1)
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.countdownLabel.isEmpty ? "STATE" : entry.countdownLabel.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(mood.ink.opacity(0.6))
                        .lineLimit(1)
                    PulseCountdown(entry: entry, size: 16, ink: mood.ink)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 1) {
                    Text("PEAK LEFT")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(mood.ink.opacity(0.6))
                        .lineLimit(1)
                    Text(entry.peakLeftText)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(mood.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            Spacer(minLength: 0)
            if appearance.showBalance {
                PulseBalanceLine(entry: entry, size: 12, captionSize: 8, showCaption: false, ink: mood.ink)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct PulseRingView: View {
    var entry: PulseEntry
    var mood: PulseMood
    var appearance: WidgetAppearance

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Text("DeepSeek")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(mood.ink.opacity(0.8))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if appearance.showRefresh { PulseRefreshAffordance(size: 11, ink: mood.ink) }
            }
            ZStack {
                Circle()
                    .stroke(mood.ink.opacity(0.18), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(mood.ink.opacity(0.9), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(entry.headline)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(mood.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    PulseCountdown(entry: entry, size: 10, ink: mood.ink)
                }
            }
            .frame(maxWidth: 70, maxHeight: 70)
            if appearance.showBalance {
                PulseBalanceLine(entry: entry, size: 11, captionSize: 8, showCaption: false, ink: mood.ink)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var progress: Double {
        guard let snapshot = entry.snapshot, snapshot.totalPeakMinutesToday > 0 else { return 0 }
        let elapsed = snapshot.totalPeakMinutesToday - snapshot.peakMinutesLeftToday
        return min(1, max(0, Double(elapsed) / Double(snapshot.totalPeakMinutesToday)))
    }
}

struct PulseTimelineView: View {
    var entry: PulseEntry
    var mood: PulseMood
    var appearance: WidgetAppearance

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(entry.headline)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(mood.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if appearance.showRefresh { PulseRefreshAffordance(size: 12, ink: mood.ink) }
            }
            PulseCountdown(entry: entry, size: 18, ink: mood.ink)
            Spacer(minLength: 0)
            if appearance.showDayBand, let schedule = entry.envelope.schedule {
                PulseDayBand(schedule: schedule, date: entry.date, barHeight: 7)
            }
            if appearance.showBalance {
                PulseBalanceLine(entry: entry, size: 12, captionSize: 8, showCaption: false, ink: mood.ink)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
