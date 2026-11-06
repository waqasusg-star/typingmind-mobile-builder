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
