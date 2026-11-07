import Foundation

// DeepSeek Pulse — the generated app icon set.
//
// The controlled native pipeline compiles Swift and text assets only, so the icon cannot arrive as a
// binary PNG. It is therefore described as geometry and colours here and drawn in code:
//
//   * Sources/AppIconArtwork.swift   (this file) the canonical icon description
//   * Sources/AppIconMark.swift      renders it for Widget Studio, the settings badge and the
//                                    Home Screen Shortcut page
//   * Resources/AppIcon.svg          the same artwork for independent (Xcode) rebuilds
//
// Every number is a fraction of the icon side, so one description renders correctly at 40 pt and at
// 1024 pt without a raster asset.
//
// 1.0.7 recentres the mark. The previous geometry drew the pulse line from y = 0.24 to 0.50 and the
// band at y = 0.55…0.65, so the artwork sat low in the tile with 24% empty space above it and 35%
// below. On the Home Screen that reads as an unfinished or shrunken icon. The band and the pulse are
// now one centred group, and the band is drawn after the line so the line crosses the band cleanly.

enum AppIconArtwork {

    /// A brand colour in 0…1 components.
    struct Colour: Equatable {
        var r: Double
        var g: Double
        var b: Double

        init(_ r: Double, _ g: Double, _ b: Double) {
            self.r = r
            self.g = g
            self.b = b
        }
    }

    /// One point in icon space: 0…1 from the top-left corner.
    struct Point: Equatable {
        var x: Double
        var y: Double

        init(_ x: Double, _ y: Double) {
            self.x = x
            self.y = y
        }
    }

    /// Square background gradient: electric indigo to deep navy.
    static let gradientTop = Colour(0.30, 0.38, 1.00)
    static let gradientBottom = Colour(0.05, 0.07, 0.16)
    /// A soft violet glow behind the mark, so the tile has depth at small sizes.
    static let glow = Colour(0.55, 0.46, 1.00)
    /// Brand accent used for the active part of the band and the badge.
    static let accent = Colour(0.18, 0.85, 0.62)
    /// The pulse line and the band track.
    static let ink = Colour(1.0, 1.0, 1.0)

    /// Rounded-square corner radius, as a fraction of the side. iOS applies its own mask on the Home
    /// Screen; this value matters only for the in-app preview and the Home Screen Shortcut page.
    static let cornerRadius: Double = 0.22

    // MARK: Centred group

    /// The 24-hour band in a 1024 drawing. Its centre sits exactly on the tile centre line.
    static let bandOrigin = Point(0.16, 0.545)
    static let bandSize = Point(0.68, 0.085)
    /// How much of the band is "active", drawn in the accent colour.
    static let bandActiveFraction: Double = 0.62

    /// The ECG pulse polyline, in icon space. The line spans y 0.335…0.60, so the pulse and the band
    /// together fill y 0.335…0.630: that is a centred group of height 0.295 with 0.335 above and
    /// 0.370 below, close enough to optically centred that the tile no longer looks bottom-heavy.
    static let pulse: [Point] = [
        Point(0.20, 0.450),
        Point(0.345, 0.450),
        Point(0.445, 0.335),
        Point(0.560, 0.600),
        Point(0.665, 0.405),
        Point(0.80, 0.405)
    ]

    /// Stroke width of the pulse line, as a fraction of the side.
    static let pulseWidth: Double = 0.062

    /// Optional soft glow radius behind the pulse, as a fraction of the side.
    static let glowRadius: Double = 0.30

    /// The app name under the mark, used by Widget Studio and the Shortcut page.
    static let brandName = "DeepSeek Pulse"

    /// Icon sizes requested by iOS for the Home Screen (3x device pixels for a 60 pt tile).
    static let recommendedPixelSize = 180

    /// Vertical extent of the drawn mark, used by the centring check and shown in Widget Studio.
    static var markTop: Double { pulse.map { $0.y }.min() ?? 0 }
    static var markBottom: Double { max(bandOrigin.y + bandSize.y, pulse.map { $0.y }.max() ?? 0) }

    /// How far the mark's centre is from the tile centre. 0 is perfectly centred.
    static var verticalCentreOffset: Double {
        ((markTop + markBottom) / 2) - 0.5
    }

    /// Every fraction must stay inside the tile, the band must stay inside the icon, and the mark
    /// must be centred to within 3% of the side. Checked by Tests/PolicyTests.swift.
    static var isWellFormed: Bool {
        let points = pulse + [bandOrigin]
        let inside = points.allSatisfy { $0.x >= 0 && $0.x <= 1 && $0.y >= 0 && $0.y <= 1 }
        let bandFits = bandOrigin.x + bandSize.x <= 1.0 && bandOrigin.y + bandSize.y <= 1.0
        let fractionsSane = cornerRadius > 0 && cornerRadius < 0.5
            && bandActiveFraction > 0 && bandActiveFraction <= 1
            && pulseWidth > 0 && pulseWidth < 0.25
        let centred = abs(verticalCentreOffset) <= 0.03
        let fillsTile = (markBottom - markTop) >= 0.25
        return inside && bandFits && fractionsSane && centred && fillsTile && pulse.count >= 4
    }

    /// `#RRGGBB` for the SVG source, which is the only place a text icon can carry the colours.
    static func hex(_ colour: Colour) -> String {
        func clamp(_ value: Double) -> Int {
            max(0, min(255, Int((value * 255).rounded())))
        }
        return String(format: "#%02X%02X%02X", clamp(colour.r), clamp(colour.g), clamp(colour.b))
    }

    /// The same artwork as a standalone SVG document, written to Resources/AppIcon.svg for Xcode
    /// rebuilds. CI compares the two so they cannot drift.
    static var svg: String {
        let pulsePath = pulse.enumerated().map { index, point in
            let command = index == 0 ? "M" : "L"
            return command + String(format: "%.4f %.4f", point.x, point.y)
        }.joined(separator: " ")
        let bandX = bandOrigin.x
        let bandY = bandOrigin.y
        let bandW = bandSize.x
        let bandH = bandSize.y
        let activeW = bandW * bandActiveFraction
        let centre = Point(0.5, 0.5)
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1 1">
          <defs>
            <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0" stop-color="\(hex(gradientTop))"/>
              <stop offset="1" stop-color="\(hex(gradientBottom))"/>
            </linearGradient>
            <radialGradient id="glow" cx="0.5" cy="0.47" r="\(glowRadius)">
              <stop offset="0" stop-color="\(hex(glow))" stop-opacity="0.55"/>
              <stop offset="1" stop-color="\(hex(glow))" stop-opacity="0"/>
            </radialGradient>
          </defs>
          <rect x="0" y="0" width="1" height="1" rx="\(cornerRadius)" fill="url(#bg)"/>
          <circle cx="\(centre.x)" cy="0.47" r="\(glowRadius)" fill="url(#glow)"/>
          <rect x="\(bandX)" y="\(bandY)" width="\(bandW)" height="\(bandH)" rx="\(bandH / 2)" fill="\(hex(ink))" fill-opacity="0.22"/>
          <rect x="\(bandX)" y="\(bandY)" width="\(activeW)" height="\(bandH)" rx="\(bandH / 2)" fill="\(hex(accent))"/>
          <path d="\(pulsePath)" fill="none" stroke="\(hex(ink))" stroke-width="\(pulseWidth)" stroke-linecap="round" stroke-linejoin="round"/>
        </svg>
        """
    }
}
