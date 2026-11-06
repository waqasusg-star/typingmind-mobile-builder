# HDrama for iPhone (1.1.0)

A separate, native iOS app that mirrors HDrama 1.9.0 on Android: one-site browser, native
video player, episode grid, quality and speed, favorites, history, exact per-episode resume,
automatic next episode, Picture in Picture and offline downloads.

**1.1.0 adds a full ad blocker.** Every feature, layout and behaviour from 1.0.0 is unchanged; the
only difference is that the web view no longer loads advertising. See section 3.

**The Android project is untouched.** This is a new codebase, not a port that changes Android behaviour.

---

## 1. Before you build: the honest platform facts

| Fact | Detail |
| --- | --- |
| No installable file can be produced here | An iOS app must be compiled and signed by Apple tooling on macOS. This source was written in a Linux-style sandbox with no Xcode, so it has **not** been compiled or run. Treat the first build as a debugging session, not a finished product. |
| You need a Mac + Apple ID | Xcode 15+, a free Apple ID (7-day personal builds) or a paid developer account (TestFlight / App Store). |
| App Store risk | A wrapper that streams and downloads a third-party site's video is very likely to be rejected under App Store Review Guidelines 4.2 (minimum functionality) and 5.2 (intellectual property). Realistic distribution: your own device via Xcode, or internal TestFlight. |
| Website access rules | The app never solves a challenge, decrypts DRM or bypasses a login. If the site blocks app traffic, complete the check in the in-app browser. |

---

## 2. Build

```bash
brew install xcodegen          # once
cd HDrama-iOS
xcodegen generate              # creates HDrama.xcodeproj from project.yml
open HDrama.xcodeproj
```

In Xcode:

1. Select the **HDrama** target → *Signing & Capabilities* → choose your Team, set a unique bundle id
   (default `com.waqas.hdrama`).
2. Connect an iPhone (iOS 15 or newer) and press **Run**.
3. Background audio is already enabled (`UIBackgroundModes: audio`) for Picture in Picture and for
   background downloads to continue while the app is not on screen.

No third-party dependencies, no CocoaPods, no Swift packages.

---

## 3. Ad blocking (new in 1.1.0)

The iPhone build previously relied on one injected CSS rule, so third-party ad scripts, popups and
interstitials still loaded. `Sources/AdBlocker.swift` now runs three local layers, applied to **both**
the browser and the invisible stream resolver (so downloads benefit too):

| Layer | What it does |
| --- | --- |
| `WKContentRuleList` (WebKit's own blocker API, iOS 11+) | Blocks ~80 ad/tracker/popunder networks by host, all third-party `script`/`iframe`/`popup`/`style-sheet`/`font`/`svg` requests, and generic third-party paths such as `/ads/`, `/prebid`, `/vast`, `/gpt`, `-banner`, `-adserver`. Rules are compiled once, cached by WebKit and reused. |
| `css-display-none` + injected stylesheet | Hides ad containers by attribute, class and id in every frame. |
| Document-start script | Replaces `window.open`, `alert`, `confirm` and `prompt`; denies notification and permission prompts; cancels off-site link hijacks; removes "ad-free / click now" plates, sticky ad boxes and full-screen countdown gates (the `1:00 … OK` panel), then releases the scroll lock those gates leave behind. |

Plus native-side hardening in `BrowserViewController`:

- `createWebViewWith` returns `nil`, so `window.open` and `target="_blank"` never open a window.
- JS alert/confirm/prompt panels are dismissed automatically instead of freezing the page.
- `itms-apps://`, `intent://`, `market://` and `mailto://` navigations (App Store ad redirects) are cancelled.
- Camera/microphone permission requests from the site are denied.
- The first page load waits for the rules to compile (1.5 s maximum), so the opening screen is not an ad.

Deliberately preserved so playback keeps working: `media` and `fetch`/XHR (`raw`) requests are never
blocked for stream discovery, first-party assets and the site's own CDN stay allowed, and a final
`ignore-previous-rules` entry guarantees that `.m3u8`, `.mpd`, `.mp4`, `.webm`, `.ts`, `.m4s` and `.aac`
requests are never blocked by any rule above it.

Nothing is proxied or routed through a third-party service; all filtering happens inside WKWebView on
the device, with no VPN profile, no DNS change and no traffic leaving the app.

**What the app cannot stop:** the screenshot that prompted this change also shows a **Safari**
notification banner. That banner is delivered by Safari itself (web push), not by this app — a
WKWebView app cannot receive web push, and this app never asks for notification permission. If it
appears while browsing in Safari, turn the site's notifications off in iOS Settings. Inside this app,
the site's own "enable notifications" prompt is denied.

---

## 4. Feature parity with HDrama 1.9.0 (Android)

| Feature | Android | iPhone |
| --- | --- | --- |
| Single-site browser, pulled to refresh | ✅ | ✅ pull-to-refresh on the web view |
| Native dock: My List, Downloads, History, Play | ✅ | ✅ same four 64 pt targets, centred, 440 pt cap |
| Play appears only on a validated playable series page | ✅ | ✅ same validation and handoff |
| Dock docks above the site's own footer | ✅ measured | ✅ measured with the same injected script |
| Dock hides behind the keyboard | ✅ | ✅ keyboard-frame observation |
| Web videos muted and paused, site Play intercepted | ✅ | ✅ same injected DOM script |
| Player chrome: title, bold `EPn / EPm`, one 5-item rail | ✅ | ✅ same order: Favorite, My List, Download, Quality, Speed |
| Tap toggles controls, centre play/pause, hold for 1.5× | ✅ | ✅ |
| Horizontal drag previews then commits a seek | ✅ | ✅ same 90 s max per screen width |
| Vertical swipe changes episode | ✅ | ✅ same thresholds |
| Resume per episode, completed episodes replay from 0 | ✅ | ✅ |
| Automatic next episode, stops at the last one | ✅ | ✅ |
| Favorites (hold the heart to remove) | ✅ | ✅ long-press the heart |
| History with hold-to-delete and clear-all | ✅ | ✅ |
| Episode sheet: 30 per range, 5 columns, downloaded badges | ✅ | ✅ |
| Download sheet: Select all / Clear / Download selected | ✅ | ✅ |
| Downloads folders, per-episode status, pause/resume/delete | ✅ | ✅ |
| Offline playback with no network fallback | ✅ | ✅ |
| Wi-Fi only | ✅ | ✅ new downloads only (see deltas) |
| Picture in Picture with rewind / play / forward | ✅ custom ±10 s | ✅ system ±15 s |
| Fit / Fill | ✅ | ✅ |
| Pull-down refresh protection while typing | ✅ | ✅ keyboard hides the dock |

### Deliberate differences (iOS cannot match these exactly)

1. **Quality.** ExoPlayer enumerates the exact renditions of a stream. AVPlayer does not expose
   HLS renditions, so the Quality sheet sets a **bitrate ceiling** (Auto / up to 1080P / 720P / 480P)
   instead of listing real track heights. Downloads use the same labels to pick an HLS bitrate.
2. **Request filtering.** `WKWebView` has no `shouldInterceptRequest` equivalent, so ads are removed
   by a WebKit content rule list (host, resource-type and path rules) instead of answering each
   sub-resource request. The result is equivalent for ads; stream discovery still relies on the
   injected `fetch`/XHR/video observer, which is why `raw` and `media` requests are never blocked.
3. **Download preparation while closed.** Android resolves a queued episode in a foreground service.
   iOS may not run a hidden web view in the background, so queued episodes are resolved while the app
   is open; the transfer itself continues in a background `URLSession` (progressive) or
   `AVAssetDownloadURLSession` (HLS). Pausing an HLS item restarts that item when resumed.
4. **Wi-Fi only** is applied to progressive downloads immediately, and to HLS downloads accepted via
   the session configuration; toggling it does not throttle an already running HLS task.
5. **PiP buttons** are the system ones (±15 s) because custom remote actions in PiP are not a public API.
6. **No "Rotate" button.** iOS apps should not force orientation; rotate the device.
7. **Access check screen.** There is no separate access activity: the player explains what to do and
   the check is completed inside the in-app browser, whose cookies are then reused.
8. **No https deep link.** Claiming `en.hdrama.net` links needs associated domains on a host you control.

---

## 5. Source layout

| File | Responsibility |
| --- | --- |
| `Sources/AppDelegate.swift` | Window, browser root, background-download reconnection |
| `Sources/Theme.swift` | Palette, typography, rounded square target, empty state |
| `Sources/Models.swift` | Series/stream types, site and browser policy, episode order, seek and swipe rules, series parser |
| `Sources/AdBlocker.swift` | Content rule list, ad CSS and the document-start ad script (browser + resolver) |
| `Sources/Scripts.swift` | Injected DOM cleanup, page inspection, stream observer |
| `Sources/Library.swift` | Favorites, per-episode positions, history |
| `Sources/Artwork.swift` | Cached posters with validation and placeholder recovery |
| `Sources/SiteClient.swift` | Cookie-aware HTML fetch for series opened outside the browser |
| `Sources/BrowserViewController.swift` | Web view, dock, inspection guard, footer docking, Play handoff |
| `Sources/Resolver.swift` | Invisible web view that resolves the site's own video URL |
| `Sources/PlayerChrome.swift` | Player chrome with pass-through hit testing |
| `Sources/PlayerViewController.swift` | AVPlayer, gestures, resume, next episode, PiP, quality, speed |
| `Sources/Sheets.swift` | Bottom sheet container, episode grid, quality and speed lists |
| `Sources/Downloads.swift` | Offline store, background transfers, Downloads screen |
| `Sources/ListViewController.swift` | My List and History |

## 6. First-device test checklist

- Open a series, tap the site's Play, confirm the native player opens the same episode.
- Lock the phone during playback, then return: position must be preserved.
- Finish an episode: the next one starts; finishing the last shows the final-episode message.
- Kill the app after starting a download, reopen: progress continues and the folder list is correct.
- Turn on Wi-Fi only, disable Wi-Fi: no new download starts.
- Rotate with the episode sheet open; the grid must stay reachable.
- Enter Picture in Picture from the options menu and restore the app.
- Open a series: no popup, no ad plate, no `1:00 / OK` gate, no App Store redirect.
- Tap the site's Play and confirm the native player still receives the episode (the blocker must not
  interfere with stream discovery).

## 7. Verification status

Written from a full read of the reviewed Android code, but **not compiled, not linted and not run** —
no Xcode or iOS SDK was available. Expect a handful of small compiler complaints on first build
(deprecated `contentEdgeInsets`, unused variables) and send them over; each is a one-line fix.
The riskiest area is `AVURLAssetHTTPHeaderFieldsKey`, an undocumented but widely used key that the
site's CDN needs for the `Referer` header; if a stream returns 403, that is the first thing to inspect.

The ad blocker is 13 content rules plus one DOM script. The JSON was machine-validated as well-formed
and the script was checked for balanced syntax, but neither has been executed in WKWebView. The first
device run should confirm: (a) ads disappear, (b) the site's Play still resolves the episode, and
(c) the dock still measures the site footer. If one rule is too broad, delete that single entry from
`AdBlocker.rules`, bump `AdBlocker.identifier`, and rebuild — nothing else depends on it.
