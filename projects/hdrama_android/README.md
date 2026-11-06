# HDrama Android 1.9.1 (versionCode 20)

See CHANGELOG.md for this maintenance review and Build-Report.json for actual verification. Build with Java 17, SDK 35 and Gradle 8.11.1. Preserve the existing signing key to update an installed copy.

# HDrama 1.9.0

Review pass: see REVIEW_FIXES.md for the 13 defects fixed, the palette/theme unification and the build hardening. The design pass below is unchanged.

Final design pass: shared dark surfaces, brand-aware colors, rounded action buttons, consistent poster cards and headers, informative empty states, adaptive browser dock, larger landscape controls, and scrolling player sheets that prioritize the episode grid in short windows.

Review fixes include stale document inspections, uneven last-range tiles, live download percentages, corrupt poster recovery, stable in-place artwork updates, correct supported-quality highlighting, compact sheets after rotation, and pull-to-refresh protection during typing. Agreed playback, resume, automatic next, PiP, download and hold-delete behavior is retained. See DESIGN_REVIEW.md and VALIDATION.md for coverage and remaining phone checks.


Latest release: 1.9.0 (build 19). Previous: 1.8.0 (build 18) — 2026-10-13.

Patch fixes: the browser action dock hides while the keyboard is open and returns above the website footer after dismissal. Completed episodes replay from zero on return; unfinished episodes retain their exact positions. Old saved end timestamps are handled when the video duration becomes available, without skipping immediately to the next episode.

Pull down at the top of the browser page to refresh. The native action dock contains My List, Downloads, History and Play; Play appears only on validated playable series pages. It sits directly above the website footer, including raised center navigation buttons.

History shows one poster card per recently watched series with its last episode and timing. Tap to resume, hold to delete an entry, or Clear history to hide all entries. Confirmation is required; favorites, downloads and every episode resume position are kept.

Player actions form one column: Favorite, My List, Download, Quality and Speed. The series title is at the top, with the current episode in bold beside the total count. Horizontal video drags preview seeks in the full video and commit on release; cancelling restores the original position and playback state. Vertical episode swipes, automatic next playback and automatic PiP are retained.


A native Android browser and player for [HDrama](https://en.hdrama.net/), Android 8.0+. This version adds quality selection, episode-grid sheets and offline downloads, and removes automatic Fill.

## Player

The player starts fullscreen in **Fit** mode, keeping the entire video visible. Fill is available only when you explicitly choose Fit / Fill. Old automatically enabled Fill state is ignored after this update.

The status bar appears with the controls and disappears when controls hide, including while holding for 1.5× speed. Android navigation stays visible and the bottom gesture area is kept clear of video touches; sticky immersive mode is disabled. The video keeps its original Fit sizing throughout.

Tap the video to show or hide controls. The center button plays or pauses. Hold the video for temporary 1.5× speed, without revealing controls. Swipe vertically for episodes. Only the raised timeline seeks; horizontal drags and double taps do not seek.

Episodes open in a rounded dark bottom sheet with 30-episode range tabs, a five-column numbered grid, an active-episode indicator, and downloaded badges.

**Quality** opens a bottom sheet containing Auto and the actual supported resolutions reported by the video. Portrait resolutions use the shorter frame dimension (1080×1920 is labeled 1080P). A source with one rendition cannot provide alternative resolutions. The choice carries across episodes; if unavailable, the nearest lower supported resolution is used, or the lowest available rendition.

## Download folders

Downloads opens a folder overview with each drama/season's title and cached thumbnail. Tap one folder to see only its episodes as compact numbered tiles. Tap a saved episode to play; other tiles open their download/retry/pause options. Hold an episode or a series folder to open a delete confirmation. Deleting a series removes only its pending/downloaded episodes, keeping other series, favorites and watch history. Back returns to the folder overview. Separate canonical series/season URLs stay separate even if their titles match; a season label is shown when the website title identifies it. Existing downloads are grouped automatically without deleting their video or progress.

Website series covers are selected ahead of generic site images, with normalized title matching and browser request headers. Verified posters are cached for offline use. Old frame thumbnails are replaced when the series page is reachable online; frame capture no longer creates download artwork. Missing covers display a placeholder until the website cover can be fetched.

## Offline watching

1. Open a drama in the native player and tap **Download**.
2. Pick download quality, select individual episodes or **Select all**, then choose **Download selected**.
3. Open **Downloads** from the player or the small Downloads icon above the browser's website menu.
4. Check progress and use **Pause all**, **Resume all**, individual pause/resume, retry, delete, or **Wi-Fi only**.
5. When an episode says **Ready offline**, tap **Play offline**. Saved episode links, titles, and series information open locally; no website request is needed to start that downloaded episode. Existing episode/time resume and Favorites remain available.

MP4, HLS, and DASH sources use Media3's download infrastructure. A single foreground service prepares normal website sources and keeps transfers active after leaving the app. The queue and download index are persistent. Source preparation waits for usable network connectivity and retries can refresh expired source links. The app requests notification permission on Android 13+ when starting a download. Android's background-service limits and a user force-stop can interrupt work; return to Downloads and choose Resume all.

Downloads are stored in app-private persistent storage, separate from the evicting playback/preload cache. Completed offline playback has no HTTP fallback. Deleting a download removes its cached video without deleting favorite or watch history. Uninstalling the app removes local downloads and progress. Videos requiring unavailable login, access, DRM, or an offline license cannot be made downloadable by this app.

Offline navigation to an episode that was not downloaded displays a clear message; it does not fetch that episode while in offline-only playback. Website ads/popups are filtered as in the previous version; advertising embedded in a video is part of the video.

## Build

Use Java 17, Android SDK 35 and Gradle 8.11.1. Import the project in Android Studio or run the commands below. The project pins Media3 1.5.1 and Kotlin 2.1.10. The private signing key is deliberately excluded from the source ZIP. Set the documented signing environment variable to the existing key to build a compatible update; an automatically generated development key cannot update an APK signed by another key.

## Validation limits

See VALIDATION.md for the recorded build/test results. Automated checks cover quality enumeration, portrait quality labels, queue persistence/deduplication, offline metadata opening, cache-only reads, episode ranges, batch selection, gestures, favorites/resume, and compact layouts. Physical-device streaming, service restart behavior, and complete downloads from the current live sites still require phone testing.

References: [Media3 downloads](https://developer.android.com/media/media3/exoplayer/downloading-media), [track selection](https://developer.android.com/media/media3/exoplayer/track-selection).

Build command:
```bash
./gradlew assembleDebug testDebugUnitTest lintDebug
```

Signing variable: `HDRAMA_BROWSER_DEBUG_KEYSTORE`.


## Polished controls and full-video seeking

- The player has no on-screen Back button. Android system Back gestures/buttons still work.
- The small thumbnail overlay is removed. Scrubbing previews directly in the full video, pauses playback temporarily, coalesces seeks, commits the exact selected point on release and restores the prior playing/paused state. Current and remaining time labels update together.
- Player controls use rounded squares, more spacing and a lower placement, adapting to compact and landscape windows.
- The browser's My List, Download and Play actions share one horizontal row of 64dp rounded-square targets above the website's bottom navigation.
- Automatic PiP includes Rewind 10 seconds, Play/Pause and Forward 10 seconds custom actions, with a private scoped receiver and immutable pending intents. Android supplies window expand/close controls.
- Automatic next-episode playback, earlier swipe animation, independent episode resume, red favorite hearts, cached poster Favorites and offline download folders remain available.

PiP controls and full-video seeking require physical-device verification. Unsupported or blocked website sources are not bypassed.
