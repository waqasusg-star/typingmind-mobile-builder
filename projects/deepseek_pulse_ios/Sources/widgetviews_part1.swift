import UIKit

struct WidgetPalette {
    static let gradientStart = UIColor(hex: 0x2B3BFF)
    static let gradientEnd = UIColor(hex: 0x131A2C)
    static let onWidget = UIColor.white
}

final class WidgetBackdropView: UIView {

    private let gradient = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        gradient.colors = [WidgetPalette.gradientStart.cgColor, WidgetPalette.gradientEnd.cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        layer.insertSublayer(gradient, at: 0)
        layer.masksToBounds = true
        layer.cornerCurve = .continuous
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        gradient.cornerRadius = layer.cornerRadius
    }
}
