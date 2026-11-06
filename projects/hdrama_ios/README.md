# HDrama for iPhone (1.1.1)

Native iOS app that mirrors HDrama 1.9.0 on Android: one-site browser, native video player, episode
grid, quality and speed, favorites, history, exact per-episode resume, automatic next episode,
Picture in Picture, offline downloads and an ad blocker.

**1.1.1 fixes the Cloudflare verification regression introduced by the 1.1.0 ad blocker.**

---

## 1. What broke in 1.1.0, and what changed

1.1.0 added an ad blocker that also interfered with the site's own Cloudflare check. Three separate
causes were found in `Sources/AdBlocker.swift` and `Sources/BrowserViewController.swift`:

| 1.1.0 behaviour | Why it broke verification | 1.1.1 behaviour |
| --- | --- | --- |
| Blocked **every** third-party `script`, `subdocument`, `style-sheet`, `font`, `svg-document` unless the host was on a six-entry allow list | A challenge that loads any asset from another host could not run, and third-party player frames were blocked too | The blanket third-party rule is **removed**. Only known ad/tracker **hosts**, strongly ad-shaped **paths** and **popups** are blocked |
| DOM script injected into **every frame** and replaced `window.open`, `alert`, `confirm`, `prompt`, `Notification.requestPermission` and `navigator.permissions.query` | Turnstile inspected that patched environment inside its own `challenges.cloudflare.com` frame, so the checkbox failed or looped | The script is **main frame only** and replaces **no globals**. Popups and dialogs are still handled natively by `WKUIDelegate`, which cannot affect a challenge |
| The sweep removed large fixed/sticky panels and released body scroll locks | The challenge is a large fixed panel, so it was eligible for removal | The sweep skips any node that **contains an iframe** or is named `cf-`, `turnstile` or `challenge`, and never unlocks scroll while a challenge is on screen |
| Main-frame navigation to any host other than `en.hdrama.net` was cancelled; `SitePolicy.verificationURL` existed but was **never used** (dead code) | A Cloudflare verification step that needs its own frame or top-level page could never complete | `verificationURL` is now wired into `decidePolicyFor`, so Cloudflare verification traffic is allowed |
| No `customUserAgent`; the default `WKWebView` string (`Mobile/15E148`, no `Safari` token) was sent | Bot protection can score a bare web view as an unsupported client and refuse the check | Browser **and** resolver send a normal iPhone Safari user agent |
| Rules ended without a Cloudflare exemption | Any rule could catch challenge traffic | Two `ignore-previous-rules` entries exempt all `*.cloudflare.com` / `*.cloudflareclient.com` hosts and every `/cdn-cgi/` path |

Ad coverage that remains: ~75 ad/tracker hosts, ad-shaped third-party paths, popups (also blocked
natively), a CSS hide list, and the main-frame DOM sweep for ad plates, "ad-free" overlays and
countdown gates. Media and `fetch`/XHR are never blocked, so stream discovery still works.

The rule list is now built with `JSONSerialization` instead of hand-escaped JSON text, so the rules
are valid JSON by construction. `AdBlocker.identifier` is bumped to `hdrama-adblock-3` so WebKit
recompiles instead of reusing its cached 1.1.0 list.

---

## 2. Build

```bash
brew install xcodegen
cd HDrama-iOS
xcodegen generate
open HDrama.xcodeproj
```

Target **HDrama** → *Signing & Capabilities* → your Team (bundle id stays `com.waqas.hdrama`).
iOS 15 or newer. Background audio is enabled for Picture in Picture and background downloads.
No third-party dependencies, no CocoaPods, no Swift packages.

The unsigned IPA produced by the builder **must be signed before installation** with your UDID
registrations service (for example https://www.ipasigner.com/), then installed.

---

## 3. Feature parity with HDrama 1.9.0 (Android)

Single-site browser with pull-to-refresh; four-target dock (My List, Downloads, History, Play) that
docks above the site footer and hides behind the keyboard; Play appears only on a validated playable
series page; player chrome with bold `EPn / EPm` and one 5-item rail (Favorite, My List, Download,
Quality, Speed); tap toggles controls, hold for 1.5x; horizontal drag previews then commits a seek
(90 s per screen width); vertical swipe changes episode; per-episode resume, completed episodes
replay from 0; automatic next episode; favorites with long-press removal; history with hold-to-delete
and clear-all; 30-per-range 5-column episode sheet; download sheet with select all/clear; download
folders with pause/resume/delete; offline playback with no network fallback; Wi-Fi only for new
downloads; Picture in Picture (system +/-15 s); Fit/Fill.

Known iOS differences: Quality is a bitrate ceiling (AVPlayer does not expose HLS renditions); ads are
removed by a content rule list rather than request interception; HLS download preparation runs while
the app is open; PiP uses system buttons; no forced rotation; the access check is completed in the
in-app browser and its cookies are reused.

---

## 4. Verification status

Static review plus a compiling unsigned device build. The rule list was validated as JSON before
saving. **No physical iPhone test was run**, so these still need a device check: (a) the Cloudflare
check completes, (b) the site's Play still resolves the episode, (c) ads, popups and countdown gates
stay gone, (d) the dock still measures the site footer.

If a check still fails on device, the next suspect is the remaining path rule: remove the single
`adPathFilter` entry from `AdBlocker.rules`, bump `AdBlocker.identifier`, rebuild.
