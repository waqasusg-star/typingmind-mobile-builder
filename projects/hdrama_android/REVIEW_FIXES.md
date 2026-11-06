# HDrama 1.9.0 — review and fix pass

Date: review pass on 1.8.0 (build 18) → 1.9.0 (build 19).

Scope: full read of the app module (33 Kotlin sources, theme, manifest, Gradle build, CI workflow,
JS helper checks, 126 existing tests) with fixes applied only where behaviour was demonstrably wrong.

## Defects fixed

| # | Area | Defect | Fix |
| --- | --- | --- | --- |
| 1 | Browser (`MainActivity`) | The page-inspection guard could stay set forever. A snapshot that arrived while the app was paused returned before clearing `inspecting`, so after returning to the app no further inspection ran: the Play button never reappeared and the dock stopped tracking the website footer. | The in-flight inspection epoch is now recorded (`inspectingEpoch`). Only the callback belonging to the current inspection releases the guard, and it releases it before the paused/expired checks. Stale callbacks still cannot release a newer inspection (existing test preserved). |
| 2 | Browser | A dead WebView renderer closed the entire app (`finish()`), losing the page and the download queue screen. | The activity now rebuilds itself (`recreate()`) after resetting inspection state, so the session survives a renderer crash. |
| 3 | Browser | `dockActions()` re-injected the dock padding `<style>` on every window-inset event, and the value is recalculated on every snapshot (about once a second). | The injected CSS is cached per document and only re-sent when the value actually changes; the cache resets on every new document. |
| 4 | Player (`PlayerActivity`) | `updatePipParams()` ran from the 300 ms progress ticker, rebuilding three `RemoteAction`s, three `PendingIntent`s and an IPC call roughly ten times per second for the whole episode. | Picture-in-picture parameters are now updated only when the relevant state changes (auto-enter, PiP mode, loading, play-when-ready, media count, seekability, video size and pixel ratio). `pipParams()` itself is unchanged, so PiP actions stay identical. |
| 5 | Player | `updateControls()` and `checkpoint()` indexed `series.episodes[index]` directly. A refreshed series with fewer episodes than the stored index crashed with `IndexOutOfBoundsException`. | Both use `getOrNull(index)` and skip the update instead. |
| 6 | Player | The `downloads` and `pip` actions exist in the chrome but had **no visible entry point** — the overflow menu only offered Fit/Fill and Rotate. | "Downloads" and "Picture in picture" are now in the Player options menu; PiP has a graceful unavailability message. |
| 7 | Downloads | An episode download stopped by unmet requirements (Wi-Fi-only/mobile data) with no stored stop reason showed "Pause download" and could not be resumed from that dialog. | The dialog treats `STATE_STOPPED` as resumable, clears the stop reason, calls `resumeDownloads()` and restarts preparation. |
| 8 | Downloads | The header size counted every download record, including failed/removed partial bytes, and said "MB" for the whole library. | It counts completed episodes only and reads "N saved · X MB offline · Y GB free". |
| 9 | Download service | `startForeground()` was unguarded: Android 12+ can throw `ForegroundServiceStartNotAllowedException`, crashing the app. | Guarded; the service stops quietly. |
| 10 | Download service | `while (!downloads.isInitialized) delay(50)` could spin forever if the database never opened, and the progress notification was never removed after the work finished. | Initialisation is bounded (10 s) then the service stops; `stopForeground(STOP_FOREGROUND_REMOVE)` runs in the job `finally` and in `onDestroy`. |
| 11 | Preload engine | `register()` keyed cache entries by episode URL only, so a different episode could be added at an index already holding a source, leaving two preload sources with the same index. | A stale source occupying the same index is removed before the new one is added. |
| 12 | Lists (`My List`) | Long-press removal deleted a description by index *after* shifting the backing list, so the adapter could drop a different row's text. | The exact listed description is captured before removal. |
| 13 | UI kit | `time()` used the default locale, so time labels could render in Arabic-Indic digits while the rest of the UI stayed Latin. | Fixed to `Locale.US`. |

## Design and theme pass

- One surface palette: `AppColors.card` / `overlay` / `danger` / `heart` replace one-off hex values in the dock, the episode bar, dialog buttons and the favorite heart (all values identical to before, so contrast checks still pass).
- `windowBackground` and `statusBarColor` moved to a single `@color/app_background` (`#101016`), removing the visible `#0D0D14` → `#101016` seam at the top of the browser, History and Downloads screens.
- The website and the browser root now share the app background instead of mixing black with the site's own dark tone.
- Website-access screen: a real 48 dp back header replaced the title label, and the three cramped buttons in one row became two full-width 48 dp targets ("Reload check", "Open in browser"). The explanatory line now uses the muted colour.
- Downloads "Wi-Fi only" switch now has proper checked/unchecked thumb and track tints instead of an always-accent thumb.
- History count reads "1 recently watched series" for a single entry.

## Build, manifest and CI hardening

- `VersionCode 19`, `versionName 1.9.0`.
- Debug signing now honours `HDRAMA_BROWSER_DEBUG_STORE_PASSWORD`, `HDRAMA_BROWSER_DEBUG_KEY_ALIAS` and `HDRAMA_BROWSER_DEBUG_KEY_PASSWORD`, so an existing release key can sign a compatible update instead of failing against the hard-coded `android`/`androiddebugkey` pair. Defaults are unchanged.
- `org.gradle.parallel` and `org.gradle.caching` enabled.
- Manifest: `android:enableOnBackInvokedCallback="true"` for predictive back, and PiP declared as an optional feature (`android:required="false"`).

## Not changed (documented risks)

1. `BrowserResolver` destroys its WebView from the main thread after `finish()`, which can be triggered inside `shouldInterceptRequest` (a background callback). Chrome recommends not destroying a WebView from inside that callback; it is unchanged because a wrong change here risks an ANR in the only source-resolution path.
2. The resolver WebView inside `EpisodePreparationService` is attached to a detached `FrameLayout`. It works, but a WebView without a window is not a documented configuration.
3. `DramaLibrary` stores `episode-position:`/`episode-completed:` keys per series per episode in SharedPreferences and never prunes them. Fine for hundreds of series, unbounded over years.
4. `Media3` `DownloadHelper` release can be called twice when preparation is cancelled at the same moment it completes.
5. Physical-device checks from `VALIDATION.md` (PiP appearance, live seeking, OEM keyboards, real offline playback, live site changes) still need a phone. Nothing in this pass was verified on hardware, and no Gradle/Android SDK build was run in this review environment.

## Verification status

No compile, lint or unit-test run was possible in this environment (no Android SDK). Changes are source-only,
keep all existing public signatures used by the 126 tests, and preserve the tested behaviours:
stale-snapshot rejection, keyboard dock hiding, footer docking, single-column rails, download tiles,
history deletion, quality highlight and PiP action titles. Run:

```bash
./gradlew assembleDebug testDebugUnitTest lintDebug
node tools/browser-script-checks.cjs
node tools/resolver-script-checks.cjs
```
