import Foundation
import SwiftUI
import WidgetKit

// DeepSeek Pulse — the five medium-family designs.
//
//   dashboard      brand + state, big countdown, balance, full band
//   ledger         balance-led with granted / topped-up columns
//   countdownHero  two cells: countdown and the local clock time of the switch
//   bandHero       tall 24-hour band, state and balance underneath
//   minimal        state word and countdown only
//
// PulseEntry supplies the derived strings (balanceText, peakLeftText, switchClockText), so every
// design shows the same numbers as the app.

struct PulseDashboardView: View {
    var entry: PulseEntry
    var mood: PulseMood
    var appearance: WidgetAppearance

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("DEEPSEEK PULSE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(mood.ink.opacity(0.85))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(entry.headline)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(mood.ink)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(mood.ink.opacity(0.18))
                    .clipShape(Capsule())
                if appearance.showRefresh { PulseRefreshAffordance(size: 13, ink: mood.ink) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    PulseCountdownCaption(entry: entry, ink: mood.ink)
                    PulseCountdown(entry: entry, size: 25, ink: mood.ink)
                }
                Spacer(minLength: 4)
                if appearance.showBalance {
                    PulseBalanceLine(entry: entry, size: 14, captionSize: 8, showCaption: false, ink: mood.ink)
                }
            }
            if appearance.showDayBand, let schedule = entry.envelope.schedule {
                PulseDayBand(schedule: schedule, date: entry.date, barHeight: 9)
            }
            Text(entry.footnote)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(mood.ink.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Text(entry.balanceCaption)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(mood.ink.opacity(0.58))
                    .lineLimit(1)
                Spacer(minLength: 0)
                PulseStatusBadge(entry: entry, ink: mood.ink)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct PulseLedgerView: View {
    var entry: PulseEntry
    var mood: PulseMood
    var appearance: WidgetAppearance

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("BALANCE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(mood.ink.opacity(0.66))
                Spacer(minLength: 0)
                Text(entry.headline)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(mood.ink)
                if appearance.showRefresh { PulseRefreshAffordance(size: 13, ink: mood.ink) }
            }
            if appearance.showBalance {
                Text(entry.balanceText)
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .foregroundColor(mood.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .accessibilityLabel("Available balance " + entry.balanceText)
                HStack(spacing: 14) {
                    PulseStat(title: "Granted", value: entry.grantedText, ink: mood.ink)
                    PulseStat(title: "Topped up", value: entry.toppedUpText, ink: mood.ink)
                    PulseStat(title: entry.countdownLabel.isEmpty ? "State" : entry.countdownLabel,
                              value: entry.headline, ink: mood.ink)
                }
            } else {
                Text(entry.footnote)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(mood.ink.opacity(0.8))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                PulseCountdown(entry: entry, size: 16, ink: mood.ink)
                Spacer(minLength: 0)
                Text(entry.balanceCaption)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(mood.ink.opacity(0.58))
                    .lineLimit(1)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct PulseCountdownHeroView: View {
    var entry: PulseEntry
    var mood: PulseMood
    var appearance: WidgetAppearance

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("DEEPSEEK PULSE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(mood.ink.opacity(0.8))
                Spacer(minLength: 0)
                if appearance.showRefresh { PulseRefreshAffordance(size: 13, ink: mood.ink) }
            }
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.countdownLabel.isEmpty ? "STATE" : entry.countdownLabel.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(mood.ink.opacity(0.6))
                        .lineLimit(1)
                    PulseCountdown(entry: entry, size: 24, ink: mood.ink)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(mood.ink.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text("SWITCH AT")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(mood.ink.opacity(0.6))
                        .lineLimit(1)
                    Text(entry.switchClockText)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(mood.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(mood.ink.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(entry.headline)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(mood.ink.opacity(0.9))
                Spacer(minLength: 0)
                if appearance.showBalance {
                    PulseBalanceLine(entry: entry, size: 13, captionSize: 8, showCaption: false, ink: mood.ink)
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct PulseBandHeroView: View {
    var entry: PulseEntry
    var mood: PulseMood
    var appearance: WidgetAppearance

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(entry.headline)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(mood.ink)
                Spacer(minLength: 0)
                if appearance.showRefresh { PulseRefreshAffordance(size: 13, ink: mood.ink) }
            }
            if appearance.showDayBand, let schedule = entry.envelope.schedule {
                PulseDayBand(schedule: schedule, date: entry.date, barHeight: 28)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                PulseCountdown(entry: entry, size: 21, ink: mood.ink)
                Spacer(minLength: 0)
                if appearance.showBalance {
                    PulseBalanceLine(entry: entry, size: 13, captionSize: 8, showCaption: false, ink: mood.ink)
                }
            }
            Text(entry.footnote)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(mood.ink.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct PulseMinimalView: View {
    var entry: PulseEntry
    var mood: PulseMood
    var appearance: WidgetAppearance

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Spacer(minLength: 0)
                if appearance.showRefresh { PulseRefreshAffordance(size: 13, ink: mood.ink) }
            }
            Spacer(minLength: 0)
            Text(entry.headline)
                .font(.system(size: 13, weight: .heavy))
                .foregroundColor(mood.ink.opacity(0.86))
                .lineLimit(1)
            PulseCountdown(entry: entry, size: 32, weight: .heavy, ink: mood.ink)
            PulseCountdownCaption(entry: entry, size: 10, ink: mood.ink)
            Spacer(minLength: 0)
            if appearance.showBalance {
                PulseBalanceLine(entry: entry, size: 12, captionSize: 8, showCaption: false, ink: mood.ink)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
