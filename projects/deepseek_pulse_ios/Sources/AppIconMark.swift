import UIKit

// DeepSeek Pulse — app icon renderer.
//
// The icon is drawn from AppIconArtwork with Core Graphics, so the build never depends on a binary
// asset being imported. Three uses:
//   * Widget Studio shows the exact mark this build carries
//   * HomeScreenShortcut installs it as a real Home Screen tile
//   * the app badge in Settings uses the same drawing
//
// 1.0.7 draws a soft radial glow behind the centred mark and states the centring result, so the
// artwork can be judged instead of guessed.

enum AppIcon {

    private static func ui(_ colour: AppIconArtwork.Colour) -> UIColor {
        UIColor(red: CGFloat(colour.r), green: CGFloat(colour.g), blue: CGFloat(colour.b), alpha: 1)
    }

    /// Renders the mark at the given square size. `opaque` fills the corners for Home Screen use;
    /// the on-screen preview keeps the iOS rounded-tile shape.
    static func image(size: CGFloat, opaque: Bool = false) -> UIImage {
        let side = max(1, size)
        let canvas = CGSize(width: side, height: side)
        let renderer = UIGraphicsImageRenderer(size: canvas)
        return renderer.image { context in
            let cg = context.cgContext
            let rect = CGRect(origin: .zero, size: canvas)

            if !opaque {
                let path = UIBezierPath(roundedRect: rect,
                                        cornerRadius: side * CGFloat(AppIconArtwork.cornerRadius))
                path.addClip()
            }

            let colours = [ui(AppIconArtwork.gradientTop).cgColor,
                           ui(AppIconArtwork.gradientBottom).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colours,
                                         locations: [0, 1]) {
                cg.drawLinearGradient(gradient,
                                      start: CGPoint(x: 0, y: 0),
                                      end: CGPoint(x: side, y: side),
                                      options: [])
            }

            // Soft glow behind the mark, so the tile has depth at 60 pt as well as at 1024 pt.
            let glowCentre = CGPoint(x: side / 2, y: side * 0.47)
            let glowColours = [ui(AppIconArtwork.glow).withAlphaComponent(0.55).cgColor,
                               ui(AppIconArtwork.glow).withAlphaComponent(0).cgColor] as CFArray
            if let glowGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                             colors: glowColours,
                                             locations: [0, 1]) {
                cg.saveGState()
                cg.drawRadialGradient(glowGradient,
                                      startCenter: glowCentre,
                                      startRadius: 0,
                                      endCenter: glowCentre,
                                      endRadius: side * CGFloat(AppIconArtwork.glowRadius),
                                      options: [])
                cg.restoreGState()
            }

            // Band track, then the active (off-peak) part of the band.
            let bandRect = CGRect(x: side * CGFloat(AppIconArtwork.bandOrigin.x),
                                  y: side * CGFloat(AppIconArtwork.bandOrigin.y),
                                  width: side * CGFloat(AppIconArtwork.bandSize.x),
                                  height: side * CGFloat(AppIconArtwork.bandSize.y))
            UIColor.white.withAlphaComponent(0.22).setFill()
            UIBezierPath(roundedRect: bandRect,
                         cornerRadius: bandRect.height / 2).fill()

            let activeRect = CGRect(x: bandRect.minX,
                                    y: bandRect.minY,
                                    width: bandRect.width * CGFloat(AppIconArtwork.bandActiveFraction),
                                    height: bandRect.height)
            ui(AppIconArtwork.accent).setFill()
            UIBezierPath(roundedRect: activeRect,
                         cornerRadius: bandRect.height / 2).fill()

            // Pulse line, drawn last so it crosses the band cleanly.
            let line = UIBezierPath()
            line.lineWidth = side * CGFloat(AppIconArtwork.pulseWidth)
            line.lineJoinStyle = .round
            line.lineCapStyle = .round
            for (index, point) in AppIconArtwork.pulse.enumerated() {
                let target = CGPoint(x: side * CGFloat(point.x), y: side * CGFloat(point.y))
                if index == 0 { line.move(to: target) } else { line.addLine(to: target) }
            }
            ui(AppIconArtwork.ink).setStroke()
            line.stroke()
        }
    }

    /// The icon the system is using, falling back to the drawn mark when no asset is installed.
    static func installedIcon(size: CGFloat = 120) -> UIImage {
        if let icon = Bundle.main.iconImage() {
            return icon
        }
        return image(size: size)
    }

    /// Whether the running bundle carries a compiled icon asset.
    static var hasBundledIcon: Bool {
        Bundle.main.iconFileName != nil || UIImage(named: "AppIcon") != nil
    }

    /// One sentence for Widget Studio, so a blank tile is never explained by guesswork.
    ///
    /// This build states the truth about the delivered bundle: the CI-generated Info.plist has no
    /// icon keys, so iOS draws its generic grid placeholder on the Home Screen. The drawing above is
    /// the same artwork shipped in Resources/AppIcon.svg for an Xcode rebuild that adds an
    /// Assets.xcassets AppIcon set.
    static var statusLine: String {
        if hasBundledIcon {
            return "This build carries a compiled app icon, so the Home Screen shows this mark."
        }
        return "The CI build has no compiled icon asset, so iOS shows its generic placeholder on the Home Screen. This is the exact artwork shipped in Resources/AppIcon.svg; adding it as an Assets.xcassets AppIcon set in Xcode replaces the placeholder."
    }

    /// Short status for the icon card title row.
    static var shortStatus: String {
        hasBundledIcon ? "Compiled icon present" : "Drawn mark - no compiled asset"
    }
}

extension Bundle {

    /// iOS stores the primary icon name in Info.plist. The controlled pipeline generates that file
    /// without an icon entry, so this returns nil there and the drawn mark is used.
    var iconFileName: String? {
        let keys = ["CFBundleIconName", "CFBundlePrimaryIcon", "CFBundleIcons"]
        for key in keys {
            if let value = object(forInfoDictionaryKey: key) as? String, !value.isEmpty {
                return value
            }
            if let value = object(forInfoDictionaryKey: key) as? [String: Any],
               let icons = value["CFBundlePrimaryIcon"] as? [String: Any],
               let names = icons["CFBundleIconFiles"] as? [String],
               let first = names.last {
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
