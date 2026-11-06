# HDrama 1.9.0 validation

Date: 2026-10-13

- Android APK build completed successfully: `com.waqas.hdramabrowser`, versionCode 19 (last recorded 1.8.0 run: versionCode 18).
- 1.9.0 source fixes are listed in REVIEW_FIXES.md; re-run `./gradlew assembleDebug testDebugUnitTest lintDebug` before shipping.
- 126 unit/Robolectric tests passed, zero errors or failures.
- Android lint: zero errors. Existing deprecation/UI warnings may remain.
- Signing certificate matches the previous release, allowing installation over the existing app.
- APK ZIP integrity verified; timestamp follows edited sources; packaged DEX contains History, pull-to-refresh, horizontal seek previews and the revised player controls.
- Compact portrait and landscape chrome rendered and inspected. The bottom episode bar, title and bold running episode count at the top, top menu and five square player controls fit within the window.

The final design pass adds a shared card/button/empty-state system, brand-aware themes, responsive browser dock, landscape action grid, scrolling adaptive episode/download sheets, stable live progress and poster updates, cached bitmap recovery, stale-document inspection guards, and effective quality selection. Design checks cover narrow/wide windows, 130% font scale, consistent final-range tile widths, disabled empty download selection, readable palette contrast, intact poster touch targets and compact Quality sheet sizing.

Retained keyboard open/close checks: native browser actions hide while the IME is visible, footer measurements during typing are ignored, and the original footer position returns after dismissal. Replay checks cover completed episode flags, old end timestamps, an end-position source restarting without immediately auto-advancing, paused completion, unchanged exact unfinished positions, and duration information arriving late.

New checks cover recently watched series cards with poster/title/episode/timing, confirmed per-series history deletion and clear-all while preserving resumes and favorites, old history migration without resurrection after clear, top-only vertical pull-to-refresh, cancelled or horizontal refresh gestures, footer-aware browser docking including raised center navigation buttons, hidden Play cells on nonseries/blocked pages, a Speed action below Quality, bold current-episode header, horizontal full-video seek commit/cancel with play/pause restoration and episode isolation. Browser JavaScript checks pass (HDrama: 7, DirectDrama: 13).

Regression checks cover independent per-episode positions, quick episode switches while another source is loading, legacy position migration, automatic next playback with no button and suppression while scrubbing, automatic PiP parameters on Android 12, avoiding PiP during app navigation, full-video scrubbing with commit/cancel playback restoration, removed thumbnail overlay and Back button, scoped PiP actions, and larger square browser targets, red saved heart, Favorites poster/title/episode/timing rows, control visibility and reserved Home-gesture space. Existing offline downloads, folder deletion, quality selection, source restrictions, and access checks also pass.

Pull-to-refresh, website footer docking, full-video seek responsiveness, native PiP button delivery/appearance and Home-to-PiP animation require phone verification. The small thumbnail overlay is removed. PiP exposes rewind 10 seconds, play/pause and forward 10 seconds. Browser action targets are a centered horizontal row of 48–64dp rounded squares, capped at 440dp total width and docked 4dp above the measured website footer, with mandatory gesture space reserved. A History button is included. Clearing History hides recent entries and keeps favorites, downloads and all episode resume positions. No DRM or unavailable website access is bypassed.
