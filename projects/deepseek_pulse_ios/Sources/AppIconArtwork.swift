import Foundation

// DeepSeek Pulse — the generated app icon set.
//
// The controlled native pipeline compiles Swift and text assets only, so the icon cannot arrive as a
// binary PNG. It is therefore described as geometry and colours here and drawn in code:
//
//   * Sources/AppIconSet.swift          (this file) the canonical icon description
//   * Sources/AppIconMark.swift         renders it for the Home Screen preview and the picker
//   * Sources/HomeScreenShortcut.swift  installs the same drawing as the Home Screen icon
//   * Resources/AppIcon.svg             the same artwork for independent (Xcode) rebuilds
//
// Every number is a fraction of the icon side, so one description renders correctly at 40 pt and at
// 1024 pt without a raster asset.

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

    /// Square background gradient.
    static let gradientTop = Colour(0.24, 0.33, 1.00)
    static let gradientBottom = Colour(0.05, 0.07, 0.15)
    /// Off-peak accent used for the active part of the band.
    static let accent = Colour(0.18, 0.85, 0.62)
    /// The pulse line.
    static let ink = Colour(1.0, 1.0, 1.0)

    /// Rounded-square corner radius, as a fraction of the side.
    static let cornerRadius: Double = 0.22

    /// The 24-hour band: origin and size, as fractions of the side.
    static let bandOrigin = Point(0.16, 0.55)
    static let bandSize = Point(0.68, 0.10)
    /// How much of the band is "active", drawn in the accent colour.
    static let bandActiveFraction: Double = 0.62

    /// The ECG pulse polyline, in icon space.
    static let pulse: [Point] = [
        Point(0.18, 0.40),
        Point(0.34, 0.40),
        Point(0.44, 0.24),
        Point(0.56, 0.50),
        Point(0.66, 0.34),
        Point(0.82, 0.34)
    ]

    /// Stroke width of the pulse line, as a fraction of the side.
    static let pulseWidth: Double = 0.055

    /// The app name under the mark, used by Widget Studio.
    static let brandName = "DeepSeek Pulse"

    /// Icon sizes requested by iOS for the Home Screen (3x device pixels for a 60 pt tile).
    static let recommendedPixelSize = 180

    /// Every fraction must stay inside the tile and the band must stay inside the icon.
    static var isWellFormed: Bool {
        let points = pulse + [bandOrigin]
        let inside = points.allSatisfy { $0.x >= 0 && $0.x <= 1 && $0.y >= 0 && $0.y <= 1 }
        let bandFits = bandOrigin.x + bandSize.x <= 1.0 && bandOrigin.y + bandSize.y <= 1.0
        let fractionsSane = cornerRadius > 0 && cornerRadius < 0.5
            && bandActiveFraction > 0 && bandActiveFraction <= 1
            && pulseWidth > 0 && pulseWidth < 0.25
        return inside && bandFits && fractionsSane && pulse.count >= 4
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
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1 1">
          <defs>
            <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0" stop-color="\(hex(gradientTop))"/>
              <stop offset="1" stop-color="\(hex(gradientBottom))"/>
            </linearGradient>
          </defs>
          <rect x="0" y="0" width="1" height="1" rx="\(cornerRadius)" fill="url(#bg)"/>
          <rect x="\(bandX)" y="\(bandY)" width="\(bandW)" height="\(bandH)" rx="\(bandH / 2)" fill="\(hex(ink))" fill-opacity="0.22"/>
          <rect x="\(bandX)" y="\(bandY)" width="\(activeW)" height="\(bandH)" rx="\(bandH / 2)" fill="\(hex(accent))"/>
          <path d="\(pulsePath)" fill="none" stroke="\(hex(ink))" stroke-width="\(pulseWidth)" stroke-linecap="round" stroke-linejoin="round"/>
        </svg>
        """
    }
}
