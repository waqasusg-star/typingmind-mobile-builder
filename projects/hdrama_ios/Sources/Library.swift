import Foundation

struct SavedDrama: Codable {
    var url: String
    var title: String
    var favorite: Bool = false
    var episode: Int = 1
    var position: Double = 0
    var favoriteAt: Double = 0
    var duration: Double = 0
    var watchedAt: Double = 0
}

/// Favorites, per-episode resume positions and recent history. Hiding history never deletes them.
final class Library {
    static let shared = Library()

    private let defaults = UserDefaults.standard
    private let recordsKey = "drama_records"
    private let positionsKey = "episode_positions"
    private let completedKey = "episode_completed"
    private let durationsKey = "episode_durations"

    private var records: [SavedDrama] = []
    private var positions: [String: Double] = [:]
    private var completed: [String: Bool] = [:]
    private var durations: [String: Double] = [:]

    private init() { load() }

    private func load() {
        if let data = defaults.data(forKey: recordsKey),
           let list = try? JSONDecoder().decode([SavedDrama].self, from: data) {
            records = list
        }
        positions = defaults.dictionary(forKey: positionsKey) as? [String: Double] ?? [:]
        completed = defaults.dictionary(forKey: completedKey) as? [String: Bool] ?? [:]
        durations = defaults.dictionary(forKey: durationsKey) as? [String: Double] ?? [:]
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: recordsKey) }
        defaults.set(positions, forKey: positionsKey)
        defaults.set(completed, forKey: completedKey)
        defaults.set(durations, forKey: durationsKey)
    }

    private func positionKey(_ url: String, _ episode: Int) -> String { url + "#" + String(episode) }

    func get(_ raw: String) -> SavedDrama? {
        guard let url = SitePolicy.seriesURL(raw) else { return nil }
        return records.first { $0.url == url }
    }

    func favorites() -> [SavedDrama] {
        records.filter { $0.favorite }.sorted { $0.favoriteAt > $1.favoriteAt }
    }

    func history() -> [SavedDrama] {
        records.filter { $0.watchedAt > 0 }.sorted { $0.watchedAt > $1.watchedAt }
    }

    func isFavorite(_ raw: String) -> Bool { get(raw)?.favorite == true }

    func episodePosition(_ raw: String, _ episode: Int) -> Double {
        guard let url = SitePolicy.seriesURL(raw) else { return 0 }
        let key = positionKey(url, episode)
        if completed[key] == true { return 0 }
        var stored = positions[key] ?? 0
        if positions[key] == nil, let record = get(url), record.episode == episode { stored = record.position }
        let duration = durations[key] ?? get(url)?.duration ?? 0
        if duration > 0 && stored >= duration - 1 { return 0 }
        return max(0, stored)
    }

    func saveProgress(_ raw: String, title: String, episode: Int, position: Double, duration: Double, completedFlag: Bool) {
        guard let url = SitePolicy.seriesURL(raw) else { return }
        let number = min(max(1, episode), 10_000)
        let key = positionKey(url, number)
        positions[key] = max(0, position)
        if duration > 0 { durations[key] = duration }
        if completedFlag || (duration > 0 && position >= duration - 1) { completed[key] = true }
        var record = get(url) ?? SavedDrama(url: url, title: title)
        record.title = String(title.prefix(200))
        record.episode = number
        record.position = max(0, position)
        record.duration = max(0, duration)
        record.watchedAt = Date().timeIntervalSince1970
        records.removeAll { $0.url == url }
        records.append(record)
        persist()
    }

    @discardableResult
    func toggleFavorite(_ raw: String, title: String) -> Bool {
        guard let url = SitePolicy.seriesURL(raw) else { return false }
        var record = get(url) ?? SavedDrama(url: url, title: title)
        record.title = String(title.prefix(200))
        record.favorite.toggle()
        if record.favorite { record.favoriteAt = Date().timeIntervalSince1970 }
        records.removeAll { $0.url == url }
        records.append(record)
        persist()
        return record.favorite
    }

    func removeFavorite(_ raw: String) {
        guard let url = SitePolicy.seriesURL(raw), var record = get(url) else { return }
        record.favorite = false
        records.removeAll { $0.url == url }
        records.append(record)
        persist()
    }

    func removeHistory(_ raw: String) {
        guard let url = SitePolicy.seriesURL(raw), var record = get(url) else { return }
        record.watchedAt = 0
        records.removeAll { $0.url == url }
        records.append(record)
        persist()
    }

    func clearHistory() {
        records = records.map { item in
            var copy = item
            copy.watchedAt = 0
            return copy
        }
        persist()
    }
}
