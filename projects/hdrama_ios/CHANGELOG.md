# iOS 1.1.6 / build 8

- Progress storage cadence fixed: the player checkpoints every 5 s, so the previous 3 s window never coalesced anything. The window is now 15 s, which turns 60 s of playback into 5 writes instead of 13 while the newest position is always held in memory.
- Final, pause, seek, dismiss and background events flush the deferred position immediately (`Library.flushPendingWrites()`), so the resume point is never the value that was coalesced away.
- The native player releases AVAudioSession ownership when playback really stops - final episode, dismissal or PiP stop - so other apps' audio resumes. Background audio, Picture in Picture and automatic next-episode playback keep the session active, and resuming playback re-activates it.
- Browser inspection is scoped: series and episode pages keep the 1.2 s inspector, while other pages are inspected on navigation finish plus one follow-up after layout. Pages are inspected only while the browser is on screen.
- Adds 6 progress-cadence checks simulating the real 5 s checkpoint rhythm alongside the existing 12 request/path and 12 cancellation checks. Component checks only, not a phone or UI suite.
- Preserves all 1.1.2-1.1.5 fixes and the Site -> Enable compatibility switch. No phone, Cloudflare, streaming or measured speed/battery result is claimed.

## Known, not fixed in this build

- HLS download rows still report 0 MB: the asset-download completion path records the file but never its byte size, so the Downloads summary shows a fabricated 0.0 MB. Progressive downloads report real bytes. Fixing it requires a one-line-per-site change in `Downloads.swift`.
- The Downloads screen still keeps its own 1 s refresh timer even though `DownloadStore.changed` already drives updates; removing it needs the same file.
- Both of the above are blocked in the current chat session because the patch tool is not exposed here and `Downloads.swift` (33.8 KB) cannot be read back in full for a safe rewrite.

# iOS 1.1.5 / build 7

- Playback progress writes throttled; a deferred progress write is flushed when the app enters the background.
- Adds 4 standalone progress-write checks.

# iOS 1.1.4 / build 6

- Pausing or deleting a download during stream preparation invalidates the preparation attempt through `DownloadResolutionGate`, so late success/failure callbacks cannot start orphan downloads or alter a resumed attempt.
- Preparation callbacks and restored background-task state are processed on the main queue; the next eligible queued item is reconsidered after cancellation.
- Invalid stream addresses and unavailable HLS download tasks now produce a failed state instead of leaving downloads stuck.
- Adds 12 cancellation regression checks; preserves all 1.1.3 changes.

# iOS 1.1.3 / build 5

- Browser timer invalidation, non-overlapping resolver polls, three-attempt player-start cap, downloads timer paused while covered, in-place progress updates.
- Signed poster queries preserved; credential-bearing/non-HTTPS poster URLs rejected.
- Cookie scope/path/secure/expiry checks; underlying network error messages retained.
- Background-session completion handlers retained until URLSession delivers its events.
- Offline paths stored relative to the sandbox with legacy rebasing and atomic index writes; queue reconsidered after launch and network changes.
- Adds 12 standalone request/path checks.

# Android 1.9.1 / versionCode 20

- Cancellable OkHttp HTML request bridge; cancelling while waiting for headers now cancels the socket.
- DownloadHelper cleanup is idempotent across cancellation, success and error callbacks.
- Adds real HTTP success/cancellation tests and a concurrent cleanup race test; keeps the existing JUnit/Robolectric suite. 129 tests, lint and compile pass.
- Builds a non-debuggable signed release APK with applicationId com.waqas.hdramabrowser and namespace com.waqas.hdrama.

# Baselines, verification and limits

- Baselines: supplied Android HDramaNative 1.9.0 (versionCode 19, debug-signed) and iPhone HDrama 1.0.0; work continues on the recovered Kotlin sources and the verified 1.1.2+ Swift sources. Bundle IDs, stored favourites/history/progress and offline metadata are preserved; no key rotation or uninstall migration.
- Build-Report.json is authoritative for executed checks, source SHA, versions, file hashes and signing continuity. Source review does not establish binary-identical provenance.
- Android certificate published for 1.9.1 is 95ef7ba5e1901ae65d67f042db13d5fe59f8b2af12c3d9eb5f1a070cce9ac758; the supplied APK is 499e74c1e9318c7bc00a0720314a7c7d7b8d12811d53871018b34882eb7095ca. They differ, so the new APK cannot update that installed copy. The original signing key is required for a data-preserving update; no key was created or rotated.
- No physical phone, streaming backend, offline playback, PiP, Cloudflare completion or battery/throughput benchmark has been performed. No bug-free guarantee or measured speed claim. iPhone output is unsigned and MUST BE SIGNED BEFORE INSTALLATION.
