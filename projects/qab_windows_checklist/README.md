# QA Task Utility (Windows) 1.0.0 (build 1)

Isolated builder acceptance project: `qab_windows_checklist`.

Flutter desktop task utility for Windows x64. Local-only: no network calls, no accounts,
no plugins, no platform channels. Persistence uses `dart:io` in the app's own folder.

## Features

- Add tasks with High / Normal / Low priority and inline validation (trim, whitespace
  collapse, 120-character limit with the current length in the message, 200-character field).
- Complete, reopen, delete, and clear completed tasks; progress bar and `x of y done` summary.
- Ordering: incomplete first, then priority, then oldest, then title.
- Empty state, error state and a live-region status line.
- Appearance control (System / Light / Dark) with Material 3 light and dark themes.
- Task data in `%APPDATA%\QaTaskUtility\tasks_v1.jsonl`, written to a temp file and renamed.
- Corrupt payloads are copied to `tasks_v1_recovery.jsonl` and the app starts clean with a
  notice plus a "Restore recovery copy" action.
- Stored titles are validated but kept as saved (only outer whitespace trimmed), so data
  round-trips exactly.

## Tests

`test/policy_test.dart` covers validation boundaries, unicode, deterministic ids, ordering,
summaries, the JSON-lines codec, schema refusal and damaged-line recovery.
`test/widget_test.dart` drives the real widget tree: empty state, validation error, add,
toggle + clear, delete, notice display, recovery restore and appearance cycling.

```bash
flutter analyze
flutter test
```

The reviewed Windows pipeline additionally performs an installer deployment smoke test and
an app-process launch check on a real Windows runner.

## Build

```bash
flutter pub get
flutter build windows --release
```

Version `1.0.0+1` is written into the app and the installer identity, not the workflow run number.

## Install

1. Run the generated `QA-Task-Utility-1.0.0-x64-Setup.exe` installer, or
2. Unzip the portable ZIP and start `qa_task_utility.exe` from the extracted folder.

## Limits

- No physical end-user Windows PC testing by this project; CI runs on a hosted Windows runner.
- No installer signing certificate is used (unsigned publisher, SmartScreen may warn).
- Single folder of local tasks; no sync, no cloud, no telemetry.
