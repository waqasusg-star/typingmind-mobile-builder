import Foundation

/// Thin URLSession wrapper. Request building, the endpoint allow-list and status mapping live in
/// RequestPolicy so the same rules can be tested without UIKit or a network call.
///
/// The client keeps the task it started so the caller can cancel it when the account changes; a
/// cancelled request never delivers a result, so a previous account cannot repopulate the cache.
final class DeepSeekClient {

    private let session: URLSession
    private var currentTask: URLSessionDataTask?

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

    var isBusy: Bool { currentTask != nil }

    /// Cancels any request in flight. The completion of a cancelled request is not called.
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    func fetchBalance(apiKey: String, completion: @escaping (Result<BalanceSnapshot, BalanceFetchError>) -> Void) {
        guard let request = RequestPolicy.requestIfValid(apiKey: apiKey) else {
            completion(.failure(.missingKey))
            return
        }

        cancel()

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            // A cancelled task means the account changed; drop the result instead of reporting it.
            if let error = error as NSError?, error.code == NSURLErrorCancelled {
                DispatchQueue.main.async { self?.currentTask = nil }
                return
            }

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
            DispatchQueue.main.async {
                self?.currentTask = nil
                completion(result)
            }
        }
        currentTask = task
        task.resume()
    }
}
