import UIKit
import AVFoundation
import Network
import CryptoKit

struct DownloadItem: Codable {
    var id: String
    var seriesUrl: String
    var seriesTitle: String
    var season: String
    var episodeNumber: Int
    var totalEpisodes: Int
    var streamUrl: String
    var referer: String
    var mime: String
    var localPath: String
    var state: String
    var progress: Double
    var bytes: Int64
    var quality: Int
    var error: String
    var createdAt: Double

    var isReady: Bool { state == "ready" }
    var isActive: Bool { state == "downloading" || state == "queued" }
}

final class NetworkMonitor {
    static let shared = NetworkMonitor()
    private let monitor = NWPathMonitor()
    private(set) var isWiFi = true
    private(set) var isOnline = true

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isWiFi = path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
                self?.isOnline = path.status == .satisfied
            }
        }
        monitor.start(queue: DispatchQueue(label: "hdrama.network"))
    }
}

/// Offline store: HLS uses AVAssetDownloadURLSession, progressive files use a background URLSession.
final class DownloadStore: NSObject {
    static let shared = DownloadStore()
    static let changed = Notification.Name("hdrama.downloads.changed")

    private(set) var items: [DownloadItem] = []
    private var resolving = false
    private let defaults = UserDefaults.standard

    var wifiOnly: Bool {
        get { defaults.bool(forKey: "downloads.wifiOnly") }
        set { defaults.set(newValue, forKey: "downloads.wifiOnly") }
    }

    private var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let path = base.appendingPathComponent("Offline", isDirectory: true)
        if !FileManager.default.fileExists(atPath: path.path) {
            try? FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        }
        return path
    }

    private lazy var hlsSession: AVAssetDownloadURLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: "com.waqas.hdrama.hls")
        configuration.allowsCellularAccess = true
        return AVAssetDownloadURLSession(configuration: configuration, assetDownloadDelegate: self, delegateQueue: .main)
    }()

    private lazy var fileSession: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: "com.waqas.hdrama.files")
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        return URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
    }()

    private override init() {
        super.init()
        load()
        reconnect()
    }

    // MARK: - Persistence

    private var indexFile: URL { directory.appendingPathComponent("index.json") }

    private func load() {
        guard let data = try? Data(contentsOf: indexFile),
              let list = try? JSONDecoder().decode([DownloadItem].self, from: data) else { return }
        items = list
        for index in items.indices where items[index].state == "downloading" {
            items[index].state = "paused"
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: indexFile)
    }

    private func notify() {
        persist()
        NotificationCenter.default.post(name: DownloadStore.changed, object: nil)
    }

    private func update(_ id: String, _ change: (inout DownloadItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
        notify()
    }

    func isReady(_ id: String) -> Bool {
        items.first(where: { $0.id == id })?.isReady == true
    }

    func fileURL(for item: DownloadItem) -> URL? {
        guard item.isReady, !item.localPath.isEmpty else { return nil }
        let url = URL(fileURLWithPath: item.localPath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Queue

    func enqueue(series: Series, indices: [Int], quality: Int, completion: @escaping (Int) -> Void) {
        var added = 0
        for index in indices where series.episodes.indices.contains(index) {
            let episode = series.episodes[index]
            if let existing = items.first(where: { $0.id == episode.pageUrl }), existing.state != "failed" { continue }
            items.removeAll { $0.id == episode.pageUrl }
            items.append(DownloadItem(id: episode.pageUrl,
                                      seriesUrl: series.url,
                                      seriesTitle: series.title,
                                      season: series.seasonLabel,
                                      episodeNumber: episode.number,
                                      totalEpisodes: series.episodes.count,
                                      streamUrl: "", referer: series.url, mime: "", localPath: "",
                                      state: "queued", progress: 0, bytes: 0, quality: quality,
                                      error: "", createdAt: Date().timeIntervalSince1970))
            added += 1
        }
        notify()
        resolveNext()
        completion(added)
    }

    private func resolveNext() {
        guard !resolving else { return }
        guard !(wifiOnly && !NetworkMonitor.shared.isWiFi) else { return }
        guard let item = items.first(where: { $0.state == "queued" }) else { return }
        resolving = true
        StreamResolver.resolve(item.id) { [weak self] result in
            guard let self = self else { return }
            self.resolving = false
            switch result {
            case .success(let stream):
                self.update(item.id) { entry in
                    entry.streamUrl = stream.url
                    entry.mime = stream.mimeType ?? ""
                    entry.referer = stream.referer
                    entry.state = "downloading"
                    entry.error = ""
                }
                self.start(itemID: item.id, stream: stream)
            case .failure(let error):
                self.update(item.id) { entry in
                    entry.state = "failed"
                    entry.error = error.localizedDescription
                }
            }
            self.resolveNext()
        }
    }

    private func bitrate(for quality: Int) -> Int {
        switch quality {
        case 1080: return 5_000_000
        case 720: return 2_800_000
        case 480: return 1_200_000
        default: return 0
        }
    }

    private func start(itemID: String, stream: Stream) {
        guard let url = URL(string: stream.url) else { return }
        let isHLS = stream.url.lowercased().contains(".m3u8") || (stream.mimeType ?? "").contains("mpegurl")
        if isHLS {
            var options: [String: Any] = [:]
            if let quality = items.first(where: { $0.id == itemID })?.quality, quality > 0 {
                options[AVAssetDownloadTaskMinimumRequiredMediaBitrateKey] = bitrate(for: quality)
            }
            let asset = AVURLAsset(url: url, options: [
                "AVURLAssetHTTPHeaderFieldsKey": [
                    "Referer": stream.referer,
                    "User-Agent": stream.userAgent
                ]
            ])
            let task = hlsSession.makeAssetDownloadTask(asset: asset, assetTitle: itemID,
                                                        assetArtworkData: nil, options: options)
            task?.taskDescription = itemID
            task?.resume()
        } else {
            var request = URLRequest(url: url)
            request.setValue(stream.referer, forHTTPHeaderField: "Referer")
            request.setValue(stream.userAgent, forHTTPHeaderField: "User-Agent")
            request.allowsCellularAccess = !wifiOnly
            let task = fileSession.downloadTask(with: request)
            task.taskDescription = itemID
            task.resume()
        }
    }

    func pause(_ id: String) {
        cancelTask(id)
        update(id) { entry in
            if entry.state == "downloading" || entry.state == "queued" { entry.state = "paused" }
        }
    }

    func resume(_ id: String) {
        update(id) { entry in
            entry.state = "queued"
            entry.error = ""
        }
        resolveNext()
    }

    func pauseAll() {
        for item in items where item.isActive { pause(item.id) }
    }

    func resumeAll() {
        for item in items where item.state == "paused" || item.state == "failed" { resume(item.id) }
    }

    func retry(_ id: String) {
        update(id) { entry in
            entry.state = "queued"
            entry.error = ""
            entry.progress = 0
        }
        resolveNext()
    }

    func delete(_ ids: [String]) {
        for id in ids {
            cancelTask(id)
            if let item = items.first(where: { $0.id == id }), !item.localPath.isEmpty {
                try? FileManager.default.removeItem(atPath: item.localPath)
            }
        }
        items.removeAll { ids.contains($0.id) }
        notify()
    }

    private func cancelTask(_ id: String) {
        hlsSession.getAllTasks { tasks in
            tasks.filter { $0.taskDescription == id }.forEach { $0.cancel() }
        }
        fileSession.getAllTasks { tasks in
            tasks.filter { $0.taskDescription == id }.forEach { $0.cancel() }
        }
    }

    private func reconnect() {
        fileSession.getAllTasks { [weak self] tasks in
            guard let self = self else { return }
            for task in tasks {
                guard let id = task.taskDescription, self.items.contains(where: { $0.id == id }) else { continue }
                self.update(id) { entry in entry.state = "downloading" }
            }
        }
        hlsSession.getAllTasks { [weak self] tasks in
            guard let self = self else { return }
            for task in tasks {
                guard let id = task.taskDescription, self.items.contains(where: { $0.id == id }) else { continue }
                self.update(id) { entry in entry.state = "downloading" }
            }
        }
    }

    private func offlinePath(_ id: String, ext: String) -> URL {
        let digest = SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest + "." + ext)
    }
}

extension DownloadStore: AVAssetDownloadDelegate {

    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask,
                    didLoad timeRange: CMTimeRange, totalTimeRangesLoaded loadedTimeRanges: [NSValue],
                    timeRangeExpectedToLoad: CMTimeRange) {
        guard let id = assetDownloadTask.taskDescription else { return }
        let expected = timeRangeExpectedToLoad.duration.seconds
        guard expected > 0 else { return }
        let loaded = loadedTimeRanges.reduce(0.0) { $0 + $1.timeRangeValue.duration.seconds }
        update(id) { entry in entry.progress = min(1, loaded / expected) }
    }

    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = assetDownloadTask.taskDescription else { return }
        update(id) { entry in
            entry.localPath = location.path
            entry.progress = 1
            entry.state = "ready"
        }
    }

    func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask,
                    didResolve mediaSelection: AVMediaSelection) {
        // Informational only.
    }
}

extension DownloadStore: URLSessionDownloadDelegate {

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription, taskIdIsProgressive(downloadTask) else { return }
        guard totalBytesExpectedToWrite > 0 else { return }
        let ratio = min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        update(id) { entry in
            entry.progress = ratio
            entry.bytes = totalBytesWritten
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription, taskIdIsProgressive(downloadTask) else { return }
        let destination = offlinePath(id, ext: "mp4")
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            update(id) { entry in
                entry.localPath = destination.path
                entry.progress = 1
                entry.state = "ready"
            }
        } catch {
            update(id) { entry in
                entry.state = "failed"
                entry.error = error.localizedDescription
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription, let error = error else { return }
        let cancelled = (error as NSError).code == NSURLErrorCancelled
        guard !cancelled else { return }
        update(id) { entry in
            if entry.state == "downloading" {
                entry.state = "failed"
                entry.error = error.localizedDescription
            }
        }
    }

    private func taskIdIsProgressive(_ task: URLSessionTask) -> Bool {
        !(task is AVAssetDownloadTask)
    }
}

// MARK: - Downloads screen

final class DownloadsViewController: UIViewController {

    private let header = UIView()
    private let summary = Theme.label("", size: 12, color: AppColors.muted)
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let backButton = UIButton(type: .system)
    private let pauseAll = UIButton(type: .system)
    private let resumeAll = UIButton(type: .system)
    private let wifiSwitch = UISwitch()
    private var folder: String?
    private var observer: NSObjectProtocol?
    private var timer: Timer?
    private var signature = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColors.background
        buildHeader()
        buildList()
        observer = NotificationCenter.default.addObserver(forName: DownloadStore.changed, object: nil, queue: .main) { [weak self] _ in
            self?.render()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.render() }
        render()
    }

    deinit {
        if let observer = observer { NotificationCenter.default.removeObserver(observer) }
        timer?.invalidate()
    }

    private func buildHeader() {
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])

        backButton.setImage(UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)), for: .normal)
        backButton.tintColor = AppColors.text
        backButton.backgroundColor = AppColors.raised
        backButton.layer.cornerRadius = 14
        backButton.accessibilityLabel = "Back"
        backButton.addTarget(self, action: #selector(goBack), for: .touchUpInside)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.widthAnchor.constraint(equalToConstant: 48).isActive = true
        backButton.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let title = Theme.label("Downloads", size: 24, weight: .bold)
        let titleRow = UIStackView(arrangedSubviews: [backButton, title])
        titleRow.axis = .horizontal
        titleRow.spacing = 14
        titleRow.alignment = .center

        let wifiLabel = Theme.label("Wi-Fi only", size: 14)
        wifiSwitch.onTintColor = AppColors.accent
        wifiSwitch.isOn = DownloadStore.shared.wifiOnly
        wifiSwitch.addTarget(self, action: #selector(wifiChanged), for: .valueChanged)
        let wifiRow = UIStackView(arrangedSubviews: [wifiLabel, UIView(), wifiSwitch])
        wifiRow.axis = .horizontal
        wifiRow.alignment = .center

        styleSecondary(pauseAll, "Pause all")
        styleSecondary(resumeAll, "Resume all")
        pauseAll.addTarget(self, action: #selector(tapPauseAll), for: .touchUpInside)
        resumeAll.addTarget(self, action: #selector(tapResumeAll), for: .touchUpInside)
        let actions = UIStackView(arrangedSubviews: [pauseAll, resumeAll])
        actions.axis = .horizontal
        actions.distribution = .fillEqually
        actions.spacing = 8
        [pauseAll, resumeAll].forEach { $0.heightAnchor.constraint(equalToConstant: 44).isActive = true }

        let column = UIStackView(arrangedSubviews: [titleRow, summary, actions, wifiRow])
        column.axis = .vertical
        column.spacing = 10
        column.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(column)
        column.pinToEdges(of: header)
    }

    private func styleSecondary(_ button: UIButton, _ title: String) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(AppColors.text, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        button.backgroundColor = AppColors.raised
        button.layer.cornerRadius = 12
        button.layer.cornerCurve = .continuous
    }

    private func buildList() {
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])
    }

    @objc private func goBack() {
        if folder != nil { folder = nil; signature = ""; render() } else { dismiss(animated: true) }
    }

    @objc private func tapPauseAll() {
        DownloadStore.shared.pauseAll()
        render()
    }

    @objc private func tapResumeAll() {
        DownloadStore.shared.resumeAll()
        render()
    }

    @objc private func wifiChanged() {
        DownloadStore.shared.wifiOnly = wifiSwitch.isOn
    }

    private func render() {
        let items = DownloadStore.shared.items
        let folders = Dictionary(grouping: items, by: { $0.seriesUrl })
        if let current = folder, folders[current] == nil { folder = nil }

        let saved = items.filter { $0.isReady }
        summary.text = "\(saved.count) saved · " + String(format: "%.1f MB offline", Double(saved.reduce(0) { $0 + $1.bytes }) / 1_048_576)

        let key = (folder ?? "root") + "|" + items.map { "\($0.id):\($0.state):\(Int($0.progress * 1000))" }.joined()
        guard key != signature else { return }
        signature = key
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if let current = folder, let episodes = folders[current] {
            let ordered = episodes.sorted { $0.episodeNumber < $1.episodeNumber }
            let title = Theme.label(ordered.first?.seriesTitle ?? "Episodes", size: 18, weight: .semibold, lines: 2)
            stack.addArrangedSubview(title)
            stack.addArrangedSubview(Theme.label("Episodes · \(ordered.count)", size: 12, color: AppColors.muted))
            addGrid(ordered)
            return
        }

        if folders.isEmpty {
            stack.addArrangedSubview(Theme.emptyState(symbol: "arrow.down.circle",
                                                      title: "Ready for offline watching",
                                                      message: "Open a series and tap Download to save episodes."))
            return
        }
        for (url, episodes) in folders.sorted(by: { ($0.value.first?.seriesTitle ?? "") < ($1.value.first?.seriesTitle ?? "") }) {
            let ready = episodes.filter { $0.isReady }.count
            let card = seriesCard(url: url,
                                  title: episodes.first?.seriesTitle ?? "Series",
                                  subtitle: episodes.first?.season ?? "Series folder",
                                  detail: "\(ready) saved · \(episodes.count) episodes")
            let tap = UITapGestureRecognizer(target: self, action: #selector(openFolder(_:)))
            card.addGestureRecognizer(tap)
            card.tag = 0
            card.accessibilityIdentifier = url
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(holdFolder(_:)))
            card.addGestureRecognizer(hold)
            stack.addArrangedSubview(card)
        }
    }

    private func addGrid(_ episodes: [DownloadItem]) {
        var row: UIStackView?
        for (position, item) in episodes.enumerated() {
            if position % 5 == 0 {
                let next = UIStackView()
                next.axis = .horizontal
                next.distribution = .fillEqually
                next.spacing = 6
                stack.addArrangedSubview(next)
                row = next
            }
            let button = UIButton(type: .system)
            let badge: String
            switch item.state {
            case "ready": badge = "✓"
            case "failed": badge = "!"
            case "downloading": badge = "\(Int(item.progress * 100))%"
            case "paused": badge = "Ⅱ"
            default: badge = "…"
            }
            button.setTitle("\(item.episodeNumber)\n\(badge)", for: .normal)
            button.titleLabel?.numberOfLines = 2
            button.titleLabel?.textAlignment = .center
            button.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
            button.setTitleColor(item.isReady ? AppColors.accent : AppColors.text, for: .normal)
            button.backgroundColor = item.isReady ? AppColors.raised : AppColors.surface
            button.layer.cornerRadius = 12
            button.heightAnchor.constraint(equalToConstant: 56).isActive = true
            button.tag = position
            button.accessibilityLabel = "Episode \(item.episodeNumber), \(item.state)"
            button.addTarget(self, action: #selector(tapEpisode(_:)), for: .touchUpInside)
            row?.addArrangedSubview(button)
        }
        let remainder = episodes.count % 5
        if remainder != 0, let last = row {
            for _ in remainder..<5 { last.addArrangedSubview(UIView()) }
        }
    }

    @objc private func openFolder(_ gesture: UITapGestureRecognizer) {
        guard let url = gesture.view?.accessibilityIdentifier else { return }
        folder = url
        signature = ""
        render()
    }

    @objc private func holdFolder(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let url = gesture.view?.accessibilityIdentifier else { return }
        let ids = DownloadStore.shared.items.filter { $0.seriesUrl == url }.map { $0.id }
        confirmDelete(title: "Delete downloads?", message: "\(ids.count) episode(s). Favorites and watch progress are kept.", ids: ids)
    }

    @objc private func tapEpisode(_ sender: UIButton) {
        guard let current = folder else { return }
        let episodes = DownloadStore.shared.items.filter { $0.seriesUrl == current }
            .sorted { $0.episodeNumber < $1.episodeNumber }
        guard episodes.indices.contains(sender.tag) else { return }
        let item = episodes[sender.tag]
        if item.isReady {
            let player = PlayerViewController(seriesUrl: item.seriesUrl, episode: item.episodeNumber, offline: item)
            player.modalPresentationStyle = .fullScreen
            present(player, animated: true)
        } else {
            episodeOptions(item)
        }
    }

    private func episodeOptions(_ item: DownloadItem) {
        let resumable = item.state == "failed" || item.state == "paused" || item.state == "queued"
        let title = "Episode \(item.episodeNumber)"
        let message: String
        switch item.state {
        case "failed": message = item.error.isEmpty ? "Download failed." : item.error
        case "paused": message = "Paused"
        case "downloading": message = "Downloading · \(Int(item.progress * 100))%"
        default: message = "Waiting to prepare its source"
        }
        let sheet = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: resumable ? "Resume download" : "Pause download", style: .default) { [weak self] _ in
            if resumable { DownloadStore.shared.resume(item.id) } else { DownloadStore.shared.pause(item.id) }
            self?.signature = ""
            self?.render()
        })
        sheet.addAction(UIAlertAction(title: "Retry", style: .default) { [weak self] _ in
            DownloadStore.shared.retry(item.id)
            self?.signature = ""
            self?.render()
        })
        sheet.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.confirmDelete(title: "Delete episode?", message: "Episode \(item.episodeNumber). Favorites and watch progress are kept.", ids: [item.id])
        })
        sheet.addAction(UIAlertAction(title: "Close", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        }
        present(sheet, animated: true)
    }

    private func confirmDelete(title: String, message: String, ids: [String]) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            DownloadStore.shared.delete(ids)
            self?.signature = ""
            self?.render()
        })
        present(alert, animated: true)
    }

    private func seriesCard(url: String, title: String, subtitle: String, detail: String) -> UIView {
        let card = UIView()
        card.backgroundColor = AppColors.surface
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = AppColors.stroke.cgColor
        card.isUserInteractionEnabled = true
        card.isAccessibilityElement = true
        card.accessibilityLabel = "Open series folder: \(title)"

        let poster = UIImageView()
        poster.translatesAutoresizingMaskIntoConstraints = false
        poster.contentMode = .scaleAspectFill
        poster.clipsToBounds = true
        poster.layer.cornerRadius = 12
        poster.backgroundColor = AppColors.raised
        poster.image = Artwork.shared.image(url) ?? UIImage(systemName: "film")
        poster.tintColor = AppColors.accent
        if Artwork.shared.image(url) == nil { Artwork.shared.fetch(Series(title: title, url: url, episodes: [])) }

        let name = Theme.label(title, size: 17, weight: .bold, lines: 3)
        let season = Theme.label(subtitle, size: 12, color: AppColors.muted)
        let info = Theme.label(detail, size: 13, color: AppColors.accent, lines: 2)
        let column = UIStackView(arrangedSubviews: [name, season, info])
        column.axis = .vertical
        column.spacing = 6
        column.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(poster)
        card.addSubview(column)
        NSLayoutConstraint.activate([
            poster.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            poster.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            poster.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -14),
            poster.widthAnchor.constraint(equalToConstant: 72),
            poster.heightAnchor.constraint(equalToConstant: 104),
            column.leadingAnchor.constraint(equalTo: poster.trailingAnchor, constant: 14),
            column.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            column.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            column.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])
        card.heightAnchor.constraint(greaterThanOrEqualToConstant: 132).isActive = true
        return card
    }
}
