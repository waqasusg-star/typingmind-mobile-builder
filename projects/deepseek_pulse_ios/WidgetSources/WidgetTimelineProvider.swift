import Foundation
import WidgetKit

// DeepSeek Pulse — WidgetKit timeline entry and provider.
//
// Compiled into the DeepSeekPulseWidgets extension together with Shared/*.swift and
// Sources/RequestPolicy.swift. All pricing maths is delegated to WidgetPlanner, so the widget and the
// app cannot disagree. The provider makes no network request and never reads the Keychain: it reads
// the snapshot bytes the app wrote.
//
// Two consequences of the private signing service are handled here, and they are what keeps the
// widget live:
//   * the App Group container may be missing, so the extension keeps its OWN copy of the snapshot
//     in its local Application Support directory and prefers whichever copy is newer;
//   * iOS draws timelines for extensions it considers in-use, so the extension rebuilds one embedded
//     copy from the schedule constants even before the app has ever written a snapshot. That copy
//     carries no balance and says so; it is not invented account data. It does keep the last
//     appearance, so a chosen theme and design survive a cold start.

// MARK: - Extension-side writer

enum PulseWidgetLocalStore {

    /// Memoised so a second refresh in the same process does not rewrite the file.
    private static var lastSignature: String?

    /// Ensures the local tier holds a usable payload, and mirrors the newest readable payload into
    /// it so a later refresh can still decode after the App Group file becomes unavailable.
    @discardableResult
    static func refresh(at date: Date,
                        location: WidgetCacheLocation = .shared) -> WidgetSnapshotStore.Loaded {
        let loaded = WidgetSnapshotStore.load(location: location, now: date)

        if let payload = loaded.envelope.payload,
           loaded.envelope.state.isUsable,
           loaded.tier != .extensionLocal {
            WidgetSnapshotStore.write(payload: payload, to: .extensionLocal, location: location)
            return loaded
        }

        if loaded.envelope.state.isUsable {
            return loaded
        }

        // No usable payload anywhere: publish the built-in schedule snapshot so the widget can count
        // down and show PEAK / OFF-PEAK immediately. No balance is fabricated.
        let seeded = WidgetSnapshotPayload.builtIn(now: date, appearance: loaded.envelope.payload?.appearance)
        let signature = String(date.timeIntervalSince1970) + (loaded.envelope.payload?.appearance?.summary ?? "default")
        if lastSignature != signature {
            lastSignature = signature
            WidgetSnapshotStore.write(payload: seeded, to: .extensionLocal, location: location)
        }
        return WidgetSnapshotStore.Loaded(envelope: WidgetCacheCodec.envelope(for: seeded, now: date),
                                          tier: .extensionLocal)
    }
}

// MARK: - Entry

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

    /// Label for the live timer slot: what is being counted down to.
    var countdownLabel: String {
        guard let schedule = envelope.schedule, schedule.discountsEnabled else { return "" }
        guard let snapshot = snapshot, snapshot.nextSwitchAt != nil else { return "" }
        return WidgetPlanner.countdownCaption(snapshot: snapshot, discountsEnabled: schedule.discountsEnabled)
    }

    var footnote: String {
        guard let schedule = envelope.schedule, let snapshot = snapshot else {
            return envelope.state.explainer
        }
        var parts = [WidgetPlanner.footnote(snapshot: snapshot, discountsEnabled: schedule.discountsEnabled)]
        if envelope.state == .stale {
            parts.append("data " + ClockFormat.relative(envelope.payload?.writtenAt ?? date, now: date))
        }
        return parts.joined(separator: " - ")
    }

    // MARK: Balance and secondary strings

    /// The available balance exactly as the app formatted it, or an honest placeholder.
    var balanceText: String { envelope.balanceLine() }

    /// Age of the balance, or why there is none.
    var balanceCaption: String { envelope.balanceCaption(now: date) }

    var grantedText: String { envelope.balance?.grantedText ?? "--" }

    var toppedUpText: String { envelope.balance?.toppedUpText ?? "--" }

    /// Peak time remaining today, as a short label.
    var peakLeftText: String {
        guard let snapshot = snapshot else { return "--" }
        guard snapshot.totalPeakMinutesToday > 0 else { return "None" }
        let minutes = snapshot.peakMinutesLeftToday
        if minutes >= 60 {
            let hours = minutes / 60
            let rest = minutes % 60
            return rest == 0 ? String(hours) + "h" : String(hours) + "h" + String(rest) + "m"
        }
        return String(minutes) + "m"
    }

    /// Local clock time of the next switch, for the Countdown Hero design.
    var switchClockText: String {
        guard let target = nextSwitchAt else { return "--:--" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: target)
    }
}

// MARK: - Provider

struct PulseTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> PulseEntry {
        PulseEntry(date: Date(), envelope: .failed(.empty))
    }

    func getSnapshot(in context: Context, completion: @escaping (PulseEntry) -> Void) {
        completion(makeEntry(at: Date()))
    }

    /// Builds entries on the real boundaries the snapshot implies: every pricing transition inside
    /// the horizon, the moment the cached balance turns stale, and UTC midnights. The policy asks
    /// for a reload at a bounded future instant rather than an open-ended .atEnd, so a finished peak
    /// window cannot leave a stale PEAK badge until midnight. iOS still applies its own budget.
    func getTimeline(in context: Context, completion: @escaping (Timeline<PulseEntry>) -> Void) {
        let now = Date()
        // Refresh the extension's own copy first; this is what makes the widget work without an
        // App Group entitlement.
        let loaded = PulseWidgetLocalStore.refresh(at: now)
        let envelope = loaded.envelope
        let reload = WidgetTimelinePlanner.reloadDate(now: now)

        guard let schedule = envelope.schedule else {
            let entries = [PulseEntry(date: now, envelope: envelope),
                           PulseEntry(date: reload, envelope: envelope)]
            completion(Timeline(entries: entries, policy: .after(reload)))
            return
        }

        let dates = WidgetTimelinePlanner.dates(now: now,
                                               schedule: schedule,
                                               dataFetchedAt: envelope.payload?.balanceFetchedAt)
        var entries: [PulseEntry] = []
        for date in dates {
            // Re-decode for later dates so the stale badge flips exactly when the cache ages out.
            let resolved = date == now ? envelope : readEnvelope(at: date).envelope
            entries.append(PulseEntry(date: date, envelope: resolved))
        }
        if entries.isEmpty {
            entries.append(PulseEntry(date: now, envelope: envelope))
        }
        completion(Timeline(entries: entries, policy: .after(reload)))
    }

    func makeEntry(at date: Date) -> PulseEntry {
        PulseEntry(date: date, envelope: readEnvelope(at: date).envelope)
    }

    /// Reads the newest readable snapshot from either tier. A missing file becomes a visible state,
    /// never a crash and never fake numbers.
    func readEnvelope(at date: Date) -> WidgetSnapshotStore.Loaded {
        WidgetSnapshotStore.load(now: date)
    }
}
