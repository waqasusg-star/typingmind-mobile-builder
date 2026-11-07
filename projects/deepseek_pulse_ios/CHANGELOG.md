# Changelog — DeepSeek Pulse (iOS)

All notable changes. Version, build, bundle identifier and the Keychain service name are kept stable
unless an entry says otherwise.

## 1.0.9 — build 10

### App icon
- Reinstalls cleanly now report the truth: the icon card asks the bundle for a compiled catalog icon
  (`Assets.car`) instead of falling back to the drawn mark for every build, so the "wireframe on the
  Home Screen" state can no longer be described incorrectly.
- The pipeline keeps the `generated_v1` icon profile enabled: a 1024 px opaque master plus the iPhone
  and iPad slots inside `Assets.car`, checked in the archive before the IPA is exported.

### Lock Screen widgets (redesigned)
- Seven accessory designs, chosen per size and persisted with the rest of the appearance:
  - Rectangular: **Ribbon** (state, live countdown, 24-hour band), **Ring** (progress ring beside the
    countdown), **Compact** (two short lines).
  - Circular: **Gauge** (state word plus peak time left) and **Countdown** (the timer alone).
  - Inline: **Sentence** and **Time only**.
- Every accessory view draws from the same `WidgetPlanner` snapshot and the same `LockScreenText`
  strings the in-app preview uses, so the preview cannot disagree with the Lock Screen.
- The Lock Screen never shows the balance or the key state: there is no room to explain either, and
  the old wording was the source of the reported errors.

### API key wording on all widgets
- The widget can no longer say **"No key"** or **"No API key saved"**. With no balance and an unknown
  key state it says **"Open app" / "Tap to load your balance"**; only a positive report of a missing
  key says **"Add key in app"**.
- Two real causes fixed:
  1. The extension's own schedule-only seed could outrank a newer app snapshot that carried a
     balance, so the widget kept rendering the empty copy. Ranking now prefers a copy with a balance
     and only then the newest write.
  2. Nothing told the app when a widget tap happened. A tap now writes a small request file in the
     shared container; the app answers it on launch and on foreground, refreshes once and stamps the
     answer. Requests are rate-limited to one per 90 seconds and expire after six hours.

### Timing
- Timeline reloads are requested every 15 minutes instead of every 60, so the state word, the band
  and the stale badge keep up with the countdown. iOS still decides the real moment, and Low Power
  Mode delays it further; this is a request, not a promise.

### Themes
- Sixteen palettes remain, and the artwork now actually reaches the surfaces: Gradient, Sunset
  horizon, Dot field, Grid, Rings and Plain are drawn on the widget background **and** on the app's
  own screen background.
- The app background, cards and navigation bar pick up the theme through one shared shape model
  (`Shared/ThemeArtworkCore.swift`), so the app and the widget cannot drift apart.

### Verification
- The `widgetkit_v1` Foundation harness gained checks for: the no-key wording policy (all four key
  states), the handshake cooldown, the request expiry boundary, the balance-first ranking rule, the
  seven accessory designs plus family clamping, the lock-screen appearance round trip including the
  legacy-payload fallback, and the artwork geometry edge cases.
- CI compiles the app for iPhone (arm64), compiles and inspects `Assets.car`, builds the widget
  extension, and exports the unsigned IPA. Signing, physical-device and Lock Screen rendering are
  verified by the installer on the device, not in CI.

## 1.0.8 — build 9

- Compiled Home Screen AppIcon, honest widget key-state wording, theme coverage tests.

## Earlier

See the repository history for 1.0.7 and before: theme catalogue, ten Home Screen designs, the
schedule-only seed, the two-tier snapshot store and the strict Keychain write path.
