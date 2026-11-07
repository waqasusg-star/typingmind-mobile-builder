import Foundation

// DeepSeek Pulse — pure artwork geometry shared by the app and the widget.
//
// Foundation only. It turns a theme's artwork id plus a size into plain shapes (ellipses, dots,
// lines), so the UIKit cards and the SwiftUI widgets draw the SAME decoration instead of two
// drifting approximations. No colour work happens here: each caller converts PulseRGB values into
// its own colour type.

struct PulseArtworkEllipse: Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var fill: PulseRGB
    var alpha: Double
}

struct PulseArtworkLine: Equatable {
    var x1: Double
    var y1: Double
    var x2: Double
    var y2: Double
    var width: Double
    var alpha: Double
}

/// One flat, filled dot. `diameter` is the circle size in the same coordinate space.
struct PulseArtworkDot: Equatable {
    var x: Double
    var y: Double
    var diameter: Double
    var alpha: Double
}

/// Everything one layer draws. Coordinates are absolute points inside a width x height box.
struct PulseArtworkLayer: Equatable {
    var ellipses: [PulseArtworkEllipse] = []
    var dots: [PulseArtworkDot] = []
    var lines: [PulseArtworkLine] = []

    var isEmpty: Bool { ellipses.isEmpty && dots.isEmpty && lines.isEmpty }
}

enum PulseThemesArtwork {

    /// Artwork ids a theme can use. Mirrors PulseThemes.artworkOptions; kept here so this file does
    /// not depend on the catalogue.
    static let supported = ["gradient", "sunset", "dot", "grid", "rings", "none"]

    /// Builds the decoration for `artwork` inside a `width` x `height` box.
    ///
    /// - Parameters:
    ///   - state: the pricing state, so the artwork can take the peak or off-peak accent.
    ///   - reduced: when true (Reduce Transparency / light chrome), only the faint decorations are
    ///     produced so text keeps its contrast.
    static func layer(artwork: String,
                      theme: PulseTheme,
                      state: PricingState,
                      width: Double,
                      height: Double,
                      reduced: Bool = false) -> PulseArtworkLayer {
        var layer = PulseArtworkLayer()
        guard width > 1, height > 1 else { return layer }
        let accent = stateColour(state, theme: theme)
        let w = width
        let h = height

        switch artwork {
        case "sunset":
            // A low sun and two horizon bands: warm, but still only decoration behind text.
            let horizon = h * 0.72
            layer.ellipses.append(PulseArtworkEllipse(x: w * 0.58, y: horizon - h * 0.34,
                                                      width: h * 0.68, height: h * 0.68,
                                                      fill: accent, alpha: reduced ? 0.10 : 0.22))
            layer.ellipses.append(PulseArtworkEllipse(x: w * 0.66, y: horizon - h * 0.26,
                                                      width: h * 0.50, height: h * 0.50,
                                                      fill: theme.peak, alpha: reduced ? 0.08 : 0.18))
            layer.lines.append(PulseArtworkLine(x1: 0, y1: horizon, x2: w, y2: horizon,
                                                width: 1.5, alpha: 0.16))
            layer.lines.append(PulseArtworkLine(x1: 0, y1: horizon + h * 0.14,
                                                x2: w, y2: horizon + h * 0.14,
                                                width: 1, alpha: 0.10))
        case "dot":
            // A dot field, subdivided again on wide boxes so dots stay small.
            let wide = w > h * 1.6
            let columns = wide ? 12 : 8
            let rows = wide ? 6 : 5
            let stepX = w / Double(columns)
            let stepY = h / Double(rows)
            let diameter = min(stepX, stepY) * 0.16
            for row in 0..<rows {
                for column in 0..<columns {
                    let strong = (row + column) % 4 == 0
                    layer.dots.append(PulseArtworkDot(x: stepX * (Double(column) + 0.5),
                                                      y: stepY * (Double(row) + 0.5),
                                                      diameter: diameter,
                                                      alpha: strong ? 0.20 : 0.10))
                }
            }
        case "grid":
            let step = max(18.0, min(w, h) / 6)
            var x = step
            while x < w {
                layer.lines.append(PulseArtworkLine(x1: x, y1: 0, x2: x, y2: h, width: 0.5, alpha: 0.10))
                x += step
            }
            var y = step
            while y < h {
                layer.lines.append(PulseArtworkLine(x1: 0, y1: y, x2: w, y2: y, width: 0.5, alpha: 0.10))
                y += step
            }
        case "rings":
            // Concentric outlines offset to one corner; callers stroke them.
            let base = min(w, h)
            for index in 0..<4 {
                let inset = Double(index) * base * 0.16
                layer.ellipses.append(PulseArtworkEllipse(x: w * 0.52 + inset * 0.5,
                                                          y: h * 0.14 + inset * 0.5,
                                                          width: base * 0.9 - inset,
                                                          height: base * 0.9 - inset,
                                                          fill: accent,
                                                          alpha: 0.16 - Double(index) * 0.025))
            }
        default:
            // "gradient" and "none" add no shapes; the gradient itself is the artwork.
            break
        }
        return layer
    }

    /// The accent a decoration takes for a pricing state.
    static func stateColour(_ state: PricingState, theme: PulseTheme) -> PulseRGB {
        switch state {
        case .peak: return theme.peak
        case .offPeak: return theme.offPeak
        case .standard: return theme.accent
        }
    }

    /// Human name used by Widget Studio and the theme picker.
    static func name(_ artwork: String) -> String {
        switch artwork {
        case "gradient": return "Gradient"
        case "sunset": return "Sunset horizon"
        case "dot": return "Dot field"
        case "grid": return "Grid"
        case "rings": return "Rings"
        case "none": return "Plain"
        default: return artwork
        }
    }
}
