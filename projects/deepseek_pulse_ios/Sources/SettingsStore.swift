import Foundation
import WidgetKit

extension Notification.Name {
    static let deepSeekSettingsChanged = Notification.Name("DeepSeekPulseSettingsChanged")
}

final class SettingsStore {

    static let shared = SettingsStore()
    static let currentSchema = 4

    private enum Key {
        static let schema = "deepseekpulse.schema"
        static let schedule = "deepseekpulse.schedule.v4"
        static let models = "deepseekpulse.models.v4"
        static let ratesCustom = "deepseekpulse.ratesCustom.v4"
        static let scheduleCustom = "deepseekpulse.scheduleCustom.v4"
        static let snapshot = "deepseekpulse.snapshot.v1"
        static let appearance = "deepseekpulse.appearance.v1"
        static let migrationNotice = "deepseekpulse.migrationNotice.v3"
        static let legacyWindow = "deepseekpulse.window.v1"
        static let legacyModels = "deepseekpulse.models.v1"
        static let legacyScheduleV2 = "deepseekpulse.schedule.v2"
        static let legacyModelsV2 = "deepseekpulse.models.v2"
        static let legacyScheduleV3 = "deepseekpulse.schedule.v3"
        static let legacyModelsV3 = "deepseekpulse.models.v3"
        static let legacyRatesCustomV3 = "deepseekpulse.ratesCustom.v3"
        static let legacyScheduleCustomV3 = "deepseekpulse.scheduleCustom.v3"
    }

    private let defaults: UserDefaults

    private(set) var schedule: PricingSchedule
    private(set) var models: [ModelRate]
    private(set) var ratesAreCustom: Bool
    private(set) var scheduleIsCustom: Bool
    /// Theme, widget designs and display switches. Read by the app and published to the widget.
    private(set) var widgetAppearance: WidgetAppearance

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedSchema = defaults.integer(forKey: Key.schema)
        let storedSchedule = SettingsStore.read(PricingSchedule.self, key: Key.schedule, defaults: defaults)
            ?? SettingsStore.read(PricingSchedule.self, key: Key.legacyScheduleV3, defaults: defaults)
        let storedModels = SettingsStore.read([ModelRate].self, key: Key.models, defaults: defaults)
            ?? SettingsStore.read([ModelRate].self, key: Key.legacyModelsV3, defaults: defaults)

        // The appearance is independent of the pricing schema, so a chosen theme survives later
        // pricing migrations.
        self.widgetAppearance = SettingsStore.read(WidgetAppearance.self,
                                                   key: Key.appearance,
                                                   defaults: defaults)?.normalised()
            ?? WidgetAppearance.defaultAppearance

        if storedSchema < SettingsStore.currentSchema {
            // Earlier builds stored a single 16:30-00:30 UTC window and retired model prices. Those
            // values are replaced with the verified ones instead of being shown as current.
            self.schedule = RateSeeds.schedule
            self.models = RateSeeds.models
            self.ratesAreCustom = false
            self.scheduleIsCustom = false

            defaults.removeObject(forKey: Key.legacyWindow)
            defaults.removeObject(forKey: Key.legacyModels)
            defaults.removeObject(forKey: Key.legacyScheduleV2)
            defaults.removeObject(forKey: Key.legacyModelsV2)
            defaults.removeObject(forKey: Key.legacyScheduleV3)
            defaults.removeObject(forKey: Key.legacyModelsV3)
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
                || defaults.bool(forKey: Key.legacyRatesCustomV3)
            self.scheduleIsCustom = defaults.bool(forKey: Key.scheduleCustom)
                || defaults.bool(forKey: Key.legacyScheduleCustomV3)
        }
    }

    // MARK: Appearance

    /// Saves the theme, widget designs and display switches, asks WidgetKit to redraw and notifies the
    /// UIKit screens so they repaint without a restart.
    func saveAppearance(_ value: WidgetAppearance) {
        let normalised = value.normalised()
        widgetAppearance = normalised
        SettingsStore.write(normalised, key: Key.appearance, defaults: defaults)
        WidgetCenter.shared.reloadTimelines(ofKind: "DeepSeekPulseWidget")
        NotificationCenter.default.post(name: .deepSeekAppearanceChanged, object: nil)
    }

    func resetAppearance() {
        saveAppearance(WidgetAppearance.defaultAppearance)
    }

    /// The palette the UIKit screens should draw with right now.
    var theme: PulseTheme { PulseThemes.theme(id: widgetAppearance.themeID) }

    // MARK: API key

    var apiKey: String {
        KeyStore.load() ?? ""
    }

    var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Increments whenever the account changes, so late responses for a previous key are discarded.
    private(set) var accountGeneration = AccountGeneration.initial

    /// A ticket for a balance request that is about to start.
    func currentAccountTicket() -> AccountTicket {
        accountGeneration.ticket()
    }

    /// Stores the key and reports exactly what happened.
    ///
    /// On a failed keychain write the previous key, cached balance and generation are left
    /// untouched, so the caller can never report "saved" for a key that is not actually stored.
    func replaceAPIKey(_ newKey: String) -> KeySaveResult {
        let previousKey = KeyStore.load()
        let change = KeyChange.compare(previous: previousKey, next: newKey)
        let trimmed = KeyChange.normalise(newKey)
        guard KeyStore.save(trimmed) else {
            return .storeFailed
        }
        let result = KeySaveResult.saved(change)
        if KeyStoreDecision.invalidates(result) {
            accountGeneration.invalidate()
            cachedSnapshot = nil
        }
        return result
    }

    /// Removes the key and reports exactly what happened.
    ///
    /// A delete that succeeds, or reports item-not-found, always invalidates pending requests and
    /// clears the cached balance, because an old cache can exist even when the key is already gone.
    func removeAPIKey() -> KeyRemovalResult {
        let previousKey = KeyStore.load()
        guard KeyStore.delete() else {
            return .deleteFailed
        }
        let result = KeyRemovalResult.removed(KeyChange.compare(previous: previousKey, next: nil))
        accountGeneration.invalidate()
        cachedSnapshot = nil
        return result
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

    /// Restores the verified schedule together with the verified 2026-2027 holiday list.
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
