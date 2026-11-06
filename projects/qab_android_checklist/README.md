# QA Checklist (Android) 1.0.0 (build 1)

Isolated builder acceptance app: `qab_android_checklist`.

Local-only task checklist. Framework views only (`android.app.Activity`), no AndroidX UI
dependencies, no network, no accounts, no analytics, no ads, no permissions requested.

## Features

- Add tasks with High / Normal / Low priority and inline validation (trim, whitespace collapse,
  120-character limit with a live message, 200-character input filter).
- Complete, reopen, delete, and clear completed tasks; progress bar and `x of y done` summary.
- Ordering: incomplete first, then priority, then oldest, then title.
- Empty state, error state, and polite/assertive accessibility live regions.
- Light and dark themes via `values-night` and `Theme.DeviceDefault` day/night resources.
- Persistence in app-private `SharedPreferences`; corrupted payloads are moved to a recovery key
  instead of being deleted, with an in-app "Restore recovery copy" action.
- Draft text and selected priority survive rotation and night-mode recreation.

## Tests

`app/src/test` holds plain-JVM JUnit tests for the platform-neutral policy (validation, order,
summary, encoding/decoding, corruption handling) and for persistence/recovery through a fake
key-value store. They do not use Robolectric and do not need a device or emulator.

```bash
./gradlew :app:testReleaseUnitTest --no-daemon
```

## Build

```bash
# Windows path in the delivered SOURCE ZIP
./gradlew :app:assembleRelease
# APKs land in app/build/outputs/apk/release/
```

The reviewed builder pipeline compiles, runs JUnit, runs lint, and signs with the repository's
existing Android release key. No credentials are stored in this project.

## Limits

- Not tested on a physical Android device by this project; CI tests are JVM-only logic tests.
- Tasks stay on one device (no cloud backup, `allowBackup=false`).
- No widget, notification or sync features by design.
