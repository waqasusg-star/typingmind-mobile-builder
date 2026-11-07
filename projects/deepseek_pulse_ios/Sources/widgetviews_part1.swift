import UIKit

// DeepSeek Pulse — the themed backdrop used by every in-app widget preview.
//
// 1.0.7 takes the gradient stops from the chosen theme instead of two hard-coded colours, so the
// previews in Widget Studio show the same palette the real Home Screen widget will use.

struct WidgetPalette {
    static var onWidget: UIColor { UIColor.white }
}

final class WidgetBackdropView: UIView {

    private let gradient = CAGradientLayer()
    private var stops: [UIColor] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        layer.insertSublayer(gradient, at: 0)
        layer.masksToBounds = true
        layer.cornerCurve = .continuous
        isUserInteractionEnabled = false
        apply(appearance: .current, state: .standard)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Paints the backdrop from a theme and the pricing state the preview is showing.
    func apply(appearance: AppAppearance, state: PricingState) {
        let colours = appearance.gradientColors(for: state)
        if colours != stops {
            stops = colours
            gradient.colors = colours.map { $0.cgColor }
        }
        gradient.locations = [0, 0.55, 1]
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        gradient.cornerRadius = layer.cornerRadius
    }
}
