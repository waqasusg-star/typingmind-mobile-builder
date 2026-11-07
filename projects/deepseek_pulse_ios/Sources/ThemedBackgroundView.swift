import UIKit

// DeepSeek Pulse — themed backdrop for the app's own cards and screen background.
//
// The palette already reached the label and card colours; 1.0.9 adds the artwork layer, so choosing
// Neon or Retro changes the app background and the widgets together instead of only the widget.
// The shapes come from Shared/ThemeArtworkCore.swift, which the widget uses too, so the two never
// drift apart.

/// A view that paints the gradient plus the artwork of the active theme.
final class ThemedBackgroundView: UIView {

    private var theme: PulseTheme = PulseThemes.fallback
    private var artwork: String = "gradient"
    private var state: PricingState = .standard
    private var showsGradient: Bool = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Updates the theme, artwork and pricing state and repaints.
    func apply(appearance: AppAppearance, state: PricingState, showsGradient: Bool = true) {
        self.theme = appearance.theme
        self.artwork = appearance.artwork
        self.state = state
        self.showsGradient = showsGradient
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard rect.width > 1, rect.height > 1 else { return }
        let context = UIGraphicsGetCurrentContext()
        context?.saveGState()

        if showsGradient {
            let ramp = theme.ramp(for: state)
            let colours = [Self.ui(ramp.top).cgColor,
                           Self.ui(ramp.middle).cgColor,
                           Self.ui(ramp.bottom).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colours,
                                         locations: [0, 0.55, 1]) {
                context?.drawLinearGradient(gradient,
                                            start: CGPoint(x: rect.minX, y: rect.minY),
                                            end: CGPoint(x: rect.maxX, y: rect.maxY),
                                            options: [])
            }
        }

        let layer = PulseThemesArtwork.layer(artwork: artwork,
                                             theme: theme,
                                             state: state,
                                             width: Double(rect.width),
                                             height: Double(rect.height))

        for dot in layer.dots {
            UIColor.white.withAlphaComponent(dot.alpha).setFill()
            UIBezierPath(ovalIn: CGRect(x: dot.x - dot.diameter / 2,
                                        y: dot.y - dot.diameter / 2,
                                        width: dot.diameter,
                                        height: dot.diameter)).fill()
        }
        for line in layer.lines {
            UIColor.white.withAlphaComponent(line.alpha).setStroke()
            let path = UIBezierPath()
            path.lineWidth = line.width
            path.move(to: CGPoint(x: line.x1, y: line.y1))
            path.addLine(to: CGPoint(x: line.x2, y: line.y2))
            path.stroke()
        }
        for ellipse in layer.ellipses {
            let box = CGRect(x: ellipse.x, y: ellipse.y,
                             width: max(0, ellipse.width), height: max(0, ellipse.height))
            guard box.width > 0, box.height > 0 else { continue }
            let path = UIBezierPath(ovalIn: box)
            let colour = Self.ui(ellipse.fill).withAlphaComponent(ellipse.alpha)
            if artwork == "rings" {
                path.lineWidth = 1
                colour.setStroke()
                path.stroke()
            } else {
                colour.setFill()
                path.fill()
            }
        }

        context?.restoreGState()
    }

    private static func ui(_ colour: PulseRGB) -> UIColor {
        UIColor(red: CGFloat(colour.r),
                green: CGFloat(colour.g),
                blue: CGFloat(colour.b),
                alpha: 1)
    }
}

/// Installs a ThemedBackgroundView behind any view controller, sized to its view.
enum ThemedBackgroundInstaller {

    private static let tag = 0x7E4D

    /// Adds or updates the themed backdrop and keeps it at the back of the hierarchy.
    static func install(in controller: UIViewController) {
        let backdrop: ThemedBackgroundView
        if let existing = controller.view.viewWithTag(tag) as? ThemedBackgroundView {
            backdrop = existing
        } else {
            backdrop = ThemedBackgroundView(frame: .zero)
            backdrop.tag = tag
            backdrop.translatesAutoresizingMaskIntoConstraints = false
            controller.view.insertSubview(backdrop, at: 0)
            NSLayoutConstraint.activate([
                backdrop.topAnchor.constraint(equalTo: controller.view.topAnchor),
                backdrop.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
                backdrop.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
                backdrop.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor)
            ])
        }
        let appearance = AppAppearance.current
        let state = SettingsStore.shared.schedule.state(at: Date())
        backdrop.apply(appearance: appearance, state: state)
    }
}
