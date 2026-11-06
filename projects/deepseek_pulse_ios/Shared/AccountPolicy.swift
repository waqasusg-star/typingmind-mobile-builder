import Foundation

// DeepSeek Pulse — account generation and balance acceptance policy.
//
// Foundation only, compiled into BOTH targets (app + widget extension) so the CI test harness can
// execute it with real Swift. It holds no secret: a generation is just an integer that increments
// whenever the signed-in account changes.
//
// Why this exists: an in-flight balance request carries the generation it was started under. If the
// user removes their key or switches account before the response arrives, accepting that response
// would write the OLD account's balance into the cache and onto the Home Screen. Accepting only a
// matching, still-current generation makes that impossible.

/// Tracks which account a piece of work belongs to.
struct AccountGeneration: Equatable {

    private(set) var value: Int

    static let initial = AccountGeneration(value: 0)

    init(value: Int) {
        self.value = max(0, value)
    }

    /// Bumps to a new generation. Called on key removal and on key change.
    mutating func invalidate() {
        value += 1
    }

    /// A ticket handed to an in-flight request.
    func ticket() -> AccountTicket {
        AccountTicket(generation: value)
    }

    /// True when the ticket still belongs to the current account.
    func accepts(_ ticket: AccountTicket) -> Bool {
        ticket.generation == value
    }
}

/// The generation captured when a balance request started.
struct AccountTicket: Equatable {
    let generation: Int
}

/// What to do with a finished balance request.
enum BalanceAcceptance: Equatable {
    /// The response belongs to the current account and may be cached.
    case accept
    /// The account changed or the key was removed after the request started.
    case discardStaleAccount
    /// No usable key existed when the request would have been sent.
    case discardNoKey

    var shouldCache: Bool { self == .accept }

    /// Short reason used in diagnostics and Widget Studio.
    var reason: String {
        switch self {
        case .accept: return "accepted"
        case .discardStaleAccount: return "discarded: the account changed"
        case .discardNoKey: return "discarded: no key"
        }
    }
}

enum AccountPolicy {

    /// Decides whether a finished request may write to the balance cache.
    static func acceptance(ticket: AccountTicket?,
                           current: AccountGeneration,
                           hasKey: Bool) -> BalanceAcceptance {
        guard hasKey else { return .discardNoKey }
        guard let ticket = ticket else { return .discardStaleAccount }
        return current.accepts(ticket) ? .accept : .discardStaleAccount
    }

    /// The cache must be cleared whenever the key is removed or replaced.
    static func clearsCache(previousKeyHash: Int?, newKeyHash: Int?) -> Bool {
        previousKeyHash != newKeyHash
    }

    /// Non-reversible fingerprint used only to detect a key change in memory. Never persisted and
    /// never written to the shared container.
    static func keyFingerprint(_ key: String) -> Int? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var hash = 5381
        for scalar in trimmed.unicodeScalars {
            hash = (hash &* 33) &+ Int(scalar.value)
        }
        return hash
    }
}
