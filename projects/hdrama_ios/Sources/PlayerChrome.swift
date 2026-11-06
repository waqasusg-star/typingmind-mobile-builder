import UIKit

/// Native, non-scrolling player chrome: title and episode on top, one action rail, raised timeline.
final class PlayerChrome: UIView {

    struct Actions {
        var episodes: () -> Void = {}
        var speed: () -> Void = {}
        var quality: () -> Void = {}
        var download: () -> Void = {}
        var downloads: () -> Void = {}
        var favorite: () -> Void = {}
        var removeFavorite: () -> Void = {}
        var myList: () -> Void = {}
        var toggle: () -> Void = {}
        var retry: () -> Void = {}
        var access: () -> Void = {}
        var options: (UIView) -> Void = { _ in }
    }

    let heading = Theme.label("Loading story…", size: 15, weight: .medium)
    let runningEpisode = Theme.label("", size: 13, color: AppColors.muted)
    let position = Theme.label("0:00 / --:--", size: 11, weight: .medium)
    let remaining = Theme.label("", size: 11, color: AppColors.muted, align: .right)
    let status = Theme.label("", size: 12, lines: 4)
    let seek = UISlider()
    let playPause = UIButton(type: .custom)
    let episodeButton = UIButton(type: .custom)
    let retryButton = UIButton(type: .custom)
    let accessButton = UIButton(type: .custom)
    let spinner = UIActivityIndicatorView(style: .large)

    let favoriteAction = SquareAction(symbol: "heart", title: "Favorite", size: 50, side: true)
    let listAction = SquareAction(symbol: "list.bullet", title: "My List", size: 50, side: true)
    let downloadAction = SquareAction(symbol: "arrow.down", title: "Download", size: 50, side: true)
    let qualityAction = SquareAction(symbol: "rectangle.on.rectangle", title: "Quality", size: 50, side: true)
    let speedAction = SquareAction(symbol: "speedometer", title: "Speed", size: 50, side: true)

    private let topBar = UIView()
    private let bottomBar = UIView()
    private let rail = UIStackView()
    private let errorCard = UIView()
    private let feedbackLabel = Theme.label("", size: 14, color: AppColors.text, align: .center)
    private var feedbackWork: DispatchWorkItem?
    private let actions: Actions
    private(set) var controlsVisible = true

    init(actions: Actions) {
        self.actions = actions
        super.init(frame: .zero)
        build()
        setEpisode(current: 0, total: 0)
        setPlayback(playing: false, enabled: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Build

    private func build() {
        isUserInteractionEnabled = true
        backgroundColor = .clear

        // Top gradient with the series title and the bold running episode.
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.isUserInteractionEnabled = true
        addSubview(topBar)
        let gradient = CAGradientLayer()
        gradient.colors = [UIColor(white: 0, alpha: 0.72).cgColor, UIColor(white: 0, alpha: 0).cgColor]
        gradient.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        gradient.name = "topGradient"
        topBar.layer.addSublayer(gradient)

        heading.lineBreakMode = .byTruncatingTail
        runningEpisode.text = ""
        let options = UIButton(type: .custom)
        options.setImage(UIImage(systemName: "ellipsis", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)), for: .normal)
        options.tintColor = AppColors.text
        options.backgroundColor = UIColor(white: 0, alpha: 0.45)
        options.layer.cornerRadius = 24
        options.accessibilityLabel = "Player options"
        options.addTarget(self, action: #selector(showOptions(_:)), for: .touchUpInside)
        options.translatesAutoresizingMaskIntoConstraints = false

        let titles = UIStackView(arrangedSubviews: [heading, runningEpisode])
        titles.axis = .vertical
        titles.spacing = 6
        titles.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(titles)
        topBar.addSubview(options)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: topAnchor),
            topBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 96),
            titles.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 16),
            titles.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            titles.trailingAnchor.constraint(equalTo: options.leadingAnchor, constant: -12),
            options.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -14),
            options.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            options.widthAnchor.constraint(equalToConstant: 48),
            options.heightAnchor.constraint(equalToConstant: 48)
        ])

        // Action rail.
        rail.axis = .vertical
        rail.alignment = .fill
        rail.spacing = 6
        rail.translatesAutoresizingMaskIntoConstraints = false
        [favoriteAction, listAction, downloadAction, qualityAction, speedAction].forEach { rail.addArrangedSubview($0) }
        addSubview(rail)
        NSLayoutConstraint.activate([
            rail.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            rail.centerYAnchor.constraint(equalTo: centerYAnchor),
            rail.widthAnchor.constraint(equalToConstant: 68)
        ])

        favoriteAction.onTap = { [weak self] in self?.actions.favorite() }
        listAction.onTap = { [weak self] in self?.actions.myList() }
        downloadAction.onTap = { [weak self] in self?.actions.download() }
        qualityAction.onTap = { [weak self] in self?.actions.quality() }
        speedAction.onTap = { [weak self] in self?.actions.speed() }
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(holdHeart(_:)))
        favoriteAction.control.addGestureRecognizer(hold)

        // Bottom timeline, raised above the home indicator.
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bottomBar)
        let bottomGradient = CAGradientLayer()
        bottomGradient.colors = [UIColor(white: 0, alpha: 0).cgColor, UIColor(white: 0, alpha: 0.65).cgColor]
        bottomGradient.name = "bottomGradient"
        bottomBar.layer.addSublayer(bottomGradient)

        position.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let times = UIStackView(arrangedSubviews: [position, remaining])
        times.axis = .horizontal
        times.distribution = .fill
        times.translatesAutoresizingMaskIntoConstraints = false

        seek.minimumTrackTintColor = AppColors.accent
        seek.maximumTrackTintColor = UIColor(white: 1, alpha: 0.3)
        seek.thumbTintColor = .white
        seek.accessibilityLabel = "Episode progress"
        seek.translatesAutoresizingMaskIntoConstraints = false

        episodeButton.backgroundColor = AppColors.card
        episodeButton.layer.cornerRadius = 10
        episodeButton.layer.cornerCurve = .continuous
        episodeButton.tintColor = AppColors.text
        episodeButton.setTitleColor(AppColors.text, for: .normal)
        episodeButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        episodeButton.setImage(UIImage(systemName: "list.bullet", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)), for: .normal)
        episodeButton.semanticContentAttribute = .forceRightToLeft
        episodeButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: -8)
        episodeButton.contentHorizontalAlignment = .leading
        episodeButton.accessibilityLabel = "Episodes"
        episodeButton.addTarget(self, action: #selector(tapEpisodes), for: .touchUpInside)
        episodeButton.translatesAutoresizingMaskIntoConstraints = false

        bottomBar.addSubview(times)
        bottomBar.addSubview(seek)
        bottomBar.addSubview(episodeButton)
        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -8),
            times.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 14),
            times.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 22),
            times.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -22),
            seek.topAnchor.constraint(equalTo: times.bottomAnchor, constant: 2),
            seek.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 16),
            seek.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -16),
            seek.heightAnchor.constraint(equalToConstant: 34),
            episodeButton.topAnchor.constraint(equalTo: seek.bottomAnchor, constant: 8),
            episodeButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 22),
            episodeButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -22),
            episodeButton.heightAnchor.constraint(equalToConstant: 46),
            episodeButton.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor, constant: -6)
        ])

        // Center play / pause.
        playPause.translatesAutoresizingMaskIntoConstraints = false
        playPause.backgroundColor = UIColor(white: 0, alpha: 0.45)
        playPause.tintColor = .white
        playPause.layer.cornerRadius = 32
        playPause.layer.borderWidth = 1
        playPause.layer.borderColor = UIColor(white: 1, alpha: 0.25).cgColor
        playPause.addTarget(self, action: #selector(tapToggle), for: .touchUpInside)
        addSubview(playPause)
        NSLayoutConstraint.activate([
            playPause.centerXAnchor.constraint(equalTo: centerXAnchor),
            playPause.centerYAnchor.constraint(equalTo: centerYAnchor),
            playPause.widthAnchor.constraint(equalToConstant: 64),
            playPause.heightAnchor.constraint(equalToConstant: 64)
        ])

        // Error card.
        errorCard.translatesAutoresizingMaskIntoConstraints = false
        errorCard.backgroundColor = UIColor(hex: 0xEC1A1723)
        errorCard.layer.cornerRadius = 18
        errorCard.layer.cornerCurve = .continuous
        errorCard.isHidden = true
        status.numberOfLines = 4
        retryButton.setTitle("Retry source", for: .normal)
        styleLink(retryButton)
        retryButton.addTarget(self, action: #selector(tapRetry), for: .touchUpInside)
        accessButton.setTitle("Check website access", for: .normal)
        styleLink(accessButton)
        accessButton.addTarget(self, action: #selector(tapAccess), for: .touchUpInside)
        let errorStack = UIStackView(arrangedSubviews: [status, retryButton, accessButton])
        errorStack.axis = .vertical
        errorStack.spacing = 4
        errorStack.translatesAutoresizingMaskIntoConstraints = false
        errorCard.addSubview(errorStack)
        addSubview(errorCard)
        NSLayoutConstraint.activate([
            errorCard.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 8),
            errorCard.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            errorCard.trailingAnchor.constraint(equalTo: rail.leadingAnchor, constant: -10),
            errorStack.topAnchor.constraint(equalTo: errorCard.topAnchor, constant: 12),
            errorStack.leadingAnchor.constraint(equalTo: errorCard.leadingAnchor, constant: 14),
            errorStack.trailingAnchor.constraint(equalTo: errorCard.trailingAnchor, constant: -14),
            errorStack.bottomAnchor.constraint(equalTo: errorCard.bottomAnchor, constant: -12),
            retryButton.heightAnchor.constraint(equalToConstant: 44),
            accessButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        retryButton.isHidden = true
        accessButton.isHidden = true

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = AppColors.accent
        spinner.hidesWhenStopped = true
        addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        feedbackLabel.translatesAutoresizingMaskIntoConstraints = false
        feedbackLabel.backgroundColor = UIColor(white: 0.05, alpha: 0.78)
        feedbackLabel.layer.cornerRadius = 22
        feedbackLabel.layer.cornerCurve = .continuous
        feedbackLabel.clipsToBounds = true
        feedbackLabel.alpha = 0
        feedbackLabel.isUserInteractionEnabled = false
        addSubview(feedbackLabel)
        NSLayoutConstraint.activate([
            feedbackLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            feedbackLabel.topAnchor.constraint(equalTo: centerYAnchor, constant: 64),
            feedbackLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -48),
            feedbackLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
    }

    private func styleLink(_ button: UIButton) {
        button.setTitleColor(AppColors.accent, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        button.contentHorizontalAlignment = .leading
    }

    /// Let taps reach the video underneath; only the chrome's own controls take touches.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)
        return result === self ? nil : result
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let layer = topBar.layer.sublayers?.first(where: { $0.name == "topGradient" }) {
            layer.frame = topBar.bounds
        }
        if let layer = bottomBar.layer.sublayers?.first(where: { $0.name == "bottomGradient" }) {
            layer.frame = bottomBar.bounds
        }
    }

    // MARK: - Actions

    @objc private func tapToggle() { actions.toggle() }
    @objc private func tapEpisodes() { actions.episodes() }
    @objc private func tapRetry() { actions.retry() }
    @objc private func tapAccess() { actions.access() }
    @objc private func showOptions(_ sender: UIView) { actions.options(sender) }

    @objc private func holdHeart(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { actions.removeFavorite() }
    }

    // MARK: - State

    func setEpisode(current: Int, total: Int) {
        guard current > 0, total > 0 else {
            runningEpisode.text = ""
            episodeButton.setTitle("Episodes", for: .normal)
            return
        }
        let text = NSMutableAttributedString(string: "EP\(current)", attributes: [.font: UIFont.systemFont(ofSize: 13, weight: .bold), .foregroundColor: AppColors.text])
        text.append(NSAttributedString(string: " / EP\(total)", attributes: [.font: UIFont.systemFont(ofSize: 13, weight: .regular), .foregroundColor: AppColors.muted]))
        runningEpisode.attributedText = text
        runningEpisode.accessibilityLabel = "Episode \(current) of \(total)"
        episodeButton.setTitle("  EP\(current) / EP\(total)", for: .normal)
    }

    func showControls(_ visible: Bool) {
        controlsVisible = visible
        let alpha: CGFloat = visible ? 1 : 0
        UIView.animate(withDuration: 0.18) {
            self.topBar.alpha = alpha
            self.rail.alpha = alpha
            self.bottomBar.alpha = alpha
            self.playPause.alpha = alpha
        }
        topBar.isUserInteractionEnabled = visible
        rail.isUserInteractionEnabled = visible
        bottomBar.isUserInteractionEnabled = visible
        playPause.isUserInteractionEnabled = visible
    }

    func showStatus(_ message: String, retry: Bool = false, access: Bool = false) {
        status.text = message
        errorCard.isHidden = message.isEmpty
        retryButton.isHidden = !retry
        accessButton.isHidden = !access
    }

    func setPlayback(playing: Bool, enabled: Bool) {
        playPause.setImage(UIImage(systemName: playing ? "pause.fill" : "play.fill",
                                   withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .bold)), for: .normal)
        playPause.accessibilityLabel = playing ? "Pause video" : "Play video"
        playPause.isEnabled = enabled
        playPause.alpha = enabled ? 1 : 0.4
    }

    func setFavorite(_ saved: Bool) {
        favoriteAction.setSymbol(saved ? "heart.fill" : "heart")
        favoriteAction.control.tintColor = saved ? AppColors.heart : AppColors.text
        favoriteAction.setTitle(saved ? "Saved" : "Favorite")
        favoriteAction.control.accessibilityLabel = saved ? "Remove from favorites" : "Add to favorites"
    }

    func setSpeed(_ value: Float) {
        speedAction.setTitle(value == 1 ? "Speed" : String(format: "%.2g×", value))
    }

    func showSeeking(_ visible: Bool) {
        if visible {
            topBar.alpha = 0
            rail.alpha = 0
            playPause.alpha = 0
        } else {
            UIView.animate(withDuration: 0.15) {
                self.topBar.alpha = self.controlsVisible ? 1 : 0
                self.rail.alpha = self.controlsVisible ? 1 : 0
                self.playPause.alpha = self.controlsVisible ? 1 : 0
            }
        }
    }

    func feedback(_ message: String, persistent: Bool = false) {
        feedbackWork?.cancel()
        feedbackLabel.text = "  \(message)  "
        UIView.animate(withDuration: 0.15) { self.feedbackLabel.alpha = 1 }
        guard !persistent else { return }
        let work = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: 0.2) { self?.feedbackLabel.alpha = 0 }
        }
        feedbackWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    func clearFeedback() {
        feedbackWork?.cancel()
        feedbackLabel.alpha = 0
    }

    func setBusy(_ busy: Bool) {
        if busy { spinner.startAnimating() } else { spinner.stopAnimating() }
    }

    func pip(hidden: Bool) {
        isHidden = hidden
    }
}
