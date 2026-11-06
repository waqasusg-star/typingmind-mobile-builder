import Foundation

/// Thin URLSession wrapper. Request building, the endpoint allow-list and status mapping live in
/// RequestPolicy so the same rules can be tested without UIKit or a network call.
final class DeepSeekClient {

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

    func fetchBalance(apiKey: String, completion: @escaping (Result<BalanceSnapshot, BalanceFetchError>) -> Void) {
        guard let request = RequestPolicy.requestIfValid(apiKey: apiKey) else {
            completion(.failure(.missingKey))
            return
        }

        session.dataTask(with: request) { data, response, error in
            let result: Result<BalanceSnapshot, BalanceFetchError>
            if let error = error {
                result = .failure(.offline(error.localizedDescription))
            } else if let http = response as? HTTPURLResponse {
                let statusFailure = RequestPolicy.error(forStatus: http.statusCode)
                if let failure = statusFailure {
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
