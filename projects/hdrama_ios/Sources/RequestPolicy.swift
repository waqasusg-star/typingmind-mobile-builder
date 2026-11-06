import Foundation

/// Pure URL/cookie rules, tested independently of UIKit and website availability.
enum RequestPolicy {
    static func posterURL(_ raw: String, base: String) -> URL? {
        guard let url = URL(string: raw, relativeTo: URL(string: base))?.absoluteURL,
              url.scheme?.lowercased() == "https", url.user == nil, url.password == nil else { return nil }
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        parts?.fragment = nil
        return parts?.url
    }
    static func matches(_ cookie: HTTPCookie, url: URL, now: Date = Date()) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let domain = cookie.domain.lowercased()
        let scope = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
        guard host == scope || (domain.hasPrefix(".") && host.hasSuffix("." + scope)) else { return false }
        if cookie.isSecure && url.scheme?.lowercased() != "https" { return false }
        if let expiry = cookie.expiresDate, expiry <= now { return false }
        let path = url.path.isEmpty ? "/" : url.path
        return path == cookie.path || (path.hasPrefix(cookie.path) && (cookie.path.hasSuffix("/") || path.dropFirst(cookie.path.count).first == "/"))
    }
}

/// Offline paths survive app-container UUID changes, without escaping the current sandbox.
enum DownloadPaths {
    static func stored(_ url: URL, home: URL) -> String {
        let prefix = home.standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        return path.hasPrefix(prefix) ? "relative:" + String(path.dropFirst(prefix.count)) : path
    }
    static func resolve(_ raw: String, home: URL) -> URL? {
        let prefix = home.standardizedFileURL.path + "/"
        var relative: String
        if raw.hasPrefix("relative:") { relative = String(raw.dropFirst(9)) }
        else if raw.hasPrefix(prefix) { relative = String(raw.dropFirst(prefix.count)) }
        else if let marker = raw.range(of: "/Containers/Data/Application/", options: .backwards) {
            let tail = raw[marker.upperBound...].split(separator: "/", maxSplits: 1)
            guard tail.count == 2 else { return nil }
            relative = String(tail[1])
        } else { return nil }
        guard relative.hasPrefix("Library/") || relative.hasPrefix("Documents/") else { return nil }
        let url = home.appendingPathComponent(relative).standardizedFileURL
        return url.path.hasPrefix(prefix) ? url : nil
    }
}


/// One live preparation attempt; late callbacks cannot revive a paused or deleted download.
struct DownloadResolutionGate {
    struct Attempt: Equatable {
        let id: String
        let generation: UInt64
    }
    private(set) var active: Attempt?
    private var generation: UInt64 = 0

    mutating func begin(_ id: String) -> Attempt {
        generation &+= 1
        let attempt = Attempt(id: id, generation: generation)
        active = attempt
        return attempt
    }

    func accepts(_ attempt: Attempt, itemID: String?, state: String?) -> Bool {
        active == attempt && itemID == attempt.id && state == "queued"
    }

    @discardableResult mutating func invalidate(_ id: String) -> Bool {
        guard active?.id == id else { return false }
        active = nil
        return true
    }

    @discardableResult mutating func finish(_ attempt: Attempt) -> Bool {
        guard active == attempt else { return false }
        active = nil
        return true
    }
}

/// Throttles playback-progress storage.
///
/// `PlayerViewController` checkpoints every 5 seconds, so a 3-second window never coalesced anything.
/// The window is 15 seconds: 60 seconds of playback now writes 5 times instead of 13, while the newest
/// position is always kept in memory and is written immediately by the final/pause/dismiss/background
/// flushes.
enum ProgressWritePolicy {
    static let minimumInterval: TimeInterval = 15

    static func shouldFlush(last: Date?, now: Date, force: Bool) -> Bool {
        if force { return true }
        guard let last = last else { return true }
        return now.timeIntervalSince(last) >= minimumInterval
    }
}
