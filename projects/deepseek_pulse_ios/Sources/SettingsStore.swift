import Foundation

extension Notification.Name {
    static let deepSeekSettingsChanged = Notification.Name("DeepSeekPulseSettingsChanged")
}

final class SettingsStore {

    static let shared = SettingsStore()
    static let currentSchema = 2

    private enum Key {
        static let schema = "deepseekpulse.schema"
        static let schedule = "deepseekpulse.schedule.v2"
        static let models = "deepseekpulse.models.v2"
        static let ratesCustom = "deepseekpulse.ratesCustom.v2"
        static let scheduleCustom = "deepseekpulse.scheduleCustom.v2"
        static let snapshot = "deepseekpulse.snapshot.v1"
        static let migrationNotice = "deepseekpulse.migrationNotice.v2"
        static let legacyWindow = "deepseekpulse.window.v1"
        static let legacyModels = "deepseekpulse.models.v1"
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
            // 1.0.0 stored a single 16:30–00:30 UTC window and deepseek-chat/deepseek-reasoner
            // prices with a 75% reasoner discount. DeepSeek no longer publishes either, so the
            // obsolete settings are dropped instead of being shown as current.
            self.schedule = RateSeeds.schedule
            self.models = RateSeeds.models
            self.ratesAreCustom = false
            self.scheduleIsCustom = false

            defaults.removeObject(forKey: Key.legacyWindow)
            defaults.removeObject(forKey: Key.legacyModels)
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
            self.models = (storedModels?.isEmpty == false) ? (storedModels ?? RateSeeds.models) : RateSeeds.models
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

    /// Restores the verified schedule but keeps explicit PRC holiday overrides the user typed in.
    func resetScheduleToOfficial() {
        var official = RateSeeds.schedule
        official.holidays = schedule.holidays
        saveSchedule(official, isCustom: false)
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
