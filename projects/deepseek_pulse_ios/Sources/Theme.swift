import UIKit

enum AppColors {
    static let background = UIColor(hex: 0x0A0F1E)
    static let surface = UIColor(hex: 0x141A2E)
    static let surfaceElevated = UIColor(hex: 0x1E2742)
    static let accent = UIColor(hex: 0x4D6BFE)
    static let accentSoft = UIColor(hex: 0x9DB0FF)
    static let peak = UIColor(hex: 0xFFB020)
    static let offPeak = UIColor(hex: 0x2FD27F)
    static let text = UIColor(hex: 0xF2F5FF)
    static let textDim = UIColor(hex: 0x97A3C2)
    static let danger = UIColor(hex: 0xFF6B7A)
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
