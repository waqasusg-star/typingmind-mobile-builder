import UIKit

final class SettingsViewController: UIViewController {

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let keyField = PaddedTextField()
    private let startField = PaddedTextField()
    private let endField = PaddedTextField()
    private let scheduleSwitch = UISwitch()
    private let localNoteLabel = Labels.caption("")
    private var rateFields: [String: [RateComponent: PaddedTextField]] = [:]
    private var discountFields: [String: PaddedTextField] = [:]

    var onSaved: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        view.backgroundColor = AppColors.background
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Close", style: .plain, target: self, action: #selector(closeTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save", style: .done, target: self, action: #selector(saveTapped))
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

        // API key
        let keyCard = CardView()
        keyCard.content.addArrangedSubview(Labels.title("API key"))
        keyCard.content.addArrangedSubview(Labels.caption("Kept in the iOS Keychain on this device and sent only to api.deepseek.com. Create or copy a key from platform.deepseek.com/api_keys."))
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

        // Schedule
        let scheduleCard = CardView()
        scheduleCard.content.addArrangedSubview(Labels.title("Off-peak schedule"))
        let switchRow = UIStackView(arrangedSubviews: [bodyLabel("Apply off-peak discounts"), scheduleSwitch])
        switchRow.axis = .horizontal
        switchRow.alignment = .center
        switchRow.spacing = 12
        scheduleCard.content.addArrangedSubview(switchRow)
        style(startField, keyboard: .numbersAndPunctuation)
        startField.placeholder = "16:30"
        style(endField, keyboard: .numbersAndPunctuation)
        endField.placeholder = "00:30"
        scheduleCard.content.addArrangedSubview(fieldRow(title: "Starts (UTC HH:MM)", field: startField))
        scheduleCard.content.addArrangedSubview(fieldRow(title: "Ends (UTC HH:MM)", field: endField))
        scheduleCard.content.addArrangedSubview(localNoteLabel)
        scheduleCard.content.addArrangedSubview(linkButton("Restore published window (16:30–00:30 UTC)", action: #selector(restoreWindow)))
        stack.addArrangedSubview(scheduleCard)

        // Rates
        let ratesCard = CardView()
        ratesCard.content.addArrangedSubview(Labels.title("Standard rates"))
        ratesCard.content.addArrangedSubview(Labels.caption("USD per 1M tokens. Compare with api-docs.deepseek.com/quick_start/pricing and edit if DeepSeek changed prices."))
        for model in SettingsStore.shared.models {
            let nameLabel = UILabel()
            nameLabel.text = model.name
            nameLabel.font = Typography.scaled(13.5, .bold, style: .subheadline)
            nameLabel.textColor = AppColors.accentSoft
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
            discountField.placeholder = "0"
            ratesCard.content.addArrangedSubview(fieldRow(title: "Off-peak discount %", field: discountField))
            discountFields[model.id] = discountField
        }
        stack.addArrangedSubview(ratesCard)

        stack.addArrangedSubview(linkButton("Reset rates to the seeded defaults", action: #selector(resetRates)))
        stack.addArrangedSubview(linkButton("Open official pricing page", action: #selector(openPricingPage)))
        stack.addArrangedSubview(Labels.caption("Seeded defaults were taken from DeepSeek's published standard schedule with the 50% (chat) and 75% (reasoner) off-peak discounts. DeepSeek can change or withdraw discounts at any time; this app does not download prices automatically."))
    }

    private func populate() {
        let store = SettingsStore.shared
        keyField.text = store.apiKey
        localNoteLabel.isHidden = !store.hasAPIKey
        startField.text = ClockFormat.minuteLabel(store.window.startMinuteUTC)
        endField.text = ClockFormat.minuteLabel(store.window.endMinuteUTC)
        scheduleSwitch.isOn = store.window.discountEnabled
        updateLocalNote()

        for model in store.models {
            if let fields = rateFields[model.id] {
                fields[.cacheHit]?.text = MoneyFormat.rate(model.standard.cacheHit)
                fields[.cacheMiss]?.text = MoneyFormat.rate(model.standard.cacheMiss)
                fields[.output]?.text = MoneyFormat.rate(model.standard.output)
            }
            discountFields[model.id]?.text = String(format: "%g", model.clampedDiscount)
        }
    }

    private func updateLocalNote() {
        let start = parseMinute(startField.text ?? "") ?? PeakWindow.seeded.startMinuteUTC
        let end = parseMinute(endField.text ?? "") ?? PeakWindow.seeded.endMinuteUTC
        localNoteLabel.text = "In your local time that is \(ClockFormat.localLabel(minuteUTC: start))–\(ClockFormat.localLabel(minuteUTC: end)). Saved on this device only."
    }

    // MARK: - Helpers

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
        field.attributedPlaceholder = NSAttributedString(string: field.placeholder ?? "",
                                                         attributes: [.foregroundColor: AppColors.textDim.withAlphaComponent(0.7)])
    }

    private func linkButton(_ title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = Typography.scaled(13, .semibold, style: .subheadline)
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

    @objc private func saveTapped() {
        dismissKeyboard()
        let store = SettingsStore.shared

        guard let start = parseMinute(startField.text ?? ""), let end = parseMinute(endField.text ?? "") else {
            alert("Check the schedule", "Enter the off-peak window as HH:MM in 24-hour UTC, for example 16:30 and 00:30.")
            return
        }
        guard start != end else {
            alert("Check the schedule", "The start and end of the off-peak window must be different times.")
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
                                    standard: standard,
                                    offPeakDiscountPercent: discount))
        }

        store.saveWindow(PeakWindow(startMinuteUTC: start,
                                    endMinuteUTC: end,
                                    discountEnabled: scheduleSwitch.isOn))
        store.saveModels(models)

        let key = keyField.text ?? ""
        if !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !KeyStore.save(key) {
                alert("Keychain error", "The API key could not be stored in the iOS Keychain. Try again.")
                return
            }
        }

        NotificationCenter.default.post(name: .deepSeekSettingsChanged, object: nil)
        onSaved?()
        dismiss(animated: true)
    }

    @objc private func removeKey() {
        KeyStore.delete()
        keyField.text = ""
        SettingsStore.shared.cachedSnapshot = nil
        NotificationCenter.default.post(name: .deepSeekSettingsChanged, object: nil)
        alert("API key removed", "The key was deleted from the Keychain and the cached balance was cleared.")
    }

    @objc private func restoreWindow() {
        startField.text = ClockFormat.minuteLabel(PeakWindow.seeded.startMinuteUTC)
        endField.text = ClockFormat.minuteLabel(PeakWindow.seeded.endMinuteUTC)
        scheduleSwitch.isOn = true
        updateLocalNote()
    }

    @objc private func resetRates() {
        SettingsStore.shared.resetRates()
        populate()
    }

    @objc private func openKeyPage() {
        guard let url = URL(string: "https://platform.deepseek.com/api_keys") else { return }
        UIApplication.shared.open(url)
    }

    @objc private func openPricingPage() {
        guard let url = URL(string: "https://api-docs.deepseek.com/quick_start/pricing") else { return }
        UIApplication.shared.open(url)
    }
}
