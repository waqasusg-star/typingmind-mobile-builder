import Foundation
import WidgetKit
import SwiftUI

// DeepSeek Pulse — WidgetKit timeline provider.
//
// Compiled into the DeepSeekPulseWidgets extension together with Shared/*.swift and
// Sources/RequestPolicy.swift. All pricing maths is delegated to WidgetPlanner. The provider makes
// no network request and never reads the Keychain: it only reads the App Group snapshot the app wrote.

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

    var countdownText: String {
        guard envelope.state.isUsable else { return "--:--" }
        guard let schedule = envelope.schedule, schedule.discountsEnabled else { return "STD" }
        guard let target = snapshot?.nextSwitchAt else { return "--" }
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

    func getTimeline(in context: Context, completion: @escaping (Timeline<PulseEntry>) -> Void) {
        let now = Date()
        let entry = makeEntry(at: now)
        var entries: [PulseEntry] = [entry]
        if entry.envelope.schedule != nil, let target = entry.snapshot?.nextSwitchAt {
            let delay = WidgetPolicy.refreshDelay(now: now, nextSwitchAt: target)
            let nextDate = now.addingTimeInterval(delay)
            entries.append(makeEntry(at: nextDate))
            entries.append(makeEntry(at: nextDate.addingTimeInterval(WidgetPolicy.minimumRefreshInterval * 30)))
        } else {
            entries.append(makeEntry(at: now.addingTimeInterval(WidgetPolicy.maximumRefreshInterval)))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    func makeEntry(at date: Date) -> PulseEntry {
        guard let fileURL = WidgetCacheLocation.shared.fileURL else {
            return PulseEntry(date: date, envelope: .failed(.groupUnavailable))
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            return PulseEntry(date: date, envelope: .failed(.empty))
        }
        return PulseEntry(date: date, envelope: WidgetCacheCodec.decode(data, now: date))
    }
}
