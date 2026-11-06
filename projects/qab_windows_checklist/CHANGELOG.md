# Changelog

## 1.0.0 (build 1)

- Initial isolated acceptance build (`qab_windows_checklist`).
- Flutter Windows task utility with priorities, validation, empty/error states and progress.
- Light/dark/system appearance control with Material 3 themes.
- Atomic file persistence in `%APPDATA%`, corrupt-data recovery copy and in-app restore.
- Unit tests for policy/codec plus widget tests for the real UI flows.
- Stored titles are validated but no longer re-normalized on load, so saved data round-trips exactly.
