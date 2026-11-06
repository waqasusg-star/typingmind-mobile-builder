import Foundation
import WebKit

/// Targeted ad filtering. Verification pages and frames retain standard browser APIs.
/// Compatibility mode removes this controller's filters and scripts, preserving website storage.
enum AdBlocker {

    /// Bump the suffix whenever the rules change so WebKit recompiles instead of using its cache.
    static let identifier = "hdrama-adblock-4"

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

    /// Built with `JSONSerialization`, so the rule list is valid JSON by construction instead of by
    /// hand-escaped regex text.
    static let rules: String = {
        var list: [[String: Any]] = adHostFilters.map { filter in
            ["trigger": ["url-filter": filter], "action": ["type": "block"]]
        }
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
      if (window.top !== window || location.hostname !== 'en.hdrama.net') return;
      if (window.__hdramaAds) return;
      window.__hdramaAds = true;
      var protectedNodes = '[class*="cf-"],[id*="cf-"],[class*="turnstile"],[id*="turnstile"],[class*="challenge"],[id*="challenge"],iframe[src*="challenges.cloudflare.com"]';
      var adNodes = '[data-ad],[data-ad-slot],[data-ad-unit],.adsbygoogle,[id^="google_ads"],[id^="div-gpt-ad"],.ad-banner,.ad-container,.advertisement,.ad-popup,.ad-slot,.banner-ad,.popunder';
      function challengeVisible() {
        return /\/cdn-cgi\//.test(location.pathname) || /just a moment|attention required|verify.{0,12}human|security verification/i.test(document.title) || document.querySelector(protectedNodes);
      }
      function sweep() {
        if (challengeVisible()) return;
        document.querySelectorAll(adNodes).forEach(function (node) {
          if (!node.parentNode || node.matches(protectedNodes) || node.closest(protectedNodes) || node.querySelector('iframe,object,embed,video,form,' + protectedNodes)) return;
          node.remove();
        });
      }
      var queued = false;
      function schedule() {
        if (queued) return;
        queued = true;
        requestAnimationFrame(function () { queued = false; sweep(); });
      }
      new MutationObserver(schedule).observe(document.documentElement, {childList:true, subtree:true});
      document.addEventListener('DOMContentLoaded', schedule, {once:true});
      schedule();
    })();
    """#
}
