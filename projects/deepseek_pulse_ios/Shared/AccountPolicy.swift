import Foundation

// DeepSeek Pulse — account generation and balance acceptance policy.
//
// Foundation only, compiled into BOTH targets (app + widget extension) so the CI harness executes
// it with real Swift. It contains no secret and no derived secret:
//
//   * the KEY ITSELF never appears here. The app compares the normalized previous and new key
//     in memory only (inside SettingsStore, next to the Keychain), and passes a plain Bool.
//   * no fingerprint, hash or token is computed, stored or serialized, so a shared payload cannot
//     carry even a reversible hint of the key.
//   * a generation is only a monotonically increasing integer naming "which account".

/// The decision the app makes when the stored key changes.
enum KeyChange: Equatable {
    /// Same normalized key, or no key before and after: the cached balance still belongs to it.
    case unchanged
    /// The key was removed, or replaced with a different one: cached balance must be discarded.
    case changed

    var clearsCachedBalance: Bool { self == .changed }

    /// Compares normalized keys. Call from the app only, with values read from the Keychain.
    static func compare(previous: String?, next: String?) -> KeyChange {
        let normalisedPrevious = normalise(previous)
        let normalisedNext = normalise(next)
        return normalisedPrevious == normalisedNext ? .unchanged : .changed
    }

    /// Trims surrounding whitespace; an all-whitespace key means "no key".
    static func normalise(_ key: String?) -> String {
        (key ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

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
    /// No usable key existed when the decision was made.
    case discardNoKey

    var shouldCache: Bool { self == .accept }

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
}
