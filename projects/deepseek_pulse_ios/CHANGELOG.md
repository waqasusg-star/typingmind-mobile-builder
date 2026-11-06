# DeepSeek Pulse — changelog

# iPhone 1.0.1 / build 2

Corrects obsolete pricing and schedule data found in 1.0.0, and separates verified defaults from user assumptions.

## Fixed

- **Obsolete schedule removed.** The single 16:30–00:30 UTC window is gone. Peak pricing is now modelled as the published set of UTC weekday intervals: **Monday–Friday 01:00–04:00 and 06:00–10:00 UTC**, excluding Chinese public holidays. Every other hour, all weekends and every listed Chinese public holiday is off-peak.
- **Obsolete prices removed.** `deepseek-chat` / `deepseek-reasoner` seeds (including the 75% reasoner discount) are replaced by the prices verified on 2026-11-06: `deepseek-flash` (V4.1-Flash-1017) 0.006 / 0.30 / 1.20 and `deepseek-v4-pro` (V4-Pro-0813) 0.044 / 1.32 / 3.96 USD per 1M tokens, both exactly 50% off in off-peak.
- **Current state** uses the new model: weekday-only peak, weekend and holiday exclusion, exact inclusive-start/exclusive-end boundaries, and a separate `standard` state when the discount switch is off.
- **Next-transition countdown** searches forward across days, weekends and listed holidays instead of assuming a daily window, so Friday evening correctly counts down to Monday 01:00 UTC. Multi-day countdowns now render as `2d 14h 30m`, and the target is shown as a UTC stamp plus a local stamp and a today/tomorrow/in-N-days tag.
- **Daily band** is drawn from the day's real intervals, with a third colour for "standard only"; the 7-day outlook shows each day's UTC windows, weekend off-peak days and listed holidays.
- **Chinese public holidays are never invented.** No holiday dates are bundled or downloaded. Each weekday is reported as **unverified** until you either add the dates you checked (Settings → PRC public holidays) or declare the range you checked. Days outside that range stay unverified, and the widget says which assumption the countdown relies on.
- **Verified vs custom is explicit.** The dashboard marks a custom schedule or custom rates, and Settings offers "Restore official schedule" (keeping your holiday dates) and "Reset rates to the verified defaults". Source URL and the verified-as-of date are shown in the app; nothing claims to auto-update prices.
- **Migration from 1.0.0** (schema v1 → v2) drops the obsolete window and retired model prices, writes the verified defaults, and shows a one-time "Upgraded from 1.0.0" note in Settings. The API key in the Keychain, the cached balance and the bundle identity are untouched.
- **Settings validation**: peak windows must be HH:MM inside one UTC day, at least one peak day or the discount switch off, holiday range must be two yyyy-MM-dd dates in order, every holiday date is parsed, and every rate must be a non-negative number.

## Preserved

- Bundle ID `com.waqas.deepseekpulse`, scheme `DeepSeekPulse`, Keychain storage of the API key, the balance endpoint `https://api.deepseek.com/user/balance` with `is_available` and `balance_infos` string fields, the cached-balance offline display, and the in-app widget-style card.
- No signing, entitlement or provisioning changes. Output is still an unsigned arm64 IPA.

## Verification

- `Tests/LogicTests.swift` rewrites the regression suite for the new model: both weekday intervals with exact boundaries, weekends, listed-holiday overrides, calendar coverage and unverified state, single-day and multi-day transitions (Friday → Monday, and Tuesday → Thursday across a holiday), countdown formatting, local-time conversion for +05:30 / +08:00 / −05:00, published peak and off-peak prices for both models, discount clamping, USD-per-1M formatting, the documented balance payload plus numeric/partial/two-currency variants, request headers and status mapping, and a Codable round-trip of the schedule.
- Component checks only. No app/UI suite, no physical-device run, no live DeepSeek account call, no signing-service compatibility test, and no automated verification of the real Chinese holiday calendar. Whether the controlled pipeline actually executes this test file is reported from the real build log, not assumed.

## Limits

- **No Home-Screen WidgetKit widget.** A WidgetKit extension and App Group are outside this single-target pipeline, so the widget remains the in-app card.
- Prices and the schedule are local data verified by hand on 2026-11-06; the app does not fetch them. If DeepSeek changes the schedule, the prices or the holiday exclusions, edit them in Settings.
- Unsigned IPA output: MUST BE SIGNED BEFORE INSTALLATION.

# iPhone 1.0.0 / build 1

First native Swift/UIKit release: widget-style balance card, `DeepSeekClient` for `GET /user/balance`, peak/off-peak engine, live countdown, 24-hour band, rate table, Keychain API key and editable schedule/rates. Superseded by 1.0.1 because the seeded 16:30–00:30 window and the `deepseek-chat` / `deepseek-reasoner` prices were obsolete.
