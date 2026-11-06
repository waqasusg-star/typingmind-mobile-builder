# DeepSeek Pulse — iPhone (native Swift/UIKit)

Version 1.0.1 (build 2). Bundle ID `com.waqas.deepseekpulse`, scheme `DeepSeekPulse`, minimum iOS 15.0.

## What it shows

- A widget-style card with your DeepSeek API account balance: total, granted and topped-up amounts, currency and API availability, read from `GET https://api.deepseek.com/user/balance` with your own API key.
- Whether pricing is currently **peak** or **off-peak**, with a live countdown to the next switch (days included), the window in UTC and in your local time, a 24-hour band for today and a 7-day outlook that shows weekends and listed PRC holidays.
- A rate table for `deepseek-flash` (V4.1-Flash-1017) and `deepseek-v4-pro` (V4-Pro-0813) with cache-hit, cache-miss and output prices in USD per 1M tokens, and the active peak or off-peak column highlighted.
- An in-app editor for the API key (iOS Keychain), the peak windows and weekdays, the PRC holiday list and the rates.

## Schedule and prices (verified 2026-11-06)

Peak = Monday–Friday **01:00–04:00** and **06:00–10:00 UTC**, excluding PRC public holidays. Every other hour, **all weekends** and every PRC public holiday is off-peak. Both models are exactly 50% off in off-peak:

| model | hit (peak / off-peak) | miss (peak / off-peak) | output (peak / off-peak) |
| --- | --- | --- | --- |
| deepseek-flash · V4.1-Flash-1017 | 0.006 / 0.003 | 0.30 / 0.15 | 1.20 / 0.60 |
| deepseek-v4-pro · V4-Pro-0813 | 0.044 / 0.022 | 1.32 / 0.66 | 3.96 / 1.98 |

Source: <https://api-docs.deepseek.com/quick_start/pricing/>. These values are stored in the app and **never downloaded**; a human verified them on 2026-11-06. Edit them in Settings if DeepSeek changes them.

## PRC public holidays: verified 2026–2027, honest about later years

The app ships an explicit, dated holiday list and the range it covers:

- **2026** (inclusive): 01-01…01-03, 02-15…02-23, 04-04…04-06, 05-01…05-05, 06-19…06-21, 09-25…09-27, 10-01…10-07.
- **2027** (inclusive): 01-01…01-03, 02-05…02-13, 04-03…04-05, 05-01…05-05, 06-09, 09-15, 10-01…10-07.

62 dates in total, coverage `2026-01-01…2027-12-31`, verified 2026-11-06. Sources: PRC State Council notices of 2025-11-04 and 2026-11-05, and the English official table opened on 2026-11-06 — <https://english.www.gov.cn/policies/latestreleases/202611/06/content_WS6aed74dcc6d00ca5f9a0e22e.html>.

- Days **inside** that range are working days unless listed; listed days are off-peak all day.
- Days **outside** it (2025 and 2028 or later) are reported as **unverified**, never guessed: the card shows "Calendar update needed: no verified PRC holiday list covers 2028…", the 7-day outlook marks those days `unverified`, and Settings shows the coverage range and source. Add the dates yourself after checking the next official notice.
- Chinese **make-up working Saturdays/Sundays never become peak**: DeepSeek charges every weekend as off-peak, so only Monday–Friday can carry a peak window.

## Custom values vs verified defaults

Rates, peak windows, peak weekdays and the discount switch are editable. When they differ from the verified defaults the dashboard says so explicitly ("Custom schedule", "your custom values"). "Restore official schedule and verified holidays" brings back the verified windows and the 2026–2027 list.

## Storage and privacy

The API key is written to the iOS Keychain and sent only to `api.deepseek.com/user/balance`, enforced by `RequestPolicy.isAllowed(url:)`. It is never bundled in source, logged or sent anywhere else. The last balance is cached locally for offline display.

## Rebuild this source archive on a Mac

This archive is self-contained: it carries a source-only `project.yml` and needs no scripts, entitlements or package dependencies.

Requirements: macOS with Xcode 16.x (the reviewed build used Xcode 16.4 / build 16F6) and XcodeGen 2.46.0 (`brew install xcodegen`).

```bash
# 1. Generate Config/Info.plist and DeepSeekPulse.xcodeproj from project.yml
xcodegen generate

# 2. Open in Xcode, choose your own signing team, then run on an arm64 iPhone
open DeepSeekPulse.xcodeproj
```

Command-line build and archive without signing (this is what produces an unsigned IPA that must be signed before installation):

```bash
xcodebuild -project DeepSeekPulse.xcodeproj -scheme DeepSeekPulse \
  -configuration Release -sdk iphoneos -destination generic/platform=iOS \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
  -archivePath build/DeepSeekPulse.xcarchive archive

mkdir -p build/Payload
cp -R build/DeepSeekPulse.xcarchive/Products/Applications/DeepSeekPulse.app build/Payload/
cd build && zip -qry DeepSeekPulse-iOS-1.0.1-build2-ios-unsigned.ipa Payload
```

Run the Foundation component checks the same way the reviewed pipeline does — only these two files, no UIKit:

```bash
swiftc -parse-as-library -O Sources/RequestPolicy.swift Tests/PolicyTests.swift -o build/policy-tests
./build/policy-tests
```

The file `native-project.json` seen in CI logs is generated by the GitHub worker and is deliberately not shipped; `project.yml` is the human-rebuildable equivalent with the same identity, version 1.0.1, build 2, iOS 15.0 and the `Sources` folder.

## Tests

`Tests/PolicyTests.swift` is a standalone Foundation harness compiled with `Sources/RequestPolicy.swift` through the `foundation_policy` test profile (`policy_test_sources` in `project.json`). It covers both weekday windows and their exact boundaries, holiday suppression and range edges, every weekend day of 2026–2027 (including make-up working weekends), multi-day countdowns across nights, weekends and holidays, the year-end switch to an unverified 2028 calendar, full 24-hour band coverage, local-time conversion, published peak/off-peak prices, number formatting, the documented balance payload and the request policy. It is a component suite — not an app, UI or physical-device test, and it makes no network call.

## Limits

- **No Home-Screen WidgetKit widget.** A WidgetKit extension and an App Group are outside this single-target pipeline, so the widget is the in-app card. No entitlement or signing change is made.
- Prices, the peak windows and the holiday list are local data verified by hand on 2026-11-06; nothing is fetched at runtime.
- Unsigned output: signing and installation are the user's step.
