import Foundation
import WidgetKit

// DeepSeek Pulse — WidgetKit timeline provider and the extension-side snapshot store.
//
// Compiled into the DeepSeekPulseWidgets extension together with Shared/*.swift and
// Sources/RequestPolicy.swift. All pricing maths is delegated to WidgetPlanner(…Core.swift), so the
// widget and the app cannot disagree. The provider makes no network request and never reads the
// Keychain: it reads the snapshot bytes the app wrote.
//
// Two consequences of the signing service are handled here, and they are what keeps the widget live:
//   * the App Group container may be missing, so the extension keeps its OWN copy of the snapshot
//     in its local Application Support directory and prefers whichever copy is newer;
//   * iOS draws timelines for extensions it considers in-use, so the extension rebuilds one
//     embedded copy from the schedule constants even before the app has ever written a snapshot.
//     That copy carries no balance and says so; it is not invented account data.
//
// 1.0.7 fixes the "No key" / "No API key saved" wording. The extension keeps its own copy of the
// snapshot, and its built-in seed wrote `hasAPIKey: false`. That copy could then stay the newest
// readable one, so the widget announced a missing key even though the app had the key in the
// Keychain. The seed now reports the key state as UNKNOWN instead of false, and every view routes its
// wording through PulseBalanceWording, which never claims a key is missing on unknown state.

// MARK: - Extension-side writer

/// Writes the extension's own snapshot copy.
///
/// Safe to call from a timeline provider: it only touches the extension container, never the
/// Keychain, never the network and never the app's UserDefaults.
enum PulseWidgetLocalStore {

    /// Ensures the local tier holds a usable payload, and mirrors the newest readable payload into
    /// it so a later refresh can still decode after the App Group file becomes unavailable.
    @discardableResult
    static func refresh(at date: Date,
                        location: WidgetCacheLocation = .shared) -> WidgetSnapshotStore.Loaded {
        let loaded = WidgetSnapshotStore.load(location: location, now: date)

        if let payload = loaded.envelope.payload,
           loaded.envelope.state.isUsable,
           loaded.tier != .extensionLocal {
            // Copy the newest readable payload into the extension tier so the widget survives the
            // loss of the group container.
            WidgetSnapshotStore.write(payload: payload, to: .extensionLocal, location: location)
            return loaded
        }

        if loaded.envelope.state.isUsable {
            return loaded
        }

        // No usable payload anywhere: publish the built-in schedule snapshot so the widget can
        // count down and show PEAK / OFF-PEAK immediately. No balance is fabricated, and the key
        // state stays unknown. The appearance already stored in this tier is carried over, so a
        // chosen theme and design are not lost.
        let existing = loaded.envelope.payload
        // 1.0.8: the key KNOWN flag is carried over too. Without it, a snapshot that positively
        // reported "no key" degraded to "unknown" every time the seed was rewritten, and the owner of
        // a keyless account never saw the actionable "Add API key" wording.
        let seeded = WidgetSnapshotPayload.builtIn(now: date,
                                                  appearance: existing?.appearance,
                                                  hasAPIKey: existing?.hasAPIKey,
                                                  hasAPIKeyKnown: existing?.hasAPIKeyKnown)
        WidgetSnapshotStore.write(payload: seeded, to: .extensionLocal, location: location)
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

    // MARK: Balance and statistics

    /// Whether a displayable balance exists in the snapshot.
    var hasBalance: Bool { envelope.hasUsableBalance }

    /// Whether the app reported that a key is stored. Nil in the payload means unknown.
    var hasAPIKey: Bool { envelope.hasAPIKey }

    /// The available balance, exactly as the app formatted it. When there is no balance this is an
    /// instruction rather than a bare "No key".
    /// Why the widget wants the app opened. Nil when nothing needs refreshing, or when the widget is
    /// still inside the handshake cooldown so a tap would loop.
    var computedRefreshReason: WidgetRefreshReason? {
        let handshake = WidgetRefreshLedger.read()
        let wanted = WidgetRefreshHandshakeRules.shouldRequest(state: envelope.state,
                                                              hasBalance: hasBalance,
                                                              lastRequestAt: handshake.requestedAt,
                                                              lastAnswerAt: handshake.answeredAt,
                                                              now: date)
        guard wanted else { return nil }
        return WidgetRefreshHandshakeRules.reason(state: envelope.state, hasBalance: hasBalance)
    }

    var balanceText: String {
        let slot = PulseBalanceWording.slot(hasBalance: hasBalance,
                                            hasAPIKey: hasAPIKey,
                                            hasAPIKeyKnown: envelope.hasAPIKeyKnown)
        return slot.isEmpty ? envelope.balanceLine() : slot
    }

    /// How fresh the balance is, or the next action when there is none.
    var balanceCaption: String {
        guard envelope.state.isUsable else {
            return PulseBalanceWording.unavailableCaption(state: envelope.state)
        }
        return PulseBalanceWording.caption(hasBalance: hasBalance,
                                           hasAPIKeyKnown: envelope.hasAPIKeyKnown,
                                           hasAPIKey: hasAPIKey,
                                           fetchedAtAge: envelope.payload?.balanceFetchedAt.map {
                                               max(0, date.timeIntervalSince($0))
                                           },
                                           isStale: envelope.state == .stale)
    }

    /// Short caption for the compact designs.
    var shortBalanceCaption: String {
        guard envelope.state.isUsable else { return envelope.state.shortLabel }
        if hasBalance, let fetched = envelope.payload?.balanceFetchedAt {
            return ClockFormat.relative(fetched, now: date)
        }
        return envelope.hasAPIKeyKnown && !hasAPIKey ? "Add key" : "Tap to load"
    }

    var grantedText: String {
        envelope.payload?.balance?.grantedText.isEmpty == false
            ? (envelope.payload?.balance?.grantedText ?? "--")
            : "--"
    }

    var toppedUpText: String {
        envelope.payload?.balance?.toppedUpText.isEmpty == false
            ? (envelope.payload?.balance?.toppedUpText ?? "--")
            : "--"
    }

    /// "3h 20m" style label for the peak time left today.
    var peakLeftText: String {
        guard let snapshot = snapshot, envelope.state.isUsable else { return "--" }
        guard let schedule = envelope.schedule, schedule.discountsEnabled else { return "--" }
        let minutes = snapshot.peakMinutesLeftToday
        if minutes == 0 { return "0m" }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return String(rest) + "m" }
        if rest == 0 { return String(hours) + "h" }
        return String(hours) + "h " + String(rest) + "m"
    }

    /// Local clock time of the next switch, for designs that show when rather than how long.
    var switchClockText: String {
        guard let target = nextSwitchAt else { return "--:--" }
        return ClockFormat.localTimeLabel(target)
    }

    /// Peak progress for the ring and the new Lock Screen gauge: 0 at the start of peak, 1 at the end.
    var peakProgress: Double {
        guard let snapshot = snapshot, snapshot.totalPeakMinutesToday > 0 else { return 0 }
        let elapsed = snapshot.totalPeakMinutesToday - snapshot.peakMinutesLeftToday
        return min(1, max(0, Double(elapsed) / Double(snapshot.totalPeakMinutesToday)))
    }

    /// What the next switch does, in two words, for the Lock Screen cells.
    var switchWord: String {
        guard let snapshot = snapshot, snapshot.nextSwitchAt != nil else { return "STATE" }
        return snapshot.nextSwitchBecomesPeak ? "Peak at" : "Off-peak at"
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
            // No usable schedule at all: one entry plus a bounded retry date.
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
        // 1.0.9: if the widget has nothing current to show, leave a request for the app to answer on
        // its next launch or foreground. The cooldown lives in WidgetRefreshHandshakeRules, so this
        // cannot hammer the app; only the timeline build records a request, never a view redraw.
        recordHandshakeRequest(for: envelope, at: now)
        completion(Timeline(entries: entries, policy: .after(reload)))
    }

    /// Writes the widget-to-app request when the snapshot needs a refresh and the cooldown allows it.
    private func recordHandshakeRequest(for envelope: WidgetSnapshotEnvelope, at now: Date) {
        let ledger = WidgetRefreshLedger.read()
        let hasBalance = envelope.hasUsableBalance
        guard WidgetRefreshHandshakeRules.shouldRequest(state: envelope.state,
                                                       hasBalance: hasBalance,
                                                       lastRequestAt: ledger.requestedAt,
                                                       lastAnswerAt: ledger.answeredAt,
                                                       now: now) else { return }
        let reason = WidgetRefreshHandshakeRules.reason(state: envelope.state, hasBalance: hasBalance)
        PulseWidgetHandshake.requestRefresh(reason: reason, at: now)
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
