import UIKit

// DeepSeek Pulse — the Settings / Widgets toolbar.
//
// The previous dashboard put Settings inside a bar-button item's menu. When that menu is not
// presented the Settings screen is unreachable, which is what happened on the signed 1.0.4 build.
// These views are plain UIButtons in a fixed-height stack, so they are always visible, always
// tappable and always have a text label next to the symbol.

final class ToolbarActionsView: UIView {

    private let settingsButton = UIButton(type: .system)
    private let widgetsButton = UIButton(type: .system)

    var onSettings: (() -> Void)?
    var onWidgets: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Fixed intrinsic height so the stack view cannot collapse the row to zero.
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 44)
    }

    private func build() {
        settingsButton.setTitle("Settings", for: .normal)
        settingsButton.setImage(UIImage(systemName: "gearshape.fill"), for: .normal)
        widgetsButton.setTitle("Widgets", for: .normal)
        widgetsButton.setImage(UIImage(systemName: "square.grid.2x2.fill"), for: .normal)

        for button in [settingsButton, widgetsButton] {
            button.tintColor = AppColors.accentSoft
            button.setTitleColor(AppColors.accentSoft, for: .normal)
            button.titleLabel?.font = Typography.scaled(13, UIFont.Weight.semibold, style: .footnote)
            button.backgroundColor = AppColors.surfaceElevated
            button.layer.cornerRadius = 12
            button.layer.cornerCurve = .continuous
            button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 14)
            button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -4, bottom: 0, right: 4)
            button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        }

        settingsButton.accessibilityLabel = "Open settings"
        widgetsButton.accessibilityLabel = "Open widget gallery help"
        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        widgetsButton.addTarget(self, action: #selector(widgetsTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [settingsButton, widgetsButton])
        stack.axis = .horizontal
        stack.spacing = 10
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    @objc private func settingsTapped() { onSettings?() }
    @objc private func widgetsTapped() { onWidgets?() }
}
