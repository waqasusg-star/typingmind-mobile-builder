import UIKit

// DeepSeek Pulse — app colour layer.
//
// Every UIColor the UIKit screens use follows the theme chosen in Widget Studio. The old hard-coded
// constants became dynamic providers, so existing views keep their names and simply repaint when the
// theme changes:
//
//   AppColors.background     -> the chosen theme's page background
//   AppColors.surface        -> card background
//   AppColors.surfaceElevated-> controls, fields, inner boxes
//   AppColors.accent/peak/offPeak/danger -> the theme's versions
//
// 1.0.7 makes the theme actually reach these colours. The previous provider ignored its trait
// argument and always resolved AppAppearance.current, which is fine for a single screen but left the
// navigation bar and any already-created window on the old palette. AppThemeRefresh now rebuilds the
// root window's background and bar appearance whenever a theme is applied.

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
        UIColor { _ in resolve(AppAppearance.current) }
    }
}

/// Applies the chosen theme to windows that already exist.
///
/// UIKit resolves the dynamic colours above on the next layout pass, but a window created before the
/// theme was stored keeps its old backgroundColor and its navigation bar colours until something asks
/// it to reload. Calling `refresh()` after `SettingsStore.saveAppearance(_:)` closes that gap.
enum AppThemeRefresh {

    static func refresh() {
        let appearance = AppAppearance.current
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                apply(appearance, to: window)
            }
        }
    }

    static func apply(_ appearance: AppAppearance, to window: UIWindow) {
        window.backgroundColor = appearance.background
        window.overrideUserInterfaceStyle = appearance.interfaceStyle

        if let navigation = window.rootViewController as? UINavigationController {
            styleNavigationBar(navigation.navigationBar, appearance: appearance)
        } else if let presented = window.rootViewController?.presentedViewController as? UINavigationController {
            styleNavigationBar(presented.navigationBar, appearance: appearance)
        }

        // Force a re-resolution of the dynamic colours in the whole hierarchy.
        window.setNeedsLayout()
        window.rootViewController?.view?.setNeedsDisplay()
    }

    static func styleNavigationBar(_ bar: UINavigationBar, appearance: AppAppearance) {
        let standard = UINavigationBarAppearance()
        standard.configureWithOpaqueBackground()
        standard.backgroundColor = appearance.background
        standard.titleTextAttributes = [.foregroundColor: appearance.text]
        standard.largeTitleTextAttributes = [.foregroundColor: appearance.text]

        let scrolled = UINavigationBarAppearance()
        scrolled.configureWithOpaqueBackground()
        scrolled.backgroundColor = appearance.background
        scrolled.titleTextAttributes = [.foregroundColor: appearance.text]
        scrolled.largeTitleTextAttributes = [.foregroundColor: appearance.text]

        bar.standardAppearance = standard
        bar.scrollEdgeAppearance = scrolled
        bar.compactAppearance = standard
        bar.tintColor = appearance.accentSoft
        bar.overrideUserInterfaceStyle = appearance.interfaceStyle
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
