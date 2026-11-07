import UIKit

enum AppColors {
    static let background = UIColor(hex: 0x0E0E15)
    static let surface = UIColor(hex: 0x1B1B27)
    static let raised = UIColor(hex: 0x262633)
    static let stroke = UIColor(hex: 0x353544)
    static let muted = UIColor(hex: 0xAFADC4)
    static let accent = UIColor(hex: 0xA491FF)
    static let accentSoft = UIColor(hex: 0xA491FF, alpha: 0.16)
    static let card = UIColor(hex: 0x141420)
    static let overlay = UIColor(hex: 0x14141E)
    static let danger = UIColor(hex: 0xFF627D)
    static let heart = UIColor(hex: 0xFF3B5C)
    static let text = UIColor(hex: 0xF6F5FA)
    static let selected = UIColor(hex: 0x312B42)
}

/// One spacing scale for every screen: 4/8/12/16/20/24/32.
enum Layout {
    static let hair: CGFloat = 4
    static let tight: CGFloat = 8
    static let snug: CGFloat = 12
    static let regular: CGFloat = 16
    static let loose: CGFloat = 20
    static let wide: CGFloat = 24
    static let section: CGFloat = 32

    static let screenInset: CGFloat = 16
    static let cardRadius: CGFloat = 18
    static let controlRadius: CGFloat = 14
    static let chipRadius: CGFloat = 12

    /// Minimum touch target (Apple HIG).
    static let tap: CGFloat = 44
    static let posterSmall = CGSize(width: 72, height: 104)
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

enum Theme {
    /// Dynamic Type aware: `size` is the base point size, scaled by the user's text setting.
    static func label(_ text: String,
                      size: CGFloat = 16,
                      weight: UIFont.Weight = .regular,
                      color: UIColor = AppColors.text,
                      lines: Int = 1,
                      align: NSTextAlignment = .left,
                      scale: Bool = true) -> UILabel {
        let view = UILabel()
        view.text = text
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        view.font = scale ? UIFontMetrics.default.scaledFont(for: base) : base
        view.adjustsFontForContentSizeCategory = scale
        view.textColor = color
        view.numberOfLines = lines
        view.textAlignment = align
        view.adjustsFontSizeToFitWidth = lines == 1
        view.minimumScaleFactor = 0.75
        return view
    }

    static func time(_ seconds: Double) -> String {
        let safe = seconds.isFinite ? seconds : 0
        let total = Int(max(0, safe).rounded(.down))
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func bytes(_ value: Int64) -> String {
        guard value > 0 else { return "" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: value)
    }

    /// 0.34 -> "34%", clamped and NaN-safe so a broken progress value never prints garbage.
    static func percent(_ value: Double) -> String {
        let safe = value.isFinite ? min(1, max(0, value)) : 0
        return "\(Int((safe * 100).rounded()))%"
    }

    static var reducesMotion: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    static func animate(_ duration: TimeInterval, _ changes: @escaping () -> Void, completion: (() -> Void)? = nil) {
        guard !reducesMotion else {
            changes()
            completion?()
            return
        }
        UIView.animate(withDuration: duration, animations: changes, completion: { _ in completion?() })
    }

    /// Shared card treatment: surface fill, hairline stroke, continuous corners.
    static func cardStyle(_ view: UIView, radius: CGFloat = Layout.cardRadius, fill: UIColor = AppColors.surface) {
        view.backgroundColor = fill
        view.layer.cornerRadius = radius
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 1
        view.layer.borderColor = AppColors.stroke.cgColor
    }

    static func pillar(_ button: UIButton, _ title: String, fill: UIColor = AppColors.raised) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(AppColors.text, for: .normal)
        button.titleLabel?.font = UIFontMetrics.default.scaledFont(for: .systemFont(ofSize: 14, weight: .semibold))
        button.backgroundColor = fill
        button.layer.cornerRadius = Layout.chipRadius
        button.layer.cornerCurve = .continuous
        button.heightAnchor.constraint(equalToConstant: Layout.tap).isActive = true
    }

    static func primary(_ button: UIButton, _ title: String) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(AppColors.background, for: .normal)
        button.titleLabel?.font = UIFontMetrics.default.scaledFont(for: .systemFont(ofSize: 15, weight: .semibold))
        button.backgroundColor = AppColors.accent
        button.layer.cornerRadius = Layout.controlRadius
        button.layer.cornerCurve = .continuous
        button.heightAnchor.constraint(equalToConstant: 48).isActive = true
    }

    static func glyph(_ symbol: String, point: CGFloat, weight: UIImage.SymbolWeight = .semibold) -> UIImage? {
        UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: point, weight: weight))
    }

    /// Poster fallback that stays legible when a series has no cached artwork yet.
    static func posterPlaceholder(into view: UIImageView) {
        view.image = glyph("film", point: 22)
        view.tintColor = AppColors.accent
        view.contentMode = .center
        view.backgroundColor = AppColors.raised
    }

    static func emptyState(symbol: String, title: String, message: String) -> UIView {
        let container = UIView()
        let badge = UIView()
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.backgroundColor = AppColors.accentSoft
        badge.layer.cornerRadius = 26
        badge.layer.cornerCurve = .continuous

        let icon = UIImageView(image: glyph(symbol, point: 24))
        icon.tintColor = AppColors.accent
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.isAccessibilityElement = false
        badge.addSubview(icon)

        let heading = label(title, size: 18, weight: .bold, align: .center, scale: false)
        heading.numberOfLines = 2
        let body = label(message, size: 14, color: AppColors.muted, lines: 0, align: .center, scale: false)
        let stack = UIStackView(arrangedSubviews: [badge, heading, body])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = Layout.snug
        stack.setCustomSpacing(Layout.loose, after: badge)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 52),
            badge.heightAnchor.constraint(equalToConstant: 52),
            icon.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 28),
            icon.heightAnchor.constraint(equalToConstant: 28),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 48),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Layout.wide),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Layout.wide),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -48)
        ])
        container.isAccessibilityElement = true
        container.accessibilityLabel = title
        container.accessibilityHint = message
        return container
    }
}

/// Rounded square target shared by the browser dock and the player action rail.
final class SquareAction: UIView {
    let control = UIButton(type: .custom)
    let caption: UILabel
    var onTap: (() -> Void)?
    private let side: Bool
    private var accentState = false

    init(symbol: String, title: String, size: CGFloat = 64, accented: Bool = false, side: Bool = false) {
        self.side = side
        self.accentState = accented
        caption = Theme.label(title, size: side ? 10 : 11,
                              color: side ? AppColors.muted : AppColors.text,
                              align: .center, scale: false)
        super.init(frame: .zero)
        control.translatesAutoresizingMaskIntoConstraints = false
        caption.translatesAutoresizingMaskIntoConstraints = false
        addSubview(control)
        addSubview(caption)
        NSLayoutConstraint.activate([
            control.topAnchor.constraint(equalTo: topAnchor),
            control.centerXAnchor.constraint(equalTo: centerXAnchor),
            control.widthAnchor.constraint(equalToConstant: size),
            control.heightAnchor.constraint(equalToConstant: size),
            caption.topAnchor.constraint(equalTo: control.bottomAnchor, constant: side ? Layout.hair : 5),
            caption.leadingAnchor.constraint(equalTo: leadingAnchor),
            caption.trailingAnchor.constraint(equalTo: trailingAnchor),
            caption.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        control.layer.cornerRadius = side ? 16 : 15
        control.layer.cornerCurve = .continuous
        control.layer.borderWidth = 1
        control.layer.shadowColor = UIColor.black.cgColor
        control.layer.shadowOpacity = accented ? 0.28 : 0
        control.layer.shadowRadius = accented ? 12 : 0
        control.layer.shadowOffset = CGSize(width: 0, height: 6)
        setSymbol(symbol)
        applyAccent(accented)
        control.addTarget(self, action: #selector(fire), for: .touchUpInside)
        control.addTarget(self, action: #selector(pressDown), for: [.touchDown, .touchDragEnter])
        control.addTarget(self, action: #selector(pressUp), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
        control.isAccessibilityElement = true
        control.accessibilityTraits = .button
        control.accessibilityLabel = title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setSymbol(_ symbol: String) {
        control.setImage(Theme.glyph(symbol, point: side ? 18 : 22), for: .normal)
    }

    func setTitle(_ value: String) {
        caption.text = value
        control.accessibilityLabel = value
    }

    func setAccent(_ value: Bool) {
        applyAccent(value)
    }

    private func applyAccent(_ value: Bool) {
        accentState = value
        control.tintColor = value ? AppColors.background : AppColors.text
        control.backgroundColor = value ? AppColors.accent : (side ? AppColors.card : AppColors.raised)
        control.layer.borderColor = (value ? AppColors.accent : AppColors.stroke).cgColor
        caption.textColor = value ? AppColors.text : (side ? AppColors.muted : AppColors.text)
    }

    @objc private func pressDown() {
        guard !Theme.reducesMotion else { return }
        UIView.animate(withDuration: 0.12) { self.control.transform = CGAffineTransform(scaleX: 0.94, y: 0.94) }
    }

    @objc private func pressUp() {
        guard !Theme.reducesMotion else { return }
        UIView.animate(withDuration: 0.18) { self.control.transform = .identity }
    }

    @objc private func fire() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onTap?()
    }
}

extension UIView {
    func pinToEdges(of parent: UIView) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            topAnchor.constraint(equalTo: parent.topAnchor),
            bottomAnchor.constraint(equalTo: parent.bottomAnchor)
        ])
    }
}
