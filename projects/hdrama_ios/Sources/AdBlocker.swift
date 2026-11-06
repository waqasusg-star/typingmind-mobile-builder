import Foundation
import WebKit

/// Network and DOM ad blocking shared by the browser, the stream resolver and downloads.
///
/// Three local layers:
/// 1. A WebKit content rule list (`WKContentRuleList`, iOS 11+) stops ad networks, third-party
///    scripts/frames/popups and generic ad paths before they are downloaded.
/// 2. `css-display-none` hides ad containers in every frame.
/// 3. A document-start script removes popups, ad dialogs, sticky ad plates and countdown gates.
///
/// Nothing is proxied, no traffic leaves the device, and stream discovery (fetch/XHR/media) is
/// never blocked, so playback resolution keeps working exactly as before.
enum AdBlocker {

    /// Bump the suffix whenever `rules` changes so WebKit recompiles instead of using its cache.
    static let identifier = "hdrama-adblock-2"

    // MARK: - Content rule list

    static let rules = #"""
    [
      {
        "trigger": {
          "url-filter": "^https?://([a-z0-9-]+\\.)*(doubleclick\\.net|googlesyndication\\.com|googleadservices\\.com|adservice\\.google\\.com|googletagservices\\.com|googletagmanager\\.com|google-analytics\\.com|analytics\\.google\\.com|adnxs\\.com|adsrvr\\.org)([/:]|$)"
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": "^https?://([a-z0-9-]+\\.)*(adroll\\.com|appnexus\\.com|taboola\\.com|outbrain\\.com|popads\\.net|popcash\\.net|popmyads\\.com|propellerads\\.com|propeller-tv\\.com|adsterra\\.com)([/:]|$)"
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": "^https?://([a-z0-9-]+\\.)*(exoclick\\.com|exosrv\\.com|realsrv\\.com|onclickads\\.net|onclckds\\.com|onclkds\\.com|hilltopads\\.net|trafficjunky\\.net|juicyads\\.com|adcash\\.com)([/:]|$)"
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": "^https?://([a-z0-9-]+\\.)*(clickadu\\.com|monetag\\.com|a-ads\\.com|revcontent\\.com|mgid\\.com|zergnet\\.com|adskeeper\\.com|bidvertiser\\.com|clickaine\\.com|adspyglass\\.com)([/:]|$)"
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": "^https?://([a-z0-9-]+\\.)*(adnium\\.com|ad-maven\\.com|adpushup\\.com|criteo\\.com|criteo\\.net|casalemedia\\.com|pubmatic\\.com|rubiconproject\\.com|openx\\.net|33across\\.com)([/:]|$)"
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": "^https?://([a-z0-9-]+\\.)*(smartadserver\\.com|teads\\.tv|spotxchange\\.com|springserve\\.com|adform\\.net|1rx\\.io|3lift\\.com|tapad\\.com|yieldmo\\.com|sharethrough\\.com)([/:]|$)"
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": "^https?://([a-z0-9-]+\\.)*(districtm\\.ca|sovrn\\.com|lijit\\.com|indexww\\.com|scorecardresearch\\.com|quantserve\\.com|hotjar\\.com|connect\\.facebook\\.net|facebook\\.net|tsyndicate\\.com)([/:]|$)"
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": "^https?://([a-z0-9-]+\\.)*(clksite\\.com|adnium\\.net|adsmoloco\\.com|popunder\\.net|adfoc\\.us|linkvertise\\.com)([/:]|$)"
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": ".*",
          "load-type": [
            "third-party"
          ],
          "resource-type": [
            "script",
            "subdocument",
            "popup",
            "svg-document",
            "font",
            "style-sheet"
          ],
          "unless-domain": [
            "en.hdrama.net",
            "*hdrama.net",
            "challenges.cloudflare.com",
            "*challenges.cloudflare.com",
            "cdn.jsdelivr.net",
            "unpkg.com",
            "cdnjs.cloudflare.com"
          ]
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": "[/._-](ad|ads|adv|adserver|adservice|adsystem|advert|adzone|adslot|adframe|adunit|prebid|popunder|popup|sponsor|banner|vast|vpaid|ima3|gpt|dfp)([/._-]|$|[0-9])",
          "load-type": [
            "third-party"
          ],
          "resource-type": [
            "script",
            "image",
            "subdocument",
            "popup"
          ],
          "unless-domain": [
            "en.hdrama.net",
            "*hdrama.net",
            "challenges.cloudflare.com",
            "*challenges.cloudflare.com",
            "cdn.jsdelivr.net",
            "unpkg.com",
            "cdnjs.cloudflare.com"
          ]
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": ".*",
          "resource-type": [
            "popup"
          ]
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": ".*"
        },
        "action": {
          "type": "css-display-none",
          "selector": "[data-ad],[data-ad-slot],[data-ad-unit],.adsbygoogle,[id^=\"google_ads\"],[id^=\"div-gpt-ad\"],.ad-banner,.ad-container,.advertisement,.ad-popup,.ad-wrapper,.ad-slot,.ad-unit,.banner-ad,.popunder,[class*=\"advert\"],[id*=\"advert\"],[class*=\"interstitial\"],[id*=\"interstitial\"],[class*=\"popunder\"],[class*=\"sponsored\"],[class*=\"adsbygoogle\"],[class*=\"ad-slot\"],[class*=\"ad_slot\"],[class*=\"adbox\"],[class*=\"ad-wrapper\"],[class*=\"adWrapper\"],[class*=\"dfp-\"],[id*=\"dfp-\"],[class*=\"taboola\"],[class*=\"outbrain\"],[class*=\"sticky-ad\"],[id*=\"sticky-ad\"]"
        }
      },
      {
        "trigger": {
          "url-filter": "\\.(m3u8|mpd|mp4|webm|ts|m4s|aac|m4a|vtt)(\\?|#|$)",
          "resource-type": [
            "media",
            "raw"
          ]
        },
        "action": {
          "type": "ignore-previous-rules"
        }
      }
    ]
    """#

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
    static func configure(_ controller: WKUserContentController) {
        controller.addUserScript(WKUserScript(source: script,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: false))
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
      var noop = function () {};

      // 1. Popups and new tabs are always an ad on this site.
      try { window.open = function () { return null; }; } catch (e) {}

      // 2. An ad dialog must never freeze the app.
      try {
        window.alert = noop;
        window.confirm = function () { return false; };
        window.prompt = function () { return null; };
      } catch (e) {}

      // 3. The site cannot ask for notification permission; the app never requests it either.
      try {
        if (window.Notification) {
          Notification.requestPermission = function () { return Promise.resolve('denied'); };
        }
        if (navigator.permissions && navigator.permissions.query) {
          var query = navigator.permissions.query.bind(navigator.permissions);
          navigator.permissions.query = function (descriptor) {
            if (descriptor && /notifications|push/.test(String(descriptor.name))) {
              return Promise.resolve({state: 'denied', onchange: null});
            }
            return query(descriptor);
          };
        }
      } catch (e) {}

      // 4. Off-site clicks can never hijack the page.
      document.addEventListener('click', function (event) {
        var node = event.target instanceof Element ? event.target : null;
        var link = node && node.closest ? node.closest('a[href]') : null;
        if (!link) return;
        var href = link.getAttribute('href') || '';
        if (!href) return;
        if (/^\s*(javascript|data):/i.test(href)) {
          event.preventDefault();
          event.stopImmediatePropagation();
          return;
        }
        try {
          var url = new URL(href, location.href);
          if (url.protocol !== 'https:' || url.host !== location.host) {
            event.preventDefault();
            event.stopImmediatePropagation();
          }
        } catch (e) {}
      }, true);

      // 5. Remove ad plates, "ad-free" offers and countdown gates.
      var AD_TEXT = /(ad[\s-]?free|adblock|click now|sponsored|you won|congratulations|spin (the|to)|jackpot|download (our |the )?app|install (our |the )?app|join (our )?telegram|watch (an )?ad|skip (the )?ad|your video will start|disable.{0,14}blocker)/i;
      var GATE = /\b\d{1,2}:\d{2}\b/;
      var AD_NODES = '[data-ad],[data-ad-slot],[data-ad-unit],.adsbygoogle,[id^="google_ads"],[id^="div-gpt-ad"],' +
        '.ad-banner,.ad-container,.advertisement,.ad-popup,.ad-wrapper,.ad-slot,.banner-ad,.popunder,' +
        '[class*="advert"],[id*="advert"],[class*="interstitial"],[id*="interstitial"],[class*="popunder"],' +
        '[class*="sponsored"],[class*="adbox"],[class*="ad-slot"],[class*="sticky-ad"],[id*="sticky-ad"]';
      var KEEP = 'video,[class*="player"],[id*="player"],nav,footer';

      function drop(node, keep) {
        if (!node || !node.parentNode) return false;
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
        // Named ad containers are safe to remove even inside a player wrapper.
        for (var i = 0; i < nodes.length; i++) drop(nodes[i], 'video');

        var boxes = document.querySelectorAll('div,section,aside,dialog,form');
        for (var j = 0; j < boxes.length; j++) {
          var node = boxes[j];
          if (!node.parentNode) continue;
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

        // Release a scroll lock that a removed ad gate left behind.
        if (document.body && getComputedStyle(document.body).overflow === 'hidden' &&
            !document.querySelector('[aria-modal="true"],dialog[open]')) {
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
