import UIKit
import CryptoKit

/// Cached series posters, kept separate from playback caches so they survive eviction.
final class Artwork {
    static let shared = Artwork()

    /// Posted when a poster finishes downloading so visible cards can refresh without a full redraw.
    static let changed = Notification.Name("hdrama.artwork.changed")

    private let defaults = UserDefaults.standard
    private let images = NSCache<NSString, UIImage>()
    private let session: URLSession

    /// Series whose poster download already failed this session, so a list refresh cannot spin up
    /// repeated requests for a dead CDN address.
    private var failed = Set<String>()

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
        images.countLimit = 120
    }

    private var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let path = base.appendingPathComponent("Posters", isDirectory: true)
        if !FileManager.default.fileExists(atPath: path.path) {
            try? FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        }
        return path
    }

    private func file(_ url: String) -> URL {
        let digest = SHA256.hash(data: Data(url.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest + ".jpg")
    }

    private func storedSource(_ seriesUrl: String) -> String? {
        defaults.string(forKey: "poster-source:" + seriesUrl)
    }

    func hasPoster(_ seriesUrl: String) -> Bool {
        FileManager.default.fileExists(atPath: file(seriesUrl).path) && storedSource(seriesUrl) != nil
    }

    func image(_ seriesUrl: String) -> UIImage? {
        guard hasPoster(seriesUrl) else { return nil }
        let source = file(seriesUrl)
        let key = seriesUrl as NSString
        if let cached = images.object(forKey: key) { return cached }
        guard let data = try? Data(contentsOf: source), let image = UIImage(data: data) else {
            // A corrupt cache entry is dropped so the next fetch can replace it.
            try? FileManager.default.removeItem(at: source)
            defaults.removeObject(forKey: "poster-source:" + seriesUrl)
            return nil
        }
        images.setObject(image, forKey: key)
        return image
    }

    func remember(_ series: Series) {
        if !series.posterUrl.isEmpty {
            // Only the artwork address is stored here; the title stays in the Library record.
            defaults.set(series.posterUrl, forKey: "poster-title:" + series.url)
        }
        defaults.set(series.seasonLabel.isEmpty
                     ? (defaults.string(forKey: "poster-season:" + series.url) ?? "")
                     : series.seasonLabel,
                     forKey: "poster-season:" + series.url)
    }

    func enrich(_ series: Series) -> Series {
        var copy = series
        if copy.posterUrl.isEmpty { copy.posterUrl = storedSource(series.url) ?? "" }
        if copy.posterUrl.isEmpty { copy.posterUrl = defaults.string(forKey: "poster-title:" + series.url) ?? "" }
        if copy.seasonLabel.isEmpty { copy.seasonLabel = defaults.string(forKey: "poster-season:" + series.url) ?? "" }
        return copy
    }

    /// og:image first, then the poster image whose alt text matches the series title.
    func poster(inHTML html: String, base: String, title: String) -> String {
        func normalized(_ value: String) -> String {
            value.lowercased().filter { $0.isLetter || $0.isNumber }
        }
        let wanted = normalized(title)
        if !wanted.isEmpty,
           let regex = try? NSRegularExpression(pattern: "<img[^>]+alt=[\"']([^\"']*)[\"'][^>]*>", options: [.caseInsensitive]) {
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            for match in regex.matches(in: html, range: range) {
                guard match.numberOfRanges > 1,
                      let full = Range(match.range(at: 0), in: html),
                      let alt = Range(match.range(at: 1), in: html) else { continue }
                guard normalized(String(html[alt])).contains(wanted) else { continue }
                let tag = String(html[full])
                if let source = attribute(tag, "src") ?? attribute(tag, "data-src"),
                   let absolute = absoluteURL(source, base: base) { return absolute }
            }
        }
        for pattern in ["<meta[^>]+property=[\"']og:image[\"'][^>]*>",
                        "<meta[^>]+name=[\"']twitter:image[\"'][^>]*>"] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)),
                  let range = Range(match.range(at: 0), in: html),
                  let content = attribute(String(html[range]), "content"),
                  let absolute = absoluteURL(content, base: base) else { continue }
            return absolute
        }
        return ""
    }

    private func attribute(_ tag: String, _ name: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: name + "=[\"']([^\"']+)[\"']", options: [.caseInsensitive]),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..<tag.endIndex, in: tag)),
              let range = Range(match.range(at: 1), in: tag) else { return nil }
        return String(tag[range])
    }

    /// Keeps the signed query string; only the fragment is discarded.
    private func absoluteURL(_ raw: String, base: String) -> String? {
        RequestPolicy.fetchablePoster(raw, base: base)?.absoluteString
    }

    func fetch(_ series: Series, completion: (() -> Void)? = nil) {
        let enriched = enrich(series)
        guard !failed.contains(series.url) else { completion?(); return }
        guard let url = RequestPolicy.fetchablePoster(enriched.posterUrl, base: series.url) else {
            completion?()
            return
        }
        let source = url.absoluteString
        if hasPoster(series.url), storedSource(series.url) == source {
            completion?()
            return
        }
        var request = URLRequest(url: url)
        request.setValue(series.url, forHTTPHeaderField: "Referer")
        request.setValue(UserAgent.current, forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request) { [weak self] data, _, _ in
            guard let self = self else { return }
            guard let data = data, data.count < 4 * 1024 * 1024, let image = UIImage(data: data) else {
                DispatchQueue.main.async {
                    self.failed.insert(series.url)
                    completion?()
                }
                return
            }
            // Posters carry no alpha; rendering them opaque first avoids a costly per-frame blend.
            let scaled = Artwork.scale(Artwork.flatten(image), limit: 260)
            if let jpeg = scaled.jpegData(compressionQuality: 0.85) {
                try? jpeg.write(to: self.file(series.url))
                self.defaults.set(source, forKey: "poster-source:" + series.url)
                self.defaults.set(source, forKey: "poster-title:" + series.url)
                self.images.setObject(scaled, forKey: series.url as NSString)
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Artwork.changed, object: nil)
                completion?()
            }
        }.resume()
    }

    private static func flatten(_ image: UIImage) -> UIImage {
        guard image.cgImage != nil else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            AppColors.surface.setFill()
            UIRectFill(CGRect(origin: .zero, size: image.size))
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private static func scale(_ image: UIImage, limit: CGFloat) -> UIImage {
        let longest = Swift.max(image.size.width, image.size.height)
        guard longest > limit, longest > 0 else { return image }
        let ratio = limit / longest
        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
