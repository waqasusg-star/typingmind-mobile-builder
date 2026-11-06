import UIKit

enum AppColors {
    static let background = UIColor(hex: 0x101016)
    static let surface = UIColor(hex: 0x1D1D28)
    static let raised = UIColor(hex: 0x272735)
    static let stroke = UIColor(hex: 0x393948)
    static let muted = UIColor(hex: 0xB6B5C8)
    static let accent = UIColor(hex: 0xA491FF)
    static let card = UIColor(hex: 0x16161F)
    static let overlay = UIColor(hex: 0x161620)
    static let danger = UIColor(hex: 0xFF627D)
    static let heart = UIColor(hex: 0xFF304F)
    static let text = UIColor(hex: 0xF6F5FA)
    static let selected = UIColor(hex: 0x322B40)
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
    static func label(_ text: String,
                      size: CGFloat = 16,
                      weight: UIFont.Weight = .regular,
                      color: UIColor = AppColors.text,
                      lines: Int = 1,
                      align: NSTextAlignment = .left) -> UILabel {
        let view = UILabel()
        view.text = text
        view.font = .systemFont(ofSize: size, weight: weight)
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

    static func emptyState(symbol: String, title: String, message: String) -> UIView {
        let container = UIView()
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = AppColors.accent
        icon.contentMode = .scaleAspectFit
        let heading = label(title, size: 18, weight: .bold, align: .center)
        heading.numberOfLines = 2
        let body = label(message, size: 14, color: AppColors.muted, lines: 0, align: .center)
        let stack = UIStackView(arrangedSubviews: [icon, heading, body])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 44),
            icon.heightAnchor.constraint(equalToConstant: 44),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 40),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -40)
        ])
        return container
    }
}

/// Rounded square target shared by the browser dock and the player action rail.
final class SquareAction: UIView {
    let control = UIButton(type: .custom)
    let caption: UILabel
    var onTap: (() -> Void)?
    private let side: Bool

    init(symbol: String, title: String, size: CGFloat = 64, accented: Bool = false, side: Bool = false) {
        self.side = side
        caption = Theme.label(title, size: side ? 10 : 11, color: side ? AppColors.muted : AppColors.text, align: .center)
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
            caption.topAnchor.constraint(equalTo: control.bottomAnchor, constant: side ? 4 : 5),
            caption.leadingAnchor.constraint(equalTo: leadingAnchor),
            caption.trailingAnchor.constraint(equalTo: trailingAnchor),
            caption.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        control.layer.cornerRadius = side ? 16 : 14
        control.layer.cornerCurve = .continuous
        control.layer.borderWidth = 1
        control.backgroundColor = accented ? AppColors.accent : (side ? AppColors.card : AppColors.raised)
        control.layer.borderColor = (accented ? AppColors.accent : AppColors.stroke).cgColor
        control.tintColor = accented ? AppColors.background : AppColors.text
        setSymbol(symbol)
        control.addTarget(self, action: #selector(fire), for: .touchUpInside)
        control.isAccessibilityElement = true
        control.accessibilityLabel = title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setSymbol(_ symbol: String) {
        let point: CGFloat = side ? 18 : 22
        control.setImage(UIImage(systemName: symbol,
                                 withConfiguration: UIImage.SymbolConfiguration(pointSize: point, weight: .semibold)),
                         for: .normal)
    }

    func setTitle(_ value: String) {
        caption.text = value
        control.accessibilityLabel = value
    }

    func setAccent(_ value: Bool) {
        control.tintColor = value ? AppColors.background : AppColors.text
        control.backgroundColor = value ? AppColors.accent : (side ? AppColors.card : AppColors.raised)
        control.layer.borderColor = (value ? AppColors.accent : AppColors.stroke).cgColor
    }

    @objc private func fire() { onTap?() }
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
