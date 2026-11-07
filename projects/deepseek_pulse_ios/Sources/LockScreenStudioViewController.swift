import UIKit

/// Lock Screen design picker.
///
/// 1.0.9 adds the seven accessory designs to the app. Each family has its own row: the rectangular
/// designs below the clock, the circular dials, and the single-line inline styles. Choosing one stores
/// it in WidgetAppearance.lockScreen, which the widget extension reads, so the Lock Screen follows the
/// choice instead of always drawing the same card.
///
/// The picker is a separate view controller so Widget Studio stays readable; it edits a copy of the
/// saved appearance and hands the finished value back through `onSave`.
final class LockScreenStudioViewController: UIViewController {

    /// Called with the new appearance after the user saves.
    var onSave: ((WidgetAppearance) -> Void)?

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let previewCard = WidgetLockScreenCardView(frame: .zero)
    private let previewCaption = Labels.caption("")
    private var working: WidgetAppearance

    init(appearance: WidgetAppearance) {
        self.working = appearance.normalised()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Lock Screen"
        view.backgroundColor = AppColors.background
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Done",
                                                            style: .done,
                                                            target: self,
                                                            action: #selector(doneTapped))
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Cancel",
                                                           style: .plain,
                                                           target: self,
                                                           action: #selector(cancelTapped))
        buildLayout()
        render()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        ThemedBackgroundInstaller.install(in: self)
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
        intro.content.addArrangedSubview(Labels.title("Lock Screen widgets"))
        intro.content.addArrangedSubview(Labels.caption("iOS 16 and later draw these beside or below the clock. Pick one design per size; the preview below is drawn from the same strings the real widget uses. The Lock Screen never shows your balance or your API key state, because there is no room to explain either."))
        stack.addArrangedSubview(intro)

        let preview = CardView()
        preview.content.addArrangedSubview(Labels.title("Preview"))
        previewCard.translatesAutoresizingMaskIntoConstraints = false
        previewCard.heightAnchor.constraint(equalToConstant: 92).isActive = true
        preview.content.addArrangedSubview(previewCard)
        preview.content.addArrangedSubview(previewCaption)
        stack.addArrangedSubview(preview)

        stack.addArrangedSubview(section(title: "Rectangular",
                                         caption: "The wide slot below the clock.",
                                         designs: LockScreenStyle.rectangularFamily))
        stack.addArrangedSubview(section(title: "Circular",
                                         caption: "The small dial beside the clock.",
                                         designs: LockScreenStyle.circularFamily))
        stack.addArrangedSubview(section(title: "Inline",
                                         caption: "One line next to the date.",
                                         designs: LockScreenStyle.inlineFamily))
    }

    private func section(title: String, caption: String, designs: [LockScreenStyle]) -> UIView {
        let card = CardView()
        card.content.addArrangedSubview(Labels.title(title))
        card.content.addArrangedSubview(Labels.caption(caption))
        for design in designs {
            card.content.addArrangedSubview(chip(for: design))
        }
        return card
    }

    private func chip(for design: LockScreenStyle) -> UIControl {
        let chip = LockScreenChip(style: design, chosen: working.lockScreen.style(forFamily: design.family) == design)
        chip.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
        return chip
    }

    @objc private func chipTapped(_ sender: LockScreenChip) {
        working.lockScreen.set(sender.style)
        render()
    }

    @objc private func doneTapped() {
        onSave?(working)
        dismiss(animated: true)
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    private func render() {
        let store = SettingsStore.shared
        let now = Date()
        let schedule = store.schedule
        let snapshot = WidgetPlanner.snapshot(schedule: schedule, at: now)
        previewCard.apply(style: working.lockScreen.rectangular,
                          snapshot: snapshot,
                          schedule: schedule,
                          now: now)
        previewCaption.text = working.lockScreen.rectangular.summary
            + " Circular: " + working.lockScreen.circular.title
            + ". Inline: " + working.lockScreen.inline.title + "."
        previewCaption.textColor = AppColors.textDim

        // Rebuild the cards so the selected chip repaints.
        rebuildSections()
    }

    private func rebuildSections() {
        for view in stack.arrangedSubviews {
            guard let card = view as? CardView else { continue }
            for child in card.content.arrangedSubviews {
                guard let chip = child as? LockScreenChip else { continue }
                chip.isChosen = working.lockScreen.style(forFamily: chip.style.family) == chip.style
            }
        }
    }
}

/// One selectable Lock Screen design.
final class LockScreenChip: UIControl {

    let style: LockScreenStyle

    private let nameLabel = UILabel()
    private let summaryLabel = UILabel()

    var isChosen: Bool = false {
        didSet { updateSelection() }
    }

    init(style: LockScreenStyle, chosen: Bool) {
        self.style = style
        super.init(frame: .zero)

        nameLabel.text = style.title
        nameLabel.font = Typography.scaled(12.5, .bold, style: .footnote)
        nameLabel.textColor = AppColors.text

        summaryLabel.text = style.summary
        summaryLabel.font = Typography.scaled(10.5, .medium, style: .caption2)
        summaryLabel.textColor = AppColors.textDim
        summaryLabel.numberOfLines = 2

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

        backgroundColor = AppColors.surfaceElevated
        isChosen = chosen
        updateSelection()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func updateSelection() {
        layer.borderColor = isChosen
            ? AppColors.accent.cgColor
            : UIColor.white.withAlphaComponent(0.12).cgColor
        layer.borderWidth = isChosen ? 2 : 1
    }
}
