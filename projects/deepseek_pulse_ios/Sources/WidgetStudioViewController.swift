import UIKit

/// Widget Studio.
///
/// Renders the widget-sized layouts with the live saved schedule, writes the shared widget
/// snapshot, and states exactly how to add the real Home Screen / Lock Screen widget.
final class WidgetStudioViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let fullCard = WidgetFullCardView(frame: .zero)
    private let compactCard = WidgetCompactCardView(frame: .zero)
    private let lockCard = WidgetLockScreenCardView(frame: .zero)
    private let liveCard = LiveActivityCardView(frame: .zero)
    private let statusLabel = Labels.caption("")
    private let bridgeLabel = Labels.caption("")

    var onRequestRefresh: (() -> Void)?

    private var timer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Widgets"
        view.backgroundColor = AppColors.background
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Close", style: .plain, target: self, action: #selector(closeTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(closeTapped))
        buildLayout()
        render()
        writeSnapshot()
        startClock()
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

        let addSteps = CardView()
        addSteps.content.addArrangedSubview(Labels.title("Add the widget"))
        addSteps.content.addArrangedSubview(Labels.caption("1. Open this app once so it saves your balance and schedule for the widget."))
        addSteps.content.addArrangedSubview(Labels.caption("2. Go to the Home Screen, touch and hold an empty area, then tap Edit or the + button."))
        addSteps.content.addArrangedSubview(Labels.caption("3. Search for DeepSeek Pulse, pick the small or medium size, then tap Add Widget."))
        addSteps.content.addArrangedSubview(Labels.caption("For the Lock Screen, use Edit Lock Screen, then add a widget and choose DeepSeek Pulse. Lock Screen widgets need iOS 16 or later; the app itself runs on iOS 15."))
        stack.addArrangedSubview(addSteps)

        stack.addArrangedSubview(titledCard(title: "Home Screen · medium", caption: "Full schedule card with the 24-hour band.", content: fullCard, height: 190))
        stack.addArrangedSubview(titledCard(title: "Home Screen · small", caption: "State and countdown only.", content: compactCard, height: 150))
        stack.addArrangedSubview(titledCard(title: "Lock Screen", caption: "Single-line state and countdown.", content: lockCard, height: 92))
        stack.addArrangedSubview(titledCard(title: "In-app card", caption: "Same data as the expanded widget layout. This is not a Dynamic Island Live Activity.", content: liveCard, height: 132))
        let policy = CardView()
        policy.content.addArrangedSubview(Labels.title("Refresh policy"))
        policy.content.addArrangedSubview(Labels.caption("The countdown and the peak/off-peak badge are drawn by iOS itself, so they keep changing while your phone is locked and without the app running. The app asks iOS to redraw the widget after a balance refresh or a settings change. iOS controls when that redraw happens and normally allows roughly one every 15 minutes, longer in Low Power Mode. The widget makes no network request and never reads your API key."))
        stack.addArrangedSubview(policy)

        let shared = CardView()
        shared.content.addArrangedSubview(Labels.title("What the widget can read"))
        shared.content.addArrangedSubview(Labels.caption("The widget uses the App Group " + WidgetShared.appGroupIdentifier + " when the signed build provides it. This build also keeps its own copy inside the widget extension, so the schedule, the countdown and the last saved balance still appear when the App Group is not granted by the signer. Your API key stays in the iOS Keychain and is never copied into either copy."))
        shared.content.addArrangedSubview(bridgeLabel)
        stack.addArrangedSubview(shared)

        let limits = CardView()
        limits.content.addArrangedSubview(Labels.title("Signing requirement"))
        limits.content.addArrangedSubview(Labels.caption("The app bundle and the DeepSeekPulseWidgets extension must be signed together with the same team. If the signer grants the App Group to one bundle only, the widget still counts down from its own copy but shows your balance only after you open this app once more."))
        stack.addArrangedSubview(limits)

        stack.addArrangedSubview(statusLabel)
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
        bridgeLabel.text = WidgetRefreshHandoff.summary(for: result)
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

        fullCard.apply(snapshot: snapshot, schedule: schedule, now: now)
        compactCard.apply(snapshot: snapshot, schedule: schedule, now: now)
        lockCard.apply(snapshot: snapshot, schedule: schedule, now: now)
        liveCard.apply(snapshot: snapshot, schedule: schedule, now: now)

        var status = "State " + snapshot.state.label
        status += " · " + snapshot.dayKey + " (" + snapshot.weekdayLabel + ")"
        status += " · " + WidgetPlanner.peakLeftLabel(minutes: snapshot.peakMinutesLeftToday)
        if snapshot.uncertain {
            status += " · holiday calendar unverified for this day"
        }
        statusLabel.text = status
    }

    @objc private func closeTapped() {
        onRequestRefresh?()
        dismiss(animated: true)
    }
}
