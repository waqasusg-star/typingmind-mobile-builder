import Foundation
import WidgetKit
import SwiftUI

// DeepSeek Pulse — WidgetKit timeline provider.
//
// Compiled into the DeepSeekPulseWidgets extension together with Shared/*.swift and
// Sources/RequestPolicy.swift. All pricing maths is delegated to WidgetPlanner, so the widget and
// the app cannot disagree. The provider makes no network request and never reads the Keychain:
// it only reads the App Group snapshot the app wrote.

struct PulseEntry: TimelineEntry {
    let date: Date
    let envelope: WidgetSnapshotEnvelope

    var snapshot: WidgetPlanner.Snapshot? {
        guard let schedule = envelope.schedule else { return nil }
        return WidgetPlanner.snapshot(schedule: schedule, at: date)
    }

    var headline: String {
        guard let schedule = envelope.schedule, let snapshot = snapshot else {
            return envelope.state.shortLabel
        }
        return WidgetPlanner.headline(snapshot: snapshot, discountsEnabled: schedule.discountsEnabled)
    }

    /// When the next switch happens, if one is known. Views use this for a self-updating timer.
    var nextSwitchAt: Date? {
        guard envelope.state.isUsable,
              let schedule = envelope.schedule,
              schedule.discountsEnabled else { return nil }
        return snapshot?.nextSwitchAt
    }

    /// Static countdown text used only when a live timer is not appropriate.
    var countdownText: String {
        guard envelope.state.isUsable else { return "--:--" }
        guard let schedule = envelope.schedule, schedule.discountsEnabled else { return "STD" }
        guard let target = nextSwitchAt else { return "--" }
        return WidgetPlanner.countdown(from: date, to: target)
    }

    var footnote: String {
        guard let schedule = envelope.schedule, let snapshot = snapshot else {
            return envelope.state.explainer
        }
        var parts = [WidgetPlanner.footnote(snapshot: snapshot, discountsEnabled: schedule.discountsEnabled)]
        if envelope.state == .stale {
            parts.append("data " + ClockFormat.relative(envelope.payload?.writtenAt ?? date, now: date))
        }
        return parts.joined(separator: " · ")
    }
}

struct PulseTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> PulseEntry {
        PulseEntry(date: Date(), envelope: .failed(.empty))
    }

    func getSnapshot(in context: Context, completion: @escaping (PulseEntry) -> Void) {
        completion(makeEntry(at: Date()))
    }

    /// Builds entries on the real boundaries the snapshot implies: the next peak/off-peak switch,
    /// the moment the cached balance turns stale, and UTC midnight. iOS decides when to reload.
    func getTimeline(in context: Context, completion: @escaping (Timeline<PulseEntry>) -> Void) {
        let now = Date()
        let envelope = readEnvelope(at: now)

        guard let schedule = envelope.schedule else {
            // No usable schedule: one entry plus a bounded retry date. Never a fabricated timeline.
            let entries = [PulseEntry(date: now, envelope: envelope),
                           PulseEntry(date: now.addingTimeInterval(WidgetPolicy.maximumRefreshInterval), envelope: envelope)]
            completion(Timeline(entries: entries, policy: .atEnd))
            return
        }

        let dates = WidgetTimelinePlanner.dates(now: now,
                                               schedule: schedule,
                                               dataFetchedAt: envelope.payload?.balanceFetchedAt)
        var entries: [PulseEntry] = []
        for date in dates {
            // Re-decode for later dates so the stale badge flips exactly when the cache ages out.
            let resolved = date == now ? envelope : readEnvelope(at: date)
            entries.append(PulseEntry(date: date, envelope: resolved))
        }
        if entries.isEmpty {
            entries.append(PulseEntry(date: now, envelope: envelope))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    func makeEntry(at date: Date) -> PulseEntry {
        PulseEntry(date: date, envelope: readEnvelope(at: date))
    }

    /// Reads the App Group snapshot. Missing container or file becomes a visible state, never a crash.
    func readEnvelope(at date: Date) -> WidgetSnapshotEnvelope {
        guard let fileURL = WidgetCacheLocation.shared.fileURL else {
            return .failed(.groupUnavailable)
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            return .failed(.empty)
        }
        return WidgetCacheCodec.decode(data, now: date)
    }
}
