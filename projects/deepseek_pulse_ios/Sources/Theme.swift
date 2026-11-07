import UIKit

// DeepSeek Pulse — app colour layer.
//
// Every UIColor the UIKit screens use now follows the theme chosen in Widget Studio. The old
// hard-coded constants became dynamic providers, so existing views keep their names and simply
// repaint when the theme changes:
//
//   AppColors.background     -> the chosen theme's page background
//   AppColors.surface        -> card background
//   AppColors.surfaceElevated-> controls, fields, inner boxes
//   AppColors.accent/peak/offPeak/danger -> the theme's versions
//
// Cards and the navigation bar resolve these on every trait/appearance change, so switching the
// theme needs no restart. 1.0.5 shipped one fixed dark palette; the Midnight theme reproduces it
// exactly, which keeps the default look unchanged.

enum AppColors {

    private static var palette: AppAppearance { AppAppearance.current }

    static var background: UIColor { dynamic { $0.background } }
    static var surface: UIColor { dynamic { $0.surface } }
    static var surfaceElevated: UIColor { dynamic { $0.surfaceElevated } }
    static var accent: UIColor { dynamic { $0.accent } }
    static var accentSoft: UIColor { dynamic { $0.accentSoft } }
    static var peak: UIColor { dynamic { $0.peak } }
    static var offPeak: UIColor { dynamic { $0.offPeak } }
    static var text: UIColor { dynamic { $0.text } }
    static var textDim: UIColor { dynamic { $0.textDim } }
    static var danger: UIColor { dynamic { $0.danger } }

    /// The interface style the chosen palette needs.
    static var interfaceStyle: UIUserInterfaceStyle { palette.interfaceStyle }

    /// Builds a colour that re-resolves whenever the system asks for it, so a theme change or a
    /// trait collection update repaints without recreating views.
    private static func dynamic(_ resolve: @escaping (AppAppearance) -> UIColor) -> UIColor {
        UIColor { traits in
            if traits.userInterfaceStyle == .unspecified {
                return resolve(AppAppearance.current)
            }
            return resolve(AppAppearance.current)
        }
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255.0
        let green = CGFloat((hex >> 8) & 0xFF) / 255.0
        let blue = CGFloat(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: 1.0)
    }
}

enum Typography {
    static func scaled(_ size: CGFloat, _ weight: UIFont.Weight, style: UIFont.TextStyle = .body) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: base, maximumPointSize: size * 1.6)
    }

    static func digits(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        let base = UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        return UIFontMetrics(forTextStyle: .title1).scaledFont(for: base, maximumPointSize: size * 1.35)
    }
}

enum Labels {
    static func title(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = Typography.scaled(15, .bold, style: .headline)
        label.textColor = AppColors.text
        label.numberOfLines = 0
        return label
    }

    static func body(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = Typography.scaled(13, .medium)
        label.textColor = AppColors.textDim
        label.numberOfLines = 0
        return label
    }

    static func caption(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = Typography.scaled(11.5, .medium, style: .caption1)
        label.textColor = AppColors.textDim
        label.numberOfLines = 0
        return label
    }
}
