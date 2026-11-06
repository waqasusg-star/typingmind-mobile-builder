# iPhone 1.0.0 / build 1

First native Swift/UIKit release of DeepSeek Pulse.

## Added

- Widget-style balance card: total, granted and topped-up amounts, currency, `is_available` state, plus the fetch age of the last successful read.
- `DeepSeekClient` that reads `GET https://api.deepseek.com/user/balance` with a bearer API key, with explicit handling for 401/403, 429, other HTTP codes, transport errors and unreadable JSON.
- Peak/off-peak engine (`PeakWindow`): UTC minute-based window that wraps midnight, inclusive start, exclusive end, next-transition computation and contiguous day segments for the timeline bar.
- Live dashboard: 1 s clock, countdown to the next peak/off-peak switch, UTC plus local-time labels, 24-hour timeline with a current-position marker, pull to refresh, refresh on foreground when the cached balance is older than 120 s.
- Rate table for `deepseek-chat` and `deepseek-reasoner` (cache hit, cache miss, output) with the currently active column highlighted.
- Settings: API key in the iOS Keychain, off-peak window in UTC with local equivalents, editable standard rates and per-model discount percentages, restore-window and reset-rates actions, links to the API keys page and the official pricing page.
- Offline behaviour: the last successful balance is cached locally and shown immediately; failure messages are explicit about the cause.

## Verification

- `Tests/LogicTests.swift` (56 checks) covers window boundaries and wrapping, next-transition math, segment coverage and off-peak duration, disabled and non-wrapping schedules, discount maths with clamping, number formatting, countdown and time-zone conversion, parsing of the documented balance payload plus numeric/partial/two-currency variants, and the HTTP status mapping and bearer header.
- Component checks only. No app/UI suite, no physical-device run, no live DeepSeek account call and no signing-service compatibility test.

## Limits

- The Apple home-screen WidgetKit widget is not built: this pipeline generates a single app target without extension targets or App Groups, so the widget is an in-app card.
- Seeded rates are not fetched from the network. Verify them at <https://api-docs.deepseek.com/quick_start/pricing>.
- Unsigned IPA output: MUST BE SIGNED BEFORE INSTALLATION.
