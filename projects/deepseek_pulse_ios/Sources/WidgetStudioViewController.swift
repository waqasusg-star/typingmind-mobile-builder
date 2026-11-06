import UIKit

/// Widget Studio.
///
/// Renders the widget-sized layouts with the live saved schedule, and states plainly which parts of
/// a Home-Screen widget this build contains and which need a WidgetKit extension target in Xcode.
final class WidgetStudioViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let fullCard = WidgetFullCardView(frame: .zero)
    private let compactCard = WidgetCompactCardView(frame: .zero)
    private let lockCard = WidgetLockScreenCardView(frame: .zero)
    private let liveCard = LiveActivityCardView(frame: .zero)
    private let statusLabel = Labels.caption("")

    var onRequestRefresh: (() -> Void)?

    private var timer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Widgets & Live Activity"
        view.backgroundColor = AppColors.background
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Close", style: .plain, target: self, action: #selector(closeTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(closeTapped))
        buildLayout()
        render()
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
        intro.content.addArrangedSubview(Labels.title("Widget previews"))
        intro.content.addArrangedSubview(Labels.caption("These are the widget layouts in this build, drawn with your saved schedule. WidgetPlanner supplies the state, the countdown and the next switch, so the app, these previews and the Live Activity card always agree."))
        stack.addArrangedSubview(intro)

        stack.addArrangedSubview(titledCard(title: "Home Screen · medium", caption: "Full schedule card with the 24-hour band.", content: fullCard, height: 190))
        stack.addArrangedSubview(titledCard(title: "Home Screen · small", caption: "State and countdown only.", content: compactCard, height: 150))
        stack.addArrangedSubview(titledCard(title: "Lock Screen", caption: "Single-line state and countdown.", content: lockCard, height: 92))
        stack.addArrangedSubview(titledCard(title: "Dynamic Island / Live Activity", caption: "Expanding card used by the ActivityKit layout.", content: liveCard, height: 132))

        let policy = CardView()
        policy.content.addArrangedSubview(Labels.title("Refresh policy"))
        policy.content.addArrangedSubview(Labels.caption("A refresh is requested just after the next peak/off-peak switch and never more than once a minute from the app. iOS itself limits widget refreshes (about 15 minutes, 60 in Low Power Mode), and the deep link deepseekpulse://status opens this screen."))
        stack.addArrangedSubview(policy)

        let extensionCard = CardView()
        extensionCard.content.addArrangedSubview(Labels.title("What is still missing for the Home Screen"))
        extensionCard.content.addArrangedSubview(Labels.caption("A Home-Screen or Lock-Screen widget and a Dynamic Island Live Activity must run in their own WidgetKit / ActivityKit extension targets with their own Info.plist and entitlements, plus an App Group for the shared schedule. This build cannot package those extra targets, so the layouts live in the app and are shown here. Open the delivered source in Xcode, add a Widget Extension target that reuses WidgetPlanner and the widget views, sign it with your team and install."))
        stack.addArrangedSubview(extensionCard)

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
