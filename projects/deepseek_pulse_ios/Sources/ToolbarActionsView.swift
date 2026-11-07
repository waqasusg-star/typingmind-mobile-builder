import UIKit

// DeepSeek Pulse — the always-visible navigation row on the dashboard.
//
// 1.0.5 introduced this row because a bar-button UIMenu was not reachable on a signed build. 1.0.7
// adds the Themes button, because the sixteen palettes shipped in 1.0.6 were unreachable: nothing in
// the UI ever opened a picker.

final class ToolbarActionsView: UIView {

    var onSettings: (() -> Void)?
    var onWidgets: (() -> Void)?
    var onThemes: (() -> Void)?

    private let settingsButton = ToolbarActionsView.makeButton(title: "Settings", symbol: "gearshape")
    private let themesButton = ToolbarActionsView.makeButton(title: "Themes", symbol: "paintpalette")
    private let widgetsButton = ToolbarActionsView.makeButton(title: "Widgets", symbol: "square.grid.2x2")

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func setUp() {
        let row = UIStackView(arrangedSubviews: [settingsButton, themesButton, widgetsButton])
        row.axis = .horizontal
        row.spacing = 10
        row.distribution = .fillEqually
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 44)
        ])

        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        themesButton.addTarget(self, action: #selector(themesTapped), for: .touchUpInside)
        widgetsButton.addTarget(self, action: #selector(widgetsTapped), for: .touchUpInside)

        refreshColours()
    }

    /// Repaints the row from the current theme. Called when a theme is applied.
    func refreshColours() {
        for button in [settingsButton, themesButton, widgetsButton] {
            button.backgroundColor = AppColors.surfaceElevated
            button.setTitleColor(AppColors.text, for: .normal)
            button.tintColor = AppColors.accentSoft
        }
    }

    private static func makeButton(title: String, symbol: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.titleLabel?.font = Typography.scaled(13, .semibold, style: .subheadline)
        button.layer.cornerRadius = 12
        button.layer.cornerCurve = .continuous
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 6)
        button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 6, bottom: 0, right: 0)
        button.accessibilityLabel = title
        return button
    }

    @objc private func settingsTapped() { onSettings?() }
    @objc private func themesTapped() { onThemes?() }
    @objc private func widgetsTapped() { onWidgets?() }
}
