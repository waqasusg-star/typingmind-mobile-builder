# DeepSeek Pulse — iPhone (native Swift/UIKit)

Version 1.0.0 (build 1). Bundle ID `com.waqas.deepseekpulse`, minimum iOS 15.0.

## What it shows

- A widget-style card with your DeepSeek API account balance: total, granted and topped-up amounts, currency and API availability, read from `GET https://api.deepseek.com/user/balance` with your own API key.
- Whether pricing is currently **peak** or **off-peak**, with a live countdown to the next switch, the window in UTC and in your local time, and a 24-hour band showing where the current moment sits.
- A rate table per model (`cache hit`, `cache miss`, `output`) in USD per 1M tokens, with the active column highlighted.
- An in-app editor for the API key (iOS Keychain), the off-peak window and the rates.

## The pricing schedule is editable seed data

The seeded values come from DeepSeek's published standard schedule together with the documented off-peak discounts (16:30–00:30 UTC, 50% off `deepseek-chat`, 75% off `deepseek-reasoner`). The app does **not** download prices, so confirm and correct them in **Settings → Standard rates** against <https://api-docs.deepseek.com/quick_start/pricing>. If DeepSeek withdrew off-peak discounts, switch the schedule off and the app reports standard pricing everywhere.

The API key is written to the iOS Keychain and sent only to `api.deepseek.com`. It is never bundled in source.

## Build

`xcodegen generate` (reads the generated project spec), then build the app target in Xcode. GitHub builds publish a versioned **unsigned** arm64 IPA, a matching source ZIP, `Build-Report.json` and `SHA256SUMS.txt`. The unsigned IPA MUST BE SIGNED BEFORE INSTALLATION.

## Limits

- Home-screen WidgetKit widgets need an app-extension target and an App Group. This controlled pipeline builds a single app target, so the widget is rendered inside the app rather than on the Home Screen.
- `Tests/LogicTests.swift` checks the schedule, rate, formatting and balance-parsing logic only. It is not an app, UI or physical-device test suite, and no real API call is made during the build.
