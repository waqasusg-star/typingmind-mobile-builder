import UIKit
import WebKit

/// Resolves the site's own public player initialisation in an invisible web view.
/// It never solves a challenge, decrypts DRM or bypasses a login.
final class StreamResolver: NSObject, WKNavigationDelegate {

    enum ResolverError: LocalizedError {
        case timeout
        case blocked
        case unsupported

        var errorDescription: String? {
            switch self {
            case .timeout: return "The episode did not provide a supported video within 30 seconds. Tap Retry, or open the episode in the browser first."
            case .blocked: return "The website requires an access check. Open the series in the browser, complete any check, then try again."
            case .unsupported: return "This episode's video format is not supported."
            }
        }
    }

    private static var active: [StreamResolver] = []

    private var webView: WKWebView?
    private var timer: Timer?
    private var deadline: Timer?
    private var completion: ((Result<Stream, Error>) -> Void)?
    private var finished = false
    private var polling = false
    private var pageUrl = ""

    static func resolve(_ pageUrl: String, completion: @escaping (Result<Stream, Error>) -> Void) {
        let resolver = StreamResolver()
        resolver.start(pageUrl, completion)
    }

    private func start(_ pageUrl: String, _ completion: @escaping (Result<Stream, Error>) -> Void) {
        self.pageUrl = pageUrl
        self.completion = completion
        StreamResolver.active.append(self)

        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let controller = WKUserContentController()
        // Same blocking as the browser, main frame only, so a Cloudflare frame is never touched.
        AdBlocker.configure(controller, mainFrameOnly: true)
        controller.addUserScript(WKUserScript(source: Scripts.observer, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController = controller

        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: configuration)
        web.navigationDelegate = self
        // The same Safari user agent as the browser: a resolver that looks like a bare web view can
        // be denied by the site's protection even when the browser has already passed the check.
        web.customUserAgent = UserAgent.current
        web.alpha = 0.01
        web.isUserInteractionEnabled = false
        web.accessibilityElementsHidden = true
        webView = web

        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first else {
            finish(.failure(ResolverError.unsupported))
            return
        }
        window.addSubview(web)
        web.load(URLRequest(url: URL(string: pageUrl) ?? URL(string: SitePolicy.home)!))

        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.poll()
        }
        deadline = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            self?.finish(.failure(ResolverError.timeout))
        }
    }

    private func poll() {
        guard !finished, !polling, let web = webView else { return }
        polling = true
        web.evaluateJavaScript(Scripts.resolverInspect) { [weak self] value, _ in
            guard let self = self else { return }
            self.polling = false
            guard !self.finished else { return }
            guard let text = value as? String,
                  let data = text.data(using: .utf8),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
            if json["blocked"] as? Bool == true {
                self.finish(.failure(ResolverError.blocked))
                return
            }
            guard let sources = json["sources"] as? [[String: Any]] else { return }
            for source in sources {
                let url = source["url"] as? String ?? ""
                let mime = source["mimeType"] as? String ?? ""
                guard StreamPolicy.candidate(url, contentType: mime) else { continue }
                let stream = Stream(url: url,
                                    referer: self.pageUrl,
                                    userAgent: UserAgent.current,
                                    mimeType: StreamPolicy.mime(mime))
                self.finish(.success(stream))
                return
            }
        }
    }

    private func finish(_ result: Result<Stream, Error>) {
        guard !finished else { return }
        finished = true
        timer?.invalidate(); timer = nil
        deadline?.invalidate(); deadline = nil
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
        StreamResolver.active.removeAll { $0 === self }
        completion?(result)
        completion = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { poll() }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(.failure(ResolverError.unsupported))
    }
}
