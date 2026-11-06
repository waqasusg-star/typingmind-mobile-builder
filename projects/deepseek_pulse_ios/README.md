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
| `Sources/` | app | UIKit screens, Keychain, client, widget bridge |
| `Shared/` | app **and** extension | payload types, cache codec, planner, policy, account policy |
| `WidgetSources/` | extension only | `@main` WidgetBundle, timeline provider, SwiftUI views |
| `Tests/` | CI harnesses | Foundation checks; never in app or extension |

The extension compiles `WidgetSources/` + `Shared/` + `Sources/RequestPolicy.swift` only. Everything
it needs is Foundation or WidgetKit; no UIKit, no `SettingsStore`, no Keychain access.

## How the widget works

1. The app fetches the balance as before. The key stays in the iOS Keychain.
2. `WidgetBridge` builds a display-only payload and writes it atomically to
   `widget-snapshot.json` in the App Group container, then calls
   `WidgetCenter.shared.reloadTimelines(ofKind:)`.
3. The extension decodes the payload and computes state and countdown offline.

### Countdown

Countdowns use `Text(target, style: .timer)`, which iOS advances itself. There is no per-second
network request, no per-second timeline entry and no background work. When no switch instant is
known — discounts off, no peak window, or unreadable data — a static label is shown instead.

### Timeline

`WidgetTimelinePlanner` (in `Shared/WidgetPolicy.swift`) builds a bounded plan:

- the current instant;
- the nearest real peak/off-peak transition inside a 24-hour horizon;
- the cache-stale crossing, emitted one second **past** the codec threshold, because the codec only
  reports stale when `age > staleAfter`;
- every UTC midnight inside the horizon, where the day key and band change;
- one bounded reload entry so the timeline always terminates.

The plan is capped at 12 entries, and the current instant, the near transition and the stale
crossing are reserved, so the cap cannot drop them. iOS still decides when a reload really happens;
nothing here promises an exact refresh time.

### States instead of fake numbers

`RECENT` (fresh cache), `CACHED` (older than one hour), `NO DATA`, `SETUP` (App Group missing),
`UPDATE` (schema mismatch), `UNREADABLE` (corrupt). A missing container never crashes the widget.

### Backgrounds

On iOS 17 and later the views declare `containerBackground(for: .widget)` so the gallery renders
them normally; older systems use the gradient background directly. Deployment target stays iOS 15,
and the Lock Screen accessories are `@available(iOS 16+)`.

## Add the widget on the iPhone

1. Open DeepSeek Pulse once so it writes the snapshot.
2. Home Screen, touch and hold an empty area, then tap Edit or the + button.
3. Search DeepSeek Pulse, choose small or medium, tap Add Widget.

Lock Screen: Edit Lock Screen, add a widget, choose DeepSeek Pulse (iOS 16+).
Tapping the widget opens the app through `com.waqas.deepseekpulse://status`.

## API key and account changes

The key lives in the iOS Keychain and is sent only to `api.deepseek.com/user/balance`, enforced by
`RequestPolicy.isAllowed(url:)`.

Saving a key replaces the stored one. `SettingsStore.replaceAPIKey` compares the normalized previous
and new key **in memory**, and when they differ it increments an account generation and clears the
cached balance. Removing the key does the same. Any balance request in flight is cancelled or its
result discarded, so a late response for a removed or changed account cannot repopulate the cache or
the widget. No key, hash or fingerprint is persisted or written to the shared container.

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

## Signing (required before installation)

Unsigned output is not installable. The app and the extension must be signed together:

- the same Apple team for `com.waqas.deepseekpulse` and `com.waqas.deepseekpulse.widgets`;
- an App Group `group.com.waqas.deepseekpulse` enabled in **both** provisioning profiles;
- the extension kept at `DeepSeekPulse.app/PlugIns/DeepSeekPulseWidgets.appex`.

Without the App Group the widget still installs and shows its `SETUP` state.

## Tests

Executed on macOS CI as Foundation component checks:

- `Tests/PolicyTests.swift` — schedule, prices, balance parsing, request policy.
- `Tests/WidgetKitTests.swift` — payload round trip, schema rejection, corruption, the staleness
  threshold measured from the fetch time, a real integration check that decodes the same bytes at
  the planner's stale entry and confirms it is stale (and fresh one second earlier), secret guard,
  sanitising, calendar and pricing boundaries, deep-link scheme, bounded timeline plans for normal,
  holiday, no-cache and non-discount schedules, UTC midnight boundaries, and the account generation
  and key-change rules.

These are component checks. They are **not** an app UI, widget gallery, shared-container, privacy
blur or physical-device test, and no device run is implied.

## Rebuild on a Mac

`project.yml` describes the two-target project for XcodeGen. The reviewed CI does not use it: the
worker generates its own `native-project.json` and Info.plists, which are included in the source
archive. Keep the CI values as the source of identity. See `BUILDER-REBUILD.md` and
`WIDGET-SIGNING.json` in the source archive.
