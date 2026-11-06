import Foundation

extension Notification.Name {
    static let deepSeekSettingsChanged = Notification.Name("DeepSeekPulseSettingsChanged")
}

final class SettingsStore {

    static let shared = SettingsStore()

    private enum Key {
        static let window = "deepseekpulse.window.v1"
        static let models = "deepseekpulse.models.v1"
        static let snapshot = "deepseekpulse.snapshot.v1"
    }

    private let defaults: UserDefaults

    private(set) var window: PeakWindow
    private(set) var models: [ModelRate]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.window = SettingsStore.read(PeakWindow.self, key: Key.window, defaults: defaults) ?? .seeded
        let stored = SettingsStore.read([ModelRate].self, key: Key.models, defaults: defaults)
        self.models = (stored?.isEmpty == false) ? (stored ?? RateSeeds.models) : RateSeeds.models
    }

    // MARK: API key

    var apiKey: String {
        KeyStore.load() ?? ""
    }

    var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Persistence

    func saveWindow(_ newValue: PeakWindow) {
        window = newValue
        SettingsStore.write(newValue, key: Key.window, defaults: defaults)
    }

    func saveModels(_ newValue: [ModelRate]) {
        guard !newValue.isEmpty else { return }
        models = newValue
        SettingsStore.write(newValue, key: Key.models, defaults: defaults)
    }

    func resetSchedule() {
        saveWindow(.seeded)
    }

    func resetRates() {
        saveModels(RateSeeds.models)
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
