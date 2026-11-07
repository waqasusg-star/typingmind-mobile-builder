import Foundation

// DeepSeek Pulse — the theme catalogue (Core).
//
// Foundation only, compiled into BOTH targets. The catalogue holds sixteen palettes; each one carries
// app chrome colours, three widget gradients (peak, off-peak, standard) and an artwork id.
//
// App-only conversion to UIColor lives in Sources/ThemeBridge.swift, so this file stays UIKit-free
// for the widget extension and the Foundation test harness.

enum PulseThemes {

    /// Used whenever a saved id is unknown. Identical to the shipped 1.0.5 look.
    static let fallbackID = "midnight"

    /// Home Screen artwork options offered by Widget Studio.
    static let artworkOptions = ["gradient", "sunset", "dot", "grid", "rings", "none"]

    private static func c(_ r: Int, _ g: Int, _ b: Int) -> PulseRGB {
        PulseRGB(Double(r) / 255.0, Double(g) / 255.0, Double(b) / 255.0)
    }

    private static func make(_ id: String,
                             _ name: String,
                             _ artwork: String,
                             bg: PulseRGB,
                             surface: PulseRGB,
                             elevated: PulseRGB,
                             text: PulseRGB,
                             dim: PulseRGB,
                             accent: PulseRGB,
                             accentSoft: PulseRGB,
                             peak: PulseRGB,
                             offPeak: PulseRGB,
                             danger: PulseRGB,
                             peakTop: PulseRGB, peakMid: PulseRGB, peakLow: PulseRGB,
                             offTop: PulseRGB, offMid: PulseRGB, offLow: PulseRGB,
                             stdTop: PulseRGB, stdMid: PulseRGB, stdLow: PulseRGB) -> PulseTheme {
        PulseTheme(id: id,
                   name: name,
                   artwork: artwork,
                   background: bg,
                   surface: surface,
                   surfaceElevated: elevated,
                   text: text,
                   textDim: dim,
                   accent: accent,
                   accentSoft: accentSoft,
                   peak: peak,
                   offPeak: offPeak,
                   danger: danger,
                   peakRamp: PulseRamp(top: peakTop, middle: peakMid, bottom: peakLow),
                   offPeakRamp: PulseRamp(top: offTop, middle: offMid, bottom: offLow),
                   standardRamp: PulseRamp(top: stdTop, middle: stdMid, bottom: stdLow))
    }

    /// Every theme, in the order Widget Studio lists them.
    static let all: [PulseTheme] = [
        make("midnight", "Midnight", "gradient",
             bg: c(10, 15, 30), surface: c(20, 26, 46), elevated: c(30, 39, 66),
             text: c(242, 245, 255), dim: c(151, 163, 194),
             accent: c(77, 107, 254), accentSoft: c(157, 176, 255),
             peak: c(255, 176, 32), offPeak: c(47, 210, 127), danger: c(255, 107, 122),
             peakTop: c(250, 148, 33), peakMid: c(190, 96, 20), peakLow: c(82, 41, 15),
             offTop: c(46, 184, 128), offMid: c(20, 120, 92), offLow: c(13, 61, 51),
             stdTop: c(77, 107, 254), stdMid: c(41, 56, 158), stdLow: c(18, 26, 46)),

        make("ocean", "Ocean", "gradient",
             bg: c(5, 20, 34), surface: c(9, 33, 52), elevated: c(15, 48, 74),
             text: c(232, 248, 255), dim: c(130, 172, 195),
             accent: c(0, 158, 214), accentSoft: c(120, 214, 245),
             peak: c(255, 190, 90), offPeak: c(64, 224, 190), danger: c(255, 120, 130),
             peakTop: c(255, 173, 66), peakMid: c(190, 108, 30), peakLow: c(60, 36, 12),
             offTop: c(52, 216, 200), offMid: c(16, 128, 150), offLow: c(6, 48, 66),
             stdTop: c(0, 148, 214), stdMid: c(6, 78, 130), stdLow: c(4, 26, 44)),

        make("sunset", "Sunset", "sunset",
             bg: c(28, 12, 24), surface: c(46, 20, 36), elevated: c(66, 29, 50),
             text: c(255, 240, 238), dim: c(206, 155, 165),
             accent: c(255, 94, 120), accentSoft: c(255, 170, 160),
             peak: c(255, 150, 70), offPeak: c(110, 220, 170), danger: c(255, 92, 100),
             peakTop: c(255, 132, 74), peakMid: c(206, 70, 60), peakLow: c(90, 24, 44),
             offTop: c(96, 208, 170), offMid: c(30, 128, 110), offLow: c(16, 56, 60),
             stdTop: c(255, 94, 120), stdMid: c(170, 54, 108), stdLow: c(52, 18, 44)),

        make("forest", "Forest", "dot",
             bg: c(9, 24, 18), surface: c(16, 37, 28), elevated: c(24, 52, 40),
             text: c(235, 250, 240), dim: c(146, 182, 160),
             accent: c(64, 178, 120), accentSoft: c(160, 226, 180),
             peak: c(232, 190, 80), offPeak: c(86, 224, 160), danger: c(240, 120, 110),
             peakTop: c(214, 176, 66), peakMid: c(150, 112, 34), peakLow: c(46, 42, 16),
             offTop: c(64, 190, 128), offMid: c(24, 112, 82), offLow: c(10, 44, 34),
             stdTop: c(52, 150, 108), stdMid: c(28, 92, 72), stdLow: c(12, 34, 28)),

        make("rose", "Rose", "rings",
             bg: c(28, 14, 26), surface: c(44, 22, 40), elevated: c(62, 31, 56),
             text: c(255, 240, 248), dim: c(206, 160, 190),
             accent: c(226, 92, 160), accentSoft: c(255, 170, 210),
             peak: c(255, 168, 96), offPeak: c(120, 220, 190), danger: c(255, 96, 128),
             peakTop: c(255, 150, 110), peakMid: c(200, 76, 96), peakLow: c(84, 26, 50),
             offTop: c(130, 220, 200), offMid: c(40, 130, 130), offLow: c(20, 54, 66),
             stdTop: c(226, 92, 160), stdMid: c(148, 50, 116), stdLow: c(52, 18, 44)),

        make("mint", "Mint", "gradient",
             bg: c(238, 252, 246), surface: c(255, 255, 255), elevated: c(214, 242, 231),
             text: c(16, 46, 38), dim: c(88, 122, 110),
             accent: c(18, 150, 118), accentSoft: c(46, 166, 138),
             peak: c(196, 128, 22), offPeak: c(14, 146, 104), danger: c(196, 60, 70),
             peakTop: c(255, 226, 150), peakMid: c(246, 182, 92), peakLow: c(190, 128, 60),
             offTop: c(214, 250, 234), offMid: c(148, 226, 200), offLow: c(96, 186, 160),
             stdTop: c(232, 250, 244), stdMid: c(196, 236, 224), stdLow: c(150, 206, 192)),

        make("cyberpunk", "Cyberpunk", "grid",
             bg: c(12, 8, 26), surface: c(24, 12, 44), elevated: c(38, 18, 64),
             text: c(240, 234, 255), dim: c(168, 150, 205),
             accent: c(254, 44, 128), accentSoft: c(120, 226, 255),
             peak: c(255, 214, 0), offPeak: c(0, 240, 214), danger: c(255, 70, 110),
             peakTop: c(255, 196, 0), peakMid: c(200, 92, 160), peakLow: c(60, 16, 76),
             offTop: c(0, 226, 214), offMid: c(0, 128, 176), offLow: c(8, 28, 64),
             stdTop: c(254, 44, 128), stdMid: c(120, 34, 168), stdLow: c(24, 10, 46)),

        make("sand", "Sand", "dot",
             bg: c(38, 32, 24), surface: c(54, 46, 35), elevated: c(72, 62, 47),
             text: c(255, 248, 236), dim: c(198, 178, 150),
             accent: c(214, 156, 84), accentSoft: c(240, 206, 150),
             peak: c(236, 168, 66), offPeak: c(160, 202, 120), danger: c(220, 110, 96),
             peakTop: c(230, 172, 90), peakMid: c(170, 116, 58), peakLow: c(66, 44, 24),
             offTop: c(168, 200, 132), offMid: c(104, 138, 84), offLow: c(44, 56, 36),
             stdTop: c(196, 150, 96), stdMid: c(132, 100, 64), stdLow: c(48, 38, 26)),

        make("graphite", "Graphite", "none",
             bg: c(16, 16, 18), surface: c(28, 28, 31), elevated: c(40, 40, 44),
             text: c(242, 242, 245), dim: c(148, 148, 156),
             accent: c(126, 140, 158), accentSoft: c(186, 196, 210),
             peak: c(214, 214, 222), offPeak: c(150, 170, 170), danger: c(226, 96, 104),
             peakTop: c(86, 86, 94), peakMid: c(52, 52, 58), peakLow: c(22, 22, 26),
             offTop: c(64, 70, 76), offMid: c(40, 44, 48), offLow: c(18, 20, 22),
             stdTop: c(70, 70, 78), stdMid: c(44, 44, 50), stdLow: c(20, 20, 24)),

        make("emerald", "Emerald", "rings",
             bg: c(3, 26, 22), surface: c(8, 42, 36), elevated: c(13, 60, 51),
             text: c(232, 255, 248), dim: c(126, 176, 162),
             accent: c(0, 196, 140), accentSoft: c(126, 240, 200),
             peak: c(255, 206, 84), offPeak: c(64, 232, 168), danger: c(255, 110, 120),
             peakTop: c(248, 192, 74), peakMid: c(176, 126, 30), peakLow: c(56, 42, 12),
             offTop: c(46, 208, 154), offMid: c(10, 122, 96), offLow: c(4, 46, 40),
             stdTop: c(0, 176, 132), stdMid: c(4, 96, 80), stdLow: c(4, 34, 30)),

        make("crimson", "Crimson", "gradient",
             bg: c(26, 10, 14), surface: c(44, 17, 23), elevated: c(64, 25, 33),
             text: c(255, 238, 238), dim: c(204, 152, 158),
             accent: c(224, 58, 74), accentSoft: c(255, 150, 150),
             peak: c(255, 152, 74), offPeak: c(96, 216, 180), danger: c(255, 82, 96),
             peakTop: c(255, 140, 90), peakMid: c(190, 60, 66), peakLow: c(70, 16, 30),
             offTop: c(88, 204, 172), offMid: c(28, 118, 108), offLow: c(12, 46, 48),
             stdTop: c(214, 46, 70), stdMid: c(140, 26, 56), stdLow: c(44, 12, 26)),

        make("nordic", "Nordic", "none",
             bg: c(46, 52, 64), surface: c(59, 66, 82), elevated: c(76, 86, 106),
             text: c(236, 239, 244), dim: c(176, 188, 206),
             accent: c(136, 192, 208), accentSoft: c(180, 220, 232),
             peak: c(235, 203, 139), offPeak: c(163, 190, 140), danger: c(191, 97, 106),
             peakTop: c(214, 176, 118), peakMid: c(150, 122, 88), peakLow: c(62, 54, 50),
             offTop: c(140, 170, 124), offMid: c(96, 122, 96), offLow: c(46, 60, 52),
             stdTop: c(104, 138, 158), stdMid: c(70, 96, 116), stdLow: c(38, 46, 60)),

        make("lavender", "Lavender", "rings",
             bg: c(244, 240, 255), surface: c(255, 255, 255), elevated: c(228, 220, 250),
             text: c(42, 32, 66), dim: c(120, 108, 150),
             accent: c(124, 92, 214), accentSoft: c(92, 62, 172),
             peak: c(190, 118, 30), offPeak: c(46, 150, 132), danger: c(198, 62, 78),
             peakTop: c(255, 226, 178), peakMid: c(238, 190, 150), peakLow: c(196, 152, 150),
             offTop: c(220, 244, 236), offMid: c(168, 218, 208), offLow: c(140, 180, 190),
             stdTop: c(240, 236, 255), stdMid: c(206, 196, 244), stdLow: c(170, 158, 220)),

        make("solar", "Solar", "sunset",
             bg: c(32, 22, 8), surface: c(48, 34, 12), elevated: c(66, 47, 18),
             text: c(255, 247, 230), dim: c(212, 184, 132),
             accent: c(240, 168, 32), accentSoft: c(255, 214, 120),
             peak: c(255, 200, 40), offPeak: c(140, 210, 120), danger: c(240, 110, 90),
             peakTop: c(255, 186, 40), peakMid: c(196, 112, 18), peakLow: c(70, 36, 8),
             offTop: c(140, 200, 116), offMid: c(84, 130, 70), offLow: c(34, 52, 30),
             stdTop: c(208, 140, 30), stdMid: c(140, 88, 22), stdLow: c(48, 30, 10)),

        make("arctic", "Arctic", "grid",
             bg: c(236, 246, 255), surface: c(255, 255, 255), elevated: c(214, 232, 248),
             text: c(18, 38, 60), dim: c(92, 122, 150),
             accent: c(32, 118, 200), accentSoft: c(58, 140, 220),
             peak: c(196, 122, 26), offPeak: c(20, 138, 132), danger: c(198, 64, 74),
             peakTop: c(255, 232, 186), peakMid: c(242, 198, 140), peakLow: c(196, 158, 128),
             offTop: c(214, 240, 250), offMid: c(160, 208, 236), offLow: c(124, 176, 216),
             stdTop: c(232, 244, 255), stdMid: c(186, 218, 244), stdLow: c(150, 190, 230)),

        make("mono", "Mono", "none",
             bg: c(10, 10, 10), surface: c(22, 22, 22), elevated: c(34, 34, 34),
             text: c(250, 250, 250), dim: c(150, 150, 150),
             accent: c(200, 200, 200), accentSoft: c(230, 230, 230),
             peak: c(236, 236, 236), offPeak: c(170, 170, 170), danger: c(220, 90, 90),
             peakTop: c(96, 96, 96), peakMid: c(56, 56, 56), peakLow: c(20, 20, 20),
             offTop: c(64, 64, 64), offMid: c(40, 40, 40), offLow: c(16, 16, 16),
             stdTop: c(72, 72, 72), stdMid: c(42, 42, 42), stdLow: c(16, 16, 16)),

        make("neon", "Neon", "grid",
             bg: c(6, 10, 20), surface: c(12, 20, 34), elevated: c(18, 30, 50),
             text: c(226, 255, 250), dim: c(120, 180, 186),
             accent: c(38, 255, 190), accentSoft: c(255, 92, 190),
             peak: c(255, 224, 64), offPeak: c(38, 255, 190), danger: c(255, 84, 120),
             peakTop: c(255, 210, 40), peakMid: c(220, 84, 160), peakLow: c(40, 10, 60),
             offTop: c(20, 232, 190), offMid: c(8, 140, 170), offLow: c(6, 30, 60),
             stdTop: c(40, 200, 255), stdMid: c(30, 90, 200), stdLow: c(8, 16, 44)),

        make("blossom", "Blossom", "dot",
             bg: c(255, 245, 246), surface: c(255, 255, 255), elevated: c(252, 226, 232),
             text: c(70, 30, 42), dim: c(150, 110, 122),
             accent: c(214, 74, 116), accentSoft: c(196, 82, 112),
             peak: c(190, 110, 24), offPeak: c(28, 142, 120), danger: c(196, 52, 66),
             peakTop: c(255, 224, 196), peakMid: c(246, 186, 170), peakLow: c(214, 150, 158),
             offTop: c(226, 246, 240), offMid: c(176, 222, 210), offLow: c(150, 190, 190),
             stdTop: c(255, 240, 244), stdMid: c(246, 206, 218), stdLow: c(222, 170, 190)),

        make("retro", "Retro", "sunset",
             bg: c(34, 26, 20), surface: c(52, 40, 30), elevated: c(70, 54, 40),
             text: c(255, 240, 214), dim: c(200, 172, 138),
             accent: c(224, 122, 54), accentSoft: c(246, 196, 120),
             peak: c(246, 176, 60), offPeak: c(122, 190, 130), danger: c(226, 96, 78),
             peakTop: c(246, 162, 66), peakMid: c(186, 96, 44), peakLow: c(62, 36, 22),
             offTop: c(126, 186, 132), offMid: c(76, 124, 92), offLow: c(30, 50, 40),
             stdTop: c(214, 124, 58), stdMid: c(140, 82, 48), stdLow: c(48, 32, 22))
    ]

    static var count: Int { all.count }

    static var fallback: PulseTheme {
        all.first { $0.id == fallbackID } ?? all[0]
    }

    static func contains(id: String) -> Bool {
        all.contains { $0.id == id }
    }

    /// Resolves an id, falling back to Midnight for unknown ids.
    static func theme(id: String) -> PulseTheme {
        all.first { $0.id == id } ?? fallback
    }

    static func theme(at index: Int) -> PulseTheme {
        guard index >= 0, index < all.count else { return fallback }
        return all[index]
    }

    static func index(of id: String) -> Int {
        all.firstIndex { $0.id == id } ?? all.firstIndex { $0.id == fallbackID } ?? 0
    }

    /// No duplicate ids, every palette displayable, every artwork known, at least ten themes.
    static var isConsistent: Bool {
        var ids = Set<String>()
        for theme in all {
            if ids.contains(theme.id) { return false }
            ids.insert(theme.id)
            if !theme.isDisplayable { return false }
            if !artworkOptions.contains(theme.artwork) { return false }
        }
        return all.count >= 10
    }

    /// Perceived luminance, used to pick white or dark ink on a palette.
    static func luminance(_ colour: PulseRGB) -> Double {
        0.2126 * colour.r + 0.7152 * colour.g + 0.0722 * colour.b
    }

    /// "light" or "dark": which on-colour the widget should draw on this theme.
    static func onColour(for theme: PulseTheme) -> String {
        luminance(theme.background) > 0.55 ? "dark" : "light"
    }

    /// Ids of the light palettes.
    static var lightThemeIDs: [String] {
        all.filter { luminance($0.background) > 0.55 }.map { $0.id }
    }
}
