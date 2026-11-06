import UIKit

/// Local-only checklist screen: framework UIKit only, no networking, no analytics.
final class ChecklistViewController: UIViewController, UITextFieldDelegate {

    private let store: ChecklistStore
    private var items: [ChecklistItem] = []
    private var priority: TaskPriority = .normal
    private var statusMessage = ""

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let summaryLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let inputRow = UIStackView()
    private let inputField = UITextField()
    private let addButton = UIButton(type: .system)
    private let errorLabel = UILabel()
    private let priorityHeader = UILabel()
    private let priorityControl = UISegmentedControl(items: TaskPriority.allCases.map { $0.label })
    private let themeHeader = UILabel()
    private let themeControl = UISegmentedControl(items: ThemeChoice.allCases.map { $0.label })
    private let tasksStack = UIStackView()
    private let emptyContainer = UIView()
    private let emptyLabel = UILabel()
    private let clearButton = UIButton(type: .system)
    private let recoveryButton = UIButton(type: .system)
    private let statusLabel = UILabel()

    private var palette: Palette {
        Palette(dark: traitCollection.userInterfaceStyle == .dark)
    }

    init(store: ChecklistStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "QA Checklist"
        navigationController?.navigationBar.prefersLargeTitles = true

        configureStaticViews()
        buildHierarchy()

        let loaded = store.load()
        items = loaded.items
        if let notice = loaded.notice { statusMessage = notice }
        inputField.text = store.loadDraft()
        if let index = TaskPriority.allCases.firstIndex(of: priority) {
            priorityControl.selectedSegmentIndex = index
        }
        if let index = ThemeChoice.allCases.firstIndex(of: store.themeChoice()) {
            themeControl.selectedSegmentIndex = index
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(persistNow),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        render()
    }

    // MARK: - Layout

    private func configureStaticViews() {
        titleLabel.text = "QA Checklist"
        titleLabel.font = .preferredFont(forTextStyle: .largeTitle)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
        titleLabel.accessibilityTraits = .header

        subtitleLabel.text = "Local-only task checklist · v1.0.0 · nothing leaves this device"
        subtitleLabel.font = .preferredFont(forTextStyle: .footnote)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.numberOfLines = 0

        summaryLabel.font = .preferredFont(forTextStyle: .subheadline)
        summaryLabel.adjustsFontForContentSizeCategory = true
        summaryLabel.numberOfLines = 0
        summaryLabel.accessibilityTraits = .updatesFrequently

        progressView.progress = 0
        progressView.layer.cornerRadius = 4
        progressView.clipsToBounds = true
        progressView.heightAnchor.constraint(equalToConstant: 8).isActive = true

        inputRow.axis = .horizontal
        inputRow.spacing = 10
        inputRow.alignment = .fill

        inputField.placeholder = "New task title"
        inputField.font = .preferredFont(forTextStyle: .body)
        inputField.adjustsFontForContentSizeCategory = true
        inputField.borderStyle = .none
        inputField.layer.cornerRadius = 12
        inputField.layer.borderWidth = 1
        inputField.autocapitalizationType = .sentences
        inputField.returnKeyType = .done
        inputField.clearButtonMode = .whileEditing
        inputField.accessibilityLabel = "Task title"
        inputField.delegate = self
        inputField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        inputField.leftViewMode = .always
        inputField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        inputField.rightViewMode = .always
        inputField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        inputField.addTarget(self, action: #selector(inputChanged), for: .editingChanged)
        inputField.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true

        addButton.setTitle("Add task", for: .normal)
        addButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        addButton.titleLabel?.adjustsFontForContentSizeCategory = true
        addButton.layer.cornerRadius = 12
        addButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 18, bottom: 12, right: 18)
        addButton.accessibilityLabel = "Add task"
        addButton.setContentHuggingPriority(.required, for: .horizontal)
        addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)
        addButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true

        errorLabel.font = .preferredFont(forTextStyle: .footnote)
        errorLabel.adjustsFontForContentSizeCategory = true
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true

        priorityHeader.text = "Priority"
        priorityHeader.font = .preferredFont(forTextStyle: .caption1)
        priorityHeader.adjustsFontForContentSizeCategory = true
        priorityControl.accessibilityLabel = "Priority"
        priorityControl.addTarget(self, action: #selector(priorityChanged), for: .valueChanged)

        themeHeader.text = "Appearance"
        themeHeader.font = .preferredFont(forTextStyle: .caption1)
        themeHeader.adjustsFontForContentSizeCategory = true
        themeControl.accessibilityLabel = "Appearance"
        themeControl.addTarget(self, action: #selector(themeChanged), for: .valueChanged)

        tasksStack.axis = .vertical
        tasksStack.spacing = 10

        emptyLabel.text = "No tasks yet.\nAdd your first task above. Incomplete tasks stay on top, highest priority first."
        emptyLabel.font = .preferredFont(forTextStyle: .callout)
        emptyLabel.adjustsFontForContentSizeCategory = true
        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyContainer.layer.cornerRadius = 14
        emptyContainer.layer.borderWidth = 1
        emptyContainer.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.topAnchor.constraint(equalTo: emptyContainer.topAnchor, constant: 20),
            emptyLabel.leadingAnchor.constraint(equalTo: emptyContainer.leadingAnchor, constant: 16),
            emptyLabel.trailingAnchor.constraint(equalTo: emptyContainer.trailingAnchor, constant: -16),
            emptyLabel.bottomAnchor.constraint(equalTo: emptyContainer.bottomAnchor, constant: -20)
        ])

        clearButton.setTitle("Clear completed", for: .normal)
        clearButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        clearButton.layer.cornerRadius = 12
        clearButton.layer.borderWidth = 1
        clearButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        clearButton.addTarget(self, action: #selector(clearCompletedTapped), for: .touchUpInside)
        clearButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true

        recoveryButton.setTitle("Restore recovery copy", for: .normal)
        recoveryButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        recoveryButton.layer.cornerRadius = 12
        recoveryButton.layer.borderWidth = 1
        recoveryButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        recoveryButton.addTarget(self, action: #selector(restoreTapped), for: .touchUpInside)
        recoveryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        recoveryButton.isHidden = true

        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.numberOfLines = 0
        statusLabel.isHidden = true

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    private func buildHierarchy() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28)
        ])

        inputRow.addArrangedSubview(inputField)
        inputRow.addArrangedSubview(addButton)

        let orderedViews: [UIView] = [
            titleLabel, subtitleLabel, summaryLabel, progressView, inputRow, errorLabel,
            priorityHeader, priorityControl, themeHeader, themeControl, tasksStack,
            emptyContainer, clearButton, recoveryButton, statusLabel
        ]
        orderedViews.forEach { contentStack.addArrangedSubview($0) }

        contentStack.setCustomSpacing(6, after: summaryLabel)
        contentStack.setCustomSpacing(8, after: progressView)
        contentStack.setCustomSpacing(18, after: subtitleLabel)
        contentStack.setCustomSpacing(6, after: priorityHeader)
        contentStack.setCustomSpacing(6, after: themeHeader)
        contentStack.setCustomSpacing(18, after: themeControl)
        contentStack.setCustomSpacing(18, after: tasksStack)
    }

    // MARK: - Rendering

    private func render() {
        applyPalette()

        let summary = ChecklistPolicy.summarize(items)
        summaryLabel.text = summary.headline
        summaryLabel.accessibilityLabel = "\(summary.headline). \(summary.percentDone) percent complete."
        progressView.progress = Float(summary.percentDone) / 100.0
        progressView.accessibilityValue = "\(summary.percentDone) percent"

        tasksStack.arrangedSubviews.forEach { arranged in
            tasksStack.removeArrangedSubview(arranged)
            arranged.removeFromSuperview()
        }
        for item in ChecklistPolicy.sortedForDisplay(items) {
            tasksStack.addArrangedSubview(makeRow(for: item))
        }
        tasksStack.isHidden = items.isEmpty
        emptyContainer.isHidden = !items.isEmpty

        let hasCompleted = items.contains { $0.done }
        clearButton.isEnabled = hasCompleted
        clearButton.alpha = hasCompleted ? 1.0 : 0.45

        updatePriorityControl()
        updateRecoveryButton()

        statusLabel.text = statusMessage
        statusLabel.isHidden = statusMessage.isEmpty
        if !statusMessage.isEmpty {
            UIAccessibility.post(notification: .announcement, argument: statusMessage)
        }
    }

    private func applyPalette() {
        let palette = self.palette
        view.backgroundColor = palette.background
        scrollView.backgroundColor = palette.background
        titleLabel.textColor = palette.primaryText
        subtitleLabel.textColor = palette.secondaryText
        summaryLabel.textColor = palette.secondaryText
        errorLabel.textColor = palette.danger
        priorityHeader.textColor = palette.secondaryText
        themeHeader.textColor = palette.secondaryText
        statusLabel.textColor = palette.secondaryText
        emptyLabel.textColor = palette.secondaryText
        emptyContainer.backgroundColor = palette.surface
        emptyContainer.layer.borderColor = palette.border.cgColor

        inputField.backgroundColor = palette.surface
        inputField.textColor = palette.primaryText
        inputField.tintColor = palette.accent
        inputField.layer.borderColor = palette.border.cgColor
        inputField.attributedPlaceholder = NSAttributedString(
            string: "New task title",
            attributes: [.foregroundColor: palette.secondaryText]
        )

        addButton.backgroundColor = palette.accent
        addButton.setTitleColor(.white, for: .normal)

        clearButton.setTitleColor(palette.primaryText, for: .normal)
        clearButton.backgroundColor = palette.surface
        clearButton.layer.borderColor = palette.border.cgColor
        recoveryButton.setTitleColor(palette.accent, for: .normal)
        recoveryButton.backgroundColor = palette.surface
        recoveryButton.layer.borderColor = palette.accent.cgColor

        priorityControl.selectedSegmentTintColor = palette.accent
        themeControl.selectedSegmentTintColor = palette.accent
        progressView.progressTintColor = palette.accent
        progressView.trackTintColor = palette.border

        if let nav = navigationController?.navigationBar {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = palette.background
            appearance.titleTextAttributes = [.foregroundColor: palette.primaryText]
            appearance.largeTitleTextAttributes = [.foregroundColor: palette.primaryText]
            nav.standardAppearance = appearance
            nav.scrollEdgeAppearance = appearance
            nav.tintColor = palette.accent
        }
    }

    private func makeRow(for item: ChecklistItem) -> UIView {
        let palette = self.palette
        let card = UIView()
        card.backgroundColor = palette.surface
        card.layer.cornerRadius = 14
        card.layer.borderWidth = 1
        card.layer.borderColor = palette.border.cgColor

        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 10)
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: card.topAnchor),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 56)
        ])

        let toggle = UIButton(type: .system)
        toggle.setImage(UIImage(systemName: item.done ? "checkmark.circle.fill" : "circle"), for: .normal)
        toggle.tintColor = item.done ? palette.accent : palette.secondaryText
        toggle.accessibilityLabel = item.done ? "Mark \(item.title) as not done" : "Mark \(item.title) as done"
        toggle.accessibilityIdentifier = "toggle-\(item.id)"
        toggle.widthAnchor.constraint(equalToConstant: 44).isActive = true
        toggle.heightAnchor.constraint(equalToConstant: 44).isActive = true
        toggle.addAction(UIAction { [weak self] _ in
            self?.setDone(id: item.id, done: !item.done)
        }, for: .touchUpInside)

        let title = UILabel()
        title.font = .preferredFont(forTextStyle: .body)
        title.adjustsFontForContentSizeCategory = true
        title.numberOfLines = 2
        title.accessibilityIdentifier = "title-\(item.id)"
        if item.done {
            title.attributedText = NSAttributedString(
                string: item.title,
                attributes: [
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .foregroundColor: palette.secondaryText,
                    .font: UIFont.preferredFont(forTextStyle: .body)
                ]
            )
        } else {
            title.text = item.title
            title.textColor = palette.primaryText
        }

        let badge = UILabel()
        badge.text = " " + item.priority.label + " "
        badge.font = .preferredFont(forTextStyle: .caption2)
        badge.textColor = palette.color(for: item.priority)
        badge.layer.cornerRadius = 10
        badge.layer.borderWidth = 1
        badge.layer.borderColor = palette.color(for: item.priority).cgColor
        badge.textAlignment = .center
        badge.setContentHuggingPriority(.required, for: .horizontal)
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)

        let delete = UIButton(type: .system)
        delete.setTitle("Delete", for: .normal)
        delete.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
        delete.setTitleColor(palette.danger, for: .normal)
        delete.layer.cornerRadius = 10
        delete.layer.borderWidth = 1
        delete.layer.borderColor = palette.danger.cgColor
        delete.contentEdgeInsets = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        delete.accessibilityLabel = "Delete \(item.title)"
        delete.accessibilityIdentifier = "delete-\(item.id)"
        delete.setContentHuggingPriority(.required, for: .horizontal)
        delete.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        delete.addAction(UIAction { [weak self] _ in
            self?.delete(id: item.id)
        }, for: .touchUpInside)

        row.addArrangedSubview(toggle)
        row.addArrangedSubview(title)
        row.addArrangedSubview(badge)
        row.addArrangedSubview(delete)
        return card
    }

    // MARK: - Mutations

    private func addCurrentInput() {
        let outcome = ChecklistPolicy.add(
            items,
            rawTitle: inputField.text,
            priority: priority,
            now: Date().timeIntervalSince1970
        )
        switch outcome {
        case .rejected(let message):
            showError(message)
        case .added(let updated, let item):
            items = updated
            inputField.text = ""
            store.saveDraft("")
            showError(nil)
            store.save(items)
            statusMessage = "Added “\(item.title)” as \(item.priority.label) priority."
            render()
            inputField.becomeFirstResponder()
        }
    }

    private func setDone(id: String, done: Bool) {
        guard let target = items.first(where: { $0.id == id }) else { return }
        items = ChecklistPolicy.setDone(items, id: id, done: done)
        store.save(items)
        statusMessage = (done ? "Completed “" : "Reopened “") + target.title + "”."
        render()
    }

    private func delete(id: String) {
        guard let target = items.first(where: { $0.id == id }) else { return }
        items = ChecklistPolicy.remove(items, id: id)
        store.save(items)
        statusMessage = "Deleted “\(target.title)”."
        render()
    }

    private func updatePriorityControl() {
        if let index = TaskPriority.allCases.firstIndex(of: priority) {
            priorityControl.selectedSegmentIndex = index
        }
    }

    private func updateRecoveryButton() {
        guard let count = store.recoveryCount() else {
            recoveryButton.isHidden = true
            return
        }
        recoveryButton.isHidden = false
        recoveryButton.setTitle("Restore recovery copy (\(count))", for: .normal)
        let label = count == 1 ? "task" : "tasks"
        recoveryButton.accessibilityLabel = "Restore \(count) \(label) from the recovery copy"
    }

    private func showError(_ message: String?) {
        guard let message = message else {
            errorLabel.text = nil
            errorLabel.isHidden = true
            return
        }
        errorLabel.text = message
        errorLabel.isHidden = false
        UIAccessibility.post(notification: .announcement, argument: message)
        inputField.becomeFirstResponder()
    }

    // MARK: - Actions

    @objc private func addTapped() {
        addCurrentInput()
    }

    @objc private func inputChanged() {
        let text = inputField.text ?? ""
        if !errorLabel.isHidden, !text.trimmingCharacters(in: .whitespaces).isEmpty {
            showError(nil)
        }
    }

    @objc private func priorityChanged() {
        let index = priorityControl.selectedSegmentIndex
        guard index >= 0, index < TaskPriority.allCases.count else { return }
        priority = TaskPriority.allCases[index]
        statusMessage = "Priority set to \(priority.label)."
        render()
    }

    @objc private func themeChanged() {
        let index = themeControl.selectedSegmentIndex
        guard index >= 0, index < ThemeChoice.allCases.count else { return }
        let choice = ThemeChoice.allCases[index]
        store.saveTheme(choice)
        if let window = view.window {
            AppDelegate.apply(theme: choice, to: window)
        }
        statusMessage = "Appearance set to \(choice.label)."
        render()
    }

    @objc private func clearCompletedTapped() {
        let removed = items.filter { $0.done }.count
        guard removed > 0 else {
            statusMessage = "No completed tasks to clear."
            render()
            return
        }
        items = ChecklistPolicy.clearCompleted(items)
        store.save(items)
        let label = removed == 1 ? "task" : "tasks"
        statusMessage = "Cleared \(removed) completed \(label)."
        render()
    }

    @objc private func restoreTapped() {
        guard let count = store.recoveryCount() else { return }
        let label = count == 1 ? "task" : "tasks"
        let alert = UIAlertController(
            title: "Restore recovery copy",
            message: "Replace the current list with the \(count) \(label) kept from unreadable saved data?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Restore", style: .default) { [weak self] _ in
            guard let self = self else { return }
            let restored = self.store.restoreRecoveryCopy()
            if !restored.items.isEmpty { self.items = restored.items }
            self.statusMessage = restored.notice ?? "Recovery copy restored."
            self.render()
        })
        present(alert, animated: true)
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    @objc private func persistNow() {
        store.save(items)
        store.saveDraft(inputField.text ?? "")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        persistNow()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            render()
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        addCurrentInput()
        return true
    }
}
