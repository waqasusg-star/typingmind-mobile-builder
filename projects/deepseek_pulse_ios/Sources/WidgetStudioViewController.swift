import UIKit

/// Widget Studio.
///
/// Renders the widget-sized layouts with the live saved schedule, writes the shared widget
/// snapshot, and states exactly how to add the real Home Screen / Lock Screen widget.
///
/// 1.0.7 adds the theme entry point to this screen and makes the previews show the same theme and
/// design the widget will use, so the studio can no longer disagree with the Home Screen.
final class WidgetStudioViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let fullCard = WidgetFullCardView(frame: .zero)
    private let compactCard = WidgetCompactCardView(frame: .zero)
    private let lockCard = WidgetLockScreenCardView(frame: .zero)
    private let liveCard = LiveActivityCardView(frame: .zero)
    private let statusLabel = Labels.caption("")
    private let bridgeLabel = Labels.caption("")
    private let themeSummaryLabel = Labels.caption("")

    var onRequestRefresh: (() -> Void)?
    var onRequestThemes: (() -> Void)?

    private var timer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Widgets"
        view.backgroundColor = AppColors.background
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Close", style: .plain, target: self, action: #selector(closeTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Themes", style: .plain, target: self, action: #selector(themesTapped))
        buildLayout()
        render()
        writeSnapshot()
        startClock()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appearanceChanged),
                                               name: .deepSeekAppearanceChanged,
                                               object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        render()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        timer?.invalidate()
        timer = nil
    }

    private func buildLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -32)
        ])

        let intro = CardView()
        intro.content.addArrangedSubview(Labels.title("Real widget installed"))
        intro.content.addArrangedSubview(Labels.caption("This build contains the DeepSeekPulseWidgets extension. The cards below are in-app previews drawn from the same WidgetPlanner state as the real widget, so what you see here is what the Home Screen widget computes."))
        stack.addArrangedSubview(intro)

        let themeCard = CardView()
        themeCard.content.addArrangedSubview(Labels.title("Theme and design"))
        themeCard.content.addArrangedSubview(themeSummaryLabel)
        let themeButton = UIButton(type: .system)
        themeButton.setTitle("Choose theme and widget design", for: .normal)
        themeButton.titleLabel?.font = Typography.scaled(14, .semibold, style: .subheadline)
        themeButton.setTitleColor(AppColors.accentSoft, for: .normal)
        themeButton.contentHorizontalAlignment = .leading
        themeButton.addTarget(self, action: #selector(themesTapped), for: .touchUpInside)
        themeCard.content.addArrangedSubview(themeButton)
        stack.addArrangedSubview(themeCard)

        stack.addArrangedSubview(iconCard())

        let addSteps = CardView()
        addSteps.content.addArrangedSubview(Labels.title("Add the widget"))
        addSteps.content.addArrangedSubview(Labels.caption("1. Open this app once so it saves your balance and schedule for the widget."))
        addSteps.content.addArrangedSubview(Labels.caption("2. Go to the Home Screen, touch and hold an empty area, then tap Edit or the + button."))
        addSteps.content.addArrangedSubview(Labels.caption("3. Search for DeepSeek Pulse, pick the small or medium size, then tap Add Widget."))
        addSteps.content.addArrangedSubview(Labels.caption("For the Lock Screen, use Edit Lock Screen, then add a widget and choose DeepSeek Pulse. Lock Screen widgets need iOS 16 or later; the app itself runs on iOS 15."))
        stack.addArrangedSubview(addSteps)

        stack.addArrangedSubview(titledCard(title: "Home Screen · medium", caption: "Full schedule card with the 24-hour band.", content: fullCard, height: 190))
        stack.addArrangedSubview(titledCard(title: "Home Screen · small", caption: "State and countdown only.", content: compactCard, height: 150))
        stack.addArrangedSubview(titledCard(title: "Lock Screen", caption: "The redesigned accessory layout: state, live countdown and the switch time.", content: lockCard, height: 92))
        stack.addArrangedSubview(titledCard(title: "In-app card", caption: "Same data as the expanded widget layout. This is not a Dynamic Island Live Activity.", content: liveCard, height: 132))

        let policy = CardView()
        policy.content.addArrangedSubview(Labels.title("Refresh policy"))
        policy.content.addArrangedSubview(Labels.caption("The countdown and the peak/off-peak badge are drawn by iOS itself, so they keep changing while your phone is locked and without the app running. The app asks iOS to redraw the widget after a balance refresh or a settings change. iOS controls when that redraw happens and normally allows roughly one every 15 minutes, longer in Low Power Mode. The widget makes no network request and never reads your API key."))
        stack.addArrangedSubview(policy)

        let shared = CardView()
        shared.content.addArrangedSubview(Labels.title("What the widget can read"))
        shared.content.addArrangedSubview(Labels.caption("The widget uses the App Group " + WidgetShared.appGroupIdentifier + " when the signed build provides it. This build also writes the extension's own copy, so the schedule, the countdown, the theme and the last saved balance still appear when the App Group is not granted by the signer. Your API key stays in the iOS Keychain and is never copied into either copy."))
        shared.content.addArrangedSubview(bridgeLabel)
        stack.addArrangedSubview(shared)

        let limits = CardView()
        limits.content.addArrangedSubview(Labels.title("Signing requirement"))
        limits.content.addArrangedSubview(Labels.caption("The app bundle and the DeepSeekPulseWidgets extension must be signed together with the same team. If the signer grants the App Group to one bundle only, the widget still counts down and keeps the last saved balance and theme from its own copy."))
        stack.addArrangedSubview(limits)

        stack.addArrangedSubview(statusLabel)
    }

    /// Shows the mark this build carries and says plainly whether iOS received an icon asset.
    private func iconCard() -> UIView {
        let card = CardView()
        card.content.addArrangedSubview(Labels.title("App icon"))

        let icon = UIImageView(image: AppIcon.installedIcon(size: 120))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.layer.cornerRadius = 22
        icon.layer.cornerCurve = .continuous
        icon.clipsToBounds = true
        icon.widthAnchor.constraint(equalToConstant: 88).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 88).isActive = true

        let text = UIStackView()
        text.axis = .vertical
        text.spacing = 6
        text.addArrangedSubview(Labels.caption(AppIcon.shortStatus))
        text.addArrangedSubview(Labels.caption(AppIcon.statusLine))

        let row = UIStackView(arrangedSubviews: [icon, text])
        row.axis = .horizontal
        row.spacing = 14
        row.alignment = .center
        card.content.addArrangedSubview(row)
        return card
    }

    private func titledCard(title: String, caption: String, content: UIView, height: CGFloat) -> UIView {
        let card = CardView()
        card.content.addArrangedSubview(Labels.title(title))
        card.content.addArrangedSubview(Labels.caption(caption))
        content.translatesAutoresizingMaskIntoConstraints = false
        content.heightAnchor.constraint(equalToConstant: height).isActive = true
        card.content.addArrangedSubview(content)
        return card
    }

    private func startClock() {
        timer?.invalidate()
        let clock = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.render()
        }
        clock.tolerance = 0.2
        RunLoop.main.add(clock, forMode: .common)
        timer = clock
    }

    /// Writes the shared snapshot when the screen opens, so the widget is not left empty.
    private func writeSnapshot() {
        let result = WidgetBridge.refresh(store: SettingsStore.shared)
        bridgeLabel.text = WidgetRefreshHandoff.summary(for: result.outcome)
        bridgeLabel.textColor = result.isWritten ? AppColors.offPeak : AppColors.danger
        // WidgetKit gives no completion callback: ask again once shortly after, in case the first
        // request was coalesced with a redraw iOS was already doing.
        DispatchQueue.main.asyncAfter(deadline: .now() + WidgetRefreshHandoff.expectedRefreshDelay) { [weak self] in
            guard let self = self, self.view.window != nil else { return }
            WidgetRefreshHandoff.requestRedraw()
        }
    }

    private func render() {
        let store = SettingsStore.shared
        let now = Date()
        let schedule = store.schedule
        let snapshot = WidgetPlanner.snapshot(schedule: schedule, at: now)
        let appearance = store.widgetAppearance.normalised()

        view.backgroundColor = AppColors.background
        fullCard.apply(snapshot: snapshot, schedule: schedule, now: now, appearance: appearance)
        compactCard.apply(snapshot: snapshot, schedule: schedule, now: now, appearance: appearance)
        lockCard.apply(snapshot: snapshot, schedule: schedule, now: now)
        liveCard.apply(snapshot: snapshot, schedule: schedule, now: now)

        themeSummaryLabel.text = "Theme " + appearance.theme.name + " · small " + appearance.smallDesign.title
            + " · medium " + appearance.mediumDesign.title
        themeSummaryLabel.textColor = AppColors.textDim

        var status = "State " + snapshot.state.label
        status += " · " + snapshot.dayKey + " (" + snapshot.weekdayLabel + ")"
        status += " · " + WidgetPlanner.peakLeftLabel(minutes: snapshot.peakMinutesLeftToday)
        if snapshot.uncertain {
            status += " · holiday calendar unverified for this day"
        }
        statusLabel.text = status
    }

    @objc private func appearanceChanged() {
        render()
    }

    @objc private func themesTapped() {
        onRequestThemes?()
    }

    @objc private func closeTapped() {
        onRequestRefresh?()
        dismiss(animated: true)
    }
}
