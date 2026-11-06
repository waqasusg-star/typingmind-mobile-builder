# DeepSeek Pulse — changelog

# iPhone 1.0.3 / build 4

Adds a **real WidgetKit widget** as an embedded extension. Bundle ID, scheme, Keychain API key,
saved schedule, prices and cached balance all carry over unchanged.

## Added — a genuine Home Screen and Lock Screen widget

- **New extension target** `DeepSeekPulseWidgets`, bundle `com.waqas.deepseekpulse.widgets`, embedded
  in the app as an `.appex` with the `com.apple.widgetkit-extension` extension point.
- `WidgetSources/WidgetBundle.swift` — canonical `@main` `WidgetBundle` declaring `PulseWidget`
  (kind `DeepSeekPulseWidget`).
- `WidgetSources/WidgetTimelineProvider.swift` — placeholder, snapshot and timeline provider.
- `WidgetSources/WidgetViews.swift` — real SwiftUI views: small and medium for iOS 15, plus Lock
  Screen accessory inline / circular / rectangular from iOS 16.
- Supported families: small and medium on iOS 15+; accessories on iOS 16+. No Dynamic Island or Live
  Activity is claimed or shipped — the in-app card is a preview, not an activity.

## Added — shared data layer

- `Shared/WidgetSharedTypes.swift` — `WidgetShared`, `WidgetDataState`, `WidgetBalance`,
  `WidgetRate`, `WidgetSnapshotPayload`, `WidgetSnapshotEnvelope`.
- `Shared/WidgetCacheStore.swift` — `WidgetCacheCodec` (encode, decode, schema probe, sanitising,
  staleness, secret-value guard) and `WidgetCacheLocation` for the App Group container.
- `Shared/WidgetPlanner.swift` and `Shared/WidgetPolicy.swift` — moved out of `Sources/` so the
  extension can compile them. The `Sources/` copies are comment-only stubs, so nothing is defined
  twice and the app and widget share one implementation.
- `Sources/WidgetBridge.swift` — app-side writer: builds a display-only payload, refuses to write
  anything matching a secret value, writes atomically, then calls
  `WidgetCenter.shared.reloadTimelines`.

## Fixes in this build (found by inspecting real CI output)

- **Duplicate Swift basenames broke the app archive.** Two files named `WidgetPlanner.swift` (in
  `Sources/` and `Shared/`) — and likewise `WidgetPolicy.swift` — existed in both the app target and
  the widget extension target. Swift rejects that with `Filename "WidgetPlanner.swift" used twice`
  even when one copy declares nothing, so the archive step failed while both test suites passed.
  The obsolete `Sources/` and duplicate `Shared/` copies were deleted, and the single remaining
  implementations are `Shared/WidgetPlannerCore.swift` and `Shared/WidgetPolicyCore.swift`, compiled
  into both targets. No marker or stub files remain.

- **Stale boundary was unreachable.** The widget test suite failed with
  "exactly at the stale limit is still fresh" because the assertion measured from the wrong
  reference. The threshold is now measured from `balanceFetchedAt`, and the timeline planner emits
  the stale crossing one second **past** the codec threshold — the codec only reports stale when
  `age > staleAfter`, so an entry placed exactly on the threshold would still render "fresh".
- **Countdown was frozen.** `Text(entry.countdownText)` never advanced. The views now use
  `Text(target, style: .timer)`, which iOS updates itself, with a static fallback when no switch is
  known. No per-second network call and no extra timeline entries.
- **Timeline could skip real transitions.** The old provider used one bounded delay plus a fixed
  30-minute step. `WidgetTimelinePlanner` now walks the real pricing schedule, includes every UTC
  midnight within a 24-hour horizon, adds the cache-stale crossing and a bounded reload entry, and
  caps the plan at 12 entries with the current instant, the near transition and the stale crossing
  reserved so the cap cannot drop them.
- **Wrong deep-link scheme.** The shared policy used `deepseekpulse://status`, but the generated
  Info.plist registers `com.waqas.deepseekpulse`. The link is now
  `com.waqas.deepseekpulse://status` and the legacy scheme is explicitly rejected.
- **Lock Screen access required iOS 16.** The accessory views and cases are `@available`-guarded so
  the app keeps its iOS 15 deployment target.
- **iOS 17 gallery placeholder.** Views now declare `containerBackground(for: .widget)` on iOS 17+
  with the gradient fallback below that, so modern galleries do not show the adopt-background
  placeholder.
- **Account change could keep the old balance.** Saving a different API key replaced the key without
  clearing the cached balance. `SettingsStore.replaceAPIKey` now compares the normalized old and
  new key in memory, increments an account generation, clears the cache, and in-flight balance
  requests are cancelled or discarded so a late response cannot repopulate a removed or changed
  account. No key, hash or fingerprint is stored or shared.
- **A failed keychain write could destroy the stored key.** `KeyStore.save` called
  `SecItemDelete` before `SecItemAdd`, so if the add failed the previous key was already gone and a
  "previous key preserved" message would have been false. Writes now update the existing item with
  `SecItemUpdate`, add only when the probe returns `errSecItemNotFound`, and report failure
  otherwise without touching the stored item. The update/add/fail decision lives in
  `KeyStoreMutationRoute`, which the tests execute directly, and no route deletes.
- **Remove key left stale numbers in one case.** Removal now invalidates pending requests and clears
  the cached balance after a successful delete *or* `errSecItemNotFound`, even when no key was
  loaded, because an old cached balance can exist without a stored key. A delete failure changes
  nothing and reports the failure.

## Changed

- Version 1.0.2 (build 3) to **1.0.3 (build 4)**.
- **Dashboard** writes the shared snapshot after every accepted balance fetch.
- **Settings** rewrites the snapshot after Save and after Remove key.
- **Widget Studio** describes the installed extension, lists the real add-widget steps and reports
  the snapshot write result. The UIKit cards remain previews only.

## Privacy and storage

- The API key remains only in the iOS Keychain, sent only to `api.deepseek.com/user/balance`.
- The shared file holds formatted balance text, the schedule, rate labels and a `hasAPIKey`
  boolean. It never holds the key, a token, a hash or a fingerprint.
- A final guard rejects any encoded payload containing `sk-`, `bearer `, `authorization`, `api_key`,
  `"apikey":"`, `access_token`, `refresh_token`, `client_secret` or `password`.
- Accessory views use `privacySensitive(true)` from iOS 16.

## Honest limits of this build

- If the App Group entitlement is absent from either bundle, the widget shows a setup message and
  no numbers. It does not crash and does not invent values.
- iOS controls widget refresh. This build asks for a reload after changes and supplies bounded
  timeline entries; it cannot promise an exact update instant.
- Unsigned IPA output: **MUST BE SIGNED BEFORE INSTALLATION.** The app and the extension must be
  signed together, with the same team and matching App Group profiles. Whether a given signing
  service supports app extensions and App Groups is not verified by this build.
- No physical-device, widget-gallery, shared-container or privacy-blur test was run here.
- Prices, peak windows and the PRC holiday list remain local data verified on 2026-11-06.

# iPhone 1.0.2 / build 3

Adds the missing widget work without changing the bundle ID, the Keychain API key, the saved
schedule or the price data.

## Added

- **Widget Studio screen** (`Sources/WidgetStudioViewController.swift`), opened from the dashboard
  toolbar menu (gear → "Widgets & Live Activity"). It renders four widget-sized layouts with the
  live saved schedule and states exactly what is still missing for the Home Screen.
- **Widget layouts**: `WidgetFullCardView` (medium: state pill, countdown, next switch, minutes of
  peak left today, 24-hour band), `WidgetCompactCardView` (small), `WidgetLockScreenCardView` and
  `LiveActivityCardView` (Dynamic Island / Live Activity card). They reuse the app's own colours,
  PillView and DayTimelineView so a widget cannot drift from the app.
- **Shared planner** `Sources/WidgetPlanner.swift`: Foundation-only widget state — PEAK / OFF-PEAK /
  STANDARD, peak minutes left today, total peak minutes of the day, next switch instant, day tag,
  compact countdown text, next-switch label in the device time zone and the unverified-calendar
  flag.
- **Widget refresh policy** `Sources/WidgetPolicy.swift`: refresh just after the next switch, a
  60-second floor, a one-hour ceiling, the `deepseekpulse://status` deep link and the App Group and
  cache-key names to use when a widget extension is added.
- **Executed widget checks** (`Tests/WidgetPlannerTests.swift` + `Tests/WidgetPlannerMain.swift`):
  state at both window edges, minutes left today, weekend and holiday suppression, the 2028
  unverified flag, countdown text, label helpers, refresh bounds and the deep-link check.

## Changed

- Version 1.0.1 (build 2) → **1.0.2 (build 3)**.
- The toolbar gear now opens a menu: **Settings** and **Widgets & Live Activity**.

## Honest limits of 1.0.2

- That release built a single application target, so a Home-Screen widget, a Lock-Screen widget and
  a Live Activity were **not in the IPA**. The layouts, planner, refresh policy and card were in the
  app, and Widget Studio showed them. This is superseded by 1.0.3, which ships the real extension.
- Prices, peak windows and the PRC holiday list remain local data verified on 2026-11-06.
- Unsigned IPA output: MUST BE SIGNED BEFORE INSTALLATION. No physical-device widget test was run.

# iPhone 1.0.1 / build 2

Corrects obsolete pricing and schedule data, adds a verified PRC holiday calendar, makes the
assumption state honest, and makes the source archive independently rebuildable.

## Fixed

- **Obsolete schedule removed.** Peak is now the published set of UTC weekday intervals —
  **Monday–Friday 01:00–04:00 and 06:00–10:00 UTC** — excluding PRC public holidays; every other
  hour, every weekend and every PRC public holiday is off-peak.
- **Obsolete prices removed**: `deepseek-flash` (V4.1-Flash-1017) 0.006 / 0.30 / 1.20 and
  `deepseek-v4-pro` (V4-Pro-0813) 0.044 / 1.32 / 3.96 USD per 1M tokens, both 50% off off-peak.
- **Verified PRC holiday calendar 2026–2027** (62 dates, coverage 2026-01-01…2027-12-31) with later
  years reported as unverified instead of guessed.
- **Weekends are always off-peak**, so a make-up working Saturday never becomes peak.
- **Current state and countdown** walk across nights, weekends and holidays; multi-day gaps render
  as `2d 14h 30m`.
- **24-hour band and 7-day outlook** drawn from the real intervals.
- **Verified vs custom is explicit** in the dashboard, the rate caption and Settings.
- **Migration schema 1/2 → 3** keeps the Keychain key and cached balance.
- **Source archive is independently rebuildable** through `project.yml` (XcodeGen).

# iPhone 1.0.0 / build 1

First native Swift/UIKit release. Superseded because the seeded 16:30–00:30 window and the
`deepseek-chat` / `deepseek-reasoner` prices were obsolete.
