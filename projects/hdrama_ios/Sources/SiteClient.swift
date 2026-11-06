import Foundation
import WebKit

/// Cookie-aware HTML fetch used when the player opens a series the browser did not hand over.
enum SiteClient {
    enum ClientError: LocalizedError {
        case access
        case blocked
        case http(Int)
        case empty

        var errorDescription: String? {
            switch self {
            case .access: return "The website denied app access. Open the series in the browser, complete any check, then try again."
            case .blocked: return "The website requires an access check. Open it in the browser first."
            case .http(let code): return "Site request failed (HTTP \(code))."
            case .empty: return "The page returned no content."
            }
        }
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 25
        configuration.httpCookieStorage = .shared
        return URLSession(configuration: configuration)
    }()

    static func fetch(_ raw: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard SitePolicy.siteURL(raw) != nil, let url = URL(string: raw) else {
            completion(.failure(ClientError.access))
            return
        }
        cookieHeader(for: url) { header in
            var request = URLRequest(url: url)
            request.setValue(UserAgent.current, forHTTPHeaderField: "User-Agent")
            request.setValue("text/html", forHTTPHeaderField: "Accept")
            if let header = header { request.setValue(header, forHTTPHeaderField: "Cookie") }
            session.dataTask(with: request) { data, response, error in
                let result: Result<String, Error>
                if error != nil {
                    result = .failure(error!)
                } else if let http = response as? HTTPURLResponse,
                          let data = data,
                          let html = String(data: data, encoding: .utf8),
                          !html.isEmpty {
                    if http.statusCode == 401 || http.statusCode == 403 {
                        result = .failure(ClientError.access)
                    } else if SeriesParser.blocked(html) {
                        result = .failure(ClientError.blocked)
                    } else if http.statusCode >= 400 {
                        result = .failure(ClientError.http(http.statusCode))
                    } else {
                        result = .success(html)
                    }
                } else {
                    result = .failure(ClientError.empty)
                }
                DispatchQueue.main.async { completion(result) }
            }.resume()
        }
    }

    /// Reuses the cookies the in-app browser already holds, so a completed access check still applies.
    private static func cookieHeader(for url: URL, completion: @escaping (String?) -> Void) {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            guard let host = url.host else { completion(nil); return }
            let matching = cookies.filter { RequestPolicy.matches($0, url: url) }
            guard !matching.isEmpty else { completion(nil); return }
            completion(matching.map { $0.name + "=" + $0.value }.joined(separator: "; "))
        }
    }
}
