# iOS 1.1.6 / build 8

## Fixed

- Progress-storage cadence: the player checkpoints every 5 s, so the previous 3 s window never coalesced anything. The window is now 15 s, which turns 60 s of playback into 5 writes instead of 13 while the newest position is always held in memory.
- Explicit flushes: final-episode end, pause, seek commit, player dismissal and app backgrounding write the deferred position immediately through `Library.flushPendingWrites()`, so the resume point is never the coalesced-away value.
- Audio ownership: the native player releases `AVAudioSession` when playback really stops (final episode, dismissal, PiP stop) so other apps' audio resumes. Background audio, Picture in Picture and automatic next-episode playback keep the session, and resuming re-activates it.
- Browser inspection is scoped: series and episode pages keep the 1.2 s inspector; every other page is inspected on navigation finish plus one follow-up after layout, and only while the browser is on screen. Navigation, ad filtering and the Site -> Enable compatibility switch are untouched.
- Downloads screen no longer polls: the redundant 1 s refresh timer was removed. `DownloadStore.changed` already drives state and in-place progress updates.
- HLS storage size is measured, not assumed: after an asset download finishes the bundle size is computed off the main queue and stored, so the summary shows real megabytes. Legacy entries with no measurement now read "size not measured yet" instead of a fabricated 0.0 MB.

## Tests

- 12 request/path checks, 12 download-cancellation checks and 6 progress-cadence checks, the last simulating the real 5 s checkpoint rhythm: 5 writes in 60 s, latest value retained, window longer than the cadence, force-flush bypass. Component checks only, not a phone or UI suite.

## Preserved

- Bundle ID `com.waqas.hdrama`, stored favourites/history/progress keys, offline index format and legacy path rebasing.
- All 1.1.2 compatibility work (targeted ad filtering, protected verification frames, per-site compatibility), 1.1.3 fixes, 1.1.4 `DownloadResolutionGate` cancellation and 1.1.5 persistence throttling.

# iOS 1.1.5 / build 7

- Playback progress writes throttled; deferred writes flushed when the app enters the background. 4 standalone progress-write checks.

# iOS 1.1.4 / build 6

- Pausing or deleting a download during stream preparation invalidates the preparation attempt through `DownloadResolutionGate`; late success/failure callbacks cannot start orphan downloads or alter a resumed attempt. Cancellation now also cancels the running resolver.
- Preparation callbacks and restored background-task state are processed on the main queue; the next eligible queued item is reconsidered after cancellation.
- Invalid stream addresses and unavailable HLS tasks now produce a failed state instead of leaving downloads stuck. 12 cancellation checks added.

# iOS 1.1.3 / build 5

- Browser timer invalidation, non-overlapping resolver polls, three-attempt player-start cap, downloads timer paused while covered, in-place progress updates, signed poster queries preserved, cookie scope/path/secure/expiry checks, underlying network errors, retained background completion handlers, sandbox-relative offline paths with legacy rebasing and atomic index writes, queue reconsidered after launch and network changes. 12 request/path checks added.

# Android 1.9.1 / versionCode 20

- Cancellable OkHttp HTML request bridge; idempotent DownloadHelper cleanup across cancellation, success and error; real HTTP success/cancellation tests plus a concurrent cleanup race test; non-debuggable signed release APK. 129 tests, lint and compile pass.

# Baselines, verification and limits

- Baselines: supplied Android HDramaNative 1.9.0 (versionCode 19, debug-signed) and iPhone HDrama 1.0.0. Work continues on the recovered Kotlin sources and the verified Swift sources; bundle IDs, stored data and offline metadata are preserved; no key rotation, uninstall or feature rewrite.
- Build-Report.json is authoritative for executed checks, source SHA, versions, file hashes and signing continuity. Source review does not establish binary-identical provenance.
- Android certificate published for 1.9.1 is 95ef7ba5e1901ae65d67f042db13d5fe59f8b2af12c3d9eb5f1a070cce9ac758; the supplied APK is 499e74c1e9318c7bc00a0720314a7c7d7b8d12811d53871018b34882eb7095ca. They differ, so that APK cannot update the installed copy; the original signing key is required for a data-preserving update. No key was created or rotated.
- No physical phone, streaming backend, offline playback, PiP, Cloudflare completion or battery/throughput benchmark has been performed here. No bug-free guarantee and no measured speed claim. iPhone output is unsigned and MUST BE SIGNED BEFORE INSTALLATION.
