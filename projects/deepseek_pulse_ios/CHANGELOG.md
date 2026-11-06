# DeepSeek Pulse — changelog

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

## Honest limits of this build

- This pipeline saves text source for one application target and the build machine generates a
  single-target project. A Home-Screen widget, a Lock-Screen widget and a Live Activity require
  separate WidgetKit / ActivityKit extension targets with their own Info.plist entries,
  entitlements and an App Group. Those package structures cannot be produced here, so **they are
  not in this IPA** — the layouts, the planner, the refresh policy and the Live Activity card are
  in the app, and Widget Studio shows them.
- To get them on the Home Screen and Dynamic Island: rebuild the delivered source ZIP in Xcode and
  add a Widget Extension target that includes `WidgetPlanner.swift` and the widget view files, then
  sign and install (README has the steps).
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
