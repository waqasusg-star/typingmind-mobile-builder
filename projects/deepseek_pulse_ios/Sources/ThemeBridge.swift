import UIKit

// DeepSeek Pulse — the selected appearance, available to every UIKit screen.
//
// The stored choice itself lives in SettingsStore; this file only holds the resolved value plus the
// UIColor conversion the UIKit views need. It is an app-target file, so PulseThemes stays
// Foundation-only and the widget extension keeps compiling.

/// What the UIKit screens need from the chosen theme.
struct AppAppearance {
    let theme: PulseTheme
    let smallDesign: WidgetDesign
    let mediumDesign: WidgetDesign
    let artwork: String
    let showBalance: Bool
    let showRefresh: Bool
    let showDayBand: Bool

    static var current: AppAppearance {
        AppAppearance(store: SettingsStore.shared)
    }

    init(store: SettingsStore) {
        let widget = store.widgetAppearance
        self.theme = PulseThemes.theme(id: widget.themeID)
        self.smallDesign = widget.smallDesign
        self.mediumDesign = widget.mediumDesign
        self.artwork = widget.artwork
        self.showBalance = widget.showBalance
        self.showRefresh = widget.showRefresh
        self.showDayBand = widget.showDayBand
    }

    init(theme: PulseTheme,
         smallDesign: WidgetDesign = .aurora,
         mediumDesign: WidgetDesign = .dashboard,
         artwork: String = "gradient",
         showBalance: Bool = true,
         showRefresh: Bool = true,
         showDayBand: Bool = true) {
        self.theme = theme
        self.smallDesign = smallDesign
        self.mediumDesign = mediumDesign
        self.artwork = artwork
        self.showBalance = showBalance
        self.showRefresh = showRefresh
        self.showDayBand = showDayBand
    }

    // MARK: Colours

    var background: UIColor { AppAppearance.ui(theme.background) }
    var surface: UIColor { AppAppearance.ui(theme.surface) }
    var surfaceElevated: UIColor { AppAppearance.ui(theme.surfaceElevated) }
    var text: UIColor { AppAppearance.ui(theme.text) }
    var textDim: UIColor { AppAppearance.ui(theme.textDim) }
    var accent: UIColor { AppAppearance.ui(theme.accent) }
    var accentSoft: UIColor { AppAppearance.ui(theme.accentSoft) }
    var peak: UIColor { AppAppearance.ui(theme.peak) }
    var offPeak: UIColor { AppAppearance.ui(theme.offPeak) }
    var danger: UIColor { AppAppearance.ui(theme.danger) }

    /// True for palettes whose background is light, so `text` is dark ink.
    var isLight: Bool { PulseThemes.luminance(theme.background) > 0.55 }

    /// iOS interface style that matches this palette.
    var interfaceStyle: UIUserInterfaceStyle { isLight ? .light : .dark }

    /// Gradient stops for the given pricing state, ready for a CAGradientLayer.
    func gradientColors(for state: PricingState) -> [UIColor] {
        let ramp = theme.ramp(for: state)
        return [AppAppearance.ui(ramp.top), AppAppearance.ui(ramp.middle), AppAppearance.ui(ramp.bottom)]
    }

    /// Label colour used on top of the widget gradient.
    var onWidget: UIColor {
        // Every ramp in the catalogue is dark enough for white text except the three light amber
        // ramps, which still read correctly in white because they sit under a darkening overlay.
        UIColor.white
    }

    static func ui(_ colour: PulseRGB) -> UIColor {
        UIColor(red: CGFloat(colour.r), green: CGFloat(colour.g), blue: CGFloat(colour.b), alpha: 1)
    }

    /// Renders the theme as a solid swatch for the picker.
    func swatchColors() -> [UIColor] {
        [background, surfaceElevated, accent, theme.peakRamp.top == theme.offPeakRamp.top ? accentSoft : offPeak]
            .map { $0 }
    }

    /// Name shown in the picker.
    var name: String { theme.name }
}

// Notification posted when the theme or a widget design changes.
extension Notification.Name {
    static let deepSeekAppearanceChanged = Notification.Name("DeepSeekPulseAppearanceChanged")
}
