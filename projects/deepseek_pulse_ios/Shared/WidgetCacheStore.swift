import Foundation

// DeepSeek Pulse — shared widget cache codec.
//
// Foundation only, compiled into BOTH targets. No UIKit work and no network access.
// The extension calls decode(...); the app calls encode(...) and writes the bytes.

/// Serializes and deserializes the shared widget payload.
///
/// Rules enforced here, and checked by Tests/WidgetKitTests.swift:
///   * a payload with an unknown schemaVersion is reported as .incompatible, never half-read
///   * malformed JSON is reported as .corrupt, never repaired into fake data
///   * data older than WidgetShared.staleAfter is reported as .stale
///   * no field can carry an API key, bearer token or request header
enum WidgetCacheCodec {

    /// Anchored patterns for material that must never be written to the shared container.
    ///
    /// The API key usually starts with "sk-". Field NAMES such as hasAPIKey are intentionally not
    /// matched: the check is about values, and a false positive would block every legitimate write.
    static let forbiddenValuePatterns = [
        "sk-",
        "bearer ",
        "authorization",
        "api_key",
        "\"apikey\":\"",
        "access_token",
        "refresh_token",
        "client_secret",
        "password"
    ]

    static func encode(_ payload: WidgetSnapshotPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }

    /// Decodes raw bytes at a known time. Never throws: every failure maps to a visible state.
    static func decode(_ data: Data, now: Date = Date()) -> WidgetSnapshotEnvelope {
        guard !data.isEmpty else { return .failed(.empty) }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        // Read the version first so a newer payload is named precisely instead of as corruption.
        struct VersionProbe: Decodable { var schemaVersion: Int }
        guard let probe = try? decoder.decode(VersionProbe.self, from: data) else {
            return .failed(.corrupt)
        }
        guard probe.schemaVersion == WidgetShared.schemaVersion else {
            return .failed(.incompatible)
        }
        guard let payload = try? decoder.decode(WidgetSnapshotPayload.self, from: data) else {
            return .failed(.corrupt)
        }
        guard payload.schemaVersion == WidgetShared.schemaVersion else {
            return .failed(.incompatible)
        }

        let reference = payload.balanceFetchedAt ?? payload.writtenAt
        let age = max(0, now.timeIntervalSince(reference))
        let state: WidgetDataState = age > WidgetShared.staleAfter ? .stale : .fresh
        return WidgetSnapshotEnvelope(payload: payload, state: state, age: age)
    }

    /// Builds an envelope from a payload without touching the file system. Used by the app.
    static func envelope(for payload: WidgetSnapshotPayload, now: Date = Date()) -> WidgetSnapshotEnvelope {
        let reference = payload.balanceFetchedAt ?? payload.writtenAt
        let age = max(0, now.timeIntervalSince(reference))
        return WidgetSnapshotEnvelope(payload: payload,
                                      state: age > WidgetShared.staleAfter ? .stale : .fresh,
                                      age: age)
    }

    /// Sanitises a balance into display-only values.
    static func sanitizedBalance(currency: String,
                                 total: String,
                                 granted: String,
                                 toppedUp: String,
                                 isAvailable: Bool) -> WidgetBalance {
        WidgetBalance(currency: safe(currency, limit: 8),
                      totalText: safe(total),
                      grantedText: safe(granted),
                      toppedUpText: safe(toppedUp),
                      isAvailable: isAvailable)
    }

    /// Removes control characters and clamps length, so a hostile API response cannot inject text
    /// into the widget or bloat the payload.
    static func safe(_ text: String, limit: Int = 40) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = trimmed.unicodeScalars.filter { scalar in
            scalar.properties.generalCategory != .control
        }
        let cleaned = String(String.UnicodeScalarView(filtered))
        if cleaned.count > limit {
            return String(cleaned.prefix(limit))
        }
        return cleaned
    }

    /// True when the encoded bytes contain secret VALUES. Used as a final guard before writing.
    static func containsSecretMaterial(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else { return true }
        let lowered = text.lowercased()
        return forbiddenValuePatterns.contains { lowered.contains($0) }
    }
}

/// File-system access to the App Group container.
///
/// containerURL returning nil is the normal, expected result when the App Group entitlement is
/// missing from one or both bundles. Callers must degrade to WidgetDataState.groupUnavailable.
struct WidgetCacheLocation {
    let appGroupIdentifier: String

    static let shared = WidgetCacheLocation(appGroupIdentifier: WidgetShared.appGroupIdentifier)

    var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    var fileURL: URL? {
        containerURL?.appendingPathComponent(WidgetShared.cacheFileName)
    }

    var isAvailable: Bool { containerURL != nil }
}
