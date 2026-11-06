import Foundation

struct Drama {
    let title: String
    let url: String
}

struct Episode {
    let number: Int
    let pageUrl: String
}

struct Series {
    let title: String
    let url: String
    let episodes: [Episode]
    var posterUrl: String = ""
    var seasonLabel: String = ""
}

struct Stream {
    let url: String
    let referer: String
    let userAgent: String
    var mimeType: String? = nil
}

struct PlaybackTarget {
    let seriesUrl: String
    let episode: Int
}

enum EpisodeOrder {
    static func next(_ index: Int, _ size: Int) -> Int? {
        let value = index + 1
        return (index >= 0 && value < size) ? value : nil
    }
    static func previous(_ index: Int, _ size: Int) -> Int? {
        let value = index - 1
        return (index < size && value >= 0) ? value : nil
    }
}

/// Single-site rules; mirrors the Android SitePolicy exactly.
enum SitePolicy {
    static let home = "https://en.hdrama.net/"
    static let host = "en.hdrama.net"

    static func siteURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == host,
              url.port == nil || url.port == 443,
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    static func verificationURL(_ raw: String) -> Bool {
        if siteURL(raw) != nil { return true }
        guard let url = URL(string: raw) else { return false }
        return url.scheme == "https" && url.host == "challenges.cloudflare.com"
            && (url.port == nil || url.port == 443) && url.user == nil && url.password == nil
    }

    static func seriesURL(_ raw: String) -> String? {
        guard let url = siteURL(raw) else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts.count <= 3, parts[0] == "series" else { return nil }
        if parts.count == 3, parts[2].range(of: "^episode-\\d+$", options: .regularExpression) == nil { return nil }
        return "https://\(host)/series/\(parts[1])"
    }

    static func mediaURL(_ raw: String) -> Bool {
        guard let url = URL(string: raw) else { return false }
        return url.scheme == "https" && ["m3u8", "mp4", "mpd", "webm"].contains(url.pathExtension.lowercased())
    }
}

enum BrowserPolicy {
    private static let adHosts: [String] = [
        "doubleclick.net", "googlesyndication.com", "googleadservices.com", "googletagmanager.com",
        "google-analytics.com", "adservice.google.com", "adnxs.com", "adsrvr.org", "adroll.com",
        "taboola.com", "outbrain.com", "popads.net", "popcash.net", "propellerads.com",
        "adsterra.com", "exoclick.com", "onclickads.net", "hilltopads.net", "trafficjunky.net",
        "juicyads.com", "adcash.com", "clickadu.com", "monetag.com", "a-ads.com"
    ]

    static func blockedHost(_ host: String) -> Bool {
        let value = host.lowercased()
        return adHosts.contains { value == $0 || value.hasSuffix("." + $0) }
    }

    static func playback(_ raw: String) -> PlaybackTarget? {
        guard let canonical = SitePolicy.seriesURL(raw), let url = URL(string: raw) else { return nil }
        let segment = url.lastPathComponent
        guard segment.hasPrefix("episode-") else { return PlaybackTarget(seriesUrl: canonical, episode: 0) }
        guard let number = Int(segment.dropFirst("episode-".count)), number > 0 else { return nil }
        return PlaybackTarget(seriesUrl: canonical, episode: number)
    }

    static func normalizeAddress(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let candidate = value.contains("://") ? value : "https://" + value
        return SitePolicy.siteURL(candidate)?.absoluteString
    }
}

enum StreamPolicy {
    static func mime(_ raw: String) -> String? {
        let value = raw.split(separator: ";").first.map(String.init)?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        switch value {
        case "application/vnd.apple.mpegurl", "application/x-mpegurl", "audio/mpegurl", "audio/x-mpegurl":
            return "application/vnd.apple.mpegurl"
        case "application/dash+xml": return "application/dash+xml"
        case "video/mp4": return "video/mp4"
        case "video/webm": return "video/webm"
        default: return nil
        }
    }

    static func candidate(_ raw: String, contentType: String = "") -> Bool {
        guard let url = URL(string: raw) else { return false }
        guard url.scheme == "https", url.user == nil, url.password == nil else { return false }
        guard let host = url.host, !BrowserPolicy.blockedHost(host) else { return false }
        return SitePolicy.mediaURL(raw) || mime(contentType) != nil
    }
}

/// One screen width covers at most 90 seconds, matching the Android gesture rules.
enum ScreenSeek {
    static func target(origin: Double, distance: CGFloat, width: CGFloat, duration: Double) -> Double {
        guard duration > 0, width > 0, distance.isFinite else { return max(0, origin) }
        let delta = Double(distance / width) * min(duration, 90)
        return min(max(0, origin + delta), duration)
    }
}

enum EpisodeSwipe {
    enum Axis { case none, horizontal, vertical }

    static func axis(dx: CGFloat, dy: CGFloat, threshold: CGFloat) -> Axis {
        if abs(dx) < threshold && abs(dy) < threshold { return .none }
        if abs(dy) > abs(dx) * 1.15 { return .vertical }
        if abs(dx) > abs(dy) * 1.15 { return .horizontal }
        return .none
    }

    static func target(index: Int, size: Int, dy: CGFloat, height: CGFloat, velocity: CGFloat) -> Int? {
        if abs(dy) < 24 { return nil }
        if abs(dy) < max(1, height) * 0.14 && abs(velocity) < 900 { return nil }
        return dy < 0 ? EpisodeOrder.next(index, size) : EpisodeOrder.previous(index, size)
    }
}

/// Reuse the series the browser already validated, so Play does not reload the page.
enum PlaybackHandoff {
    private static var pending: Series?
    static func offer(_ series: Series) { pending = series }
    static func take(_ url: String) -> Series? {
        defer { pending = nil }
        return pending?.url == url ? pending : nil
    }
}

enum SeriesParser {
    static func series(html: String, url: String) -> Series? {
        guard let canonical = SitePolicy.seriesURL(url) else { return nil }
        let title = heading(html) ?? (URL(string: canonical)?.lastPathComponent.replacingOccurrences(of: "-", with: " ") ?? "Series")
        var found: [Int: String] = [:]
        let pattern = "href=[\"']([^\"']*?/series/[^\"'/]+/episode-(\\d+)/?)[\"']"
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            for match in regex.matches(in: html, range: range) {
                guard match.numberOfRanges == 3,
                      let pathRange = Range(match.range(at: 1), in: html),
                      let numberRange = Range(match.range(at: 2), in: html),
                      let number = Int(html[numberRange]) else { continue }
                let absolute = absolutePath(String(html[pathRange]))
                guard SitePolicy.seriesURL(absolute) == canonical else { continue }
                if found[number] == nil { found[number] = absolute }
            }
        }
        let episodes = found.keys.sorted().map { Episode(number: $0, pageUrl: found[$0]!) }
        guard !episodes.isEmpty else { return nil }
        return Series(title: title, url: canonical, episodes: episodes,
                      posterUrl: Artwork.shared.poster(inHTML: html, base: canonical, title: title),
                      seasonLabel: season(title))
    }

    static func absolutePath(_ value: String) -> String {
        var path = value
        if path.hasPrefix("//") { path = "https:" + path }
        else if path.hasPrefix("/") { path = "https://en.hdrama.net" + path }
        else if !path.hasPrefix("http") { path = "https://en.hdrama.net/" + path }
        if let cut = path.firstIndex(where: { $0 == "?" || $0 == "#" }) { path = String(path[..<cut]) }
        while path.hasSuffix("/") { path.removeLast() }
        return path
    }

    private static func heading(_ html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "<h1[^>]*>(.*?)</h1>", options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        let text = html[range]
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return text.replacingOccurrences(of: "\\s*Episode\\s*\\d+.*$", with: "", options: [.regularExpression, .caseInsensitive])
    }

    static func season(_ title: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\b(?:Season\\s*|S)(\\d+)\\b", options: [.caseInsensitive]),
              let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..<title.endIndex, in: title)),
              let range = Range(match.range(at: 1), in: title) else { return "" }
        return "Season \(title[range])"
    }

    static func blocked(_ html: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: "<title[^>]*>(.*?)</title>", options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)),
              let range = Range(match.range(at: 1), in: html) else { return false }
        let title = html[range].lowercased()
        return title.contains("just a moment") || title.contains("attention required") || title.contains("access denied")
    }
}

enum UserAgent {
    static var current = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
}
