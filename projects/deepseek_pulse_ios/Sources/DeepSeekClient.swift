import Foundation

enum DeepSeekError: Equatable {
    case missingKey
    case unauthorized
    case rateLimited
    case http(Int)
    case offline(String)
    case invalidResponse(String)

    var message: String {
        switch self {
        case .missingKey:
            return "Add your DeepSeek API key in Settings to load the account balance."
        case .unauthorized:
            return "The API key was rejected (401/403). Check the key in Settings and try again."
        case .rateLimited:
            return "DeepSeek is rate limiting requests (429). Wait a moment, then refresh."
        case .http(let code):
            return "api.deepseek.com returned HTTP \(code)."
        case .offline(let detail):
            return "Network error: \(detail)"
        case .invalidResponse(let detail):
            return "Unexpected response: \(detail)"
        }
    }
}

final class DeepSeekClient {

    static let balanceURL = URL(string: "https://api.deepseek.com/user/balance")!

    private let session: URLSession

    init(session: URLSession = URLSession(configuration: DeepSeekClient.makeConfiguration())) {
        self.session = session
    }

    static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }

    static func request(apiKey: String) -> URLRequest {
        var request = URLRequest(url: balanceURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    static func error(forStatus status: Int) -> DeepSeekError? {
        switch status {
        case 200: return nil
        case 401, 403: return .unauthorized
        case 429: return .rateLimited
        default: return .http(status)
        }
    }

    func fetchBalance(apiKey: String, completion: @escaping (Result<BalanceSnapshot, DeepSeekError>) -> Void) {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.failure(.missingKey))
            return
        }

        session.dataTask(with: DeepSeekClient.request(apiKey: trimmed)) { data, response, error in
            let result: Result<BalanceSnapshot, DeepSeekError>
            if let error = error {
                result = .failure(.offline(error.localizedDescription))
            } else if let http = response as? HTTPURLResponse {
                if let failure = DeepSeekClient.error(forStatus: http.statusCode) {
                    result = .failure(failure)
                } else if let data = data, let snapshot = BalanceParser.snapshot(from: data, at: Date()) {
                    result = .success(snapshot)
                } else {
                    result = .failure(.invalidResponse("balance JSON could not be read"))
                }
            } else {
                result = .failure(.invalidResponse("no HTTP response"))
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }
}
