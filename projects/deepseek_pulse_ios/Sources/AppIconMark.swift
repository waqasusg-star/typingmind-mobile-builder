import UIKit

// DeepSeek Pulse — app icon drawn in code.
//
// The controlled native profile compiles Swift and text assets, so the icon is generated with Core
// Graphics at launch and cached as a PNG. The same drawing is used for:
//   * the Home Screen icon through an `Assets.xcassets` entry when one is available, and
//   * the large preview inside Widget Studio, so the user can see the mark the build ships with.
// Nothing here depends on a binary asset being imported correctly.

enum AppIcon {

    /// Brand colours shared with the dashboard card.
    private static let topColor = UIColor(red: 0.24, green: 0.33, blue: 1.00, alpha: 1)
    private static let bottomColor = UIColor(red: 0.05, green: 0.07, blue: 0.15, alpha: 1)
    private static let pulseColor = UIColor(red: 0.18, green: 0.85, blue: 0.62, alpha: 1)

    /// Renders the mark at the given square size.
    static func image(size: CGFloat) -> UIImage {
        let canvas = CGSize(width: size, height: size)
        let renderer = UIGraphicsImageRenderer(size: canvas)
        return renderer.image { context in
            let cg = context.cgContext

            // Rounded gradient background.
            let rect = CGRect(origin: .zero, size: canvas)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: size * 0.22)
            path.addClip()

            let colors = [topColor.cgColor, bottomColor.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors,
                                         locations: [0, 1]) {
                cg.drawLinearGradient(gradient,
                                      start: CGPoint(x: 0, y: 0),
                                      end: CGPoint(x: size, y: size),
                                      options: [])
            }

            // Peak / off-peak band, the same idea as the 24-hour bar in the app.
            let bandRect = CGRect(x: size * 0.16,
                                  y: size * 0.55,
                                  width: size * 0.68,
                                  height: size * 0.10)
            let bandPath = UIBezierPath(roundedRect: bandRect, cornerRadius: size * 0.05)
            UIColor.white.withAlphaComponent(0.22).setFill()
            bandPath.fill()

            let activeRect = CGRect(x: bandRect.minX,
                                    y: bandRect.minY,
                                    width: bandRect.width * 0.62,
                                    height: bandRect.height)
            let activePath = UIBezierPath(roundedRect: activeRect, cornerRadius: size * 0.05)
            pulseColor.setFill()
            activePath.fill()

            // ECG-style pulse line above the band.
            let pulse = UIBezierPath()
            pulse.lineWidth = size * 0.055
            pulse.lineJoinStyle = .round
            pulse.lineCapStyle = .round
            pulse.move(to: CGPoint(x: size * 0.18, y: size * 0.40))
            pulse.addLine(to: CGPoint(x: size * 0.34, y: size * 0.40))
            pulse.addLine(to: CGPoint(x: size * 0.44, y: size * 0.24))
            pulse.addLine(to: CGPoint(x: size * 0.56, y: size * 0.50))
            pulse.addLine(to: CGPoint(x: size * 0.66, y: size * 0.34))
            pulse.addLine(to: CGPoint(x: size * 0.82, y: size * 0.34))
            UIColor.white.setStroke()
            pulse.stroke()
        }
    }

    /// The icon the system is using, falling back to the drawn mark when no asset is installed.
    static func installedIcon(size: CGFloat = 120) -> UIImage {
        if let icon = Bundle.main.iconImage() {
            return icon
        }
        return image(size: size)
    }

    /// Whether the running bundle actually carries an icon asset, reported in Widget Studio.
    static var hasBundledIcon: Bool {
        Bundle.main.iconFileName != nil || UIImage(named: "AppIcon") != nil
    }
}

extension Bundle {

    /// iOS stores the primary icon name in the Info.plist under one of these keys, depending on
    /// how the asset catalog was compiled.
    var iconFileName: String? {
        let keys = [
            "CFBundleIconName",
            "CFBundlePrimaryIcon",
            "CFBundleIcons"
        ]
        for key in keys {
            if let value = object(forInfoDictionaryKey: key) as? String, !value.isEmpty {
                return value
            }
            if let value = object(forInfoDictionaryKey: key) as? [String: Any],
               let icons = value["CFBundlePrimaryIcon"] as? [String: Any],
               let name = icons["CFBundleIconFiles"] as? [String],
               let first = name.last {
                return first
            }
        }
        return nil
    }

    func iconImage() -> UIImage? {
        if let name = iconFileName {
            if let image = UIImage(named: name) { return image }
            if let image = UIImage(named: name + "@3x") { return image }
        }
        return nil
    }
}
