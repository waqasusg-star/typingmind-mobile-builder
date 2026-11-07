import Foundation

// DeepSeek Pulse — file-level plumbing for the widget-to-app refresh handoff.
//
// Foundation only, compiled into BOTH targets. The rules live in Shared/WidgetRefreshCore.swift;
// this file only reads and writes the small request/answer files, so the widget and the app share one
// implementation instead of two guesses.
//
// Files are tiny JSON documents in the App Group container:
//   widget-refresh-request.json   written by the widget, consumed by the app
//   widget-refresh-answer.json    written by the app, read by the widget
// Neither file can contain an API key: the schema has no field for one.

struct WidgetRefreshAnswer: Codable, Equatable {
    static let schema = 1
    var schemaVersion: Int
    var answeredAt: Date
    /// The number of requests the app has answered, which lets the widget notice a new answer even
    /// when two answers land in the same second.
    var answeredCount: Int

    init(answeredAt: Date, answeredCount: Int) {
        self.schemaVersion = WidgetRefreshAnswer.schema
        self.answeredAt = answeredAt
        self.answeredCount = max(0, answeredCount)
    }
}

/// What the widget last knew about the handshake. Read by the views to decide wording and cooldown.
struct WidgetRefreshLedger: Equatable {
    var requestedAt: Date?
    var answeredAt: Date?
    var answeredCount: Int

    static let empty = WidgetRefreshLedger(requestedAt: nil, answeredAt: nil, answeredCount: 0)

    /// Reads the App Group files. Any missing or malformed file is simply absent, never an error.
    static func read(location: WidgetCacheLocation = .shared) -> WidgetRefreshLedger {
        var ledger = WidgetRefreshLedger.empty
        if let data = WidgetRefreshStore.read(.request, location: location),
           let request = WidgetRefreshStore.decodeRequest(data) {
            ledger.requestedAt = request.requestedAt
        }
        if let data = WidgetRefreshStore.read(.answer, location: location),
           let answer = WidgetRefreshStore.decodeAnswer(data) {
            ledger.answeredAt = answer.answeredAt
            ledger.answeredCount = answer.answeredCount
        }
        return ledger
    }
}

/// Which handshake file a call refers to.
enum WidgetRefreshFile: String {
    case request = "widget-refresh-request.json"
    case answer = "widget-refresh-answer.json"
}

enum WidgetRefreshStore {

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    static func url(for file: WidgetRefreshFile, location: WidgetCacheLocation) -> URL? {
        guard let container = location.containerURL else { return nil }
        return container.appendingPathComponent(file.rawValue)
    }

    static func read(_ file: WidgetRefreshFile, location: WidgetCacheLocation = .shared) -> Data? {
        guard let url = url(for: file, location: location) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func decodeRequest(_ data: Data) -> WidgetRefreshRequest? {
        guard let request = try? decoder().decode(WidgetRefreshRequest.self, from: data) else { return nil }
        guard request.schemaVersion == WidgetRefreshRequest.schema else { return nil }
        return request
    }

    static func decodeAnswer(_ data: Data) -> WidgetRefreshAnswer? {
        guard let answer = try? decoder().decode(WidgetRefreshAnswer.self, from: data) else { return nil }
        guard answer.schemaVersion == WidgetRefreshAnswer.schema else { return nil }
        return answer
    }

    /// Writes the widget's request. Returns true only when the bytes reached the container.
    @discardableResult
    static func writeRequest(_ request: WidgetRefreshRequest,
                             location: WidgetCacheLocation = .shared) -> Bool {
        guard let url = url(for: .request, location: location) else { return false }
        guard let data = try? encoder().encode(request) else { return false }
        return (try? data.write(to: url, options: [.atomic])) != nil
    }

    /// Writes the app's answer.
    @discardableResult
    static func writeAnswer(_ answer: WidgetRefreshAnswer,
                            location: WidgetCacheLocation = .shared) -> Bool {
        guard let url = url(for: .answer, location: location) else { return false }
        guard let data = try? encoder().encode(answer) else { return false }
        return (try? data.write(to: url, options: [.atomic])) != nil
    }

    /// Removes the request file once the app has answered it, so a stale tap cannot fire twice.
    static func clearRequest(location: WidgetCacheLocation = .shared) {
        guard let url = url(for: .request, location: location) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
