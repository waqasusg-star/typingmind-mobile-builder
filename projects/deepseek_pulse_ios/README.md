# DeepSeek Pulse — native iPhone app + WidgetKit extension

Version 1.0.4 (build 5) · bundle `com.waqas.deepseekpulse` · widget bundle
`com.waqas.deepseekpulse.widgets` · iOS 15.0+

Offline dashboard for DeepSeek pricing: current peak / off-peak state, the next switch, the rate
table and your account balance from `api.deepseek.com/user/balance` using your own API key. The key
lives in the iOS Keychain and is never put in a widget payload or a log.

## Layout

| Path | Target | Contents |
| --- | --- | --- |
| `Sources/` | app | UIKit screens, settings, Keychain adapter, app widget bridge |
| `Shared/` | app + extension | Foundation only: schedule, planner, snapshot codec, storage tiers, account policy |
| `Sources/RequestPolicy.swift` | app + extension | UIKit-free pricing/schedule/balance logic |
| `WidgetSources/` | extension | `@main` WidgetBundle, timeline provider, SwiftUI views |
| `Tests/` | CI harnesses | `PolicyTests` (foundation_policy) and `WidgetKitTests` (widgetkit_v1) |

## Widget storage

The widget reads two tiers and prefers the first usable one:

1. `group.com.waqas.deepseekpulse` App Group container, file `widget-snapshot.json`, written by the app.
2. The extension's own Application Support copy, file `pulse-widget-local.json`. The extension writes
   this itself, so the countdown and schedule work even when the App Group entitlement is not granted
   by the signer.

When neither tier holds data, the extension writes a schedule-only snapshot from the verified
constants. It contains no balance and no key flag.

## Build

```bash
xcodegen generate      # uses project.yml; CI generates its own controlled spec
open DeepSeekPulse.xcodeproj
```

Pick your signing team, select the DeepSeekPulse scheme, add `com.waqas.deepseekpulse` as an App Group
on both the app and the widget target if your team allows it, then run on a device.

The signing service must sign **both** bundles; a signed IPA that keeps only the app bundle shows no
widget at all.

## Known limits

- WidgetKit decides refresh timing; the widget never polls the network and never counts down with
  extra timeline entries (iOS renders the timer itself).
- The extension cannot read the Keychain, so it can never fetch a balance on its own.
- Physical-device, gallery and shared-container behaviour are not verified by a CI build.
