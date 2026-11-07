import UIKit
import WebKit

// DeepSeek Pulse — install the drawn app mark as a real Home Screen tile.
//
// Why this exists: the reviewed native pipeline compiles Swift sources and text resources, so an
// `Assets.xcassets` AppIcon set cannot be added as a binary PNG. iOS only shows a Home Screen icon
// for an application bundle that carries one.
//
// This helper therefore uses the public WebKit route Apple provides for any site: it serves the icon
// bytes from a local, on-device loopback server, opens that page over http://127.0.0.1, and lets the
// user add it with Safari's own "Add to Home Screen". The result is a genuine Home Screen tile with
// the mark above and the app name underneath.
//
// Limits, stated plainly in the UI:
//   * the tile opens the loopback page, not the app bundle, so API keys and stored data live in the
//     app itself and are not touched by it;
//   * the real app icon appears in Settings, Spotlight and the App Library from the app bundle;
//   * the local server exists only while this screen (or the app) is alive.

enum AppIconServeResult: Equatable {
    /// The page is ready; Safari can be opened at `url`.
    case ready(URL)
    /// The loopback listener could not start on this device.
    case listenFailed(String)
    /// The icon or page could not be encoded.
    case payloadFailed

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var message: String {
        switch self {
        case .ready(let url):
            return "Ready. Opening " + url.absoluteString
        case .listenFailed(let detail):
            return "The local page could not start: " + detail
        case .payloadFailed:
            return "The icon could not be rendered on this device."
        }
    }
}

/// Serves one small HTML page plus the icon PNG from 127.0.0.1 so Safari can add it to the Home Screen.
final class AppIconLoopbackServer {

    /// Port pinned to a high, unprivileged value; if it is busy the next port is tried.
    private static let basePort: UInt16 = 8731
    private static let portAttempts = 8

    private var listener: AnyObject?
    private(set) var port: UInt16 = AppIconLoopbackServer.basePort

    /// The page contents and the PNG bytes, both generated from AppIconArtwork.
    let pageData: Data
    let iconData: Data

    init?() {
        guard let png = AppIcon.image(size: CGFloat(AppIconArtwork.recommendedPixelSize), opaque: true)
            .pngData() else { return nil }
        iconData = png
        pageData = Data(AppIconLoopbackServer.page.replacingOccurrences(of: "{{ICON_SIZE}}",
                                                                       with: String(AppIconArtwork.recommendedPixelSize)).utf8)
    }

    /// The HTML Safari will show. It declares the manifest icons Safari needs for the tile, and it
    /// stores nothing: no key, no balance, no identifier.
    static let page = """<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-title" content="DeepSeek Pulse">
<link rel="apple-touch-icon" sizes="{{ICON_SIZE}}x{{ICON_SIZE}}" href="/icon.png">
<title>DeepSeek Pulse</title>
<style>
body{margin:0;min-height:100vh;display:flex;flex-direction:column;justify-content:center;
font-family:-apple-system,sans-serif;background:#0A0F1E;color:#F2F5FF;padding:28px;text-align:center}
img{width:112px;height:112px;border-radius:26px;margin:0 auto 20px;display:block}
h1{font-size:20px;margin:0 0 10px}
p{font-size:14px;line-height:1.5;color:#97A3C2;margin:6px 0}
</style></head>
<body>
<img src="/icon.png" alt="DeepSeek Pulse">
<h1>DeepSeek Pulse</h1>
<p>Tap the Share button, then Add to Home Screen.</p>
<p>This page only installs the icon. Pricing, balance and your API key stay inside the DeepSeek Pulse app.</p>
</body></html>
"""

    /// Starts a loopback HTTP listener. Returns the page URL Safari should open.
    func start() -> AppIconServeResult {
        if listener != nil {
            return .ready(url ?? AppIconLoopbackServer.url(port: port))
        }
        for offset in 0..<AppIconLoopbackServer.portAttempts {
            let candidate = AppIconLoopbackServer.basePort + UInt16(offset)
            if let server = LoopbackHTTPServer.start(port: candidate, handler: { [weak self] path in
                guard let self = self else { return (404, "text/plain", Data()) }
                if path.contains("icon.png") {
                    return (200, "image/png", self.iconData)
                }
                return (200, "text/html; charset=utf-8", self.pageData)
            }) {
                listener = server
                port = candidate
                return .ready(AppIconLoopbackServer.url(port: candidate))
            }
        }
        return .listenFailed("no free local port in " + String(AppIconLoopbackServer.basePort) + "…")
    }

    func stop() {
        listener = nil
    }

    var url: URL? { AppIconLoopbackServer.url(port: port) }

    static func url(port: UInt16) -> URL {
        URL(string: "http://127.0.0.1:" + String(port) + "/") ?? URL(string: "http://127.0.0.1/")!
    }
}

/// Thin wrapper so the availability decision is testable and the UI can explain itself.
enum HomeScreenShortcut {

    /// Only Safari can add a page to the Home Screen, and only over http/https.
    static var canInstall: Bool {
        UIApplication.shared.canOpenURL(AppIconLoopbackServer.url(port: AppIconLoopbackServer.basePort))
    }

    static let steps = [
        "1. The page opens in Safari with the icon and the name DeepSeek Pulse.",
        "2. Tap the Share button (the square with the arrow).",
        "3. Choose Add to Home Screen, then Add.",
        "4. The tile appears with this icon. Move it anywhere on your Home Screen."
    ]
}
