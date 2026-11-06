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
    private let outlookCard = CardView()
    private let outlookStack = UIStackView()
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

        windowCard.content.addArrangedSubview(Labels.title("Peak / off-peak window (UTC)"))
        timelineView.translatesAutoresizingMaskIntoConstraints = false
        timelineView.heightAnchor.constraint(equalToConstant: 78).isActive = true
        windowCard.content.addArrangedSubview(timelineView)

        let legend = UIStackView(arrangedSubviews: [
            legendItem(title: "Peak (standard price)", color: AppColors.peak),
            legendItem(title: "Off-peak (discount)", color: AppColors.offPeak),
            legendItem(title: "Standard only", color: AppColors.textDim)
        ])
        legend.axis = .horizontal
        legend.spacing = 12
        legend.distribution = .fillProportionally
        windowCard.content.addArrangedSubview(legend)
        windowCard.content.addArrangedSubview(windowCaption)
        contentStack.addArrangedSubview(windowCard)

        outlookCard.content.addArrangedSubview(Labels.title("Next 7 days (UTC)"))
        outlookStack.axis = .vertical
        outlookStack.spacing = 8
        outlookCard.content.addArrangedSubview(outlookStack)
        contentStack.addArrangedSubview(outlookCard)

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

        let footer = Labels.caption("Version \(appVersion). Schedule and prices are stored on this iPhone and are not downloaded; they were verified by hand on \(RateSeeds.verifiedAsOf). Balance is read from api.deepseek.com/user/balance with your own API key.")
        contentStack.addArrangedSubview(footer)
    }

    private func legendItem(title: String, color: UIColor) -> UIView {
        let dot = UIView()
        dot.backgroundColor = color
        dot.layer.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 8).isActive = true

        let label = UILabel()
        label.text = title
        label.font = Typography.scaled(10, .semibold, style: .caption2)
        label.textColor = AppColors.textDim
        label.numberOfLines = 2

        let stack = UIStackView(arrangedSubviews: [dot, label])
        stack.axis = .horizontal
        stack.spacing = 5
        stack.alignment = .center
        return stack
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0.1"
        let build = info?["CFBundleVersion"] as? String ?? "2"
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
        let schedule = store.schedule
        let state = schedule.state(at: now)

        widgetCard.apply(makeWidgetContent(at: now))
        timelineView.segments = schedule.segments(for: now)
        timelineView.nowSeconds = PricingSchedule.secondsOfDayUTC(now)
        windowCaption.text = makeScheduleCaption(schedule: schedule, models: store.models, now: now)
        rebuildOutlook(schedule: schedule, now: now)

        let modelSignature = store.models.map {
            "\($0.id):\($0.label):\($0.standard.cacheHit):\($0.standard.cacheMiss):\($0.standard.output):\($0.offPeakDiscountPercent)"
        }.joined(separator: ",")
        let signature = "\(state.rawValue)|\(schedule.discountsEnabled)|\(modelSignature)"
        if signature != lastRateSignature {
            lastRateSignature = signature
            ratesTable.update(models: store.models,
                              offPeakActive: state == .offPeak,
                              discountEnabled: schedule.discountsEnabled)
            ratesCaption.text = makeRatesCaption(schedule: schedule, state: state, store: store)
        }
    }

    private func makeWidgetContent(at now: Date) -> WidgetContent {
        let store = SettingsStore.shared
        let schedule = store.schedule
        let state = schedule.state(at: now)
        let snapshot = store.cachedSnapshot

        var content = WidgetContent()
        content.hasKey = store.hasAPIKey
        content.stateText = state.label
        switch state {
        case .peak: content.stateColor = AppColors.peak
        case .offPeak: content.stateColor = AppColors.offPeak
        case .standard: content.stateColor = AppColors.textDim
        }

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

        content.detailLine = countdownLine(schedule: schedule, now: now)
        content.noteLine = notesLine(schedule: schedule, store: store, now: now)
        content.clockLine = "Now \(ClockFormat.utcTimeLabel(now)) · \(ClockFormat.localTimeLabel(now)) local"
        return content
    }

    private func countdownLine(schedule: PricingSchedule, now: Date) -> String {
        guard schedule.discountsEnabled else {
            return "Off-peak discounts are switched off — standard price applies around the clock."
        }
        guard let next = schedule.nextTransition(after: now) else {
            return "No peak window is configured, so every hour is off-peak."
        }
        let seconds = max(0, Int(next.date.timeIntervalSince(now).rounded()))
        let what = next.becomesPeak ? "Peak starts" : "Off-peak starts"
        let dayTag = next.daysAhead == 0 ? "today" : (next.daysAhead == 1 ? "tomorrow" : "in \(next.daysAhead) days")
        return "\(what) \(ClockFormat.utcStamp(next.date)) (\(ClockFormat.localStamp(next.date)) local · \(dayTag)) — in \(ClockFormat.countdown(seconds: seconds))"
    }

    private func notesLine(schedule: PricingSchedule, store: SettingsStore, now: Date) -> String {
        var notes: [String] = []
        let outsideCheckedRange = schedule.holidays.coverageStart != nil
        let reason = outsideCheckedRange ? "outside the checked holiday range" : "holiday calendar not on file"

        if schedule.isUncertain(at: now) {
            notes.append("Weekday peaks assume no PRC public holiday today (\(reason)).")
        } else if let next = schedule.nextTransition(after: now), next.uncertain {
            notes.append("Countdown assumes \(PricingSchedule.dayKey(next.date)) is not a PRC public holiday (\(reason)).")
        }
        if store.scheduleIsCustom {
            notes.append("Custom schedule — the official windows were verified \(RateSeeds.verifiedAsOf).")
        }
        return notes.joined(separator: " ")
    }

    private func makeScheduleCaption(schedule: PricingSchedule, models: [ModelRate], now: Date) -> String {
        guard schedule.discountsEnabled else {
            return "Off-peak discounts are switched off, so one standard price applies around the clock. Holiday data: \(schedule.holidays.summary)."
        }
        let discounts = models.map { "\($0.name) \(Int($0.clampedDiscount.rounded()))%" }.joined(separator: " · ")
        var parts: [String] = [
            "Peak \(schedule.weekdaySummary) \(schedule.intervalSummaryUTC)",
            "your local time \(schedule.intervalSummaryLocal(on: now))",
            "off-peak \(discounts) off"
        ]
        let day = schedule.daySchedule(for: now)
        if day.kind == .holiday {
            parts.append("today is a listed PRC public holiday → off-peak all day")
        } else if day.intervals.isEmpty {
            parts.append("today has no peak window → off-peak all day")
        }
        parts.append("holidays: \(schedule.holidays.summary)")
        return parts.joined(separator: " · ")
    }

    private func makeRatesCaption(schedule: PricingSchedule, state: PricingState, store: SettingsStore) -> String {
        var text: String
        switch state {
        case .offPeak: text = "Off-peak prices are active now, so the OFF-PEAK column is highlighted."
        case .peak: text = "Peak (standard) prices are active now, so the PEAK column is highlighted."
        case .standard: text = "The off-peak column is inactive because the discount schedule is switched off."
        }
        if store.ratesAreCustom {
            text += " These rates are your custom values, not the verified defaults."
        } else {
            text += " Verified by hand on \(RateSeeds.verifiedAsOf); the app does not download prices."
        }
        text += " Source: \(schedule.sourceURL)"
        return text
    }

    private func rebuildOutlook(schedule: PricingSchedule, now: Date) {
        for view in outlookStack.arrangedSubviews {
            outlookStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for (offset, day) in schedule.outlook(from: now, days: 7).enumerated() {
            outlookStack.addArrangedSubview(outlookRow(day: day, offset: offset, schedule: schedule, now: now))
        }
    }

    private func outlookRow(day: DaySchedule, offset: Int, schedule: PricingSchedule, now: Date) -> UIView {
        let dayLabel = UILabel()
        let date = PricingSchedule.date(fromDayKey: day.key) ?? now
        dayLabel.text = ClockFormat.utcDayLabel(date) + (offset == 0 ? " · today" : "")
        dayLabel.font = Typography.scaled(12, .semibold, style: .footnote)
        dayLabel.textColor = AppColors.text
        dayLabel.widthAnchor.constraint(equalToConstant: 108).isActive = true

        let detail = UILabel()
        detail.font = Typography.scaled(11.5, .medium, style: .caption1)
        detail.numberOfLines = 0
        if !schedule.discountsEnabled {
            detail.text = "standard all day"
            detail.textColor = AppColors.textDim
        } else if day.intervals.isEmpty {
            detail.text = day.kind == .holiday ? "PRC public holiday · off-peak" : "off-peak all day"
            detail.textColor = day.kind == .holiday ? AppColors.offPeak : AppColors.textDim
        } else {
            let windows = day.intervals.map { $0.utcLabel }.joined(separator: ", ")
            detail.text = windows + " UTC" + (day.kind == .unverified ? " · unverified" : "")
            detail.textColor = AppColors.peak
        }

        let row = UIStackView(arrangedSubviews: [dayLabel, detail])
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .firstBaseline
        return row
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
        let target = URL(string: SettingsStore.shared.schedule.sourceURL)
            ?? URL(string: "https://api-docs.deepseek.com/quick_start/pricing/")
        guard let url = target else { return }
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
