# DeepSeek Pulse — changelog

# iPhone 1.0.3 / build 4

Adds a **real WidgetKit widget** as an embedded extension. Bundle ID, scheme, Keychain API key,
saved schedule, prices and cached balance all carry over unchanged.

## Added — a genuine Home Screen and Lock Screen widget

- **New extension target** `DeepSeekPulseWidgets`, bundle `com.waqas.deepseekpulse.widgets`, embedded
  in the app as a `.appex`. This is a real WidgetKit extension, not an in-app preview.
- `WidgetSources/WidgetBundle.swift` — canonical `@main` `WidgetBundle` declaring `PulseWidget`
  (kind `DeepSeekPulseWidget`).
- `WidgetSources/WidgetTimelineProvider.swift` — `PulseTimelineProvider` with placeholder, snapshot
  and timeline. Entries are placed at the next peak/off-peak boundary the app computes locally,
  plus a bounded follow-up. iOS decides when these are honoured.
- `WidgetSources/WidgetViews.swift` — real SwiftUI views: small, medium, and iOS 16 accessory
  inline / circular / rectangular with `privacySensitive`. Deployment target stays iOS 15.
- Supported families: small and medium on iOS 15+; Lock Screen accessories on iOS 16+. This is not
  a Dynamic Island or Live Activity; none is claimed or shipped.

## Added — shared data layer

- `Shared/WidgetSharedTypes.swift` — `WidgetShared`, `WidgetDataState`, `WidgetBalance`,
  `WidgetRate`, `WidgetSnapshotPayload`, `WidgetSnapshotEnvelope`. Foundation only.
- `Shared/WidgetCacheStore.swift` — `WidgetCacheCodec` (encode, decode, schema probe, sanitising,
  stale calculation, secret-value guard) and `WidgetCacheLocation` for the App Group container.
- `Shared/WidgetPlanner.swift` and `Shared/WidgetPolicy.swift` — moved out of `Sources/` so the
  extension can compile them. The `Sources/` copies are reduced to comment-only stubs, so nothing
  is defined twice and the app and widget share one implementation.
- `Sources/WidgetBridge.swift` — app-side writer: builds a display-only payload, encodes it,
  refuses to write anything matching a secret value, writes atomically, then calls
  `WidgetCenter.shared.reloadTimelines`.

## Changed

- Version 1.0.2 (build 3) to **1.0.3 (build 4)**.
- **Dashboard** writes the shared snapshot after every successful balance fetch.
- **Settings** rewrites the snapshot after Save (schedule, rates, holidays, key).
- **Remove key** now also rewrites the snapshot, so a removed account leaves no balance numbers on
  the Home Screen.
- **Widget Studio** describes the installed extension, lists the real add-widget steps, and reports
  the snapshot write result. The UIKit cards remain previews only.

## Privacy and storage

- The API key remains only in the iOS Keychain. The shared file contains formatted balance text,
  the schedule, rate labels and a `hasAPIKey` boolean — never the key, never a token.
- A final guard rejects any encoded payload containing `sk-`, `bearer `, `authorization`,
  `apikey`, `access_token`, `refresh_token`, `client_secret` or `password` values.
- Widget data is marked privacy sensitive, so a locked device hides the balance text.

## Honest limits of this build

- If the App Group entitlement is absent from either bundle, the widget shows a setup message and
  no numbers. It does not crash and does not invent values.
- Unsigned IPA output: **MUST BE SIGNED BEFORE INSTALLATION.** The app and the extension must be
  signed together with the same team and matching App Group profiles. Whether a given signing
  service supports app extensions and App Groups is not verified by this build.
- No physical-device, widget-gallery or shared-container test was run here.
- Prices, peak windows and the PRC holiday list remain local data verified on 2026-11-06.

# iPhone 1.0.2 / build 3

Widget Studio previews, shared planner and refresh policy, still without an extension target.

# iPhone 1.0.1 / build 2

Corrected obsolete pricing and schedule data, added a verified PRC holiday calendar, made the
assumption state honest, and made the source archive independently rebuildable.

# iPhone 1.0.0 / build 1

First native Swift/UIKit release.
