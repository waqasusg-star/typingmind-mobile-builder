import Foundation
import SwiftUI
import WidgetKit

// DeepSeek Pulse — themed widget background.
//
// One component draws the gradient for the current pricing state plus the theme's artwork layer
// (sunset horizon, dot field, grid or concentric rings). Both the Home Screen designs and the Lock
// Screen previews use it, so a theme change is visible everywhere instead of only in a picker swatch.
//
// iOS 17 requires the container background to be declared through `containerBackground(for:)`; older
// systems take the same view as a plain background, which is what `pulseBackground` already did.

struct PulseWidgetBackdrop: View {
    var mood: PulseMood
    var state: PricingState
    var artwork: String
    var overlay: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                mood.gradient(for: state)
                PulseArtworkShape(theme: mood.theme,
                                  state: state,
                                  artwork: artwork,
                                  size: geometry.size,
                                  ink: mood.ink)
                // A soft top-left highlight keeps the card from looking flat on dark palettes.
                RadialGradient(colors: [mood.ink.opacity(0.10), Color.clear],
                               center: .topLeading,
                               startRadius: 0,
                               endRadius: max(60, geometry.size.width * 0.8))
                if overlay > 0 { Color.black.opacity(overlay) }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

/// Draws the shared artwork geometry produced by PulseThemesArtwork.
struct PulseArtworkShape: View {
    var theme: PulseTheme
    var state: PricingState
    var artwork: String
    var size: CGSize
    var ink: Color

    var body: some View {
        let layer = PulseThemesArtwork.layer(artwork: artwork,
                                             theme: theme,
                                             state: state,
                                             width: Double(size.width),
                                             height: Double(size.height))
        ZStack(alignment: .topLeading) {
            ForEach(Array(layer.dots.enumerated()), id: \.offset) { pair in
                Circle()
                    .fill(ink.opacity(pair.element.alpha))
                    .frame(width: pair.element.diameter, height: pair.element.diameter)
                    .offset(x: pair.element.x - pair.element.diameter / 2,
                            y: pair.element.y - pair.element.diameter / 2)
            }
            ForEach(Array(layer.lines.enumerated()), id: \.offset) { pair in
                Path { path in
                    path.move(to: CGPoint(x: pair.element.x1, y: pair.element.y1))
                    path.addLine(to: CGPoint(x: pair.element.x2, y: pair.element.y2))
                }
                .stroke(ink.opacity(pair.element.alpha), lineWidth: pair.element.width)
            }
            ForEach(Array(layer.ellipses.enumerated()), id: \.offset) { pair in
                // "rings" is stroked and "sunset" is filled; both come from the same ellipse list.
                let colour = PulseMood.colour(pair.element.fill)
                let width = max(0, pair.element.width)
                let height = max(0, pair.element.height)
                Group {
                    if artwork == "rings" {
                        Ellipse().stroke(colour.opacity(pair.element.alpha), lineWidth: 1)
                    } else {
                        Ellipse().fill(colour.opacity(pair.element.alpha))
                    }
                }
                .frame(width: width, height: height)
                .offset(x: pair.element.x, y: pair.element.y)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
    }
}
