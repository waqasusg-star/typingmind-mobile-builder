# Changelog

## 1.0.0 (build 1)

- Initial isolated acceptance build (`qab_android_checklist`).
- Local task checklist with priorities, validation, empty/error states, progress summary.
- JVM unit tests for policy, ordering, serialization and corruption recovery.
- Light/dark themes and accessibility labels/live regions.
- Fixed a unit-test assertion that compared a Task to a Boolean; the no-op toggle path is now
  asserted through the task state instead.
- Replaced API 29 `setMinHeight`/`setMinWidth` setters with the API 1 `minimumHeight`/
  `minimumWidth` properties and removed the ProgressBar minimum height so lint passes on minSdk 26.
