# Changelog

## 1.0.0 (build 1)

- Initial isolated acceptance build (`qab_ios_checklist`).
- Native UIKit checklist with priorities, validation, empty/error states and progress summary.
- Dark/light appearance control persisted across launches.
- Corrupt-data recovery copy with in-app restore.
- `foundation_policy` test suite executing real Foundation logic checks in CI.
- Stored titles are validated but no longer re-normalized on load, so saved data round-trips exactly.
