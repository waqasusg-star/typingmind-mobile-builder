import UIKit

// DeepSeek Pulse — the missing theme and design picker.
//
// 1.0.6 shipped sixteen palettes in Shared/ThemeCatalogCore.swift and ten widget designs in
// Shared/WidgetAppearanceCore.swift, but nothing in the UI ever called
// SettingsStore.saveAppearance(_:). The dashboard never observed .deepSeekAppearanceChanged, so the
// app background and the widgets both stayed on Midnight. That is why the themes looked absent.
//
// This screen is the only place a theme or a design is chosen:
//   * a live preview card drawn with the same tokens the widgets use
//   * all sixteen palettes as tappable swatches, marked with a real check when selected
//   * the five small designs and the five medium designs
//   * the three display switches
//   * Apply saves once, rewrites the widget snapshot and posts the change notification

/// One tappable theme swatch.
final class ThemeSwatchView: UIControl {

    let themeID: String

    private let swatch = UIView(frame: .zero)
    private let titleLabel = UILabel()
    private let check = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))

    var isSelectedTheme: Bool = false {
        didSet { updateSelection() }
    }

    init(themeID: String, name: String, colours: [UIColor]) {
        self.themeID = themeID
        super.init(frame: .zero)

        swatch.translatesAutoresizingMaskIntoConstraints = false
        swatch.layer.cornerRadius = 12
        swatch.layer.cornerCurve = .continuous
        swatch.layer.borderWidth = 1
        swatch.layer.borderColor = UIColor.white.withAlphaComponent(0.14).cgColor
        swatch.isUserInteractionEnabled = false

        // Vertical stack of the palette's own colours, so the swatch is the theme, not a guess.
        let bars = UIStackView()
        bars.axis = .vertical
        bars.distribution = .fillEqually
        bars.translatesAutoresizingMaskIntoConstraints = false
        for colour in colours {
            let bar = UIView(frame: .zero)
            bar.backgroundColor = colour
            bars.addArrangedSubview(bar)
        }
        swatch.addSubview(bars)
        NSLayoutConstraint.activate([
            bars.topAnchor.constraint(equalTo: swatch.topAnchor),
            bars.leadingAnchor.constraint(equalTo: swatch.leadingAnchor),
            bars.trailingAnchor.constraint(equalTo: swatch.trailingAnchor),
            bars.bottomAnchor.constraint(equalTo: swatch.bottomAnchor)
        ])

        check.tintColor = UIColor.white
        check.translatesAutoresizingMaskIntoConstraints = false
        check.layer.shadowColor = UIColor.black.cgColor
        check.layer.shadowOpacity = 0.5
        check.layer.shadowRadius = 3
        check.layer.shadowOffset = .zero
        swatch.addSubview(check)
        NSLayoutConstraint.activate([
            check.trailingAnchor.constraint(equalTo: swatch.trailingAnchor, constant: -5),
            check.bottomAnchor.constraint(equalTo: swatch.bottomAnchor, constant: -5),
            check.widthAnchor.constraint(equalToConstant: 15),
            check.heightAnchor.constraint(equalToConstant: 15)
        ])

        titleLabel.text = name
        titleLabel.font = Typography.scaled(11, .semibold, style: .caption1)
        titleLabel.textColor = AppColors.text
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.7
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(swatch)
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            swatch.topAnchor.constraint(equalTo: topAnchor),
            swatch.leadingAnchor.constraint(equalTo: leadingAnchor),
            swatch.trailingAnchor.constraint(equalTo: trailingAnchor),
            swatch.heightAnchor.constraint(equalToConstant: 56),
            titleLabel.topAnchor.constraint(equalTo: swatch.bottomAnchor, constant: 4),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = name + " theme"
        updateSelection()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1.0 }
    }

    private func updateSelection() {
        check.isHidden = !isSelectedTheme
        accessibilityValue = isSelectedTheme ? "Selected" : "Not selected"
        swatch.layer.borderColor = isSelectedTheme
            ? AppColors.accent.cgColor
            : UIColor.white.withAlphaComponent(0.14).cgColor
        swatch.layer.borderWidth = isSelectedTheme ? 2 : 1
    }
}

/// One tappable widget-design chip.
final class DesignChip: UIControl {

    let design: WidgetDesign

    private let nameLabel = UILabel()
    private let summaryLabel = UILabel()

    var isChosen: Bool = false {
        didSet { updateSelection() }
    }

    init(design: WidgetDesign, chosen: Bool) {
        self.design = design
        super.init(frame: .zero)

        nameLabel.text = design.title
        nameLabel.font = Typography.scaled(12.5, .bold, style: .footnote)
        nameLabel.numberOfLines = 1

        summaryLabel.text = design.summary
        summaryLabel.font = Typography.scaled(10.5, .medium, style: .caption2)
        summaryLabel.numberOfLines = 2
        summaryLabel.textColor = AppColors.textDim

        let stack = UIStackView(arrangedSubviews: [nameLabel, summaryLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isUserInteractionEnabled = false
        addSubview(stack)

        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        layer.borderWidth = 1

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9)
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = design.familyLabel + " design " + design.title
        isChosen = chosen
        updateSelection()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1.0 }
    }

    private func updateSelection() {
        if isChosen {
            backgroundColor = AppColors.accent.withAlphaComponent(0.18)
            layer.borderColor = AppColors.accent.cgColor
            nameLabel.textColor = AppColors.text
        } else {
            backgroundColor = AppColors.surfaceElevated
            layer.borderColor = UIColor.clear.cgColor
            nameLabel.textColor = AppColors.textDim
        }
        accessibilityValue = isChosen ? "Selected" : "Not selected"
    }
}

/// The theme and widget-design picker. Presented modally from the dashboard and Widget Studio.
final class ThemeStudioViewController: UIViewController {

    private let store = SettingsStore.shared
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let previewCard = CardView()
    private let previewLabel = Labels.title("")
    private let previewBody = Labels.body("")
    private let previewApply = UILabel()

    private var working: WidgetAppearance
    private var swatches: [ThemeSwatchView] = []
    private var smallChips: [DesignChip] = []
    private var mediumChips: [DesignChip] = []
    private let balanceSwitch = UISwitch()
    private let refreshSwitch = UISwitch()
    private let bandSwitch = UISwitch()

    var onApplied: (() -> Void)?

    init(initial: WidgetAppearance) {
        self.working = initial.normalised()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Themes"
        view.backgroundColor = AppColors.background
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Close", style: .plain, target: self, action: #selector(closeTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Apply", style: .done, target: self, action: #selector(applyTapped))
        buildLayout()
        render()
    }

    // MARK: - Layout

    private func buildLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
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

        previewCard.content.addArrangedSubview(Labels.caption("LIVE PREVIEW"))
        previewApply.font = Typography.scaled(26, .bold)
        previewApply.textColor = AppColors.text
        previewApply.numberOfLines = 1
        previewApply.adjustsFontSizeToFitWidth = true
        previewApply.minimumScaleFactor = 0.6
        previewCard.content.addArrangedSubview(previewApply)
        previewCard.content.addArrangedSubview(previewLabel)
        previewCard.content.addArrangedSubview(previewBody)
        stack.addArrangedSubview(previewCard)

        let themeCard = CardView()
        themeCard.content.addArrangedSubview(Labels.title("Theme"))
        themeCard.content.addArrangedSubview(Labels.caption(String(PulseThemes.count) + " palettes. The chosen palette paints the app background, the cards, the tabs and both widget sizes."))
        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 12
        var row: UIStackView?
        for (index, theme) in PulseThemes.all.enumerated() {
            if index % 4 == 0 {
                let newRow = UIStackView()
                newRow.axis = .horizontal
                newRow.spacing = 10
                newRow.distribution = .fillEqually
                grid.addArrangedSubview(newRow)
                row = newRow
            }
            let colours = [AppAppearance.ui(theme.background),
                           AppAppearance.ui(theme.surfaceElevated),
                           AppAppearance.ui(theme.accent)]
            let swatch = ThemeSwatchView(themeID: theme.id, name: theme.name, colours: colours)
            swatch.addTarget(self, action: #selector(themeTapped(_:)), for: .touchUpInside)
            swatches.append(swatch)
            row?.addArrangedSubview(swatch)
        }
        themeCard.content.addArrangedSubview(grid)
        stack.addArrangedSubview(themeCard)

        let smallCard = CardView()
        smallCard.content.addArrangedSubview(Labels.title("Home Screen · small"))
        smallCard.content.addArrangedSubview(Labels.caption("Five designs for the small widget."))
        for design in WidgetDesign.smallFamily {
            let chip = DesignChip(design: design, chosen: working.smallDesign == design)
            chip.addTarget(self, action: #selector(smallTapped(_:)), for: .touchUpInside)
            smallChips.append(chip)
            smallCard.content.addArrangedSubview(chip)
        }
        stack.addArrangedSubview(smallCard)

        let mediumCard = CardView()
        mediumCard.content.addArrangedSubview(Labels.title("Home Screen · medium"))
        mediumCard.content.addArrangedSubview(Labels.caption("Five designs for the medium widget."))
        for design in WidgetDesign.mediumFamily {
            let chip = DesignChip(design: design, chosen: working.mediumDesign == design)
            chip.addTarget(self, action: #selector(mediumTapped(_:)), for: .touchUpInside)
            mediumChips.append(chip)
            mediumCard.content.addArrangedSubview(chip)
        }
        stack.addArrangedSubview(mediumCard)

        let switches = CardView()
        switches.content.addArrangedSubview(Labels.title("What the widget shows"))
        balanceSwitch.addTarget(self, action: #selector(switchChanged), for: .valueChanged)
        refreshSwitch.addTarget(self, action: #selector(switchChanged), for: .valueChanged)
        bandSwitch.addTarget(self, action: #selector(switchChanged), for: .valueChanged)
        switches.content.addArrangedSubview(switchRow("Balance", control: balanceSwitch))
        switches.content.addArrangedSubview(switchRow("Refresh icon", control: refreshSwitch))
        switches.content.addArrangedSubview(switchRow("24-hour band", control: bandSwitch))
        stack.addArrangedSubview(switches)

        let note = CardView()
        note.content.addArrangedSubview(Labels.title("How this is saved"))
        note.content.addArrangedSubview(Labels.caption("Apply stores the choice on this iPhone, repaints the app immediately and rewrites the widget snapshot. iOS decides when the Home Screen draws the next timeline, usually within a minute. The Lock Screen widgets follow the same pricing state; iOS draws those in its own monochrome style, so the palette does not apply there."))
        stack.addArrangedSubview(note)

        balanceSwitch.isOn = working.showBalance
        refreshSwitch.isOn = working.showRefresh
        bandSwitch.isOn = working.showDayBand
    }

    private func switchRow(_ title: String, control: UISwitch) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = Typography.scaled(13.5, .medium, style: .subheadline)
        label.textColor = AppColors.text
        let row = UIStackView(arrangedSubviews: [label, control])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        return row
    }

    // MARK: - Rendering

    @objc private func themeTapped(_ sender: ThemeSwatchView) {
        working.themeID = sender.themeID
        render()
    }

    @objc private func smallTapped(_ sender: DesignChip) {
        working.smallDesign = sender.design
        render()
    }

    @objc private func mediumTapped(_ sender: DesignChip) {
        working.mediumDesign = sender.design
        render()
    }

    @objc private func switchChanged() {
        working.showBalance = balanceSwitch.isOn
        working.showRefresh = refreshSwitch.isOn
        working.showDayBand = bandSwitch.isOn
        render()
    }

    private func render() {
        let theme = working.theme
        for swatch in swatches {
            swatch.isSelectedTheme = swatch.themeID == working.themeID
        }
        for chip in smallChips {
            chip.isChosen = chip.design == working.smallDesign
        }
        for chip in mediumChips {
            chip.isChosen = chip.design == working.mediumDesign
        }

        // The preview card is painted with the palette being considered, not the saved one, so a tap
        // shows its result before Apply.
        previewCard.backgroundColor = AppAppearance.ui(theme.surface)
        previewLabel.text = theme.name + " · " + working.smallDesign.title + " + " + working.mediumDesign.title
        previewLabel.textColor = AppAppearance.ui(theme.text)
        previewBody.textColor = AppAppearance.ui(theme.textDim)

        let now = Date()
        let schedule = store.schedule
        let snapshot = WidgetPlanner.snapshot(schedule: schedule, at: now)
        let headline = WidgetPlanner.headline(snapshot: snapshot, discountsEnabled: schedule.discountsEnabled)
        previewApply.text = headline
        previewApply.textColor = AppAppearance.ui(stateColour(for: snapshot.state, in: theme))

        var lines: [String] = []
        lines.append(WidgetPlanner.footnote(snapshot: snapshot, discountsEnabled: schedule.discountsEnabled))
        if working.showBalance {
            if let cached = store.cachedSnapshot, let info = cached.primary {
                lines.append("Balance " + MoneyFormat.amount(info.totalBalance, currency: info.currency))
            } else if store.hasAPIKey {
                lines.append("Balance loads when you open the app with a saved key")
            } else {
                lines.append("No API key saved yet")
            }
        }
        if !working.showDayBand { lines.append("24-hour band hidden") }
        previewBody.text = lines.joined(separator: " · ")
    }

    private func stateColour(for state: PricingState, in theme: PulseTheme) -> PulseRGB {
        switch state {
        case .peak: return theme.peak
        case .offPeak: return theme.offPeak
        case .standard: return theme.textDim
        }
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    /// Saves once, rewrites the snapshot and lets the presenting screen repaint.
    @objc private func applyTapped() {
        let chosen = working.normalised()
        store.saveAppearance(chosen)
        let result = WidgetBridge.refresh(store: store)
        onApplied?()

        let message = "Theme " + chosen.theme.name + " saved with " + chosen.smallDesign.title
            + " (small) and " + chosen.mediumDesign.title + " (medium). "
            + WidgetRefreshHandoff.summary(for: result.outcome)
        let alert = UIAlertController(title: "Theme applied", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Done", style: .default) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }
}
