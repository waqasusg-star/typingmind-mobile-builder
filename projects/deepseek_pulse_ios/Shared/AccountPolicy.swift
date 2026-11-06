import Foundation

// DeepSeek Pulse — account generation, key-change and balance acceptance policy.
//
// Foundation only, compiled into BOTH targets (app + widget extension) so the CI harness executes it
// with real Swift. It contains no secret and no derived secret:
//
//   * the KEY ITSELF never appears here. The app compares the normalized previous and new key in
//     memory only, inside SettingsStore next to the Keychain.
//   * no fingerprint, hash or token is computed, stored or serialized, so a shared payload cannot
//     carry even a reversible hint of the key.
//   * a generation is only a monotonically increasing integer naming "which account".

// MARK: - Key change

/// The decision the app makes when the stored key changes.
enum KeyChange: Equatable {
    /// Same normalized key, or no key before and after: the cached balance still belongs to it.
    case unchanged
    /// The key was removed, or replaced with a different one: cached balance must be discarded.
    case changed

    var clearsCachedBalance: Bool { self == .changed }

    /// Compares normalized keys. Call with values read from the Keychain.
    static func compare(previous: String?, next: String?) -> KeyChange {
        normalise(previous) == normalise(next) ? .unchanged : .changed
    }

    /// Trims surrounding whitespace; an all-whitespace key means "no key".
    static func normalise(_ key: String?) -> String {
        (key ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Explicit write result

/// Outcome of a keychain write. Failure is its own case so the caller cannot mistake it for
/// "nothing changed", which is a successful no-op with the opposite meaning.
enum KeySaveResult: Equatable {
    /// The key is stored. `change` says whether the account actually changed.
    case saved(KeyChange)
    /// The keychain write failed. The previous key, cache and generation are untouched.
    case storeFailed

    var isStored: Bool {
        if case .saved = self { return true }
        return false
    }

    /// Only a stored key that actually changed clears the cached balance.
    var shouldClearCachedBalance: Bool {
        if case .saved(let change) = self { return change.clearsCachedBalance }
        return false
    }

    /// True only when this call really stored a new key for a different account.
    var didChangeAccount: Bool { shouldClearCachedBalance }
}

/// Outcome of a key removal.
enum KeyRemovalResult: Equatable {
    case removed(KeyChange)
    /// The keychain delete reported an error, so the key may still be present.
    case deleteFailed

    var isRemoved: Bool {
        if case .removed = self { return true }
        return false
    }

    var shouldClearCachedBalance: Bool {
        if case .removed(let change) = self { return change.clearsCachedBalance }
        return false
    }
}

/// Pure decisions derived from a result, so tests do not need a Keychain.
enum KeyStoreDecision {

    /// Should the app show a failure message?
    static func isFailure(_ result: KeySaveResult) -> Bool {
        !result.isStored
    }

    /// Should the cache and generation be invalidated after a save?
    static func invalidates(_ result: KeySaveResult) -> Bool {
        result.shouldClearCachedBalance
    }

    /// Should the app show a failure message for a removal?
    static func isFailure(_ result: KeyRemovalResult) -> Bool {
        !result.isRemoved
    }

    /// Should removal invalidate the cache?
    ///
    /// True for any successful removal, not only one that changed the loaded key: a stale cached
    /// balance can exist even when the keychain currently holds no key (for example the key was
    /// cleared outside the app), so the numbers must still go.
    static func invalidates(_ result: KeyRemovalResult) -> Bool {
        result.isRemoved
    }
}

// MARK: - Keychain mutation routing

/// How a keychain write must be performed.
///
/// The old adapter deleted the existing item first, so a failed add lost the previous key. This
/// policy updates the existing item in place, adds only when the item is absent, and never
/// schedules a delete on failure.
enum KeyStoreMutationRoute: Equatable {
    /// Update the existing item's value with SecItemUpdate.
    case updateExisting
    /// No item exists: create one with SecItemAdd.
    case addNew
    /// An unexpected status: report failure and leave the stored item untouched.
    case fail

    /// `status` is the OSStatus of the existence probe (SecItemUpdate result).
    /// - Parameter itemMissingStatus: the errSecItemNotFound raw value, injected by the adapter.
    static func route(probeStatus: Int32, itemMissingStatus: Int32) -> KeyStoreMutationRoute {
        if probeStatus == 0 { return .updateExisting }
        if probeStatus == itemMissingStatus { return .addNew }
        return .fail
    }

    /// A route must never delete an item as part of saving.
    var deletesExistingItem: Bool { false }

    /// Only a confirmed success may invalidate the account.
    var isSuccess: Bool { self == .updateExisting || self == .addNew }
}

// MARK: - Account generation

/// Tracks which account a piece of work belongs to.
struct AccountGeneration: Equatable {

    private(set) var value: Int

    static let initial = AccountGeneration(value: 0)

    init(value: Int) {
        self.value = max(0, value)
    }

    /// Bumps to a new generation. Called only after a confirmed key change or removal.
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
