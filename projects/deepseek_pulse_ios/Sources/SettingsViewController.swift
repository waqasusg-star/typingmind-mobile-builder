import UIKit

final class SettingsViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let keyField = PaddedTextField()
    private let scheduleSwitch = UISwitch()
    private let coverageStartField = PaddedTextField()
    private let coverageEndField = PaddedTextField()
    private let holidayDatePicker = UIDatePicker()
    private let holidayListStack = UIStackView()
    private let holidayNoteLabel = Labels.caption("")
    private let localNoteLabel = Labels.caption("")

    private var dayButtons: [UIButton] = []
    private var windowFields: [[PaddedTextField]] = []
    private var rateFields: [String: [RateComponent: PaddedTextField]] = [:]
    private var discountFields: [String: PaddedTextField] = [:]

    private var peakDays: Set<Int> = []
    private var holidays: Set<String> = []

    var onSaved: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        view.backgroundColor = AppColors.background
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Close", style: .plain, target: self, action: #selector(closeTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save", style: .done, target: self, action: #selector(saveTapped))

        let store = SettingsStore.shared
        peakDays = store.schedule.peakWeekdays
        holidays = store.schedule.holidays.dates

        buildForm()
        populate()

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    // MARK: - Form

    private func buildForm() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
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

        if SettingsStore.shared.migrationNoticePending {
            let migrationCard = CardView()
            migrationCard.content.addArrangedSubview(Labels.title("Upgraded from 1.0.0"))
            migrationCard.content.addArrangedSubview(Labels.caption("The old 16:30–00:30 UTC window and the retired deepseek-chat / deepseek-reasoner prices were removed. The schedule and prices now match the official page as checked on \(RateSeeds.verifiedAsOf)."))
            migrationCard.content.addArrangedSubview(linkButton("Dismiss this notice", action: #selector(dismissMigrationNotice)))
            stack.addArrangedSubview(migrationCard)
        }

        // API key
        let keyCard = CardView()
        keyCard.content.addArrangedSubview(Labels.title("API key"))
        keyCard.content.addArrangedSubview(Labels.caption("Kept in the iOS Keychain on this device and sent only to api.deepseek.com/user/balance. Create or copy a key from platform.deepseek.com/api_keys."))
        style(keyField, keyboard: .asciiCapable)
        keyField.isSecureTextEntry = true
        keyField.placeholder = "sk-…"
        keyField.heightAnchor.constraint(equalToConstant: 40).isActive = true
        keyCard.content.addArrangedSubview(keyField)
        let keyButtons = UIStackView(arrangedSubviews: [
            linkButton("Open DeepSeek API keys", action: #selector(openKeyPage)),
            linkButton("Remove key", action: #selector(removeKey))
        ])
        keyButtons.axis = .horizontal
        keyButtons.spacing = 16
        keyCard.content.addArrangedSubview(keyButtons)
        stack.addArrangedSubview(keyCard)

        // Pricing schedule
        let scheduleCard = CardView()
        scheduleCard.content.addArrangedSubview(Labels.title("Pricing schedule"))
        scheduleCard.content.addArrangedSubview(Labels.caption("Official schedule as checked on \(RateSeeds.verifiedAsOf): peak Monday–Friday 01:00–04:00 and 06:00–10:00 UTC, excluding PRC public holidays. Every other hour, all weekends and every PRC public holiday is off-peak."))

        let switchRow = UIStackView(arrangedSubviews: [bodyLabel("Apply off-peak discounts"), scheduleSwitch])
        switchRow.axis = .horizontal
        switchRow.alignment = .center
        switchRow.spacing = 12
        scheduleSwitch.addTarget(self, action: #selector(scheduleToggleChanged), for: .valueChanged)
        scheduleCard.content.addArrangedSubview(switchRow)

        scheduleCard.content.addArrangedSubview(Labels.caption("Peak days (UTC)"))
        let dayRow = UIStackView()
        dayRow.axis = .horizontal
        dayRow.spacing = 6
        dayRow.distribution = .fillEqually
        for iso in 1...7 {
            let button = UIButton(type: .system)
            button.setTitle(PricingSchedule.weekdayShort(iso), for: .normal)
            button.titleLabel?.font = Typography.scaled(12, .bold, style: .footnote)
            button.tag = iso
            button.layer.cornerRadius = 9
            button.layer.cornerCurve = .continuous
            button.heightAnchor.constraint(equalToConstant: 34).isActive = true
            button.addTarget(self, action: #selector(toggleDay(_:)), for: .touchUpInside)
            dayButtons.append(button)
            dayRow.addArrangedSubview(button)
        }
        scheduleCard.content.addArrangedSubview(dayRow)
        scheduleCard.content.addArrangedSubview(Labels.caption("Peak windows in UTC. Leave both fields of a window empty to drop it; a window must start and end on the same UTC day."))

        for index in 0..<2 {
            let start = PaddedTextField()
            style(start, keyboard: .numbersAndPunctuation)
            start.placeholder = index == 0 ? "01:00" : "06:00"
            let end = PaddedTextField()
            style(end, keyboard: .numbersAndPunctuation)
            end.placeholder = index == 0 ? "04:00" : "10:00"
            windowFields.append([start, end])
            scheduleCard.content.addArrangedSubview(fieldRow(title: "Window \(index + 1) start (UTC)", field: start))
            scheduleCard.content.addArrangedSubview(fieldRow(title: "Window \(index + 1) end (UTC)", field: end))
        }

        scheduleCard.content.addArrangedSubview(localNoteLabel)
        scheduleCard.content.addArrangedSubview(linkButton("Restore official schedule (verified \(RateSeeds.verifiedAsOf))", action: #selector(restoreOfficialSchedule)))
        stack.addArrangedSubview(scheduleCard)

        // PRC holidays
        let holidayCard = CardView()
        holidayCard.content.addArrangedSubview(Labels.title("PRC public holidays"))
        holidayCard.content.addArrangedSubview(Labels.caption("No holiday list is bundled or downloaded, so the app cannot know them by itself. Add the dates you checked in the official State Council holiday notice; a listed date becomes off-peak all day. Nothing is added automatically."))

        holidayDatePicker.datePickerMode = .date
        holidayDatePicker.preferredDatePickerStyle = .compact
        holidayDatePicker.timeZone = TimeZone(secondsFromGMT: 0)
        var pickerCalendar = Calendar(identifier: .gregorian)
        pickerCalendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        holidayDatePicker.calendar = pickerCalendar
        holidayDatePicker.locale = Locale(identifier: "en_US_POSIX")
        let addRow = UIStackView(arrangedSubviews: [holidayDatePicker, linkButton("Add date", action: #selector(addHoliday))])
        addRow.axis = .horizontal
        addRow.spacing = 12
        addRow.alignment = .center
        holidayCard.content.addArrangedSubview(addRow)

        holidayListStack.axis = .vertical
        holidayListStack.spacing = 6
        holidayCard.content.addArrangedSubview(holidayListStack)
        holidayCard.content.addArrangedSubview(holidayNoteLabel)

        style(coverageStartField, keyboard: .numbersAndPunctuation)
        coverageStartField.placeholder = "2026-01-01"
        style(coverageEndField, keyboard: .numbersAndPunctuation)
        coverageEndField.placeholder = "2026-12-31"
        holidayCard.content.addArrangedSubview(Labels.caption("Range you have actually checked (yyyy-MM-dd). Days inside the range count as working days unless listed; days outside it are reported as unverified."))
        holidayCard.content.addArrangedSubview(fieldRow(title: "Checked from", field: coverageStartField))
        holidayCard.content.addArrangedSubview(fieldRow(title: "Checked to", field: coverageEndField))
        holidayCard.content.addArrangedSubview(linkButton("Clear all holiday dates", action: #selector(clearHolidays)))
        stack.addArrangedSubview(holidayCard)

        // Rates
        let ratesCard = CardView()
        ratesCard.content.addArrangedSubview(Labels.title("Standard (peak) rates"))
        ratesCard.content.addArrangedSubview(Labels.caption("USD per 1M tokens. Verified defaults: deepseek-flash 0.006 / 0.30 / 1.20 and deepseek-v4-pro 0.044 / 1.32 / 3.96, both 50% off in off-peak. Edit only if DeepSeek changed prices."))
        for model in SettingsStore.shared.models {
            let nameLabel = UILabel()
            nameLabel.text = model.displayName
            nameLabel.font = Typography.scaled(13.5, .bold, style: .subheadline)
            nameLabel.textColor = AppColors.accentSoft
            nameLabel.numberOfLines = 0
            ratesCard.content.addArrangedSubview(nameLabel)

            var fields: [RateComponent: PaddedTextField] = [:]
            for component in RateComponent.allCases {
                let field = PaddedTextField()
                style(field, keyboard: .decimalPad)
                field.placeholder = "0.00"
                ratesCard.content.addArrangedSubview(fieldRow(title: component.title, field: field))
                fields[component] = field
            }
            rateFields[model.id] = fields

            let discountField = PaddedTextField()
            style(discountField, keyboard: .decimalPad)
            discountField.placeholder = "50"
            ratesCard.content.addArrangedSubview(fieldRow(title: "Off-peak discount %", field: discountField))
            discountFields[model.id] = discountField
        }
        stack.addArrangedSubview(ratesCard)

        stack.addArrangedSubview(linkButton("Reset rates to the verified defaults", action: #selector(resetRates)))
        stack.addArrangedSubview(linkButton("Open official pricing page", action: #selector(openPricingPage)))
        stack.addArrangedSubview(Labels.caption("Source: \(RateSeeds.sourceNote). Prices are never fetched automatically; this screen is the only place they change."))
    }

    private func populate() {
        let store = SettingsStore.shared
        keyField.text = store.apiKey
        scheduleSwitch.isOn = store.schedule.discountsEnabled

        for (index, interval) in store.schedule.sortedIntervals.prefix(2).enumerated() {
            windowFields[index][0].text = ClockFormat.minuteLabel(interval.startMinuteUTC)
            windowFields[index][1].text = ClockFormat.minuteLabel(interval.endMinuteUTC)
        }
        coverageStartField.text = store.schedule.holidays.coverageStart ?? ""
        coverageEndField.text = store.schedule.holidays.coverageEnd ?? ""

        for model in store.models {
            if let fields = rateFields[model.id] {
                fields[.cacheHit]?.text = MoneyFormat.rate(model.standard.cacheHit)
                fields[.cacheMiss]?.text = MoneyFormat.rate(model.standard.cacheMiss)
                fields[.output]?.text = MoneyFormat.rate(model.standard.output)
            }
            discountFields[model.id]?.text = String(format: "%g", model.clampedDiscount)
        }

        refreshDayButtons()
        refreshHolidayList()
        updateLocalNote()
    }

    private func refreshDayButtons() {
        for button in dayButtons {
            let selected = peakDays.contains(button.tag)
            button.backgroundColor = selected ? AppColors.accent : AppColors.surfaceElevated
            button.setTitleColor(selected ? .white : AppColors.textDim, for: .normal)
        }
    }

    private func refreshHolidayList() {
        for view in holidayListStack.arrangedSubviews {
            holidayListStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        if holidays.isEmpty {
            let empty = Labels.caption("No holiday dates added.")
            holidayListStack.addArrangedSubview(empty)
        } else {
            for key in holidays.sorted() {
                let label = UILabel()
                label.text = key
                label.font = Typography.digits(13, .medium)
                label.textColor = AppColors.text

                let remove = UIButton(type: .system)
                remove.setTitle("Remove", for: .normal)
                remove.titleLabel?.font = Typography.scaled(12, .semibold, style: .caption1)
                remove.setTitleColor(AppColors.danger, for: .normal)
                remove.addAction(UIAction { [weak self] _ in
                    self?.holidays.remove(key)
                    self?.refreshHolidayList()
                }, for: .touchUpInside)

                let row = UIStackView(arrangedSubviews: [label, remove])
                row.axis = .horizontal
                row.spacing = 12
                row.alignment = .center
                holidayListStack.addArrangedSubview(row)
            }
        }
        let summary = currentCalendarPreview().summary
        holidayNoteLabel.text = "Calendar: \(summary)."
    }

    private func currentCalendarPreview() -> HolidayCalendar {
        let start = trimmed(coverageStartField.text)
        let end = trimmed(coverageEndField.text)
        return HolidayCalendar(dates: holidays,
                               coverageStart: start.isEmpty ? nil : start,
                               coverageEnd: end.isEmpty ? nil : end,
                               verifiedAsOf: (start.isEmpty || end.isEmpty) ? nil : PricingSchedule.dayKey(Date()))
    }

    private func updateLocalNote() {
        var intervals: [PeakInterval] = []
        for pair in windowFields {
            let start = parseMinute(pair[0].text ?? "")
            let end = parseMinute(pair[1].text ?? "")
            if let start = start, let end = end, start < end {
                intervals.append(PeakInterval(startMinuteUTC: start, endMinuteUTC: end))
            }
        }
        let local = intervals.map { interval in
            ClockFormat.localLabel(minuteUTC: interval.startMinuteUTC) + "–" + ClockFormat.localLabel(minuteUTC: interval.endMinuteUTC)
        }.joined(separator: ", ")
        localNoteLabel.text = local.isEmpty
            ? "No valid window yet."
            : "In your local time those windows are \(local). Saved on this device only."
    }

    // MARK: - Helpers

    private func trimmed(_ text: String?) -> String {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func bodyLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = Typography.scaled(13.5, .medium, style: .subheadline)
        label.textColor = AppColors.text
        label.numberOfLines = 0
        return label
    }

    private func fieldRow(title: String, field: UITextField) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = Typography.scaled(12.5, .medium, style: .footnote)
        label.textColor = AppColors.textDim
        label.numberOfLines = 0

        field.widthAnchor.constraint(equalToConstant: 104).isActive = true

        let row = UIStackView(arrangedSubviews: [label, field])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        return row
    }

    private func style(_ field: PaddedTextField, keyboard: UIKeyboardType) {
        field.backgroundColor = AppColors.surfaceElevated
        field.layer.cornerRadius = 10
        field.layer.cornerCurve = .continuous
        field.textColor = AppColors.text
        field.tintColor = AppColors.accentSoft
        field.font = Typography.scaled(14, .medium, style: .subheadline)
        field.keyboardType = keyboard
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.clearButtonMode = .whileEditing
        field.inputAccessoryView = makeAccessory()
    }

    private func linkButton(_ title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = Typography.scaled(13, .semibold, style: .subheadline)
        button.titleLabel?.numberOfLines = 0
        button.setTitleColor(AppColors.accentSoft, for: .normal)
        button.contentHorizontalAlignment = .leading
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func makeAccessory() -> UIToolbar {
        let bar = UIToolbar()
        bar.sizeToFit()
        bar.items = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(dismissKeyboard))
        ]
        return bar
    }

    private func parseMinute(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    private func parseNumber(_ text: String?) -> Double? {
        guard let text = text else { return nil }
        return Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    private func alert(_ title: String, _ message: String) {
        let controller = UIAlertController(title: title, message: message, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: "OK", style: .default))
        present(controller, animated: true)
    }

    // MARK: - Actions

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func dismissMigrationNotice() {
        SettingsStore.shared.migrationNoticePending = false
        alert("Notice dismissed", "Reopen Settings any time; the verified schedule and prices stay in place.")
    }

    @objc private func scheduleToggleChanged() {
        updateLocalNote()
    }

    @objc private func toggleDay(_ sender: UIButton) {
        if peakDays.contains(sender.tag) {
            peakDays.remove(sender.tag)
        } else {
            peakDays.insert(sender.tag)
        }
        refreshDayButtons()
    }

    @objc private func addHoliday() {
        let key = PricingSchedule.dayKey(holidayDatePicker.date)
        holidays.insert(key)
        refreshHolidayList()
    }

    @objc private func clearHolidays() {
        holidays.removeAll()
        refreshHolidayList()
    }

    @objc private func restoreOfficialSchedule() {
        let official = RateSeeds.schedule
        scheduleSwitch.isOn = official.discountsEnabled
        peakDays = official.peakWeekdays
        for (index, pair) in windowFields.enumerated() {
            if index < official.sortedIntervals.count {
                pair[0].text = ClockFormat.minuteLabel(official.sortedIntervals[index].startMinuteUTC)
                pair[1].text = ClockFormat.minuteLabel(official.sortedIntervals[index].endMinuteUTC)
            } else {
                pair[0].text = ""
                pair[1].text = ""
            }
        }
        refreshDayButtons()
        updateLocalNote()
    }

    @objc private func resetRates() {
        SettingsStore.shared.resetModelsToOfficial()
        for model in RateSeeds.models {
            if let fields = rateFields[model.id] {
                fields[.cacheHit]?.text = MoneyFormat.rate(model.standard.cacheHit)
                fields[.cacheMiss]?.text = MoneyFormat.rate(model.standard.cacheMiss)
                fields[.output]?.text = MoneyFormat.rate(model.standard.output)
            }
            discountFields[model.id]?.text = String(format: "%g", model.clampedDiscount)
        }
    }

    @objc private func removeKey() {
        KeyStore.delete()
        keyField.text = ""
        SettingsStore.shared.cachedSnapshot = nil
        NotificationCenter.default.post(name: .deepSeekSettingsChanged, object: nil)
        alert("API key removed", "The key was deleted from the Keychain and the cached balance was cleared.")
    }

    @objc private func openKeyPage() {
        guard let url = URL(string: "https://platform.deepseek.com/api_keys") else { return }
        UIApplication.shared.open(url)
    }

    @objc private func openPricingPage() {
        guard let url = URL(string: RateSeeds.sourceURL) else { return }
        UIApplication.shared.open(url)
    }

    @objc private func saveTapped() {
        dismissKeyboard()
        let store = SettingsStore.shared

        var intervals: [PeakInterval] = []
        for (index, pair) in windowFields.enumerated() {
            let startText = trimmed(pair[0].text)
            let endText = trimmed(pair[1].text)
            if startText.isEmpty && endText.isEmpty { continue }
            guard let start = parseMinute(startText), let end = parseMinute(endText) else {
                alert("Check window \(index + 1)", "Enter both edges as HH:MM in 24-hour UTC, for example 01:00 and 04:00.")
                return
            }
            guard start < end else {
                alert("Check window \(index + 1)", "The start must be earlier than the end; a window cannot cross midnight.")
                return
            }
            intervals.append(PeakInterval(startMinuteUTC: start, endMinuteUTC: end))
        }
        guard !intervals.isEmpty || !scheduleSwitch.isOn else {
            alert("Check the schedule", "Add at least one peak window, or switch off-peak discounts off.")
            return
        }
        guard !peakDays.isEmpty || !scheduleSwitch.isOn else {
            alert("Check the schedule", "Select at least one peak weekday, or switch off-peak discounts off.")
            return
        }

        let coverageStart = trimmed(coverageStartField.text)
        let coverageEnd = trimmed(coverageEndField.text)
        if !coverageStart.isEmpty || !coverageEnd.isEmpty {
            guard PricingSchedule.date(fromDayKey: coverageStart) != nil,
                  PricingSchedule.date(fromDayKey: coverageEnd) != nil else {
                alert("Check the holiday range", "Enter both range ends as yyyy-MM-dd, for example 2026-01-01 and 2026-12-31.")
                return
            }
            guard coverageStart <= coverageEnd else {
                alert("Check the holiday range", "The range start must not be later than the range end.")
                return
            }
        }
        for key in holidays where PricingSchedule.date(fromDayKey: key) == nil {
            alert("Check the holiday dates", "\(key) is not a yyyy-MM-dd date.")
            return
        }

        var models: [ModelRate] = []
        for model in store.models {
            var standard = model.standard
            if let fields = rateFields[model.id] {
                for component in RateComponent.allCases {
                    guard let field = fields[component],
                          let value = parseNumber(field.text),
                          value >= 0 else {
                        alert("Check the rates", "Enter a valid non-negative USD price for \(model.name) — \(component.title).")
                        return
                    }
                    switch component {
                    case .cacheHit: standard.cacheHit = value
                    case .cacheMiss: standard.cacheMiss = value
                    case .output: standard.output = value
                    }
                }
            }
            guard let discountField = discountFields[model.id],
                  let discount = parseNumber(discountField.text),
                  discount >= 0, discount <= 100 else {
                alert("Check the discount", "Enter the off-peak discount for \(model.name) as a percentage between 0 and 100.")
                return
            }
            models.append(ModelRate(id: model.id,
                                    name: model.name,
                                    label: model.label,
                                    standard: standard,
                                    offPeakDiscountPercent: discount))
        }

        let official = RateSeeds.schedule
        let scheduleIsCustom = scheduleSwitch.isOn != official.discountsEnabled
            || peakDays != official.peakWeekdays
            || intervals.sorted { $0.startMinuteUTC < $1.startMinuteUTC } != official.sortedIntervals

        let calendar = HolidayCalendar(dates: holidays,
                                       coverageStart: coverageStart.isEmpty ? nil : coverageStart,
                                       coverageEnd: coverageEnd.isEmpty ? nil : coverageEnd,
                                       verifiedAsOf: (coverageStart.isEmpty || coverageEnd.isEmpty) ? nil : PricingSchedule.dayKey(Date()))

        let schedule = PricingSchedule(peakWeekdays: peakDays.isEmpty ? official.peakWeekdays : peakDays,
                                       intervals: intervals.sorted { $0.startMinuteUTC < $1.startMinuteUTC },
                                       holidays: calendar,
                                       discountsEnabled: scheduleSwitch.isOn,
                                       sourceURL: official.sourceURL,
                                       verifiedAsOf: official.verifiedAsOf)

        let ratesAreCustom = models != RateSeeds.models

        let key = keyField.text ?? ""
        if !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !KeyStore.save(key) {
                alert("Keychain error", "The API key could not be stored in the iOS Keychain. Try again.")
                return
            }
        }

        store.saveSchedule(schedule, isCustom: scheduleIsCustom)
        store.saveModels(models, isCustom: ratesAreCustom)

        NotificationCenter.default.post(name: .deepSeekSettingsChanged, object: nil)
        onSaved?()
        dismiss(animated: true)
    }
}
