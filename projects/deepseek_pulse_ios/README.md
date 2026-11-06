# DeepSeek Pulse — iPhone (native Swift/UIKit)

Version 1.0.2 (build 3). Bundle ID `com.waqas.deepseekpulse`, scheme `DeepSeekPulse`, minimum iOS 15.0.

## What it shows

- Peak / off-peak pricing state with a live countdown to the next switch, the windows in UTC and in
  your local time, a 24-hour band and a 7-day outlook that marks weekends and PRC holidays.
- Your DeepSeek API account balance (total, granted, topped up) from
  `GET https://api.deepseek.com/user/balance` with your own key, cached for offline display.
- A rate table for `deepseek-flash` (V4.1-Flash-1017) and `deepseek-v4-pro` (V4-Pro-0813).
- **Widget Studio** (toolbar gear → "Widgets & Live Activity"): the medium, small, Lock-Screen and
  Live-Activity widget layouts drawn with your live saved schedule.

## Widgets: what is real in 1.0.2 and what is not

| Piece | File | Status |
| --- | --- | --- |
| Shared widget planner | `Sources/WidgetPlanner.swift` | Implemented, compiled, executed checks |
| Medium widget layout | `Sources/WidgetFullCardView.swift` | Implemented, compiled, shown in Widget Studio |
| Small widget layout | `Sources/WidgetCompactCardView.swift` | Implemented, compiled |
| Lock Screen layout | `Sources/WidgetLockScreenCardView.swift` | Implemented, compiled |
| Live Activity card | `Sources/LiveActivityCardView.swift` | Implemented, compiled |
| Refresh + deep-link policy | `Sources/WidgetPolicy.swift` | Implemented, compiled |
| WidgetKit Home-Screen extension | — | **Not shipped** |
| ActivityKit Live Activity extension | — | **Not shipped** |

A Home-Screen widget, a Lock-Screen widget and a Dynamic Island Live Activity must live in their own
WidgetKit / ActivityKit extension targets with their own Info.plist, entitlements and an App Group.
This pipeline builds a single application target, so those extensions are not in the IPA and are not
pretended to be.

### Adding the real widget in Xcode

1. `brew install xcodegen` then `xcodegen generate` in this source folder.
2. Xcode → File → New → Target → **Widget Extension** (enable *Include Live Activity* if you want
   the Dynamic Island card). Bundle id `com.waqas.deepseekpulse.widget`.
3. Add `Sources/WidgetPlanner.swift`, `Sources/WidgetFullCardView.swift`,
   `Sources/WidgetCompactCardView.swift`, `Sources/WidgetLockScreenCardView.swift`,
   `Sources/LiveActivityCardView.swift` and `Sources/WidgetPolicy.swift` to the extension target.
4. Timeline: `WidgetPlanner.snapshot(schedule: store.schedule, at: Date())`; entry date
   `WidgetPolicy.refreshDelay(now:nextSwitchAt:)`.
5. Enable the App Group `group.com.waqas.deepseekpulse` on both targets and point `SettingsStore` at
   it so the extension reads the same schedule. Use `WidgetPolicy.deepLinkURL()` for the tap target.
6. Sign with your own team and install.

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
enforced by `RequestPolicy.isAllowed(url:)`. The last balance is cached locally.

## Rebuild on a Mac

```bash
xcodegen generate
open DeepSeekPulse.xcodeproj
```

Unsigned command-line build (this is what an unsigned IPA is):

```bash
xcodebuild -project DeepSeekPulse.xcodeproj -scheme DeepSeekPulse \
  -configuration Release -sdk iphoneos -destination generic/platform=iOS \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
  -archivePath build/DeepSeekPulse.xcarchive archive
mkdir -p build/Payload
cp -R build/DeepSeekPulse.xcarchive/Products/Applications/DeepSeekPulse.app build/Payload/
cd build && zip -qry DeepSeekPulse-iOS-1.0.2-build3-ios-unsigned.ipa Payload
```

## Tests

`Tests/WidgetPlannerTests.swift` (widget state, minutes left, countdown text, refresh bounds, deep
link) and `Tests/PolicyTests.swift` (schedule, prices, balance payload, request policy) are
Foundation component checks. They are not an app, UI or device suite and make no network call.

## Limits

- Home-Screen / Lock-Screen widget and Dynamic Island Live Activity extensions are **not** in this
  IPA; see the table and the Xcode steps above.
- Prices, windows and holidays are local data verified by hand on 2026-11-06.
- Unsigned output: MUST BE SIGNED BEFORE INSTALLATION.
