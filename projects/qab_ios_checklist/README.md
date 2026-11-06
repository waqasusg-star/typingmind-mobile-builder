# QA Checklist iOS 1.0.0 (build 1)

Isolated builder acceptance app: `qab_ios_checklist`.

Native Swift/UIKit task checklist. Local-only: no networking, accounts, analytics or
package dependencies. Built by the reviewed unsigned native iPhone pipeline
(`macos-15-intel`) as a real arm64 device app.

## Features

- Add tasks with High / Normal / Low priority and inline validation (trim, whitespace
  collapse, 120-character limit, 200-character input field limit).
- Complete, reopen, delete, and clear completed tasks; progress bar and `x of y done` summary.
- Ordering: incomplete first, then priority, then oldest, then title.
- Empty state, error state, and VoiceOver announcements for status changes.
- Appearance control (System / Light / Dark) applied through `overrideUserInterfaceStyle`
  and persisted; palette adapts to the trait collection.
- Dynamic Type fonts, 44 pt minimum touch targets, accessibility labels and identifiers.
- Persistence in `UserDefaults`; unreadable payloads are copied to a recovery key instead of
  being destroyed, with an in-app "Restore recovery copy" action and confirmation alert.
- Draft text survives app suspension.

## Tested logic (real CI execution)

`test_profile: foundation_policy` compiles and runs `Sources/RequestPolicy.swift` together with
`Tests/PolicyTests.swift` as a standalone Foundation executable. That suite covers title
validation boundaries, unicode, deterministic ids, ordering, summaries, mutations, the JSON-lines
codec round trip, schema refusal, damaged-line recovery, and priority/appearance parsing.

It is a component check: it does not exercise UIKit rendering, VoiceOver, or a physical device.

## Build

```bash
# The reviewed worker runs xcodebuild for an arm64 device build and exports an unsigned IPA.
# Locally, with your own signing team:
 xcodegen generate   # needs project.yml
 xcodebuild -project QabChecklist.xcodeproj -scheme QabChecklist -destination 'generic/platform=iOS' build
```

## Install

1. Sign the unsigned IPA with your UDID-based service (e.g. https://www.ipasigner.com/).
2. Install the signed IPA on the registered device.

**The unsigned IPA must be signed before installation.**

## Limits

- No physical-device or VoiceOver testing was performed by this project.
- Logic tests are Foundation-only; they do not cover UIKit layout behaviour.
- Tasks stay on one device; no cloud sync.
