import UIKit
import AVFoundation
import AVKit

final class VideoSurfaceView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

/// Native player: AVPlayer video with the same chrome, gestures, resume and automatic next episode.
final class PlayerViewController: UIViewController, AVPictureInPictureControllerDelegate {

    private let seriesUrl: String
    private let requestedEpisode: Int?
    private let offlineItem: DownloadItem?

    private var series: Series?
    private var index = 0
    private let player = AVPlayer()
    private let videoView = VideoSurfaceView()
    private var chrome: PlayerChrome!
    private var timeObserver: Any?
    private var endObserver: NSObject?
    private var failObserver: NSObject?
    private var controlObservation: NSKeyValueObservation?
    private var pip: AVPictureInPictureController?

    private var loading = false
    private var desiredPlay = true
    private var speed: Float = 1
    private var qualityLabel: Int = 0
    private var controls = true
    private var holdSpeed = false
    private var scrubbing = false
    private var dragAxis: EpisodeSwipe.Axis = .none
    private var dragOrigin: Double = 0
    private var dragDuration: Double = 0
    private var dragStart: CGPoint = .zero
    private var resumeTarget: Double = 0
    private var lastCheckpoint = Date.distantPast
    private var lastPreview = Date.distantPast
    private var loadToken = 0
    private var hideWork: DispatchWorkItem?
    private var streamCache: [String: (Stream, Date)] = [:]

    private var currentPosition: Double {
        let value = player.currentTime().seconds
        return value.isFinite ? max(0, value) : 0
    }

    private var isPlaying: Bool { player.timeControlStatus == .playing }

    /// HLS adapts by itself; this is the ceiling chosen in the Quality sheet.
    private var peakBitrate: Double {
        switch qualityLabel {
        case 1080: return 5_000_000
        case 720: return 2_800_000
        case 480: return 1_200_000
        default: return 0
        }
    }

    init(seriesUrl: String, episode: Int?, offline: DownloadItem?) {
        self.seriesUrl = SitePolicy.seriesURL(seriesUrl) ?? seriesUrl
        self.requestedEpisode = episode
        self.offlineItem = offline
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var prefersStatusBarHidden: Bool { !controls }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var prefersHomeIndicatorAutoHidden: Bool { !controls }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureAudio()
        buildVideo()
        buildChrome()
        observePlayer()
        loadSeries()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        checkpoint()
        player.pause()
    }

    deinit {
        if let observer = timeObserver { player.removeTimeObserver(observer) }
        if let observer = endObserver { NotificationCenter.default.removeObserver(observer) }
        if let observer = failObserver { NotificationCenter.default.removeObserver(observer) }
    }

    private func configureAudio() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
    }

    private func buildVideo() {
        videoView.translatesAutoresizingMaskIntoConstraints = false
        videoView.playerLayer.player = player
        videoView.playerLayer.videoGravity = .resizeAspect
        videoView.backgroundColor = .black
        view.addSubview(videoView)
        NSLayoutConstraint.activate([
            videoView.topAnchor.constraint(equalTo: view.topAnchor),
            videoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            videoView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        videoView.addGestureRecognizer(tap)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(handleHold(_:)))
        hold.minimumPressDuration = 0.55
        videoView.addGestureRecognizer(hold)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        videoView.addGestureRecognizer(pan)
    }

    private func buildChrome() {
        var actions = PlayerChrome.Actions()
        actions.episodes = { [weak self] in self?.showEpisodes() }
        actions.speed = { [weak self] in self?.showSpeed() }
        actions.quality = { [weak self] in self?.showQuality() }
        actions.download = { [weak self] in self?.showDownload() }
        actions.downloads = { [weak self] in self?.openDownloads() }
        actions.favorite = { [weak self] in self?.toggleFavorite() }
        actions.removeFavorite = { [weak self] in self?.removeFavorite() }
        actions.myList = { [weak self] in self?.showMyList() }
        actions.toggle = { [weak self] in self?.togglePlayback() }
        actions.retry = { [weak self] in self?.prepare(index: self?.index ?? 0, resume: true) }
        actions.access = { [weak self] in self?.showAccessHelp() }
        actions.options = { [weak self] anchor in self?.showOptions(anchor) }
        chrome = PlayerChrome(actions: actions)
        chrome.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(chrome)
        chrome.pinToEdges(of: view)
        chrome.seek.addTarget(self, action: #selector(seekDown), for: .touchDown)
        chrome.seek.addTarget(self, action: #selector(seekChanged), for: .valueChanged)
        chrome.seek.addTarget(self, action: #selector(seekUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        if AVPictureInPictureController.isPictureInPictureSupported() {
            pip = AVPictureInPictureController(playerLayer: videoView.playerLayer)
            pip?.delegate = self
            pip?.canStartPictureInPictureAutomaticallyFromInline = true
        }
        chrome.setFavorite(Library.shared.isFavorite(seriesUrl))
        chrome.setSpeed(speed)
    }

    private func observePlayer() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.3, preferredTimescale: 600), queue: .main) { [weak self] _ in
            self?.updateProgress()
            self?.maybeCheckpoint()
        }
        controlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            guard let self = self else { return }
            if player.timeControlStatus == .playing {
                self.loading = false
                self.chrome.setBusy(false)
                self.chrome.showStatus("")
                self.scheduleHide()
                if self.speed != 1 { player.rate = self.speed }
            }
            self.updateChrome()
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                            object: nil, queue: .main) { [weak self] note in
            guard let self = self, let item = note.object as? AVPlayerItem, item === self.player.currentItem else { return }
            self.reachedEnd()
        }
        failObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime,
                                                             object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.loading = false
            self.chrome.setBusy(false)
            self.chrome.showStatus("Playback failed. Tap Retry source to refresh the stream.", retry: true)
            self.showControls(true)
        }
    }

    // MARK: - Series

    private func loadSeries() {
        if let offline = offlineItem {
            let episode = Episode(number: offline.episodeNumber, pageUrl: offline.id)
            let local = Series(title: offline.seriesTitle, url: offline.seriesUrl, episodes: [episode],
                               seasonLabel: offline.season)
            series = local
            index = 0
            chrome.heading.text = local.title
            prepare(index: 0, resume: true)
            return
        }
        if let handoff = PlaybackHandoff.take(seriesUrl) {
            apply(handoff)
            return
        }
        loading = true
        chrome.setBusy(true)
        chrome.showStatus("Loading episodes…")
        SiteClient.fetch(seriesUrl) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let html):
                guard let series = SeriesParser.series(html: html, url: self.seriesUrl) else {
                    self.loading = false
                    self.chrome.setBusy(false)
                    self.chrome.showStatus("No episode links were found. The site layout may have changed.", retry: true)
                    return
                }
                self.apply(series)
            case .failure(let error):
                self.loading = false
                self.chrome.setBusy(false)
                var accessRequired = false
                if let clientError = error as? SiteClient.ClientError {
                    switch clientError {
                    case .access, .blocked: accessRequired = true
                    default: accessRequired = false
                    }
                }
                self.chrome.showStatus(error.localizedDescription, retry: !accessRequired, access: accessRequired)
                self.showControls(true)
            }
        }
    }

    private func apply(_ loaded: Series) {
        series = loaded
        Artwork.shared.remember(loaded)
        Artwork.shared.fetch(loaded)
        chrome.heading.text = loaded.title
        let saved = Library.shared.get(seriesUrl)
        let wanted = requestedEpisode ?? saved?.episode ?? loaded.episodes.first?.number ?? 1
        index = loaded.episodes.firstIndex { $0.number == wanted } ?? 0
        chrome.setFavorite(saved?.favorite == true)
        prepare(index: index, resume: true)
    }

    private func prepare(index newIndex: Int, resume: Bool) {
        guard let current = series, current.episodes.indices.contains(newIndex) else { return }
        checkpoint()
        index = newIndex
        chrome.clearFeedback()
        let episode = current.episodes[newIndex]
        resumeTarget = Library.shared.episodePosition(seriesUrl, episode.number)
        if !resume { desiredPlay = true }
        loading = true
        loadToken += 1
        let token = loadToken
        chrome.setBusy(true)
        chrome.showStatus("Opening episode \(episode.number)…")
        showControls(true)
        updateChrome()
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
            guard let self = self, self.loadToken == token, self.loading else { return }
            self.loading = false
            self.chrome.setBusy(false)
            self.chrome.showStatus("The video server did not start playback. Tap Retry source to refresh the stream.", retry: true)
            self.showControls(true)
        }

        if let offline = offlineItem {
            // Offline playback never falls back to the network.
            guard offline.id == episode.pageUrl, let url = DownloadStore.shared.fileURL(for: offline) else {
                loading = false
                chrome.setBusy(false)
                chrome.showStatus("This episode is not downloaded. Choose a saved episode or return to Downloads.",
                                  retry: false, access: false)
                showControls(true)
                return
            }
            play(url: url, position: resumeTarget)
            return
        }
        if let cached = streamCache[episode.pageUrl], Date().timeIntervalSince(cached.1) < 60 {
            play(stream: cached.0, position: resumeTarget)
            return
        }
        StreamResolver.resolve(episode.pageUrl) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let stream):
                self.streamCache[episode.pageUrl] = (stream, Date())
                if self.index == newIndex { self.play(stream: stream, position: self.resumeTarget) }
            case .failure(let error):
                self.loading = false
                self.chrome.setBusy(false)
                var blocked = false
                if let resolverError = error as? StreamResolver.ResolverError, case .blocked = resolverError { blocked = true }
                self.chrome.showStatus(error.localizedDescription, retry: !blocked, access: blocked)
                self.showControls(true)
            }
        }
    }

    private func play(url: URL, position: Double) {
        let item = AVPlayerItem(url: url)
        start(item: item, position: position)
    }

    private func play(stream: Stream, position: Double) {
        guard let url = URL(string: stream.url) else { return }
        // Header fields for the site's CDN. AVURLAsset supports this documented-by-practice key.
        let headers: [String: String] = [
            "Referer": stream.referer,
            "Origin": "https://en.hdrama.net",
            "User-Agent": stream.userAgent
        ]
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        start(item: AVPlayerItem(asset: asset), position: position)
    }

    private func start(item: AVPlayerItem, position: Double) {
        player.replaceCurrentItem(with: item)
        item.preferredPeakBitRate = peakBitrate
        if position > 0 {
            player.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        if desiredPlay {
            player.play()
            player.rate = speed
        } else {
            player.pause()
        }
        updateChrome()
    }

    // MARK: - Playback control

    private func togglePlayback() {
        if loading || player.currentItem == nil {
            chrome.feedback("Opening episode…")
            return
        }
        desiredPlay.toggle()
        if desiredPlay { player.play(); player.rate = speed } else { player.pause() }
        chrome.feedback(desiredPlay ? "Playing" : "Paused")
        showControls(true)
        checkpoint()
        updateChrome()
    }

    private func reachedEnd() {
        checkpoint(completed: true)
        guard let current = series, let next = EpisodeOrder.next(index, current.episodes.count) else {
            desiredPlay = false
            chrome.showStatus("You've reached the final episode.")
            showControls(true)
            return
        }
        prepare(index: next, resume: false)
    }

    private func duration() -> Double {
        guard let item = player.currentItem else { return 0 }
        let value = item.duration.seconds
        return value.isFinite && value > 0 ? value : 0
    }

    private func updateProgress() {
        guard !scrubbing else { return }
        let total = duration()
        let position = currentPosition
        if total > 0 {
            chrome.seek.value = Float(min(1, position / total))
            chrome.position.text = Theme.time(position) + " / " + Theme.time(total)
            chrome.remaining.text = "−" + Theme.time(max(0, total - position))
        } else {
            chrome.position.text = Theme.time(position) + " / --:--"
            chrome.remaining.text = ""
        }
        chrome.seek.isEnabled = total > 0 && !loading
    }

    private func updateChrome() {
        chrome.setPlayback(playing: isPlaying, enabled: !loading && player.currentItem != nil)
        if let current = series, current.episodes.indices.contains(index) {
            chrome.setEpisode(current: current.episodes[index].number, total: current.episodes.count)
        }
        setNeedsStatusBarAppearanceUpdate()
    }

    private func maybeCheckpoint() {
        guard !loading, isPlaying else { return }
        if Date().timeIntervalSince(lastCheckpoint) >= 5 { checkpoint() }
    }

    private func checkpoint(completed: Bool = false) {
        guard let current = series, current.episodes.indices.contains(index), !loading else { return }
        let episode = current.episodes[index]
        Library.shared.saveProgress(seriesUrl, title: current.title, episode: episode.number,
                                    position: currentPosition, duration: duration(), completedFlag: completed)
        lastCheckpoint = Date()
    }

    // MARK: - Chrome visibility

    private func showControls(_ visible: Bool) {
        controls = visible && !holdSpeed
        chrome.showControls(controls)
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        if controls { scheduleHide() } else { hideWork?.cancel() }
    }

    private func scheduleHide() {
        hideWork?.cancel()
        guard !scrubbing, !holdSpeed else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.isPlaying, !self.scrubbing else { return }
            self.showControls(false)
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    // MARK: - Gestures

    @objc private func handleTap() { showControls(!controls) }

    @objc private func handleHold(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            guard !loading, !scrubbing, player.currentItem != nil else { return }
            holdSpeed = true
            player.rate = 1.5
            chrome.clearFeedback()
            showControls(false)
        case .ended, .cancelled, .failed:
            if holdSpeed {
                holdSpeed = false
                player.rate = desiredPlay ? speed : 0
            }
        default: break
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: videoView)
        switch gesture.state {
        case .began:
            dragAxis = .none
            dragStart = gesture.location(in: videoView)
        case .changed:
            if dragAxis == .none {
                dragAxis = EpisodeSwipe.axis(dx: translation.x, dy: translation.y, threshold: 20)
                if dragAxis == .horizontal, duration() > 0, !loading {
                    dragOrigin = currentPosition
                    dragDuration = duration()
                    scrubbing = true
                    player.pause()
                    hideWork?.cancel()
                    showControls(true)
                }
            }
            if dragAxis == .horizontal, dragDuration > 0 {
                let target = ScreenSeek.target(origin: dragOrigin, distance: translation.x,
                                               width: videoView.bounds.width, duration: dragDuration)
                preview(target)
            }
        case .ended, .cancelled, .failed:
            if dragAxis == .horizontal {
                let target = ScreenSeek.target(origin: dragOrigin,
                                               distance: gesture.state == .cancelled ? 0 : translation.x,
                                               width: videoView.bounds.width, duration: dragDuration)
                commit(target)
            }
            if dragAxis == .vertical, gesture.state == .ended, let current = series {
                let velocity = gesture.velocity(in: videoView)
                if let next = EpisodeSwipe.target(index: index, size: current.episodes.count,
                                                  dy: translation.y, height: videoView.bounds.height,
                                                  velocity: velocity.y) {
                    prepare(index: next, resume: false)
                }
            }
            dragAxis = .none
            scrubbing = false
            scheduleHide()
        default: break
        }
    }

    private func preview(_ target: Double) {
        let total = dragDuration
        chrome.seek.value = total > 0 ? Float(min(1, target / total)) : 0
        chrome.position.text = Theme.time(target) + " / " + Theme.time(total)
        chrome.remaining.text = "−" + Theme.time(max(0, total - target))
        guard Date().timeIntervalSince(lastPreview) > 0.15 else { return }
        lastPreview = Date()
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func commit(_ target: Double) {
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let self = self else { return }
            if self.desiredPlay { self.player.play(); self.player.rate = self.speed }
        }
        scrubbing = false
        checkpoint()
    }

    // MARK: - Timeline

    @objc private func seekDown() {
        guard duration() > 0, !loading else { return }
        scrubbing = true
        hideWork?.cancel()
    }

    @objc private func seekChanged() {
        guard scrubbing, duration() > 0 else { return }
        let total = duration()
        let target = Double(chrome.seek.value) * total
        chrome.position.text = Theme.time(target) + " / " + Theme.time(total)
        chrome.remaining.text = "−" + Theme.time(max(0, total - target))
        if Date().timeIntervalSince(lastPreview) > 0.15 {
            lastPreview = Date()
            player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    @objc private func seekUp() {
        guard scrubbing, duration() > 0 else { return }
        let target = Double(chrome.seek.value) * duration()
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        scrubbing = false
        checkpoint()
        scheduleHide()
    }

    // MARK: - Actions

    private func toggleFavorite() {
        guard let current = series else { return }
        checkpoint()
        let saved = Library.shared.toggleFavorite(seriesUrl, title: current.title)
        chrome.setFavorite(saved)
        scheduleHide()
    }

    private func removeFavorite() {
        guard series != nil else { return }
        checkpoint()
        Library.shared.removeFavorite(seriesUrl)
        chrome.setFavorite(false)
        chrome.feedback("Removed from My List")
        scheduleHide()
    }

    private func showEpisodes() {
        guard let current = series else { return }
        hideWork?.cancel()
        let sheet = EpisodeSheetViewController(series: current, current: index, downloadMode: false,
                                               onEpisode: { [weak self] selected in
            guard let self = self else { return }
            if selected != self.index { self.prepare(index: selected, resume: false) }
        }, onDownload: { _ in })
        present(sheet, animated: true)
    }

    private func showDownload() {
        guard let current = series else { return }
        hideWork?.cancel()
        let sheet = EpisodeSheetViewController(series: current, current: index, downloadMode: true,
                                               onEpisode: { _ in },
                                               onDownload: { [weak self] selected in
            guard let self = self else { return }
            self.queueDownloads(selected)
        })
        sheet.qualityOptions = [0, 1080, 720, 480]
        sheet.onQuality = { [weak self] value in self?.qualityLabel = value }
        present(sheet, animated: true)
    }

    private func queueDownloads(_ indices: [Int]) {
        guard let current = series, !indices.isEmpty else { return }
        DownloadStore.shared.enqueue(series: current, indices: indices, quality: qualityLabel) { [weak self] added in
            self?.chrome.feedback(added > 0 ? "Episodes queued. Open Downloads for progress." : "Already saved or unavailable.")
        }
    }

    private func openDownloads() {
        hideWork?.cancel()
        player.pause()
        let controller = DownloadsViewController()
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true)
    }

    private func showMyList() {
        hideWork?.cancel()
        let controller = ListViewController(mode: .favorites)
        controller.onOpen = { [weak self] item in
            guard let self = self else { return }
            // Close the list and this player, then open the chosen series from the browser.
            let presenter = self.presentingViewController
            self.dismiss(animated: true) {
                let player = PlayerViewController(seriesUrl: item.url, episode: nil, offline: nil)
                player.modalPresentationStyle = .fullScreen
                presenter?.present(player, animated: true)
            }
        }
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true)
    }

    private func showSpeed() {
        hideWork?.cancel()
        let values: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]
        let sheet = ChoiceSheetViewController(title: "Playback speed",
                                              options: values.map { ($0 == 1 ? "Normal (1×)" : String(format: "%.2g×", $0), Float($0) == speed) })
        sheet.onSelect = { [weak self] selected in
            guard let self = self else { return }
            self.speed = values[selected]
            self.chrome.setSpeed(self.speed)
            if self.desiredPlay { self.player.rate = self.speed }
            self.showControls(true)
        }
        present(sheet, animated: true)
    }

    private func showQuality() {
        hideWork?.cancel()
        let options = ["Auto", "High · up to 1080P", "Medium · up to 720P", "Low · up to 480P"]
        let values = [0, 1080, 720, 480]
        let selected = values.firstIndex(of: qualityLabel) ?? 0
        let sheet = ChoiceSheetViewController(title: "Quality",
                                              options: options.enumerated().map { ($0.element, $0.offset == selected) })
        sheet.footnote = "HLS streams adapt automatically. This sets a ceiling rather than an exact rendition."
        sheet.onSelect = { [weak self] index in
            guard let self = self else { return }
            self.qualityLabel = values[index]
            self.player.currentItem?.preferredPeakBitRate = self.peakBitrate
            self.showControls(true)
        }
        present(sheet, animated: true)
    }

    private func showOptions(_ anchor: UIView) {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let fill = videoView.playerLayer.videoGravity == .resizeAspectFill
        sheet.addAction(UIAlertAction(title: fill ? "Fit video" : "Fill screen", style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.videoView.playerLayer.videoGravity = fill ? .resizeAspect : .resizeAspectFill
        })
        sheet.addAction(UIAlertAction(title: "Downloads", style: .default) { [weak self] _ in self?.openDownloads() })
        if pip != nil {
            sheet.addAction(UIAlertAction(title: "Picture in picture", style: .default) { [weak self] _ in
                guard let pip = self?.pip else { return }
                if pip.isPictureInPicturePossible { pip.startPictureInPicture() }
                else { self?.chrome.feedback("Picture in picture is not available right now") }
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = anchor
            popover.sourceRect = anchor.bounds
        }
        present(sheet, animated: true)
    }

    private func showAccessHelp() {
        let alert = UIAlertController(title: "Website access",
                                      message: "Open this series in the in-app browser, complete any check the website shows, then tap Play again.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - Picture in picture

    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        showControls(true)
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }
}
