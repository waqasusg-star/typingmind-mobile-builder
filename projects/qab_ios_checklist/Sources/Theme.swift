import UIKit

/// Resolved colour set for the current light/dark appearance.
struct Palette {
    let dark: Bool

    var background: UIColor {
        dark ? UIColor(red: 0.063, green: 0.075, blue: 0.098, alpha: 1)
             : UIColor(red: 0.957, green: 0.965, blue: 0.984, alpha: 1)
    }

    var surface: UIColor {
        dark ? UIColor(red: 0.102, green: 0.122, blue: 0.161, alpha: 1)
             : UIColor.white
    }

    var border: UIColor {
        dark ? UIColor(white: 0.227, alpha: 1)
             : UIColor(red: 0.863, green: 0.882, blue: 0.925, alpha: 1)
    }

    var primaryText: UIColor {
        dark ? UIColor(white: 0.949, alpha: 1)
             : UIColor(red: 0.086, green: 0.102, blue: 0.133, alpha: 1)
    }

    var secondaryText: UIColor {
        dark ? UIColor(white: 0.655, alpha: 1)
             : UIColor(red: 0.357, green: 0.392, blue: 0.455, alpha: 1)
    }

    var accent: UIColor {
        dark ? UIColor(red: 0.478, green: 0.635, blue: 1.0, alpha: 1)
             : UIColor(red: 0.184, green: 0.373, blue: 0.878, alpha: 1)
    }

    var danger: UIColor {
        dark ? UIColor(red: 1.0, green: 0.541, blue: 0.541, alpha: 1)
             : UIColor(red: 0.702, green: 0.149, blue: 0.118, alpha: 1)
    }

    func color(for priority: TaskPriority) -> UIColor {
        switch priority {
        case .high: return danger
        case .normal: return accent
        case .low: return secondaryText
        }
    }
}
