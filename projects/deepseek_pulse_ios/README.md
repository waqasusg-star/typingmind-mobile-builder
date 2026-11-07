# DeepSeek Pulse — native iPhone app + WidgetKit extension

Version 1.0.5 (build 6) · bundle `com.waqas.deepseekpulse` · widget bundle
`com.waqas.deepseekpulse.widgets` · iOS 15.0+

Offline dashboard for DeepSeek pricing: current peak / off-peak state, the next switch, the rate
table and your account balance from `api.deepseek.com/user/balance` using your own API key. The key
lives in the iOS Keychain and is never put in a widget payload or a log.

## Navigation

The dashboard opens with an always-visible **Settings** and **Widgets** button row above the balance
card. Settings holds the API key, the pricing schedule, the holiday calendar and the rates. Widgets
holds the widget previews and the add-to-Home-Screen steps.

## Layout

| Path | Target | Contents |
| --- | --- | --- |
| `Sources/` | app | UIKit screens, toolbar buttons, app icon drawing, Keychain adapter, widget bridge |
| `Shared/` | app + extension | Foundation only: schedule, planner, snapshot codec, storage tiers, account policy |
| `Sources/RequestPolicy.swift` | app + extension | UIKit-free pricing/schedule/balance logic |
| `WidgetSources/` | extension | `@main` WidgetBundle, timeline provider, SwiftUI views |
| `Tests/` | CI harnesses | `PolicyTests` (foundation_policy) and `WidgetKitTests` (widgetkit_v1) |

## Widget storage

1. `group.com.waqas.deepseekpulse` App Group container, file `widget-snapshot.json`, written by the app.
2. The extension's own Application Support copy, file `pulse-widget-local.json`, written by the extension.

When neither tier holds data, the extension writes a schedule-only snapshot from the verified
constants. It contains no balance and no key flag.

## App icon

`Sources/AppIconMark.swift` draws the mark at any size. The CI-generated project compiles the app
sources and Info.plist; if your Xcode project adds an `Assets.xcassets` AppIcon set, iOS uses that
image, otherwise Widget Studio shows the drawn mark and says so.

## Build

```bash
xcodegen generate      # uses project.yml; CI generates its own controlled spec
open DeepSeekPulse.xcodeproj
```

Pick your signing team, add `com.waqas.deepseekpulse` as an App Group on both targets if allowed, then
run on a device. The signing service must sign **both** bundles.

## Known limits

- WidgetKit decides refresh timing; the widget never polls the network.
- The extension cannot read the Keychain, so it can never fetch a balance on its own.
- Physical-device, gallery and shared-container behaviour are not verified by a CI build.
