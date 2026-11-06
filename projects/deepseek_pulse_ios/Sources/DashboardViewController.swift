import UIKit

final class DashboardViewController: UIViewController {

    private enum MessageTone {
        case neutral
        case warning
    }

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let widgetCard = WidgetCardView()
    private let windowCard = CardView()
    private let timelineView = DayTimelineView()
    private let windowCaption = Labels.caption("")
    private let ratesCard = CardView()
    private let ratesTable = RateTableView()
    private let ratesCaption = Labels.caption("")
    private let messageCard = CardView()
    private let messageLabel = Labels.body("")
    private let refreshControl = UIRefreshControl()
    private let pricingButton = UIButton(type: .system)
    private let client = DeepSeekClient()

    private var timer: Timer?
    private var isLoading = false
    private var lastRateSignature = ""

    private lazy var refreshItem = UIBarButtonItem(image: UIImage(systemName: "arrow.clockwise"),
                                                   style: .plain,
                                                   target: self,
                                                   action: #selector(refreshTapped))
    private lazy var settingsItem = UIBarButtonItem(image: UIImage(systemName: "gearshape"),
                                                    style: .plain,
                                                    target: self,
                                                    action: #selector(settingsTapped))

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "DeepSeek Pulse"
        view.backgroundColor = AppColors.background
        navigationItem.rightBarButtonItems = [settingsItem, refreshItem]
        buildLayout()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(settingsChanged),
                                               name: .deepSeekSettingsChanged,
                                               object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startClock()
        render()
        autoRefreshIfStale()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Layout

    private func buildLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.refreshControl = refreshControl
        refreshControl.tintColor = AppColors.textDim
        refreshControl.addTarget(self, action: #selector(refreshTapped), for: .valueChanged)
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 18),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -18),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28)
        ])

        messageCard.isHidden = true
        messageCard.content.addArrangedSubview(messageLabel)
        contentStack.addArrangedSubview(messageCard)

        contentStack.addArrangedSubview(widgetCard)

        windowCard.content.addArrangedSubview(Labels.title("Peak / off-peak window"))
        timelineView.translatesAutoresizingMaskIntoConstraints = false
        timelineView.heightAnchor.constraint(equalToConstant: 78).isActive = true
        windowCard.content.addArrangedSubview(timelineView)
        windowCard.content.addArrangedSubview(windowCaption)
        contentStack.addArrangedSubview(windowCard)

        ratesCard.content.addArrangedSubview(Labels.title("Rates per 1M tokens"))
        ratesCard.content.addArrangedSubview(ratesTable)
        ratesCard.content.addArrangedSubview(ratesCaption)
        contentStack.addArrangedSubview(ratesCard)

        pricingButton.setTitle("Open official DeepSeek pricing page", for: .normal)
        pricingButton.titleLabel?.font = Typography.scaled(14, .semibold, style: .subheadline)
        pricingButton.setTitleColor(AppColors.accentSoft, for: .normal)
        pricingButton.contentHorizontalAlignment = .leading
        pricingButton.addTarget(self, action: #selector(openPricingPage), for: .touchUpInside)
        contentStack.addArrangedSubview(pricingButton)

        let footer = Labels.caption("Version \(appVersion). Rates and the off-peak window are stored on this iPhone and can be edited in Settings. Balance is read from api.deepseek.com/user/balance with your own API key.")
        contentStack.addArrangedSubview(footer)
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: - Clock

    private func startClock() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.render()
        }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - Rendering

    private func render() {
        let store = SettingsStore.shared
        let now = Date()
        let window = store.window
        let offPeak = window.isOffPeak(at: now)

        widgetCard.apply(makeWidgetContent(at: now))

        timelineView.window = window
        timelineView.nowSeconds = PeakWindow.secondsOfDayUTC(now)
        windowCaption.text = makeWindowCaption(window: window, models: store.models)

        let signature = "\(window.discountEnabled)|\(window.startMinuteUTC)|\(window.endMinuteUTC)|\(offPeak)|" + store.models.map { model in
            "\(model.id):\(model.standard.cacheHit):\(model.standard.cacheMiss):\(model.standard.output):\(model.offPeakDiscountPercent)"
        }.joined(separator: ",")
        if signature != lastRateSignature {
            lastRateSignature = signature
            ratesTable.update(models: store.models, offPeakActive: offPeak, discountEnabled: window.isActive)
            ratesCaption.text = makeRatesCaption(window: window, offPeak: offPeak)
        }
    }

    private func makeWidgetContent(at now: Date) -> WidgetContent {
        let store = SettingsStore.shared
        let window = store.window
        let offPeak = window.isOffPeak(at: now)
        let snapshot = store.cachedSnapshot

        var content = WidgetContent()
        content.hasKey = store.hasAPIKey
        content.stateText = window.stateLabel(at: now)
        content.stateColor = window.isActive ? (offPeak ? AppColors.offPeak : AppColors.peak) : AppColors.textDim

        if let info = snapshot?.primary {
            content.totalAmount = MoneyFormat.amount(info.totalBalance, currency: info.currency)
            content.currencyCode = info.currency
            content.granted = MoneyFormat.amount(info.grantedBalance, currency: info.currency)
            content.toppedUp = MoneyFormat.amount(info.toppedUpBalance, currency: info.currency)
            let available = snapshot?.isAvailable ?? false
            content.availabilityText = available
                ? "\(info.currency) · available for API calls"
                : "\(info.currency) · account not available — check balance and plan"
            content.availabilityColor = available ? AppColors.offPeak : AppColors.danger
            content.updatedLine = snapshot.map { "Balance updated " + ClockFormat.relative($0.fetchedAt, now: now) } ?? ""
        } else if store.hasAPIKey {
            content.totalAmount = "—"
            content.availabilityText = "Pull to refresh to load your balance."
            content.availabilityColor = AppColors.textDim
            content.updatedLine = "No balance loaded yet"
        } else {
            content.totalAmount = "—"
            content.availabilityText = "Add your DeepSeek API key in Settings to show your account balance."
            content.availabilityColor = UIColor.white.withAlphaComponent(0.8)
            content.updatedLine = "Key stored in the iOS Keychain"
        }

        content.detailLine = scheduleLine(window: window, offPeak: offPeak, now: now)
        content.clockLine = "Now \(ClockFormat.utcTimeLabel(now)) · \(ClockFormat.localTimeLabel(now)) local"
        return content
    }

    private func scheduleLine(window: PeakWindow, offPeak: Bool, now: Date) -> String {
        guard window.isActive else {
            return "Off-peak discount schedule is switched off — standard rates apply all day."
        }
        guard let next = window.nextTransition(after: now) else {
            return "Off-peak \(ClockFormat.minuteLabel(window.startMinuteUTC))–\(ClockFormat.minuteLabel(window.endMinuteUTC)) UTC"
        }
        let targetMinute = next.becomesOffPeak ? window.startMinuteUTC : window.endMinuteUTC
        let seconds = max(0, Int(next.date.timeIntervalSince(now).rounded()))
        let localTarget = ClockFormat.localLabel(minuteUTC: targetMinute, on: now)
        let prefix = next.becomesOffPeak ? "Off-peak starts" : "Off-peak ends"
        return "\(prefix) \(ClockFormat.minuteLabel(targetMinute)) UTC (\(localTarget) local) · in \(ClockFormat.countdown(seconds: seconds))"
    }

    private func makeWindowCaption(window: PeakWindow, models: [ModelRate]) -> String {
        guard window.isActive else {
            return "Standard (peak) pricing is used at all hours. Turn the schedule back on in Settings if DeepSeek publishes off-peak discounts again."
        }
        let startLocal = ClockFormat.localLabel(minuteUTC: window.startMinuteUTC)
        let endLocal = ClockFormat.localLabel(minuteUTC: window.endMinuteUTC)
        let discounts = models.map { "\($0.name) \(Int($0.clampedDiscount.rounded()))%" }.joined(separator: " · ")
        return "Off-peak \(ClockFormat.minuteLabel(window.startMinuteUTC))–\(ClockFormat.minuteLabel(window.endMinuteUTC)) UTC (\(startLocal)–\(endLocal) local). Discounts: \(discounts)."
    }

    private func makeRatesCaption(window: PeakWindow, offPeak: Bool) -> String {
        var text = offPeak
            ? "Off-peak prices are active now, so the OFF-PEAK column is highlighted."
            : "Standard peak prices apply now, so the PEAK column is highlighted."
        if !window.isActive {
            text = "The off-peak column is inactive because the discount schedule is switched off."
        }
        return text + " " + RateSeeds.sourceNote + "."
    }

    // MARK: - Actions

    @objc private func refreshTapped() {
        refresh(force: true)
    }

    @objc private func settingsTapped() {
        let controller = SettingsViewController()
        controller.onSaved = { [weak self] in
            guard let self = self else { return }
            self.lastRateSignature = ""
            self.render()
            self.refresh(force: true)
        }
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .formSheet
        present(navigation, animated: true)
    }

    @objc private func settingsChanged() {
        lastRateSignature = ""
        render()
    }

    @objc private func openPricingPage() {
        guard let url = URL(string: "https://api-docs.deepseek.com/quick_start/pricing") else { return }
        UIApplication.shared.open(url)
    }

    private func autoRefreshIfStale() {
        let store = SettingsStore.shared
        guard store.hasAPIKey else {
            showMessage("Add your DeepSeek API key in Settings to load your account balance.", tone: .neutral)
            return
        }
        if let snapshot = store.cachedSnapshot, Date().timeIntervalSince(snapshot.fetchedAt) < 120 {
            showMessage(nil, tone: .neutral)
            return
        }
        refresh(force: false)
    }

    private func refresh(force: Bool) {
        guard !isLoading else { return }
        let key = SettingsStore.shared.apiKey
        guard !key.isEmpty else {
            showMessage("Add your DeepSeek API key in Settings to load your account balance.", tone: .neutral)
            refreshControl.endRefreshing()
            return
        }

        isLoading = true
        showMessage("Contacting api.deepseek.com…", tone: .neutral)
        client.fetchBalance(apiKey: key) { [weak self] result in
            guard let self = self else { return }
            self.isLoading = false
            self.refreshControl.endRefreshing()
            switch result {
            case .success(let snapshot):
                SettingsStore.shared.cachedSnapshot = snapshot
                self.showMessage(nil, tone: .neutral)
            case .failure(let error):
                self.showMessage(error.message, tone: .warning)
            }
            self.render()
        }
    }

    private func showMessage(_ text: String?, tone: MessageTone) {
        guard let text = text, !text.isEmpty else {
            messageCard.isHidden = true
            return
        }
        messageLabel.text = text
        messageLabel.textColor = tone == .warning ? AppColors.danger : AppColors.textDim
        messageCard.isHidden = false
    }
}
