import Foundation
import WebKit

/// Network and DOM ad blocking shared by the browser, the stream resolver and downloads.
///
/// 1.1.1 redesign: advertising is removed **without touching anything the site's Cloudflare
/// verification depends on**. The 1.1.0 blocker interfered with verification in three ways:
///
/// 1. It blocked every third-party `script`, `subdocument`, `style-sheet`, `font` and `svg-document`
///    unless the host was on a six-entry allow list, so a challenge that loads any asset from another
///    host could not run (and third-party player frames were caught too).
/// 2. Its DOM script ran in **every** frame (`forMainFrameOnly: false`) and replaced `window.open`,
///    `alert`, `confirm`, `prompt`, `Notification.requestPermission` and
///    `navigator.permissions.query` inside the `challenges.cloudflare.com` Turnstile frame. Turnstile
///    inspects that environment, so the checkbox failed or looped.
/// 3. Its sweep removed large fixed/sticky panels and released body scroll locks. The Cloudflare
///    challenge is a large fixed panel, so it was eligible for removal.
///
/// 1.1.1 keeps only: known ad/tracker hosts, strongly ad-shaped ad paths, popups (also blocked
/// natively by `createWebViewWith` returning nil), a CSS hide list, and a **main-frame only** sweep
/// that refuses to touch any node containing an iframe or anything named `cf-`, `turnstile` or
/// `challenge`. More rules exempt Cloudflare challenge traffic explicitly. Nothing is proxied, no
/// traffic leaves the device, and stream discovery is never blocked.
enum AdBlocker {

    /// Bump the suffix whenever the rules change so WebKit recompiles instead of using its cache.
    static let identifier = "hdrama-adblock-3"

    // MARK: - Content rule list

    /// Ad and tracker hosts, blocked by host only so nothing else on the page is affected.
    private static let adHostFilters: [String] = [
        #"^https?://([a-z0-9-]+\.)*(doubleclick\.net|googlesyndication\.com|googleadservices\.com|adservice\.google\.com|googletagservices\.com|googletagmanager\.com|google-analytics\.com|analytics\.google\.com)([/:]|$)"#,
        #"^https?://([a-z0-9-]+\.)*(adnxs\.com|adsrvr\.org|adroll\.com|appnexus\.com|taboola\.com|outbrain\.com|popads\.net|popcash\.net|popmyads\.com|propellerads\.com|propeller-tv\.com|adsterra\.com)([/:]|$)"#,
        #"^https?://([a-z0-9-]+\.)*(exoclick\.com|exosrv\.com|realsrv\.com|onclickads\.net|onclckds\.com|onclkds\.com|hilltopads\.net|trafficjunky\.net|juicyads\.com|adcash\.com)([/:]|$)"#,
        #"^https?://([a-z0-9-]+\.)*(clickadu\.com|monetag\.com|a-ads\.com|revcontent\.com|mgid\.com|zergnet\.com|adskeeper\.com|bidvertiser\.com|clickaine\.com|adspyglass\.com)([/:]|$)"#,
        #"^https?://([a-z0-9-]+\.)*(adnium\.com|adnium\.net|ad-maven\.com|adpushup\.com|criteo\.com|criteo\.net|casalemedia\.com|pubmatic\.com|rubiconproject\.com|openx\.net|33across\.com)([/:]|$)"#,
        #"^https?://([a-z0-9-]+\.)*(smartadserver\.com|teads\.tv|spotxchange\.com|springserve\.com|adform\.net|1rx\.io|3lift\.com|tapad\.com|yieldmo\.com|sharethrough\.com)([/:]|$)"#,
        #"^https?://([a-z0-9-]+\.)*(districtm\.ca|sovrn\.com|lijit\.com|indexww\.com|scorecardresearch\.com|quantserve\.com|hotjar\.com|connect\.facebook\.net|tsyndicate\.com)([/:]|$)"#,
        #"^https?://([a-z0-9-]+\.)*(clksite\.com|adsmoloco\.com|popunder\.net|adfoc\.us|linkvertise\.com)([/:]|$)"#
    ]

    /// Only strongly ad-shaped paths are blocked; a plain third-party script or frame is now allowed,
    /// because Cloudflare and the site's own player both use them.
    private static let adPathFilter = #"[/._-](adserver|adservice|adsystem|advert|adzone|adslot|adframe|adunit|prebid|popunder|popupad|vast|vpaid|ima3|gpt|dfp)([/._-]|$|[0-9])"#

    /// Cloudflare, the site itself and the CDNs it needs are never matched by the path rule.
    private static let keepDomains = ["en.hdrama.net", "*hdrama.net", "*cloudflare.com",
                                      "*cloudflareclient.com", "cdn.jsdelivr.net", "unpkg.com",
                                      "cdnjs.cloudflare.com"]

    private static let cssSelector = #"[data-ad],[data-ad-slot],[data-ad-unit],.adsbygoogle,[id^="google_ads"],[id^="div-gpt-ad"],.ad-banner,.ad-container,.advertisement,.ad-popup,.ad-wrapper,.ad-slot,.ad-unit,.banner-ad,.popunder,[class*="advert"],[class*="ad-slot"],[class*="ad_slot"],[class*="adbox"],[class*="ad-wrapper"],[class*="dfp-"],[id*="dfp-"],[class*="taboola"],[class*="outbrain"],[class*="sticky-ad"],[id*="sticky-ad"]"#

    /// Built with `JSONSerialization`, so the rule list is valid JSON by construction instead of by
    /// hand-escaped regex text.
    static let rules: String = {
        var list: [[String: Any]] = adHostFilters.map { filter in
            ["trigger": ["url-filter": filter], "action": ["type": "block"]]
        }
        list.append([
            "trigger": [
                "url-filter": adPathFilter,
                "load-type": ["first-party", "third-party"],
                "resource-type": ["image", "script", "subdocument", "style-sheet"],
                "unless-domain": keepDomains
            ],
            "action": ["type": "block"]
        ])
        list.append([
            "trigger": ["url-filter": ".*", "resource-type": ["popup"]],
            "action": ["type": "block"]
        ])
        list.append([
            "trigger": ["url-filter": ".*"],
            "action": ["type": "css-display-none", "selector": cssSelector]
        ])
        // Nothing above may touch Cloudflare verification traffic, whatever host it uses.
        list.append([
            "trigger": ["url-filter": #"^https?://([a-z0-9-]+\.)*(cloudflare\.com|cloudflareclient\.com|cloudflareinsights\.com|cloudflare-dns\.com)([/:]|$)"#],
            "action": ["type": "ignore-previous-rules"]
        ])
        list.append([
            "trigger": ["url-filter": #"^https?://[^/]+/cdn-cgi/"#],
            "action": ["type": "ignore-previous-rules"]
        ])
        // Playback discovery keeps working: media and fetch/XHR responses are never blocked.
        list.append([
            "trigger": ["url-filter": #"\.(m3u8|mpd|mp4|webm|ts|m4s|aac|m4a|vtt)(\?|#|$)"#,
                        "resource-type": ["media", "raw"]],
            "action": ["type": "ignore-previous-rules"]
        ])
        guard let data = try? JSONSerialization.data(withJSONObject: list, options: []),
              let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }()

    private static var compiled: WKContentRuleList?
    private static var compileFailed = false
    private static var compiling = false
    private static var waiters: [() -> Void] = []
    private static var attachments: [WKUserContentController] = []
    private static var timeoutScheduled = false

    /// Compile at launch so the first page load is already filtered.
    static func prepare() {
        guard compiled == nil, !compiling, !compileFailed else { return }
        compiling = true
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: identifier,
                                                                encodedContentRuleList: rules) { list, _ in
            DispatchQueue.main.async {
                compiling = false
                if let list = list {
                    compiled = list
                    let pending = attachments
                    attachments = []
                    for controller in pending { controller.add(list) }
                } else {
                    compileFailed = true
                    attachments = []
                }
                flush(force: false)
            }
        }
    }

    /// Adds the blocking script and the compiled rules to a web view configuration.
    ///
    /// The script is injected into the main frame only: it must never run inside the
    /// `challenges.cloudflare.com` verification frame.
    static func configure(_ controller: WKUserContentController, mainFrameOnly: Bool = true) {
        controller.addUserScript(WKUserScript(source: script,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: mainFrameOnly))
        if let compiled = compiled {
            controller.add(compiled)
            return
        }
        attachments.append(controller)
        prepare()
    }

    /// Runs `action` once blocking is available, or after a short timeout, so a compile problem
    /// can never leave the browser on an empty screen.
    static func whenReady(_ action: @escaping () -> Void) {
        if compiled != nil || compileFailed { action(); return }
        waiters.append(action)
        prepare()
        if !timeoutScheduled {
            timeoutScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { flush(force: true) }
        }
    }

    private static func flush(force: Bool) {
        if !force, compiled == nil, !compileFailed { return }
        timeoutScheduled = false
        let actions = waiters
        waiters = []
        for action in actions { action() }
    }

    // MARK: - DOM script

    static let script = #"""
    (function () {
      if (window.__hdramaAds) return;
      window.__hdramaAds = true;

      // Cloudflare verification must never be touched. No global here is replaced any more
      // (window.open, alert, confirm, prompt and navigator.permissions are left alone); popups and
      // dialogs are already handled natively by WKUIDelegate, which cannot affect a challenge.
      var CF_SAFE = '[class*="cf-"],[id*="cf-"],[class*="turnstile"],[id*="turnstile"],' +
        '[class*="challenge"],[id*="challenge"],#challenge-stage,#challenge-form';

      function isProtected(node) {
        if (!node || !node.matches) return true;
        try {
          if (node.matches(CF_SAFE)) return true;
          if (node.closest && node.closest(CF_SAFE)) return true;
          if (node.querySelector && node.querySelector('iframe,object,embed,' + CF_SAFE)) return true;
        } catch (e) { return true; }
        return false;
      }

      // 1. Ad redirects (app store, intent, javascript, data links) cannot hijack the page.
      //    Ordinary links are left alone so logins and access checks keep working.
      document.addEventListener('click', function (event) {
        var node = event.target instanceof Element ? event.target : null;
        var link = node && node.closest ? node.closest('a[href]') : null;
        if (!link || isProtected(link)) return;
        var href = link.getAttribute('href') || '';
        if (!href) return;
        if (/^\s*(javascript|data|itms-apps|itms|intent|market|mailto|tel):/i.test(href)) {
          event.preventDefault();
          event.stopImmediatePropagation();
        }
      }, true);

      // 2. Remove ad plates, "ad-free" offers and countdown gates. Protected nodes are skipped.
      var AD_TEXT = /(ad[\s-]?free|adblock|click now|sponsored|you won|congratulations|spin (the|to)|jackpot|download (our |the )?app|install (our |the )?app|join (our )?telegram|watch (an )?ad|skip (the )?ad|your video will start|disable.{0,14}blocker)/i;
      var GATE = /\b\d{1,2}:\d{2}\b/;
      var AD_NODES = '[data-ad],[data-ad-slot],[data-ad-unit],.adsbygoogle,[id^="google_ads"],[id^="div-gpt-ad"],' +
        '.ad-banner,.ad-container,.advertisement,.ad-popup,.ad-wrapper,.ad-slot,.banner-ad,.popunder,' +
        '[class*="advert"],[class*="popunder"],[class*="adbox"],[class*="ad-slot"],' +
        '[class*="sticky-ad"],[id*="sticky-ad"]';
      var KEEP = 'video,[class*="player"],[id*="player"],nav,footer';

      function drop(node, keep) {
        if (!node || !node.parentNode) return false;
        if (isProtected(node)) return false;
        if (node.querySelector && node.querySelector(keep)) return false;
        if (node.closest && node.closest(keep)) return false;
        node.remove();
        return true;
      }

      var lastSweep = 0;
      function sweep() {
        var now = Date.now();
        if (now - lastSweep < 250) return;
        lastSweep = now;
        var width = window.innerWidth || 1;
        var height = window.innerHeight || 1;
        var nodes = document.querySelectorAll(AD_NODES);
        for (var i = 0; i < nodes.length; i++) drop(nodes[i], 'video');

        var boxes = document.querySelectorAll('div,section,aside,dialog,form');
        for (var j = 0; j < boxes.length; j++) {
          var node = boxes[j];
          if (!node.parentNode || isProtected(node)) continue;
          var style = getComputedStyle(node);
          if (style.position !== 'fixed' && style.position !== 'sticky') continue;
          if (style.display === 'none' || style.visibility === 'hidden') continue;
          var rect = node.getBoundingClientRect();
          if (rect.width * rect.height < width * height * 0.18) continue;
          var text = (node.innerText || '').slice(0, 300);
          var gate = GATE.test(text) && text.length < 90 && node.querySelector('button,a,[role="button"]');
          if (!AD_TEXT.test(text) && !gate) continue;
          drop(node, KEEP);
        }

        // Release a scroll lock a removed ad gate left behind, but never while a check is showing.
        if (document.body && getComputedStyle(document.body).overflow === 'hidden' &&
            !document.querySelector('[aria-modal="true"],dialog[open],' + CF_SAFE)) {
          document.body.style.overflow = '';
          document.documentElement.style.overflow = '';
        }
      }

      var queued = false;
      function run() {
        queued = false;
        try { sweep(); } catch (e) {}
      }
      function schedule() {
        if (queued) return;
        queued = true;
        if (typeof window.requestAnimationFrame === 'function') window.requestAnimationFrame(run);
        else setTimeout(run, 16);
      }

      try {
        new MutationObserver(schedule).observe(document.documentElement, {childList: true, subtree: true});
      } catch (e) {}
      document.addEventListener('DOMContentLoaded', schedule, {once: true});
      window.addEventListener('load', schedule, {once: true});
      setInterval(function () { try { sweep(); } catch (e) {} }, 1500);
    })();
    """#
}
