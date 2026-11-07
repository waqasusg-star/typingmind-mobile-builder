# Changelog — DeepSeek Pulse (iOS)

## 1.0.8 — build 9

### The Home Screen icon is now a compiled asset

Reported on 1.0.7: the icon shown in Widget Studio was a Core Graphics drawing, and the Home Screen
icon slot was still empty after installing a signed build.

Fixed:

- **Real compiled AppIcon.** The project now builds through the `generated_v1` icon profile, which
  produces one opaque 1024x1024 master plus the 18 iPhone/iPad slots inside a compiled `Assets.car`,
  and the CI step verifies the icon keys, the PNGs and the `CFBundleIcons` entries in the actual
  archive and IPA. `Resources/AppIcon.json` supplies the brand colours: background `#153E75`,
  foreground `#FFFFFF`, the `pulse` symbol and the `DP` initials.
- `Sources/AppIconArtwork.swift` and `Sources/AppIconMark.swift` are **unchanged and both kept**. They
  are two different things: `AppIconArtwork` draws the in-app preview and the Home Screen shortcut
  artwork, `AppIconMark` draws the vector brand mark. Neither one is the compiled icon, so neither one
  is a substitute for the asset catalogue.

### The widget stops accusing the account of having no key

Fixed:

- **The key state is now carried across a reseed.** The extension rewrites its own schedule-only
  snapshot whenever no readable payload exists, and that rewrite used to drop the "key state is
  known" flag. A snapshot that had positively reported "no key" therefore degraded to "unknown" on
  the next seed, and the owner of a keyless account never saw the actionable wording. `builtIn(...)`
  now accepts the known flag, and `PulseWidgetLocalStore.refresh` passes through whatever the last
  snapshot recorded.
- All widget surfaces keep routing their account wording through `PulseBalanceWording`, so a widget
  distinguishes, separately: a saved key with no balance yet ("Load in app"), a positively missing key
  ("Add API key"), a real balance with its age ("Updated 4m ago" / "Saved 2h ago"), and an unreadable
  or incompatible snapshot (its own explainer). The Lock Screen families still show no balance at all,
  because that slot is too small to explain an account.
- The API key continues to live only in the app's Keychain. The payload still has no field that could
  carry it, and the secret scan still runs before every write.

### Themes and tests

- The palette catalogue and the ten widget designs are unchanged in behaviour. The executed widget
  suite now proves the catalogue itself: at least ten themes, unique ids, every channel displayable,
  every ramp displayable in all three pricing states, every id resolving to its own name instead of
  the fallback, ten designs with unique codes, and a saved appearance (theme, both designs and the
  display switches) surviving an encode/decode round trip.
- Two seed assertions were corrected. They previously asserted the literal string "No key" for a
  snapshot with no account data at all, which contradicts the honesty rule the views follow. They now
  assert the placeholder balance, the absence of invented account data, and the exact wording each
  real key state produces.

Unchanged:

- Bundle ID `com.waqas.deepseekpulse`, widget bundle `com.waqas.deepseekpulse.widgets`, App Group
  `group.com.waqas.deepseekpulse`, Keychain service/account and every stored setting. No user data is
  migrated, cleared or reformatted.
- The two storage tiers, the built-in schedule seed, the live `Text(timerInterval:)` countdown, the
  deep-link refresh route and the Settings save path.

### What this build does not prove

- The IPA is **unsigned**. Both the app and the widget extension must be signed with the same team
  and with profiles that both authorise `group.com.waqas.deepseekpulse`; until that happens the
  extension cannot read the shared container, and the widget runs on its own local tier.
- Nothing here was observed on a physical iPhone: the Home Screen icon placement, the Lock Screen
  widget rendering, App Group runtime access and live `api.deepseek.com` balance calls remain
  unverified until you install the signed build and look.
- WidgetKit decides when a timeline is actually reloaded. The app can request a reload and clear the
  saved balance immediately; it cannot make iOS redraw sooner than iOS chooses.

---

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
