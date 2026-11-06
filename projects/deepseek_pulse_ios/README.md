# DeepSeek Pulse — iPhone (native Swift/UIKit)

Version 1.0.1 (build 2). Bundle ID `com.waqas.deepseekpulse`, minimum iOS 15.0.

## What it shows

- A widget-style card with your DeepSeek API account balance: total, granted and topped-up amounts, currency and API availability, read from `GET https://api.deepseek.com/user/balance` with your own API key.
- Whether pricing is currently **peak** or **off-peak**, with a live countdown to the next switch (days included), the window in UTC and in your local time, a 24-hour band for today and a 7-day outlook that shows weekends and listed holidays.
- A rate table for `deepseek-flash` (V4.1-Flash-1017) and `deepseek-v4-pro` (V4-Pro-0813) with cache-hit, cache-miss and output prices in USD per 1M tokens, and the active peak or off-peak column highlighted.
- An in-app editor for the API key (iOS Keychain), the peak windows, the peak weekdays, the PRC holiday list and the rates.

## The official schedule and prices (verified 2026-11-06)

Peak = Monday–Friday **01:00–04:00** and **06:00–10:00 UTC**, excluding Chinese public holidays. Every other hour, all weekends and every Chinese public holiday is off-peak (50% off) for both models:

| model | hit (peak / off-peak) | miss (peak / off-peak) | output (peak / off-peak) |
| --- | --- | --- | --- |
| deepseek-flash · V4.1-Flash-1017 | 0.006 / 0.003 | 0.30 / 0.15 | 1.20 / 0.60 |
| deepseek-v4-pro · V4-Pro-0813 | 0.044 / 0.022 | 1.32 / 0.66 | 3.96 / 1.98 |

Source: <https://api-docs.deepseek.com/quick_start/pricing/>. These values live in the app and are **not downloaded**; a human checked them on that date. Edit them in Settings if they change.

### Chinese public holidays are not bundled

No holiday list is included or fetched, so the app cannot know a Chinese public holiday by itself. It therefore:

- treats every weekday as a peak day by default and labels such days **unverified** — in the widget, the schedule caption and the 7-day outlook;
- lets you add the dates you checked in the official holiday notice (Settings → PRC public holidays), each of which becomes off-peak all day;
- lets you enter the date range you actually checked; days outside that range stay **unverified** instead of pretending accuracy.

## Custom values

Rates, peak windows, peak weekdays and the discount switch are editable. When they differ from the verified defaults the dashboard says so explicitly ("Custom schedule", "your custom values"), so verified defaults and your own assumptions are never mixed up. "Restore official schedule" keeps your holiday dates and restores the verified windows.

## Storage and privacy

The API key is written to the iOS Keychain and sent only to `api.deepseek.com/user/balance` as a Bearer token. It is never bundled in source, logged or sent anywhere else. The last balance is cached locally for offline display.

## Build

XcodeGen reads the generated project spec, then build the app target. GitHub builds publish a versioned **unsigned** arm64 IPA, a matching source ZIP, `Build-Report.json` and `SHA256SUMS.txt`. The unsigned IPA MUST BE SIGNED BEFORE INSTALLATION.

## Limits

- **No Home-Screen WidgetKit widget.** A real widget needs an app-extension target and an App Group, which this controlled single-target pipeline does not build; the widget is the in-app card.
- `Tests/LogicTests.swift` exercises the schedule, transition, holiday, rate, formatting and balance-parsing logic. It is not an app/UI or physical-device suite, and the build makes no live DeepSeek API call.
