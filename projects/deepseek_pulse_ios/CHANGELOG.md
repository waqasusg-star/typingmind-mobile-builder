# Changelog — DeepSeek Pulse (iOS)

## 1.0.5 — build 6

### Settings is reachable, and the icon is no longer blank

Reported on build 1.0.4: the Settings screen could not be opened and the Home Screen icon was empty.

Fixed:

- **Settings and Widgets are real buttons.** They used to live inside a bar-button `UIMenu`, which was
  not reachable on the signed build. The dashboard now shows a fixed row of two labelled buttons
  (gearshape → Settings, grid → Widgets & Live Activity) at the top of the scroll view, with an
  explicit 44 pt intrinsic height so the stack view cannot collapse them. Accessibility labels are set.
- **App icon.** `Sources/AppIconMark.swift` draws the brand mark with Core Graphics (blue-to-navy
  gradient, pulse line, peak/off-peak band). Widget Studio now shows the icon the build actually
  carries and states whether a compiled icon asset was found in the bundle.
- The remaining toolbar items (refresh and the overflow menu) are unchanged, so a long press or an
  untappable menu can no longer hide the main navigation.

Unchanged:

- Version-1.0.4 widget behaviour: two storage tiers, the built-in schedule seed and the live
  PEAK IN / OFF-PEAK IN timer.
- Bundle ID `com.waqas.deepseekpulse`, widget bundle `com.waqas.deepseekpulse.widgets`, App Group
  identifier, Keychain service/account and stored settings. No user data is migrated or cleared.

### What this build does not prove

Neither change was observed on a physical iPhone in this session. The toolbar row is plain UIKit in
reachable layouts, but the real check is opening it on your device after signing.

---

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
  unshared container; it is reserved for the rare case where no tier can be opened at all.
- **Live countdown labelling.** The timer is the iOS-rendered `Text(timerInterval:)`, now with a
  caption ("PEAK IN" / "OFF-PEAK IN") above it, generated from the same `WidgetPlanner` value as the
  footnote so the two cannot contradict.

Changed:

- Widget Studio explains what the widget reads from each tier and reports the real bridge result.
- `WidgetDataState.fresh` badge reads `UPDATED` instead of `RECENT`.

---

## 1.0.3 — build 4

- Real WidgetKit extension (`DeepSeekPulseWidgets`) embedded in the app, `widgetkit_v1` profile.
- `WidgetPlanner` moved to `Shared/` so the extension and the app compute the same state.
- Removed the duplicate `Sources/WidgetPlanner.swift` that broke the app target.
- Timeline planner emits every transition, the stale crossing (+1s) and UTC midnights.
