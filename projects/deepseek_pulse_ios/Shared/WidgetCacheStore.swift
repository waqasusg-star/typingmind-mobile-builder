import Foundation

// DeepSeek Pulse — shared widget cache codec and local-tier fallback.
//
// Foundation only, compiled into BOTH targets. No UIKit work and no network access.
// The app calls encode(...) and writes the bytes; the extension calls decode(...).
//
// Two storage tiers exist so the widget can still show its own fresh data when the App Group
// entitlement is missing from either bundle:
//   tier 1  the App Group container  (works only when BOTH bundles carry the group entitlement)
//   tier 2  the extension's own container  (always writable by the extension)
// WidgetSnapshotStore resolves the order and a tier is an explicit parameter of every call, so the
// module stays Foundation-only and is exercised by the real Swift test harness.

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
        return envelope(for: payload, now: now)
    }

    /// Builds an envelope from a payload without touching the file system. Used by the app.
    static func envelope(for payload: WidgetSnapshotPayload, now: Date = Date()) -> WidgetSnapshotEnvelope {
        let reference = payload.balanceFetchedAt ?? payload.writtenAt
        let age = max(0, now.timeIntervalSince(reference))
        let state: WidgetDataState = age > WidgetShared.staleAfter ? .stale : .fresh
        return WidgetSnapshotEnvelope(payload: payload, state: state, age: age)
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

/// A place the snapshot can be stored.
///
/// `.appGroup` needs the group entitlement on BOTH bundles. `.extensionLocal` is the extension's
/// own Application Support directory and is always available to the extension, which is why the
/// widget can still tick on its own data when sharing is impossible.
enum WidgetCacheTier: String, Equatable {
    case appGroup
    case extensionLocal
}

/// File-system access to both snapshot tiers.
///
/// A nil containerURL is the normal, expected result when the App Group entitlement is missing
/// from one or both bundles; callers fall back to `.extensionLocal` instead of showing a setup
/// banner forever.
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

    /// The extension's own directory. Falls back to NSTemporaryDirectory only if the system refuses
    /// the Application Support path, which keeps the writer total instead of throwing.
    func extensionLocalDirectory() -> URL {
        let manager = FileManager.default
        if let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let directory = support.appendingPathComponent("WidgetSnapshot", isDirectory: true)
            if (try? manager.createDirectory(at: directory, withIntermediateDirectories: true)) != nil {
                return directory
            }
            return support
        }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    func fileURL(for tier: WidgetCacheTier) -> URL? {
        switch tier {
        case .appGroup:
            return fileURL
        case .extensionLocal:
            return extensionLocalDirectory().appendingPathComponent(WidgetShared.localCacheFileName)
        }
    }

    func isAvailable(_ tier: WidgetCacheTier) -> Bool {
        fileURL(for: tier) != nil
    }
}

/// Reads and writes the snapshot, preferring the App Group and falling back to the extension's own
/// file. Every method is total: nothing here throws into a caller and nothing invents data.
enum WidgetSnapshotStore {

    /// Result of a read, with the tier it came from so the UI can say where the data lives.
    struct Loaded: Equatable {
        var envelope: WidgetSnapshotEnvelope
        var tier: WidgetCacheTier?
    }

    static let tiers: [WidgetCacheTier] = [.appGroup, .extensionLocal]

    /// Reads the first tier that holds a decodable payload.
    ///
    /// An incompatible or corrupt App Group file does not stop the search: a good local copy is
    /// still worth showing. When no tier decodes, the most informative failure is returned
    /// (groupUnavailable only when neither tier is usable at all).
    static func load(location: WidgetCacheLocation = .shared,
                     now: Date = Date(),
                     order: [WidgetCacheTier] = WidgetSnapshotStore.tiers) -> Loaded {
        var firstFailure: WidgetSnapshotEnvelope?
        var sawUsableTier = false

        for tier in order {
            guard let url = location.fileURL(for: tier) else { continue }
            sawUsableTier = true
            guard let data = try? Data(contentsOf: url) else { continue }
            let envelope = WidgetCacheCodec.decode(data, now: now)
            if envelope.state.isUsable {
                return Loaded(envelope: envelope, tier: tier)
            }
            if firstFailure == nil {
                firstFailure = envelope
            }
        }
        if let firstFailure = firstFailure {
            return Loaded(envelope: firstFailure, tier: nil)
        }
        return Loaded(envelope: .failed(sawUsableTier ? .empty : .groupUnavailable), tier: nil)
    }

    /// Writes the encoded bytes to one tier. Returns the URL on success.
    @discardableResult
    static func write(payload: WidgetSnapshotPayload,
                      to tier: WidgetCacheTier,
                      location: WidgetCacheLocation = .shared) -> URL? {
        guard let url = location.fileURL(for: tier) else { return nil }
        guard let data = try? WidgetCacheCodec.encode(payload) else { return nil }
        guard !WidgetCacheCodec.containsSecretMaterial(data) else { return nil }
        do {
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            return nil
        }
    }
}
