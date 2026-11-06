# iOS 1.1.4 / build 6

- Pausing or deleting a download during stream preparation now cancels its resolver and invalidates the preparation attempt. Late success/failure callbacks cannot start orphan downloads or alter a resumed attempt.
- Preparation callbacks and restored background-task state are processed on the main queue. The next eligible queued item is reconsidered after cancellation.
- Invalid stream addresses and unavailable HLS download tasks now produce a failed state instead of leaving downloads stuck.
- Adds 12 cancellation regression checks, alongside the existing 12 request/path checks. These are component tests, not phone or UI tests.
- Preserves all 1.1.3 performance, offline-path and compatibility changes below. No measured speed or battery improvement is claimed.

# HDrama maintenance review — Android 1.9.1 (20), iOS 1.1.3 (5)

## Baselines and preserved identity

- Supplied Android package: HDramaNative 1.9.0, versionCode 19, applicationId com.waqas.hdramabrowser, namespace com.waqas.hdrama. Original Kotlin source is HDramaNative-1.9.0-fixed.zip. The supplied APK is debug-signed; the build report compares the resulting certificate against its SHA-256 fingerprint.
- Supplied iPhone package: HDrama 1.0.0, build 1. Changes are applied to the newer verified 1.1.2/build 4 Swift source, preserving its compiler fixes, targeted ad filtering and per-site compatibility switch. Bundle ID remains com.waqas.hdrama.
- Existing favorites, history, progress, offline metadata names and package identities are retained. No key rotation, uninstall/migration or feature rewrite is performed.

## Android 1.9.1 / versionCode 20

- Network HTML requests now use a cancellable OkHttp callback bridge. Cancelling while waiting for response headers cancels its actual socket rather than waiting for the 35-second call timeout. Bounded body decoding still uses the existing IO path. Responses are closed if cancellation wins the callback race.
- DownloadHelper cleanup is idempotent across cancellation, success and error callbacks. Cancelled preparation avoids accessing an already released helper.
- Adds actual HTTP success/cancellation tests and a concurrent cleanup race test. Retains the existing JUnit/Robolectric suites.
- Builds a non-debuggable release APK, runs native tests and lint, checks package/version and validates the signature. The signing stage uses only existing configured repository secrets and executes no app code.

## iOS 1.1.3 / build 5

- Browser timer is invalidated when the controller is released; the resolver prevents overlapping JavaScript polls and caps player-start retries at three.
- Downloads pause their refresh timer while covered. Progress updates edit existing episode buttons instead of rebuilding the entire grid, keeping touch targets and scrolling stable.
- Signed poster URL queries are preserved; credential-bearing/non-HTTPS poster URLs are rejected.
- Cookie reuse now checks domain scope, path boundaries, HTTPS-only flags and expiry. Network failures retain their underlying error message instead of becoming an empty-page message.
- Background-session completion handlers are retained until URLSession finishes delivering its events.
- Offline media paths are stored relative to the app sandbox. Legacy container paths are safely rebased after app-container UUID changes; unrelated/traversal paths are rejected. Download index writes are atomic.
- Queued downloads are reconsidered after launch and network changes, while respecting offline/Wi-Fi-only conditions. Explicitly paused items stay paused.
- Adds 12 standalone Foundation request/path checks. These are component tests, not a full app or UI test suite.

## Verification and limits

Build-Report.json is authoritative for executed checks, test counts, source SHA, package versions, file hashes and signing continuity. Source review does not establish binary-identical provenance to the supplied packages. The original source ZIPs are preserved separately.

No physical phone, streaming backend, offline playback, PiP, Cloudflare completion or battery/throughput benchmark has been performed here. No "bug-free" guarantee or measured speed/battery percentage is claimed. iPhone output is unsigned and MUST BE SIGNED BEFORE INSTALLATION. If Android certificates differ, it cannot update the supplied installed APK; use the original signing key for a data-preserving compatible update.
