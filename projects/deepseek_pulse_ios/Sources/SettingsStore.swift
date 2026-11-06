import Foundation

extension Notification.Name {
    static let deepSeekSettingsChanged = Notification.Name("DeepSeekPulseSettingsChanged")
}

final class SettingsStore {

    static let shared = SettingsStore()
    static let currentSchema = 3

    private enum Key {
        static let schema = "deepseekpulse.schema"
        static let schedule = "deepseekpulse.schedule.v3"
        static let models = "deepseekpulse.models.v3"
        static let ratesCustom = "deepseekpulse.ratesCustom.v3"
        static let scheduleCustom = "deepseekpulse.scheduleCustom.v3"
        static let snapshot = "deepseekpulse.snapshot.v1"
        static let migrationNotice = "deepseekpulse.migrationNotice.v3"
        static let legacyWindow = "deepseekpulse.window.v1"
        static let legacyModels = "deepseekpulse.models.v1"
        static let legacyScheduleV2 = "deepseekpulse.schedule.v2"
        static let legacyModelsV2 = "deepseekpulse.models.v2"
    }

    private let defaults: UserDefaults

    private(set) var schedule: PricingSchedule
    private(set) var models: [ModelRate]
    private(set) var ratesAreCustom: Bool
    private(set) var scheduleIsCustom: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedSchema = defaults.integer(forKey: Key.schema)
        let storedSchedule = SettingsStore.read(PricingSchedule.self, key: Key.schedule, defaults: defaults)
        let storedModels = SettingsStore.read([ModelRate].self, key: Key.models, defaults: defaults)

        if storedSchema < SettingsStore.currentSchema {
            // 1.0.0 stored a single 16:30–00:30 UTC window and retired deepseek-chat / reasoner
            // prices. Those values are dropped instead of being shown as current.
            self.schedule = RateSeeds.schedule
            self.models = RateSeeds.models
            self.ratesAreCustom = false
            self.scheduleIsCustom = false

            defaults.removeObject(forKey: Key.legacyWindow)
            defaults.removeObject(forKey: Key.legacyModels)
            defaults.removeObject(forKey: Key.legacyScheduleV2)
            defaults.removeObject(forKey: Key.legacyModelsV2)
            SettingsStore.write(self.schedule, key: Key.schedule, defaults: defaults)
            SettingsStore.write(self.models, key: Key.models, defaults: defaults)
            defaults.set(false, forKey: Key.ratesCustom)
            defaults.set(false, forKey: Key.scheduleCustom)
            defaults.set(SettingsStore.currentSchema, forKey: Key.schema)
            if storedSchema > 0 {
                defaults.set(true, forKey: Key.migrationNotice)
            }
        } else {
            self.schedule = storedSchedule ?? RateSeeds.schedule
            let stored = storedModels ?? []
            self.models = stored.isEmpty ? RateSeeds.models : stored
            self.ratesAreCustom = defaults.bool(forKey: Key.ratesCustom)
            self.scheduleIsCustom = defaults.bool(forKey: Key.scheduleCustom)
        }
    }

    // MARK: API key

    var apiKey: String {
        KeyStore.load() ?? ""
    }

    var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Increments whenever the account changes, so late responses for a previous key are discarded.
    private(set) var accountGeneration = AccountGeneration.initial

    /// Fingerprint of the key the cached balance belongs to. In memory only, never persisted.
    private var cachedKeyFingerprint: Int?

    /// A ticket for a balance request that is about to start.
    func currentAccountTicket() -> AccountTicket {
        accountGeneration.ticket()
    }

    /// Stores the key and invalidates the previous account when it actually changed.
    /// Returns true when the cache was cleared.
    @discardableResult
    func replaceAPIKey(_ newKey: String) -> Bool {
        let previousFingerprint = AccountPolicy.keyFingerprint(apiKey)
        let newFingerprint = AccountPolicy.keyFingerprint(newKey)
        let trimmed = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeyStore.delete()
        } else if !KeyStore.save(trimmed) {
            return false
        }
        return finishKeyTransition(previousFingerprint: previousFingerprint, newFingerprint: newFingerprint)
    }

    /// Removes the key and invalidates the account.
    @discardableResult
    func removeAPIKey() -> Bool {
        let previousFingerprint = AccountPolicy.keyFingerprint(apiKey)
        KeyStore.delete()
        return finishKeyTransition(previousFingerprint: previousFingerprint, newFingerprint: nil)
    }

    private func finishKeyTransition(previousFingerprint: Int?, newFingerprint: Int?) -> Bool {
        guard AccountPolicy.clearsCache(previousKeyHash: previousFingerprint, newKeyHash: newFingerprint) else {
            return false
        }
        accountGeneration.invalidate()
        cachedKeyFingerprint = newFingerprint
        cachedSnapshot = nil
        return true
    }

    /// True when a finished request may still write to the cache.
    func acceptsBalance(ticket: AccountTicket?) -> BalanceAcceptance {
        AccountPolicy.acceptance(ticket: ticket, current: accountGeneration, hasKey: hasAPIKey)
    }

    // MARK: Persistence

    func saveSchedule(_ value: PricingSchedule, isCustom: Bool) {
        schedule = value
        scheduleIsCustom = isCustom
        SettingsStore.write(value, key: Key.schedule, defaults: defaults)
        defaults.set(isCustom, forKey: Key.scheduleCustom)
    }

    func saveModels(_ value: [ModelRate], isCustom: Bool) {
        guard !value.isEmpty else { return }
        models = value
        ratesAreCustom = isCustom
        SettingsStore.write(value, key: Key.models, defaults: defaults)
        defaults.set(isCustom, forKey: Key.ratesCustom)
    }

    /// Restores the verified schedule together with the verified 2026–2027 holiday list.
    func resetScheduleToOfficial() {
        saveSchedule(RateSeeds.schedule, isCustom: false)
    }

    func resetModelsToOfficial() {
        saveModels(RateSeeds.models, isCustom: false)
    }

    var migrationNoticePending: Bool {
        get { defaults.bool(forKey: Key.migrationNotice) }
        set { defaults.set(newValue, forKey: Key.migrationNotice) }
    }

    var cachedSnapshot: BalanceSnapshot? {
        get { SettingsStore.read(BalanceSnapshot.self, key: Key.snapshot, defaults: defaults) }
        set {
            if let newValue = newValue {
                SettingsStore.write(newValue, key: Key.snapshot, defaults: defaults)
            } else {
                defaults.removeObject(forKey: Key.snapshot)
            }
        }
    }

    // MARK: Codable helpers

    private static func read<T: Decodable>(_ type: T.Type, key: String, defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func write<T: Encodable>(_ value: T, key: String, defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
