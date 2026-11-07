import UIKit

final class DashboardViewController: UIViewController {

    private enum MessageTone {
        case neutral
        case warning
    }

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let widgetCard = WidgetCardView(frame: .zero)
    private let windowCard = CardView()
    private let timelineView = DayTimelineView(frame: .zero)
    private let windowCaption = Labels.caption("")
    private let outlookCard = CardView()
    private let outlookStack = UIStackView()
    private let ratesCard = CardView()
    private let ratesTable = RateTableView(frame: .zero)
    private let ratesCaption = Labels.caption("")
    private let messageCard = CardView()
    private let messageLabel = Labels.body("")
    private let refreshControl = UIRefreshControl()
    private let pricingButton = UIButton(type: .system)
    private let client = DeepSeekClient()
    private let actionsBar = ToolbarActionsView()

    private var timer: Timer?
    private var isLoading = false
    private var lastRateSignature = ""
    /// True while a balance load is answering a request that came from the widget.
    private var pendingWidgetAnswer = false

    private lazy var refreshItem = UIBarButtonItem(image: UIImage(systemName: "arrow.clockwise"),
                                                   style: .plain,
                                                   target: self,
                                                   action: #selector(refreshTapped))
    private lazy var settingsItem = UIBarButtonItem(menu: UIMenu(title: "Options", children: [
        UIAction(title: "Settings", image: UIImage(systemName: "gearshape")) { [weak self] _ in
            self?.settingsTapped()
        },
        UIAction(title: "Themes", image: UIImage(systemName: "paintpalette")) { [weak self] _ in
            self?.themesTapped()
        },
        UIAction(title: "Widgets & Live Activity", image: UIImage(systemName: "square.grid.2x2")) { [weak self] _ in
            self?.widgetStudioTapped()
        }
    ]))

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
        // 1.0.7: without this the app never repainted after a theme was applied.
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appearanceChanged),
                                               name: .deepSeekAppearanceChanged,
                                               object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyTheme()
        ThemedBackgroundInstaller.install(in: self)
        startClock()
        render()
        autoRefreshIfStale()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        timer?.invalidate()
        timer = nil
    }

    /// 1.0.9: also repaints the themed backdrop, so switching theme changes the screen background
    /// and the artwork together with the card colours.
    ///
    /// It must NOT call AppThemeRefresh.refresh(): that reaches every window, which marks the root
    /// view for display and re-enters this method.
    private func applyTheme() {
        view.backgroundColor = AppColors.background
        ThemedBackgroundInstaller.install(in: self)
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

        // Settings, Themes, Widgets as always-visible buttons: the previous bar-button menu could not
        // be reached on a signed build, which left Settings impossible to open. 1.0.7 adds Themes to
        // the same row so the sixteen palettes are reachable in one tap.
        actionsBar.onSettings = { [weak self] in self?.settingsTapped() }
        actionsBar.onThemes = { [weak self] in self?.themesTapped() }
        actionsBar.onWidgets = { [weak self] in self?.widgetStudioTapped() }
        contentStack.addArrangedSubview(actionsBar)

        contentStack.addArrangedSubview(widgetCard)

        windowCard.content.addArrangedSubview(Labels.title("Peak / off-peak window (UTC)"))
        timelineView.translatesAutoresizingMaskIntoConstraints = false
        timelineView.heightAnchor.constraint(equalToConstant: 78).isActive = true
        windowCard.content.addArrangedSubview(timelineView)

        let legend = UIStackView(arrangedSubviews: [
            legendItem(title: "Peak", color: AppColors.peak),
            legendItem(title: "Off-peak", color: AppColors.offPeak),
            legendItem(title: "Standard", color: AppColors.textDim)
        ])
        legend.axis = .horizontal
        legend.spacing = 10
        legend.distribution = .fillEqually
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
        pricingButton.titleLabel?.font = Typography.scaled(14, UIFont.Weight.semibold, style: .subheadline)
        pricingButton.setTitleColor(AppColors.accentSoft, for: .normal)
        pricingButton.contentHorizontalAlignment = .leading
        pricingButton.addTarget(self, action: #selector(openPricingPage), for: .touchUpInside)
        contentStack.addArrangedSubview(pricingButton)

        let footer = Labels.caption("Version " + appVersion + ". Prices, the peak windows and the PRC holiday list are stored on this iPhone and are not downloaded; they were verified by hand on " + RateSeeds.verifiedAsOf + ". Balance is read from api.deepseek.com/user/balance with your own API key.")
        contentStack.addArrangedSubview(footer)
    }

    private func legendItem(title: String, color: UIColor) -> UIView {
        let dot = UIView(frame: .zero)
        dot.backgroundColor = color
        dot.layer.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 8).isActive = true

        let label = UILabel()
        label.text = title
        label.font = Typography.scaled(10, UIFont.Weight.semibold, style: .caption2)
        label.textColor = AppColors.textDim

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
        return version + " (" + build + ")"
    }

    // MARK: - Clock

    private func startClock() {
        timer?.invalidate()
        let clock = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.render()
        }
        clock.tolerance = 0.15
        RunLoop.main.add(clock, forMode: .common)
        timer = clock
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

        var signature = state.rawValue
        signature += "|" + String(schedule.discountsEnabled)
        for model in store.models {
            signature += "|" + model.id + ":" + model.label + ":" + String(model.standard.cacheHit)
                + ":" + String(model.standard.cacheMiss) + ":" + String(model.standard.output)
                + ":" + String(model.offPeakDiscountPercent)
        }
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
        if state == .peak {
            content.stateColor = AppColors.peak
        } else if state == .offPeak {
            content.stateColor = AppColors.offPeak
        } else {
            content.stateColor = AppColors.textDim
        }

        if let info = snapshot?.primary {
            content.totalAmount = MoneyFormat.amount(info.totalBalance, currency: info.currency)
            content.currencyCode = info.currency
            content.granted = MoneyFormat.amount(info.grantedBalance, currency: info.currency)
            content.toppedUp = MoneyFormat.amount(info.toppedUpBalance, currency: info.currency)
            let available = snapshot?.isAvailable ?? false
            if available {
                content.availabilityText = info.currency + " · available for API calls"
                content.availabilityColor = AppColors.offPeak
            } else {
                content.availabilityText = info.currency + " · account not available — check balance and plan"
                content.availabilityColor = AppColors.danger
            }
            if let snapshot = snapshot {
                content.updatedLine = "Balance updated " + ClockFormat.relative(snapshot.fetchedAt, now: now)
            }
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
        content.clockLine = "Now " + ClockFormat.utcTimeLabel(now) + " · " + ClockFormat.localTimeLabel(now) + " local"
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
        var what = "Off-peak starts"
        if next.becomesPeak { what = "Peak starts" }
        var dayTag = "in " + String(next.daysAhead) + " days"
        if next.daysAhead == 0 { dayTag = "today" }
        if next.daysAhead == 1 { dayTag = "tomorrow" }
        return what + " " + ClockFormat.utcStamp(next.date)
            + " (" + ClockFormat.localStamp(next.date) + " local · " + dayTag + ")"
            + " — in " + ClockFormat.countdown(seconds: seconds)
    }

    private func notesLine(schedule: PricingSchedule, store: SettingsStore, now: Date) -> String {
        var notes: [String] = []
        if schedule.isUncertain(at: now) {
            notes.append("Today is a weekday, so the peak windows assume no PRC public holiday (" + schedule.holidays.summary + ").")
        } else if let next = schedule.nextTransition(after: now) {
            if next.uncertain {
                notes.append("Countdown assumes " + PricingSchedule.dayKey(next.date) + " is not a PRC public holiday.")
            }
        }
        if let warning = schedule.calendarWarning(at: now) {
            notes.append(warning)
        }
        if store.scheduleIsCustom {
            notes.append("Custom schedule — the official windows were verified " + RateSeeds.verifiedAsOf + ".")
        }
        return notes.joined(separator: " ")
    }

    private func makeScheduleCaption(schedule: PricingSchedule, models: [ModelRate], now: Date) -> String {
        guard schedule.discountsEnabled else {
            return "Off-peak discounts are switched off, so one standard price applies around the clock. Holidays: " + schedule.holidays.summary + "."
        }
        var discounts: [String] = []
        for model in models {
            discounts.append(model.name + " " + String(Int(model.clampedDiscount.rounded())) + "%")
        }
        var parts: [String] = [
            "Peak " + schedule.weekdaySummary + " " + schedule.intervalSummaryUTC,
            "your local time " + schedule.intervalSummaryLocal(on: now),
            "off-peak " + discounts.joined(separator: " · ") + " off",
            "all weekends are off-peak"
        ]
        let day = schedule.daySchedule(for: now)
        if day.kind == .holiday {
            parts.append("today is a listed PRC public holiday → off-peak all day")
        } else if day.intervals.isEmpty {
            parts.append("today has no peak window → off-peak all day")
        }
        parts.append("holidays: " + schedule.holidays.summary)
        return parts.joined(separator: " · ")
    }

    private func makeRatesCaption(schedule: PricingSchedule, state: PricingState, store: SettingsStore) -> String {
        var text = "Peak (standard) prices are active now, so the PEAK column is highlighted."
        if state == .offPeak {
            text = "Off-peak prices are active now, so the OFF-PEAK column is highlighted."
        } else if state == .standard {
            text = "The off-peak column is inactive because the discount schedule is switched off."
        }
        if store.ratesAreCustom {
            text += " These rates are your custom values, not the verified defaults."
        } else {
            text += " Verified by hand on " + RateSeeds.verifiedAsOf + "; the app does not download prices."
        }
        text += " Source: " + schedule.sourceURL
        return text
    }

    private func rebuildOutlook(schedule: PricingSchedule, now: Date) {
        for view in outlookStack.arrangedSubviews {
            outlookStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let days = schedule.outlook(from: now, days: 7)
        var offset = 0
        for day in days {
            outlookStack.addArrangedSubview(outlookRow(day: day, offset: offset, schedule: schedule, now: now))
            offset += 1
        }
    }

    private func outlookRow(day: DaySchedule, offset: Int, schedule: PricingSchedule, now: Date) -> UIView {
        let dayLabel = UILabel()
        let date = PricingSchedule.date(fromDayKey: day.key) ?? now
        var label = ClockFormat.utcDayLabel(date)
        if offset == 0 { label += " · today" }
        dayLabel.text = label
        dayLabel.font = Typography.scaled(12, UIFont.Weight.semibold, style: .footnote)
        dayLabel.textColor = AppColors.text
        dayLabel.widthAnchor.constraint(equalToConstant: 110).isActive = true

        let detail = UILabel()
        detail.font = Typography.scaled(11.5, UIFont.Weight.medium, style: .caption1)
        detail.numberOfLines = 0
        if !schedule.discountsEnabled {
            detail.text = "standard all day"
            detail.textColor = AppColors.textDim
        } else if day.intervals.isEmpty {
            if day.kind == .holiday {
                detail.text = "PRC public holiday · off-peak"
                detail.textColor = AppColors.offPeak
            } else {
                detail.text = "off-peak all day"
                detail.textColor = AppColors.textDim
            }
        } else {
            var windows: [String] = []
            for interval in day.intervals {
                windows.append(interval.utcLabel)
            }
            var text = windows.joined(separator: ", ") + " UTC"
            if day.kind == .unverified { text += " · unverified" }
            detail.text = text
            detail.textColor = AppColors.peak
        }

        let row = UIStackView(arrangedSubviews: [dayLabel, detail])
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .firstBaseline
        return row
    }

    // MARK: - Theme

    /// Repaints this screen and its navigation bar from the saved palette.
    private func applyTheme() {
        let appearance = AppAppearance.current
        view.backgroundColor = appearance.background
        window?.backgroundColor = appearance.background
        window?.overrideUserInterfaceStyle = appearance.interfaceStyle
        if let navigation = navigationController {
            AppThemeRefresh.styleNavigationBar(navigation.navigationBar, appearance: appearance)
        }
        actionsBar.refreshColours()
        lastRateSignature = ""
    }

    @objc private func appearanceChanged() {
        applyTheme()
        render()
    }

    // MARK: - Actions

    @objc private func refreshTapped() {
        refresh()
    }

    /// Called by AppDelegate when the widget deep link asks for a balance refresh.
    func refreshIfAskedByWidget(_ url: URL) {
        guard WidgetRefreshHandoff.wantsRefresh(url) else { return }
        refresh()
    }

    @objc private func themesTapped() {
        presentThemeStudio()
    }

    private func presentThemeStudio() {
        let studio = ThemeStudioViewController(initial: SettingsStore.shared.widgetAppearance)
        studio.onApplied = { [weak self] in
            guard let self = self else { return }
            self.applyTheme()
            self.render()
        }
        let navigation = UINavigationController(rootViewController: studio)
        navigation.modalPresentationStyle = .formSheet
        AppThemeRefresh.styleNavigationBar(navigation.navigationBar, appearance: AppAppearance.current)
        present(navigation, animated: true)
    }

    @objc private func widgetStudioTapped() {
        let studio = WidgetStudioViewController()
        studio.onRequestRefresh = { [weak self] in
            self?.lastRateSignature = ""
            self?.applyTheme()
            self?.render()
        }
        studio.onRequestThemes = { [weak self] in
            self?.presentThemeStudio()
        }
        let navigation = UINavigationController(rootViewController: studio)
        navigation.modalPresentationStyle = .formSheet
        AppThemeRefresh.styleNavigationBar(navigation.navigationBar, appearance: AppAppearance.current)
        present(navigation, animated: true)
    }

    @objc private func settingsTapped() {
        let controller = SettingsViewController()
        controller.onSaved = { [weak self] in
            guard let self = self else { return }
            self.lastRateSignature = ""
            self.applyTheme()
            self.render()
            self.refresh()
        }
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .formSheet
        AppThemeRefresh.styleNavigationBar(navigation.navigationBar, appearance: AppAppearance.current)
        present(navigation, animated: true)
    }

    @objc private func settingsChanged() {
        lastRateSignature = ""
        // The account may have changed: drop any request that is still in flight for the old key.
        client.cancel()
        isLoading = false
        refreshControl.endRefreshing()
        ThemedBackgroundInstaller.install(in: self)
        render()
    }

    @objc private func openPricingPage() {
        let target = URL(string: SettingsStore.shared.schedule.sourceURL)
        guard let url = target else { return }
        UIApplication.shared.open(url)
    }

    private func autoRefreshIfStale() {
        let store = SettingsStore.shared
        // 1.0.9: a widget tap arrives here too. The request is answered either way, so the widget
        // stops asking and shows the honest "Open app" wording instead of a permanent key error.
        let widgetAsked = WidgetHandshakeConsumer.pendingReason() != nil
        guard store.hasAPIKey else {
            if widgetAsked {
                completeWidgetRequest()
                showMessage("The widget asked for a refresh, but no API key is saved yet. Add your key in Settings.", tone: .neutral)
            } else {
                showMessage("Add your DeepSeek API key in Settings to load your account balance.", tone: .neutral)
            }
            return
        }
        if let snapshot = store.cachedSnapshot {
            if Date().timeIntervalSince(snapshot.fetchedAt) < 120 && !widgetAsked {
                showMessage(nil, tone: .neutral)
                return
            }
        }
        refresh()
    }

    /// Answers a pending widget request after the balance load settles: clears the request, writes the
    /// answer stamp and asks WidgetKit for a fresh entry.
    private func completeWidgetRequest() {
        let previous = WidgetHandshakeConsumer.lastAnswer()?.answeredCount ?? 0
        WidgetHandshakeConsumer.completeRequest(previousCount: previous)
        WidgetBridge.reloadWidgets()
    }

    private func refresh() {
        guard !isLoading else { return }
        let key = SettingsStore.shared.apiKey
        guard !key.isEmpty else {
            showMessage("Add your DeepSeek API key in Settings to load your account balance.", tone: .neutral)
            refreshControl.endRefreshing()
            return
        }

        if WidgetHandshakeConsumer.pendingReason() != nil {
            // Consume the request once the response lands, so the widget cannot re-ask in a loop.
            pendingWidgetAnswer = true
        }

        isLoading = true
        // The ticket identifies the account this request belongs to. If the key is removed or
        // changed before the response arrives, the result is discarded instead of cached.
        let ticket = SettingsStore.shared.currentAccountTicket()
        showMessage("Contacting api.deepseek.com…", tone: .neutral)
        client.fetchBalance(apiKey: key) { [weak self] result in
            guard let self = self else { return }
            self.isLoading = false
            self.refreshControl.endRefreshing()

            let acceptance = SettingsStore.shared.acceptsBalance(ticket: ticket)
            guard acceptance.shouldCache else {
                // Late response for a removed or replaced account: no cache write, no widget write.
                self.showMessage(SettingsStore.shared.hasAPIKey
                                 ? "That balance was discarded because the account changed."
                                 : "Add your DeepSeek API key in Settings to load your account balance.",
                                 tone: .neutral)
                self.render()
                if self.pendingWidgetAnswer {
                    self.pendingWidgetAnswer = false
                    self.completeWidgetRequest()
                }
                return
            }

            switch result {
            case .success(let snapshot):
                SettingsStore.shared.cachedSnapshot = snapshot
                // Publish the display-only snapshot for the widget extension (no key inside).
                WidgetBridge.refresh(store: SettingsStore.shared)
                self.showMessage(nil, tone: .neutral)
            case .failure(let error):
                // Even a failed fetch rewrites the snapshot, so the widget learns that a key IS
                // present and stops claiming there is none.
                WidgetBridge.refresh(store: SettingsStore.shared)
                self.showMessage(error.message, tone: .warning)
            }
            self.render()
            if self.pendingWidgetAnswer {
                self.pendingWidgetAnswer = false
                self.completeWidgetRequest()
            }
        }
    }

    private func showMessage(_ text: String?, tone: MessageTone) {
        guard let text = text else {
            messageCard.isHidden = true
            return
        }
        if text.isEmpty {
            messageCard.isHidden = true
            return
        }
        messageLabel.text = text
        if tone == .warning {
            messageLabel.textColor = AppColors.danger
        } else {
            messageLabel.textColor = AppColors.textDim
        }
        messageCard.isHidden = false
    }

    /// Answers a pending widget request after a balance load settles: clears the widget's request file,
    /// writes the answer stamp and asks WidgetKit for a fresh entry. Rate limiting lives in
    /// WidgetRefreshHandshakeRules, so this can be called from every path that finishes a load.
    private func completeWidgetRequest() {
        let previous = WidgetHandshakeConsumer.lastAnswer()?.answeredCount ?? 0
        WidgetHandshakeConsumer.completeRequest(previousCount: previous)
        WidgetBridge.reloadWidgets()
    }
}
