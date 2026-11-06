import UIKit
import WebKit

/// Single-site browser with the same native dock, footer docking and Play handoff as the Android app.
final class BrowserViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {

    private var webView: WKWebView!
    private var compatibilityEnabled: Bool { UserDefaults.standard.bool(forKey: "site.compatibility." + SitePolicy.host) }
    private var siteAction: SquareAction!
    private let dock = UIView()
    private let dockStack = UIStackView()
    private var playAction: SquareAction!
    private var listAction: SquareAction!
    private var downloadsAction: SquareAction!
    private var historyAction: SquareAction!
    private let progressBar = UIProgressView(progressViewStyle: .default)
    private let refreshControl = UIRefreshControl()
    private var dockBottom: NSLayoutConstraint!
    private var progressObservation: NSKeyValueObservation?
    private var timer: Timer?
    private var followUpWork: DispatchWorkItem?

    private var inspecting = false
    private var inspectingEpoch = -1
    private var inspectionEpoch = 0
    private var injectedCSS = ""
    private var currentPage = ""
    private var validatedPage = ""
    private var target: PlaybackTarget?
    private var validatedSeries: Series?
    private var footerHeight: CGFloat = 0
    private var launchRequested = false
    private var keyboardVisible = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColors.background
        buildWebView()
        buildDock()
        buildProgress()
        observeKeyboard()
        // Hold the first request until the ad rules are compiled (or a 1.5 s timeout), so even the
        // opening page is filtered instead of showing a first-load ad.
        AdBlocker.whenReady { [weak self] in
            guard let self = self else { return }
            self.loadHome()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            self?.timerTick()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        timer?.fireDate = Date()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        timer?.fireDate = .distantFuture
        followUpWork?.cancel()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateDockPosition()
    }

    deinit {
        timer?.invalidate()
        followUpWork?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - UI

    private func buildWebView() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let controller = WKUserContentController()
        // Main frame only: the ad DOM script must never run inside the Cloudflare verification frame.
        if !compatibilityEnabled {
            AdBlocker.configure(controller, mainFrameOnly: true)
            controller.addUserScript(WKUserScript(source: Scripts.install, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        configuration.userContentController = controller
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        // A normal Safari user agent; the default WKWebView string can be treated as an unsupported
        // client by the site's bot protection, which is one reason a check can fail to pass.
        webView.customUserAgent = UserAgent.current
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.backgroundColor = AppColors.background
        webView.isOpaque = false
        webView.scrollView.backgroundColor = AppColors.background
        webView.scrollView.refreshControl = refreshControl
        refreshControl.tintColor = AppColors.accent
        refreshControl.removeTarget(self, action: #selector(reloadPage), for: .valueChanged)
        refreshControl.addTarget(self, action: #selector(reloadPage), for: .valueChanged)
        view.insertSubview(webView, at: 0)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            guard let self = self else { return }
            self.progressBar.progress = Float(webView.estimatedProgress)
            self.progressBar.isHidden = webView.estimatedProgress >= 1
        }
    }

    private func buildProgress() {
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.progressTintColor = AppColors.accent
        progressBar.trackTintColor = .clear
        progressBar.isUserInteractionEnabled = false
        progressBar.isHidden = true
        view.addSubview(progressBar)
        NSLayoutConstraint.activate([
            progressBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressBar.heightAnchor.constraint(equalToConstant: 2)
        ])
    }

    private func buildDock() {
        dock.translatesAutoresizingMaskIntoConstraints = false
        dock.backgroundColor = AppColors.overlay
        dock.layer.cornerRadius = 20
        dock.layer.cornerCurve = .continuous
        dock.layer.borderWidth = 1
        dock.layer.borderColor = AppColors.stroke.cgColor

        dockStack.axis = .horizontal
        dockStack.distribution = .fillEqually
        dockStack.alignment = .fill
        dockStack.spacing = 0
        dockStack.translatesAutoresizingMaskIntoConstraints = false
        dock.addSubview(dockStack)
        NSLayoutConstraint.activate([
            dockStack.topAnchor.constraint(equalTo: dock.topAnchor, constant: 6),
            dockStack.bottomAnchor.constraint(equalTo: dock.bottomAnchor, constant: -6),
            dockStack.leadingAnchor.constraint(equalTo: dock.leadingAnchor, constant: 8),
            dockStack.trailingAnchor.constraint(equalTo: dock.trailingAnchor, constant: -8)
        ])

        siteAction = SquareAction(symbol: "shield.lefthalf.filled", title: "Site")
        siteAction.onTap = { [weak self] in self?.showSiteOptions() }
        listAction = SquareAction(symbol: "heart", title: "My List")
        downloadsAction = SquareAction(symbol: "arrow.down", title: "Download")
        historyAction = SquareAction(symbol: "clock", title: "History")
        playAction = SquareAction(symbol: "play.fill", title: "Play", accented: true)
        playAction.isHidden = true

        listAction.onTap = { [weak self] in self?.presentList(.favorites) }
        downloadsAction.onTap = { [weak self] in
            let controller = DownloadsViewController()
            controller.modalPresentationStyle = .fullScreen
            self?.present(controller, animated: true)
        }
        historyAction.onTap = { [weak self] in self?.presentList(.history) }
        playAction.onTap = { [weak self] in self?.openPlayer() }

        [listAction, downloadsAction, historyAction, siteAction, playAction].forEach { dockStack.addArrangedSubview($0!) }

        view.addSubview(dock)
        let preferred = dock.widthAnchor.constraint(equalToConstant: 440)
        preferred.priority = .defaultHigh
        preferred.isActive = true
        dockBottom = dock.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -60)
        NSLayoutConstraint.activate([
            dock.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            dock.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 12),
            dock.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -12),
            dock.widthAnchor.constraint(lessThanOrEqualToConstant: 440),
            dockBottom
        ])
        updateDockPosition()
    }

    private func updateDockPosition() {
        guard dockBottom != nil else { return }
        let safe = view.safeAreaInsets.bottom
        dockBottom.constant = -(footerHeight + safe + 4)
    }

    private func observeKeyboard() {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)),
                                               name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func keyboardChanged(_ note: Notification) {
        var overlap: CGFloat = 0
        if let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
           note.name == UIResponder.keyboardWillChangeFrameNotification {
            let converted = view.convert(frame, from: nil)
            overlap = max(0, view.bounds.maxY - converted.minY)
        }
        keyboardVisible = overlap > 80
        dock.isHidden = keyboardVisible
        if !keyboardVisible { updateDockPosition() }
    }

    private func showSiteOptions() {
        let message = compatibilityEnabled
            ? "Compatibility is ON for this site. Ad filters and page helpers are paused; ads may appear. Cookies stay available. Turn it off after verification to restore native Play detection."
            : "Compatibility is OFF. If verification cannot finish, pause ad filters and page helpers for this site. Cookies are kept; no challenge is solved automatically."
        let alert = UIAlertController(title: "Site compatibility", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: compatibilityEnabled ? "Restore ad blocking" : "Enable compatibility", style: .default) { [weak self] _ in
            guard let self = self else { return }
            let destination = self.webView.url.flatMap { SitePolicy.siteURL($0.absoluteString) } ?? URL(string: SitePolicy.home)!
            UserDefaults.standard.set(!self.compatibilityEnabled, forKey: "site.compatibility." + SitePolicy.host)
            self.webView.stopLoading()
            self.progressObservation = nil
            self.webView.navigationDelegate = nil
            self.webView.uiDelegate = nil
            self.webView.removeFromSuperview()
            self.inspectionEpoch += 1
            self.inspecting = false
            self.currentPage = ""
            self.validatedPage = ""
            self.target = nil
            self.validatedSeries = nil
            self.footerHeight = 0
            self.playAction.isHidden = true
            self.followUpWork?.cancel()
            self.buildWebView()
            self.webView.load(URLRequest(url: destination))
            self.updateDockPosition()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func reloadPage() {
        target = nil
        validatedPage = ""
        validatedSeries = nil
        playAction?.isHidden = true
        webView.reload()
    }

    private func loadHome() {
        guard let url = URL(string: SitePolicy.home) else { return }
        webView.load(URLRequest(url: url))
    }

    // MARK: - Inspection

    /// Series and episode pages need repeated inspection while the page settles; the rest of the site
    /// is inspected once per navigation plus one follow-up after layout, instead of every 1.2 s.
    private var isSeriesLikePage: Bool {
        guard let url = webView.url?.absoluteString else { return false }
        return BrowserPolicy.playback(url) != nil
    }

    private func timerTick() {
        guard isSeriesLikePage else { return }
        inspectPage()
    }

    private func scheduleFollowUpInspection() {
        followUpWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, !self.isSeriesLikePage else { return }
            self.inspectPage()
        }
        followUpWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func inspectPage() {
        guard !compatibilityEnabled, !keyboardVisible, !inspecting,
              viewIfLoaded?.window != nil,
              let url = webView.url?.absoluteString,
              SitePolicy.siteURL(url) != nil else { return }
        inspecting = true
        let epoch = inspectionEpoch
        inspectingEpoch = epoch
        let source = Scripts.inspect.replacingOccurrences(of: "__KNOWN_PAGE__", with: jsonString(validatedPage))
        webView.evaluateJavaScript(source) { [weak self] value, _ in
            guard let self = self else { return }
            // Only the current inspection releases the guard, and it releases even when backgrounded.
            if epoch == self.inspectingEpoch { self.inspecting = false }
            guard epoch == self.inspectionEpoch,
                  let text = value as? String,
                  let data = text.data(using: .utf8),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
            self.accept(json)
        }
    }

    private func accept(_ data: [String: Any]) {
        guard let url = data["url"] as? String,
              SitePolicy.siteURL(url) != nil,
              webView.url?.absoluteString == url else { return }
        pageChanged(url)

        let html = data["html"] as? String ?? ""
        if (data["blocked"] as? Bool == true) || SeriesParser.blocked(html) {
            target = nil
            validatedSeries = nil
            playAction?.isHidden = true
            launchRequested = false
            return
        }

        if let footer = data["footerHeight"] as? Double,
           let viewport = data["viewportHeight"] as? Double,
           viewport > 0, webView.bounds.height > 0, !keyboardVisible {
            let scale = webView.bounds.height / CGFloat(viewport)
            footerHeight = min(max(0, CGFloat(footer)), CGFloat(viewport) * 0.3) * scale
            updateDockPosition()
            injectDockSpace(viewport: CGFloat(viewport))
        }

        if !html.isEmpty || validatedPage != url {
            let candidate = BrowserPolicy.playback(url)
            let parsed = candidate == nil ? nil : SeriesParser.series(html: html, url: url)
            target = parsed != nil ? candidate : nil
            validatedSeries = parsed
            if target != nil { validatedPage = url }
        }

        playAction?.isHidden = target == nil
        if let series = validatedSeries, target != nil {
            playAction?.control.accessibilityLabel = "Play \(series.title) in native player"
            Artwork.shared.fetch(series)
            if launchRequested {
                launchRequested = false
                openPlayer()
            }
        }
    }

    private func pageChanged(_ url: String) {
        guard url != currentPage else { return }
        inspectionEpoch += 1
        inspecting = false
        inspectingEpoch = -1
        injectedCSS = ""
        currentPage = url
        footerHeight = 0
        target = nil
        validatedSeries = nil
        validatedPage = ""
        launchRequested = false
        playAction?.isHidden = true
        updateDockPosition()
    }

    private func injectDockSpace(viewport: CGFloat) {
        let scale = max(0.5, webView.bounds.height / max(1, viewport))
        let space = (dock.bounds.height + footerHeight + view.safeAreaInsets.bottom + 12) / scale
        let css = "body{padding-bottom:\(Int(space))px!important}"
        guard css != injectedCSS else { return }
        injectedCSS = css
        let js = "(function(){var s=document.getElementById('native-dock-space');"
            + "if(!s){s=document.createElement('style');s.id='native-dock-space';"
            + "(document.head||document.documentElement).appendChild(s);}"
            + "var css=" + jsonString(css) + ";if(s.textContent!==css)s.textContent=css;})()"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func jsonString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed),
              let text = String(data: data, encoding: .utf8) else { return "\"\"" }
        return text
    }

    // MARK: - Player

    private func openPlayer() {
        guard let target = target, validatedPage == webView.url?.absoluteString else { return }
        if let series = validatedSeries { PlaybackHandoff.offer(series) }
        webView.evaluateJavaScript(Scripts.pauseVideo, completionHandler: nil)
        let controller = PlayerViewController(seriesUrl: target.seriesUrl,
                                             episode: target.episode > 0 ? target.episode : nil,
                                             offline: nil)
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true)
    }

    private func presentList(_ mode: ListViewController.Mode) {
        let controller = ListViewController(mode: mode)
        controller.onOpen = { [weak self] item in
            guard let self = self else { return }
            self.dismiss(animated: true) {
                let player = PlayerViewController(seriesUrl: item.url, episode: nil, offline: nil)
                player.modalPresentationStyle = .fullScreen
                self.present(player, animated: true)
            }
        }
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url?.absoluteString ?? ""
        if url == "hdrama-native://play" {
            decisionHandler(.cancel)
            if target != nil, validatedPage == webView.url?.absoluteString {
                openPlayer()
            } else {
                launchRequested = true
                inspectPage()
            }
            return
        }
        if navigationAction.targetFrame?.isMainFrame == false,
           url == "about:blank" || url == "about:srcdoc" {
            decisionHandler(.allow)
            return
        }
        // Cloudflare verification must be allowed to load and finish, including in its own frame.
        // 1.1.0 cancelled this traffic, which could stop the check from ever completing.
        if navigationAction.targetFrame != nil, SitePolicy.verificationURL(url) {
            decisionHandler(.allow)
            return
        }
        // itms-apps://, intent://, market:// and mailto:// are advertising or store redirects.
        if let scheme = navigationAction.request.url?.scheme?.lowercased(), scheme != "http", scheme != "https" {
            decisionHandler(.cancel)
            return
        }
        if navigationAction.targetFrame == nil {
            decisionHandler(.cancel)
            return
        }
        if navigationAction.targetFrame?.isMainFrame == true, SitePolicy.siteURL(url) == nil {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        inspectionEpoch += 1
        inspecting = false
        inspectingEpoch = -1
        injectedCSS = ""
        validatedPage = ""
        target = nil
        validatedSeries = nil
        launchRequested = false
        playAction?.isHidden = true
        progressBar.isHidden = false
        pageChanged(webView.url?.absoluteString ?? "")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refreshControl.endRefreshing()
        progressBar.isHidden = true
        inspectPage()
        scheduleFollowUpInspection()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        refreshControl.endRefreshing()
        progressBar.isHidden = true
        showToast("Website could not load. Check your connection.")
    }

    // MARK: - WKUIDelegate: dialogs and popups are advertising surfaces

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        // window.open and target="_blank" never create a second web view.
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        // Dismiss instead of blocking the page behind a system alert.
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(false)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        completionHandler(nil)
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.deny)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // Rebuild the page instead of closing the app when the web content process dies.
        inspecting = false
        inspectingEpoch = -1
        webView.reload()
    }

    private func showToast(_ message: String) {
        let container = UIView()
        container.backgroundColor = AppColors.overlay
        container.layer.cornerRadius = 14
        container.layer.cornerCurve = .continuous
        container.layer.borderWidth = 1
        container.layer.borderColor = AppColors.stroke.cgColor
        container.alpha = 0
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)

        let label = Theme.label(message, size: 13, color: AppColors.text, lines: 2, align: .center)
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            container.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            container.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -48),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16)
        ])
        UIView.animate(withDuration: 0.2) {
            container.alpha = 1
        } completion: { _ in
            UIView.animate(withDuration: 0.3, delay: 2.4, options: []) {
                container.alpha = 0
            } completion: { _ in
                container.removeFromSuperview()
            }
        }
    }
}
