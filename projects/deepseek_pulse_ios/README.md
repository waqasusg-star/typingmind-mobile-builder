# DeepSeek Pulse — iPhone (native Swift/UIKit + WidgetKit)

Version 1.0.3 (build 4). Bundle ID `com.waqas.deepseekpulse`, scheme `DeepSeekPulse`, extension
`DeepSeekPulseWidgets` (`com.waqas.deepseekpulse.widgets`), App Group
`group.com.waqas.deepseekpulse`, minimum iOS 15.0.

## What it shows

- Peak / off-peak pricing state with the next switch, the windows in UTC and local time, a 24-hour
  band and a 7-day outlook that marks weekends and PRC holidays.
- Your DeepSeek API balance (total, granted, topped up) from
  `GET https://api.deepseek.com/user/balance`, cached for offline display.
- A rate table for `deepseek-flash` (V4.1-Flash-1017) and `deepseek-v4-pro` (V4-Pro-0813).
- **A real Home Screen and Lock Screen widget** running in its own WidgetKit extension.

## Source layout

| Path | Compiled into | Contents |
| --- | --- | --- |
| `Sources/` | app | UIKit screens, Keychain, client, bridge |
| `Shared/` | app **and** extension | payload types, cache codec, planner, policy |
| `WidgetSources/` | extension only | `@main` WidgetBundle, timeline provider, SwiftUI views |
| `Tests/` | CI harnesses | Foundation checks; never in app or extension |

The extension compiles `WidgetSources/` + `Shared/` + `Sources/RequestPolicy.swift` only. Everything
it needs is Foundation or WidgetKit; no UIKit, no `SettingsStore`, no Keychain access.

## How the widget gets its data

1. The app fetches the balance as before. The key stays in the iOS Keychain.
2. `WidgetBridge` builds a display-only payload and writes it atomically to
   `widget-snapshot.json` in the App Group container.
3. `WidgetCenter.shared.reloadTimelines(ofKind:)` asks iOS to redraw.
4. The extension decodes the payload and computes state, countdown and timeline boundaries offline.

Honest states instead of fake numbers: `LIVE`, `STALE`, `NO DATA`, `SETUP` (App Group missing),
`UPDATE` (schema mismatch), `UNREADABLE` (corrupt). A missing container never crashes the widget.

## Add the widget on the iPhone

1. Open DeepSeek Pulse once so it writes the snapshot.
2. Home Screen, touch and hold an empty area, then tap Edit or the + button.
3. Search DeepSeek Pulse, choose small or medium, tap Add Widget.

Lock Screen: Edit Lock Screen, add a widget, choose DeepSeek Pulse. Requires iOS 16+.

## Schedule and prices (verified 2026-11-06)

Peak = Monday–Friday **01:00–04:00** and **06:00–10:00 UTC**, excluding PRC public holidays. Every
other hour, all weekends and every PRC holiday is off-peak. Both models are 50% off off-peak.

| model | hit (peak / off-peak) | miss (peak / off-peak) | output (peak / off-peak) |
| --- | --- | --- | --- |
| deepseek-flash · V4.1-Flash-1017 | 0.006 / 0.003 | 0.30 / 0.15 | 1.20 / 0.60 |
| deepseek-v4-pro · V4-Pro-0813 | 0.044 / 0.022 | 1.32 / 0.66 | 3.96 / 1.98 |

Source: <https://api-docs.deepseek.com/quick_start/pricing/>. Stored in the app, never downloaded.

## PRC public holidays

Verified list for 2026 and 2027 (coverage `2026-01-01…2027-12-31`, 62 dates); later years are
reported as unverified rather than guessed.

## Storage and privacy

The API key is written to the iOS Keychain and sent only to `api.deepseek.com/user/balance`,
enforced by `RequestPolicy.isAllowed(url:)`. The shared widget file never contains the key: it
holds formatted balance text, the schedule, rate labels and a `hasAPIKey` boolean.

## Signing (required before installation)

Unsigned output is not installable. The app and the extension must be signed together:

- the same Apple team for `com.waqas.deepseekpulse` and `com.waqas.deepseekpulse.widgets`;
- an App Group `group.com.waqas.deepseekpulse` enabled in **both** provisioning profiles;
- the extension kept inside `DeepSeekPulse.app/PlugIns/`, never stripped.

Without the App Group the widget still installs and shows its `SETUP` state.

## Tests

- `Tests/PolicyTests.swift` — schedule, prices, balance payload, request policy.
- `Tests/WidgetPlannerTests.swift` — widget state, minutes left, countdown text, refresh bounds.
- `Tests/WidgetKitTests.swift` — payload round trip, schema rejection, corruption, staleness
  boundary, secret guard, sanitising, calendar and boundary behaviour, identity constants.

These are Foundation component checks run on macOS CI. They are not an app, UI, gallery or
physical-device suite.

## Rebuild on a Mac

`project.yml` describes the two-target project for XcodeGen. The reviewed CI does not use it: the
worker generates its own `native-project.json` and Info.plists. Keep the CI values as the source of
identity. See `BUILDER-REBUILD.md` in the source archive.
