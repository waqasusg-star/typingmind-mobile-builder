import UIKit

final class SettingsViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let keyField = PaddedTextField(frame: .zero)
    private let scheduleSwitch = UISwitch()
    private let coverageStartField = PaddedTextField(frame: .zero)
    private let coverageEndField = PaddedTextField(frame: .zero)
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
    private var holidaysExpanded = false

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
            migrationCard.content.addArrangedSubview(Labels.title("Upgraded from an earlier build"))
            migrationCard.content.addArrangedSubview(Labels.caption("The old 16:30–00:30 UTC window and the retired deepseek-chat / deepseek-reasoner prices were removed. The schedule, prices and the 2026–2027 PRC holiday list now match the official sources checked on " + RateSeeds.verifiedAsOf + "."))
            migrationCard.content.addArrangedSubview(linkButton("Dismiss this notice", action: #selector(dismissMigrationNotice)))
            stack.addArrangedSubview(migrationCard)
        }

        // API key
        let keyCard = CardView()
        keyCard.content.addArrangedSubview(Labels.title("API key"))
        keyCard.content.addArrangedSubview(Labels.caption("Kept in the iOS Keychain on this device and sent only to api.deepseek.com/user/balance. Create or copy a key from platform.deepseek.com/api_keys."))
        keyField.isSecureTextEntry = true
        keyField.placeholder = "sk-…"
        keyField.keyboardType = .asciiCapable
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
        scheduleCard.content.addArrangedSubview(Labels.caption("Verified on " + RateSeeds.verifiedAsOf + ": peak Monday–Friday 01:00–04:00 and 06:00–10:00 UTC, excluding PRC public holidays. Every other hour, every weekend and every PRC public holiday is off-peak."))

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
            button.titleLabel?.font = Typography.scaled(12, UIFont.Weight.bold, style: .footnote)
            button.tag = iso
            button.layer.cornerRadius = 9
            button.layer.cornerCurve = .continuous
            button.heightAnchor.constraint(equalToConstant: 34).isActive = true
            button.addTarget(self, action: #selector(toggleDay(_:)), for: .touchUpInside)
            dayButtons.append(button)
            dayRow.addArrangedSubview(button)
        }
        scheduleCard.content.addArrangedSubview(dayRow)
        scheduleCard.content.addArrangedSubview(Labels.caption("Peak windows in UTC. Leave both fields of a window empty to drop it; a window must start and end inside the same UTC day."))

        for index in 0..<2 {
            let start = PaddedTextField(frame: .zero)
            start.keyboardType = .numbersAndPunctuation
            start.placeholder = "01:00"
            start.inputAccessoryView = makeAccessory()
            let end = PaddedTextField(frame: .zero)
            end.keyboardType = .numbersAndPunctuation
            end.placeholder = "04:00"
            end.inputAccessoryView = makeAccessory()
            windowFields.append([start, end])
            scheduleCard.content.addArrangedSubview(fieldRow(title: "Window " + String(index + 1) + " start (UTC)", field: start))
            scheduleCard.content.addArrangedSubview(fieldRow(title: "Window " + String(index + 1) + " end (UTC)", field: end))
        }

        scheduleCard.content.addArrangedSubview(localNoteLabel)
        scheduleCard.content.addArrangedSubview(linkButton("Restore official schedule and verified holidays", action: #selector(restoreOfficialSchedule)))
        stack.addArrangedSubview(scheduleCard)

        // PRC holidays
        let holidayCard = CardView()
        holidayCard.content.addArrangedSubview(Labels.title("PRC public holidays"))
        holidayCard.content.addArrangedSubview(Labels.caption("Verified for 2026 and 2027 from the State Council notices. The app never downloads a holiday list, so 2028 and later are reported as unverified until you add them. Chinese make-up working Saturdays and Sundays stay off-peak here, because DeepSeek charges every weekend as off-peak."))

        holidayDatePicker.datePickerMode = .date
        holidayDatePicker.preferredDatePickerStyle = .compact
        holidayDatePicker.timeZone = TimeZone(secondsFromGMT: 0)
        var pickerCalendar = Calendar(identifier: .gregorian)
        pickerCalendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
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

        coverageStartField.keyboardType = .numbersAndPunctuation
        coverageStartField.placeholder = "2026-01-01"
        coverageStartField.inputAccessoryView = makeAccessory()
        coverageEndField.keyboardType = .numbersAndPunctuation
        coverageEndField.placeholder = "2027-12-31"
        coverageEndField.inputAccessoryView = makeAccessory()
        holidayCard.content.addArrangedSubview(Labels.caption("Range you have actually checked (yyyy-MM-dd). Days inside the range count as working days unless listed; days outside it are reported as unverified."))
        holidayCard.content.addArrangedSubview(fieldRow(title: "Checked from", field: coverageStartField))
        holidayCard.content.addArrangedSubview(fieldRow(title: "Checked to", field: coverageEndField))
        holidayCard.content.addArrangedSubview(linkButton("Open the official PRC holiday notice", action: #selector(openHolidaySource)))
        holidayCard.content.addArrangedSubview(linkButton("Clear all holiday dates", action: #selector(clearHolidays)))
        stack.addArrangedSubview(holidayCard)

        // Rates
        let ratesCard = CardView()
        ratesCard.content.addArrangedSubview(Labels.title("Standard (peak) rates"))
        ratesCard.content.addArrangedSubview(Labels.caption("USD per 1M tokens. Verified defaults: deepseek-flash 0.006 / 0.30 / 1.20 and deepseek-v4-pro 0.044 / 1.32 / 3.96, both 50% off in off-peak. Edit only if DeepSeek changed prices."))
        for model in SettingsStore.shared.models {
            let nameLabel = UILabel()
            nameLabel.text = model.displayName
            nameLabel.font = Typography.scaled(13.5, UIFont.Weight.bold, style: .subheadline)
            nameLabel.textColor = AppColors.accentSoft
            nameLabel.numberOfLines = 0
            ratesCard.content.addArrangedSubview(nameLabel)

            var fields: [RateComponent: PaddedTextField] = [:]
            for component in RateComponent.allCases {
                let field = PaddedTextField(frame: .zero)
                field.keyboardType = .decimalPad
                field.placeholder = "0.00"
                field.inputAccessoryView = makeAccessory()
                ratesCard.content.addArrangedSubview(fieldRow(title: component.title, field: field))
                fields[component] = field
            }
            rateFields[model.id] = fields

            let discountField = PaddedTextField(frame: .zero)
            discountField.keyboardType = .decimalPad
            discountField.placeholder = "50"
            discountField.inputAccessoryView = makeAccessory()
            ratesCard.content.addArrangedSubview(fieldRow(title: "Off-peak discount %", field: discountField))
            discountFields[model.id] = discountField
        }
        stack.addArrangedSubview(ratesCard)

        stack.addArrangedSubview(linkButton("Reset rates to the verified defaults", action: #selector(resetRates)))
        stack.addArrangedSubview(linkButton("Open official pricing page", action: #selector(openPricingPage)))
        stack.addArrangedSubview(Labels.caption("Source: " + RateSeeds.sourceNote + ". Prices are never fetched automatically; this screen is the only place they change."))
    }

    private func populate() {
        let store = SettingsStore.shared
        keyField.text = store.apiKey
        scheduleSwitch.isOn = store.schedule.discountsEnabled

        for index in 0..<windowFields.count {
            if index < store.schedule.sortedIntervals.count {
                let interval = store.schedule.sortedIntervals[index]
                windowFields[index][0].text = ClockFormat.minuteLabel(interval.startMinuteUTC)
                windowFields[index][1].text = ClockFormat.minuteLabel(interval.endMinuteUTC)
            } else {
                windowFields[index][0].text = ""
                windowFields[index][1].text = ""
            }
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
            if selected {
                button.backgroundColor = AppColors.accent
                button.setTitleColor(UIColor.white, for: .normal)
            } else {
                button.backgroundColor = AppColors.surfaceElevated
                button.setTitleColor(AppColors.textDim, for: .normal)
            }
        }
    }

    private var sortedHolidays: [String] {
        holidays.sorted()
    }

    private func refreshHolidayList() {
        for view in holidayListStack.arrangedSubviews {
            holidayListStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let sorted = sortedHolidays
        if sorted.isEmpty {
            holidayListStack.addArrangedSubview(Labels.caption("No holiday dates added."))
        } else {
            let limit = holidaysExpanded ? sorted.count : 8
            for index in 0..<min(limit, sorted.count) {
                holidayListStack.addArrangedSubview(holidayRow(key: sorted[index], index: index))
            }
            if sorted.count > 8 {
                var title = "Show all " + String(sorted.count) + " dates"
                if holidaysExpanded { title = "Show fewer dates" }
                holidayListStack.addArrangedSubview(linkButton(title, action: #selector(toggleHolidayExpansion)))
            }
        }

        holidayNoteLabel.text = "Calendar: " + currentCalendarPreview().summary + "."
    }

    private func holidayRow(key: String, index: Int) -> UIView {
        let label = UILabel()
        label.text = key
        label.font = Typography.digits(13, UIFont.Weight.medium)
        label.textColor = AppColors.text

        let remove = UIButton(type: .system)
        remove.setTitle("Remove", for: .normal)
        remove.titleLabel?.font = Typography.scaled(12, UIFont.Weight.semibold, style: .caption1)
        remove.setTitleColor(AppColors.danger, for: .normal)
        remove.tag = index
        remove.addTarget(self, action: #selector(removeHolidayRow(_:)), for: .touchUpInside)

        let row = UIStackView(arrangedSubviews: [label, remove])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        return row
    }

    private func currentCalendarPreview() -> HolidayCalendar {
        let start = trimmed(coverageStartField.text)
        let end = trimmed(coverageEndField.text)
        var calendar = HolidayCalendar(dates: holidays,
                                       coverageStart: start.isEmpty ? nil : start,
                                       coverageEnd: end.isEmpty ? nil : end,
                                       verifiedAsOf: nil)
        if !start.isEmpty && !end.isEmpty && start <= end {
            calendar.verifiedAsOf = PricingSchedule.dayKey(Date())
        }
        calendar.source = SettingsStore.shared.schedule.holidays.source
        return calendar
    }

    private func updateLocalNote() {
        var intervals: [PeakInterval] = []
        for pair in windowFields {
            let start = parseMinute(pair[0].text ?? "")
            let end = parseMinute(pair[1].text ?? "")
            if let startMinute = start, let endMinute = end {
                if startMinute < endMinute {
                    intervals.append(PeakInterval(startMinuteUTC: startMinute, endMinuteUTC: endMinute))
                }
            }
        }
        var local: [String] = []
        for interval in intervals {
            local.append(ClockFormat.localLabel(minuteUTC: interval.startMinuteUTC)
                         + "–" + ClockFormat.localLabel(minuteUTC: interval.endMinuteUTC))
        }
        if local.isEmpty {
            localNoteLabel.text = "No valid window yet."
        } else {
            localNoteLabel.text = "In your local time those windows are " + local.joined(separator: ", ") + ". Saved on this device only."
        }
    }

    // MARK: - Helpers

    private func trimmed(_ text: String?) -> String {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func bodyLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = Typography.scaled(13.5, UIFont.Weight.medium, style: .subheadline)
        label.textColor = AppColors.text
        label.numberOfLines = 0
        return label
    }

    private func fieldRow(title: String, field: UITextField) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = Typography.scaled(12.5, UIFont.Weight.medium, style: .footnote)
        label.textColor = AppColors.textDim
        label.numberOfLines = 0

        field.widthAnchor.constraint(equalToConstant: 104).isActive = true

        let row = UIStackView(arrangedSubviews: [label, field])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        return row
    }

    private func linkButton(_ title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = Typography.scaled(13, UIFont.Weight.semibold, style: .subheadline)
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

    @objc private func toggleHolidayExpansion() {
        holidaysExpanded = !holidaysExpanded
        refreshHolidayList()
    }

    @objc private func addHoliday() {
        holidays.insert(PricingSchedule.dayKey(holidayDatePicker.date))
        refreshHolidayList()
    }

    @objc private func removeHolidayRow(_ sender: UIButton) {
        let sorted = sortedHolidays
        guard sender.tag >= 0, sender.tag < sorted.count else { return }
        holidays.remove(sorted[sender.tag])
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
        holidays = official.holidays.dates
        holidaysExpanded = false
        coverageStartField.text = official.holidays.coverageStart ?? ""
        coverageEndField.text = official.holidays.coverageEnd ?? ""
        for index in 0..<windowFields.count {
            if index < official.sortedIntervals.count {
                windowFields[index][0].text = ClockFormat.minuteLabel(official.sortedIntervals[index].startMinuteUTC)
                windowFields[index][1].text = ClockFormat.minuteLabel(official.sortedIntervals[index].endMinuteUTC)
            } else {
                windowFields[index][0].text = ""
                windowFields[index][1].text = ""
            }
        }
        refreshDayButtons()
        refreshHolidayList()
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

    @objc private func openHolidaySource() {
        guard let url = URL(string: RateSeeds.holidaySource) else { return }
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
        for index in 0..<windowFields.count {
            let startText = trimmed(windowFields[index][0].text)
            let endText = trimmed(windowFields[index][1].text)
            if startText.isEmpty && endText.isEmpty { continue }
            guard let start = parseMinute(startText), let end = parseMinute(endText) else {
                alert("Check window " + String(index + 1), "Enter both edges as HH:MM in 24-hour UTC, for example 01:00 and 04:00.")
                return
            }
            guard start < end else {
                alert("Check window " + String(index + 1), "The start must be earlier than the end; a window cannot cross midnight.")
                return
            }
            intervals.append(PeakInterval(startMinuteUTC: start, endMinuteUTC: end))
        }
        if scheduleSwitch.isOn && intervals.isEmpty {
            alert("Check the schedule", "Add at least one peak window, or switch off-peak discounts off.")
            return
        }
        if scheduleSwitch.isOn && peakDays.isEmpty {
            alert("Check the schedule", "Select at least one peak weekday, or switch off-peak discounts off.")
            return
        }

        let coverageStart = trimmed(coverageStartField.text)
        let coverageEnd = trimmed(coverageEndField.text)
        if !coverageStart.isEmpty || !coverageEnd.isEmpty {
            guard PricingSchedule.date(fromDayKey: coverageStart) != nil,
                  PricingSchedule.date(fromDayKey: coverageEnd) != nil else {
                alert("Check the holiday range", "Enter both range ends as yyyy-MM-dd, for example 2026-01-01 and 2027-12-31.")
                return
            }
            guard coverageStart <= coverageEnd else {
                alert("Check the holiday range", "The range start must not be later than the range end.")
                return
            }
        }
        for key in holidays {
            if PricingSchedule.date(fromDayKey: key) == nil {
                alert("Check the holiday dates", key + " is not a yyyy-MM-dd date.")
                return
            }
        }

        var models: [ModelRate] = []
        for model in store.models {
            var standard = model.standard
            if let fields = rateFields[model.id] {
                for component in RateComponent.allCases {
                    guard let field = fields[component],
                          let value = parseNumber(field.text),
                          value >= 0 else {
                        alert("Check the rates", "Enter a valid non-negative USD price for " + model.name + " — " + component.title + ".")
                        return
                    }
                    if component == .cacheHit { standard.cacheHit = value }
                    if component == .cacheMiss { standard.cacheMiss = value }
                    if component == .output { standard.output = value }
                }
            }
            guard let discountField = discountFields[model.id],
                  let discount = parseNumber(discountField.text),
                  discount >= 0, discount <= 100 else {
                alert("Check the discount", "Enter the off-peak discount for " + model.name + " as a percentage between 0 and 100.")
                return
            }
            models.append(ModelRate(id: model.id,
                                    name: model.name,
                                    label: model.label,
                                    standard: standard,
                                    offPeakDiscountPercent: discount))
        }

        let official = RateSeeds.schedule
        let sortedNew = intervals.sorted { $0.startMinuteUTC < $1.startMinuteUTC }
        let isCustom = scheduleSwitch.isOn != official.discountsEnabled
            || peakDays != official.peakWeekdays
            || sortedNew != official.sortedIntervals

        let existing = store.schedule.holidays
        let newStart: String? = coverageStart.isEmpty ? nil : coverageStart
        let newEnd: String? = coverageEnd.isEmpty ? nil : coverageEnd
        var verifiedAsOf = existing.verifiedAsOf
        if newStart != existing.coverageStart || newEnd != existing.coverageEnd {
            verifiedAsOf = PricingSchedule.dayKey(Date())
        }
        let calendar = HolidayCalendar(dates: holidays,
                                       coverageStart: newStart,
                                       coverageEnd: newEnd,
                                       verifiedAsOf: verifiedAsOf,
                                       source: existing.source)

        let updatedSchedule = PricingSchedule(peakWeekdays: peakDays.isEmpty ? official.peakWeekdays : peakDays,
                                              intervals: sortedNew,
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

        store.saveSchedule(updatedSchedule, isCustom: isCustom)
        store.saveModels(models, isCustom: ratesAreCustom)

        NotificationCenter.default.post(name: .deepSeekSettingsChanged, object: nil)
        onSaved?()
        dismiss(animated: true)
    }
}
