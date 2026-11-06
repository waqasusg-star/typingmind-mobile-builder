# DeepSeek Pulse — changelog

# iPhone 1.0.1 / build 2

Corrects obsolete pricing and schedule data, adds a verified PRC holiday calendar and makes the assumption state honest. The not-yet-delivered change set keeps version 1.0.1 build 2.

## Fixed

- **Obsolete schedule removed.** The single 16:30–00:30 UTC window is gone. Peak is modelled as the published set of UTC weekday intervals — **Monday–Friday 01:00–04:00 and 06:00–10:00 UTC** — excluding PRC public holidays; every other hour, every weekend and every PRC public holiday is off-peak.
- **Obsolete prices removed.** `deepseek-chat` / `deepseek-reasoner` (including the 75% reasoner discount) are replaced by the verified 2026-11-06 prices: `deepseek-flash` (V4.1-Flash-1017) 0.006 / 0.30 / 1.20 and `deepseek-v4-pro` (V4-Pro-0813) 0.044 / 1.32 / 3.96 USD per 1M tokens, both exactly 50% off in off-peak.
- **Verified PRC holiday calendar for 2026–2027.** 62 inclusive dates (2026: 01-01…01-03, 02-15…02-23, 04-04…04-06, 05-01…05-05, 06-19…06-21, 09-25…09-27, 10-01…10-07; 2027: 01-01…01-03, 02-05…02-13, 04-03…04-05, 05-01…05-05, 06-09, 09-15, 10-01…10-07) with coverage `2026-01-01…2027-12-31`, verified 2026-11-06, from the State Council notices of 2025-11-04 and 2026-11-05 and the English official table. No holiday date was invented.
- **Unknown years are labelled, not guessed.** Outside the verified range (2025, 2028+) the day is `unverified`: the card prints "Calendar update needed: no verified PRC holiday list covers 2028…", the outlook marks the day, and Settings shows the coverage range and source.
- **Weekends are always off-peak.** Because DeepSeek charges all weekends off-peak, a PRC make-up working Saturday/Sunday never becomes a peak day; only Monday–Friday can carry a peak window. The 2026–2027 test loop checks every weekend day at 02:00 and 07:00 UTC.
- **Current state and countdown** use the multi-interval model with inclusive starts and exclusive ends. The next-transition search walks forward day by day across nights, weekends and listed holidays, so Friday evening counts down to Monday 01:00 UTC. Multi-day gaps render as `2d 14h 30m`; the target shows a UTC stamp, a local stamp and a today/tomorrow/in-N-days tag.
- **24-hour band and 7-day outlook** are drawn from the day's real intervals with a third colour for "standard only"; weekends and listed holidays render as one off-peak band.
- **Verified vs custom is explicit.** Custom schedules and custom rates are labelled on the dashboard and in the rates caption; "Restore official schedule and verified holidays" reinstates the verified windows and the 2026–2027 list.
- **Migration schema 1/2 → 3** drops the obsolete window and retired prices, installs the verified schedule, prices and holiday list, keeps the Keychain API key and the cached balance, and shows a one-time upgrade notice in Settings.
- **Settings validation**: windows must be HH:MM inside one UTC day, at least one peak day while discounts are on, the coverage range must be two ordered yyyy-MM-dd dates, every holiday date is parsed, and every rate must be a non-negative number. Saving an unchanged coverage range keeps its original verification date instead of restamping it.
- **Structure for testability.** The UIKit-free logic moved to `Sources/RequestPolicy.swift` (endpoint allow-list, bearer header building, status mapping included); `Sources/DeepSeekKit.swift` is now a comment-only placeholder so nothing is defined twice; `Tests/LogicTests.swift` is a comment-only redirect and the harness lives in `Tests/PolicyTests.swift`.

## Preserved

- Bundle ID `com.waqas.deepseekpulse`, scheme `DeepSeekPulse`, Keychain storage of the API key, the balance endpoint `https://api.deepseek.com/user/balance` with `is_available` and `balance_infos` string fields, the cached-balance offline display and the in-app widget-style card.
- No WidgetKit extension, entitlement, signing or provisioning change. Output stays an unsigned arm64 IPA.

## Verification

- `Tests/PolicyTests.swift` (Foundation, compiled with `Sources/RequestPolicy.swift` via test profile `foundation_policy`) covers: both weekday windows and exact boundaries; holiday suppression plus range edges (2026-01-01, 2026-02-23, 2026-10-07, 2027-10-07 listed; 2026-02-24, 2027-10-08 working); every weekend day of 2026–2027; multi-day countdowns (Friday → Monday 62.5 h, New Year 2026 → Monday 96.5 h, Spring Festival follow-up 17 h); the year-end switch to an unverified 2028 calendar with `uncertain` transitions and the calendar warning; full 24-hour band coverage on working days, weekends, holidays and unverified days; local conversion at UTC, +05:30, +08:00 and −05:00; published peak and off-peak prices for both models with discount clamping; number formatting; the documented balance payload plus numeric/partial/two-currency variants and a Codable round-trip; and the request policy (endpoint allow-list, lookalike host, cleartext, bearer header, status mapping).
- Executed results are reported only from the real build report and log. Component checks are not an app/UI/device suite, no DeepSeek account is called during the build, and no signing-service compatibility is claimed.

## Known limits

- **No Home-Screen WidgetKit widget.** A WidgetKit extension and App Group are outside this single-target pipeline; the widget remains the in-app card.
- Prices, windows and the holiday list are local data verified on 2026-11-06. Nothing is fetched at runtime, so a later DeepSeek or State Council change needs a manual edit.
- Unsigned IPA output: MUST BE SIGNED BEFORE INSTALLATION.

# iPhone 1.0.0 / build 1

First native Swift/UIKit release: widget-style balance card, balance client, peak/off-peak engine, live countdown, 24-hour band, rate table, Keychain API key and editable schedule/rates. Superseded because the seeded 16:30–00:30 window and the `deepseek-chat` / `deepseek-reasoner` prices were obsolete.
