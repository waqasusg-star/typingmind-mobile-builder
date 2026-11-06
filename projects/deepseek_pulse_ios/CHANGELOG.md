# Changelog — DeepSeek Pulse (iOS)

## 1.0.4 — build 5

### Widget shows live details without an App Group

The 1.0.3 widget showed *"Widget data access is unavailable"* on the Home Screen because every
number was read from the App Group container, which this signing identity does not provide. The
widget now works from its own storage as well.

Fixed:

- **Two storage tiers.** The snapshot is stored in the App Group container when it exists and in the
  extension's own Application Support copy (`pulse-widget-local.json`) in every case. The timeline
  provider reads both and prefers the group copy, then the local copy.
- **Instant first render.** When neither tier has usable data, the extension writes a schedule-only
  snapshot built from the verified constants (`RateSeeds.schedule`, published rate labels). No
  balance, no key flag, no fetch time is invented — the widget says "No key" or "No data yet".
- **The setup banner is gone.** `WidgetDataState.groupUnavailable` no longer appears for a merely
  unshared container; it is reserved for the rare case where no tier can be opened at all, and its
  text now tells the user to open a widget once instead of asking for a reinstall.
- **Live countdown labelling.** The timer is the same iOS-rendered `Text(timerInterval:)`, now with a
  caption ("PEAK IN" / "OFF-PEAK IN") above it so the ticking number is self-explanatory. The caption
  and the footnote are generated from the same `WidgetPlanner` value, so they cannot contradict.
- **Empty titles removed.** `EmptyView` inside `Text` removed two SwiftUI `Text("")` initialisations
  in the badge and caption paths.

Changed:

- Widget Studio explains what the widget reads from each tier, and reports the real bridge result
  (`WidgetRefreshHandoff.summary`) instead of a permanent warning.
- `WidgetDataState.fresh` badge reads `UPDATED` instead of `RECENT`.
- New `Timer` redraw request ~3s after the first one, for the case iOS coalesced the first request.

Unchanged:

- Bundle ID `com.waqas.deepseekpulse`, widget bundle `com.waqas.deepseekpulse.widgets`, scheme
  `DeepSeekPulse`, App Group identifier, Keychain service/account and stored settings keys. No app
  data is migrated, cleared or rewritten by this update.
- The API key never leaves the Keychain: `WidgetCacheCodec.containsSecretMaterial` still blocks any
  payload containing key-shaped values, and both tiers are display-only.

New source files: `Shared/WidgetPayloadSeeds.swift`, `Shared/WidgetRefreshHandoff.swift`.

### What this build does not prove

The widget was not exercised on a physical iPhone in this session. WidgetKit refresh timing, the
shared-container behaviour after signing and the Home/Lock Screen gallery all remain unverified until
observed on your device.

---

## 1.0.3 — build 4

- Real WidgetKit extension (`DeepSeekPulseWidgets`) embedded in the app, `widgetkit_v1` profile.
- `WidgetPlanner` moved to `Shared/` so the extension and the app compute the same state.
- Removed the duplicate `Sources/WidgetPlanner.swift` that broke the app target.
- Timeline planner emits every transition, the stale crossing (+1s) and UTC midnights.
