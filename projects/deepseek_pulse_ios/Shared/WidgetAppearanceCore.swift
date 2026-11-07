import Foundation

// DeepSeek Pulse — theme catalogue, widget designs and the stored appearance model (Core).
//
// Foundation only: compiled into BOTH the app (Sources/ + Shared/) and the WidgetKit extension
// (WidgetSources/ + Shared/ + Sources/RequestPolicy.swift), and executed by the widgetkit_v1
// harness on CI. Basename ends in "Core" so it cannot clash with any app-only view file.
//
// Contents:
//   * PulseRGB / PulseRamp / PulseTheme colour tokens
//   * WidgetDesign: the ten widget layouts (five small, five medium)
//   * WidgetAppearance: the persisted choice, with a tolerant decoder
//   * PulseThemes: 16 palettes driving both the app background and the widget gradients

// MARK: - Colour tokens

struct PulseRGB: Codable, Equatable, Hashable {
    var r: Double
    var g: Double
    var b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = PulseRGB.clamp(r)
        self.g = PulseRGB.clamp(g)
        self.b = PulseRGB.clamp(b)
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }

    var isDisplayable: Bool {
        (0...1).contains(r) && (0...1).contains(g) && (0...1).contains(b)
    }
}

struct PulseRamp: Codable, Equatable, Hashable {
    var top: PulseRGB
    var middle: PulseRGB
    var bottom: PulseRGB

    var isDisplayable: Bool {
        top.isDisplayable && middle.isDisplayable && bottom.isDisplayable
    }
}

struct PulseTheme: Codable, Equatable, Hashable {
    var id: String
    var name: String
    /// gradient | sunset | dot | grid | rings | none
    var artwork: String
    var background: PulseRGB
    var surface: PulseRGB
    var surfaceElevated: PulseRGB
    var text: PulseRGB
    var textDim: PulseRGB
    var accent: PulseRGB
    var accentSoft: PulseRGB
    var peak: PulseRGB
    var offPeak: PulseRGB
    var danger: PulseRGB
    var peakRamp: PulseRamp
    var offPeakRamp: PulseRamp
    var standardRamp: PulseRamp

    func ramp(for state: PricingState) -> PulseRamp {
        switch state {
        case .peak: return peakRamp
        case .offPeak: return offPeakRamp
        case .standard: return standardRamp
        }
    }

    var isDisplayable: Bool {
        let colours = [background, surface, surfaceElevated, text, textDim,
                       accent, accentSoft, peak, offPeak, danger]
        let ramps = [peakRamp, offPeakRamp, standardRamp]
        return colours.allSatisfy { $0.isDisplayable } && ramps.allSatisfy { $0.isDisplayable }
    }
}

// MARK: - Widget designs

/// The ten widget layouts. `rawValue` is persisted, so these names are stable.
enum WidgetDesign: String, Codable, CaseIterable, Equatable {
    case aurora
    case vault
    case splitColumn
    case ring
    case timeline
    case dashboard
    case ledger
    case countdownHero
    case bandHero
    case minimal

    static let smallFamily: [WidgetDesign] = [.aurora, .vault, .splitColumn, .ring, .timeline]
    static let mediumFamily: [WidgetDesign] = [.dashboard, .ledger, .countdownHero, .bandHero, .minimal]

    /// Small first, then medium; used by Widget Studio and the tests.
    static var ordered: [WidgetDesign] { smallFamily + mediumFamily }

    var title: String {
        switch self {
        case .aurora: return "Aurora"
        case .vault: return "Vault"
        case .splitColumn: return "Split Column"
        case .ring: return "Ring"
        case .timeline: return "Timeline"
        case .dashboard: return "Dashboard"
        case .ledger: return "Ledger"
        case .countdownHero: return "Countdown Hero"
        case .bandHero: return "Band Hero"
        case .minimal: return "Minimal"
        }
    }

    var familyLabel: String {
        WidgetDesign.smallFamily.contains(self) ? "Small" : "Medium"
    }

    var summary: String {
        switch self {
        case .aurora: return "State pill, countdown and the available balance."
        case .vault: return "Balance first, with the countdown underneath."
        case .splitColumn: return "Countdown and peak time left, side by side."
        case .ring: return "A progress ring around the state word."
        case .timeline: return "Today's UTC band beside the state and countdown."
        case .dashboard: return "Countdown, balance and the full 24-hour band."
        case .ledger: return "Balance with granted and topped-up columns."
        case .countdownHero: return "Two large cells: countdown and switch time."
        case .bandHero: return "A tall 24-hour band, then state and balance."
        case .minimal: return "Just the state word and the countdown."
        }
    }

    static func defaultDesign(forFamily family: String) -> WidgetDesign {
        family == "small" ? .aurora : .dashboard
    }

    /// Stable two-letter code, so all ten designs can be listed from one integer each.
    var code: String {
        switch self {
        case .aurora: return "au"
        case .vault: return "va"
        case .splitColumn: return "sc"
        case .ring: return "ri"
        case .timeline: return "ti"
        case .dashboard: return "da"
        case .ledger: return "le"
        case .countdownHero: return "ch"
        case .bandHero: return "bh"
        case .minimal: return "mi"
        }
    }

    static func design(code: String) -> WidgetDesign? {
        ordered.first { $0.code == code }
    }
}

// MARK: - Balance wording

/// The one place that decides what the balance slot says. Foundation-only, so the app previews and
/// the WidgetKit extension produce identical words for identical state.
///
/// Why this exists: the widget used to render "No key" whenever `hasAPIKey` was false, and a
/// balance request that silently produced nothing also left `hasAPIKey` false. On a phone where the
/// key is present that reads as the app claiming the key is missing. The rule is now:
///   * a real available balance always wins;
///   * a key that is known to be present with no balance yet says "Load in app";
///   * only a key that is genuinely absent says "Add API key";
///   * a saved balance with no key flag still shows the number, because the number is real data.
enum PulseBalanceWording {

    /// Wording used in the balance slot itself (short).
    ///
    /// 1.0.9: the slot no longer prints "No key". With no known key state it says "Open app"; only a
    /// positive "no key" report says "Add key in app". A widget cannot read the Keychain, so the
    /// other wording was a guess that read as an error on a working account.
    static func slot(hasBalance: Bool, hasAPIKey: Bool) -> String {
        if hasBalance { return "" }
        return hasAPIKey ? "Load in app" : "Open app"
    }

    /// Wording used in the balance slot when the key state is known explicitly.
    static func slot(hasBalance: Bool, hasAPIKey: Bool, hasAPIKeyKnown: Bool) -> String {
        if hasBalance { return "" }
        return WidgetRefreshHandshakeRules.noBalanceTitle(hasAPIKeyKnown: hasAPIKeyKnown,
                                                        hasAPIKey: hasAPIKey)
    }

    /// The older two-argument slot wording, kept for the views that only know the flag.
    static func legacySlot(hasBalance: Bool, hasAPIKey: Bool) -> String {
        slot(hasBalance: hasBalance, hasAPIKey: hasAPIKey, hasAPIKeyKnown: true)
    }

    /// The long caption under the balance slot.
    static func caption(hasBalance: Bool, hasAPIKey: Bool, fetchedAtAge: TimeInterval?, isStale: Bool) -> String {
        if hasBalance {
            guard let age = fetchedAtAge else { return "Saved balance" }
            let relative = ClockFormat.relative(Date().addingTimeInterval(-age), now: Date())
            return isStale ? "Saved " + relative : "Updated " + relative
        }
        return hasAPIKey
            ? "Key saved - open the app to load the balance"
            : WidgetRefreshHandshakeRules.noBalanceCaption(hasAPIKeyKnown: true, hasAPIKey: false)
    }

    /// Caption that respects an unknown key state.
    static func caption(hasBalance: Bool,
                        hasAPIKeyKnown: Bool,
                        hasAPIKey: Bool,
                        fetchedAtAge: TimeInterval?,
                        isStale: Bool) -> String {
        if hasBalance { return caption(hasBalance: true, hasAPIKey: hasAPIKey,
                                       fetchedAtAge: fetchedAtAge, isStale: isStale) }
        return WidgetRefreshHandshakeRules.noBalanceCaption(hasAPIKeyKnown: hasAPIKeyKnown,
                                                           hasAPIKey: hasAPIKey)
    }

    /// Never claim a key is missing when the snapshot could not be read at all.
    static func unavailableCaption(state: WidgetDataState) -> String {
        state.explainer
    }
}

// MARK: - Stored appearance

/// Everything the widget needs to draw itself in the chosen style.
///
/// Decoding is deliberately tolerant: a payload written by an older build, or one carrying an
/// unknown theme id, falls back instead of blanking the widget.
struct WidgetAppearance: Codable, Equatable {
    var themeID: String
    var smallDesign: WidgetDesign
    var mediumDesign: WidgetDesign
    /// 1.0.9: the Lock Screen choices, one design per accessory family.
    var lockScreen: LockScreenAppearance
    var artwork: String
    var showBalance: Bool
    var showRefresh: Bool
    var showDayBand: Bool

    static let defaultAppearance = WidgetAppearance(themeID: PulseThemes.fallbackID,
                                                    smallDesign: .aurora,
                                                    mediumDesign: .dashboard,
                                                    lockScreen: .defaultAppearance,
                                                    artwork: "gradient",
                                                    showBalance: true,
                                                    showRefresh: true,
                                                    showDayBand: true)

    func design(forFamily family: String) -> WidgetDesign {
        family == "small" ? smallDesign : mediumDesign
    }

    var theme: PulseTheme { PulseThemes.theme(id: themeID) }

    var summary: String {
        theme.name + " | " + smallDesign.title + " + " + mediumDesign.title
            + " | Lock Screen: " + lockScreen.rectangular.title
    }

    enum CodingKeys: String, CodingKey {
        case themeID, smallDesign, mediumDesign, lockScreen, artwork
        case showBalance, showRefresh, showDayBand
    }

    init(themeID: String,
         smallDesign: WidgetDesign,
         mediumDesign: WidgetDesign,
         lockScreen: LockScreenAppearance = .defaultAppearance,
         artwork: String,
         showBalance: Bool,
         showRefresh: Bool,
         showDayBand: Bool) {
        self.themeID = themeID
        self.smallDesign = smallDesign
        self.mediumDesign = mediumDesign
        self.lockScreen = lockScreen
        self.artwork = artwork
        self.showBalance = showBalance
        self.showRefresh = showRefresh
        self.showDayBand = showDayBand
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = WidgetAppearance.defaultAppearance
        themeID = (try? container.decodeIfPresent(String.self, forKey: .themeID)) ?? defaults.themeID
        artwork = (try? container.decodeIfPresent(String.self, forKey: .artwork)) ?? defaults.artwork
        showBalance = (try? container.decodeIfPresent(Bool.self, forKey: .showBalance)) ?? defaults.showBalance
        showRefresh = (try? container.decodeIfPresent(Bool.self, forKey: .showRefresh)) ?? defaults.showRefresh
        showDayBand = (try? container.decodeIfPresent(Bool.self, forKey: .showDayBand)) ?? defaults.showDayBand

        // 1.0.9: absent for payloads written by 1.0.8 and earlier, which fall back to the new design
        // set instead of blanking the Lock Screen slot.
        lockScreen = (try? container.decodeIfPresent(LockScreenAppearance.self, forKey: .lockScreen))
            ?? defaults.lockScreen

        let small = (try? container.decodeIfPresent(WidgetDesign.self, forKey: .smallDesign)) ?? defaults.smallDesign
        let medium = (try? container.decodeIfPresent(WidgetDesign.self, forKey: .mediumDesign)) ?? defaults.mediumDesign
        smallDesign = WidgetDesign.smallFamily.contains(small) ? small : defaults.smallDesign
        mediumDesign = WidgetDesign.mediumFamily.contains(medium) ? medium : defaults.mediumDesign

        if !PulseThemes.contains(id: themeID) { themeID = defaults.themeID }
        if !PulseThemes.artworkOptions.contains(artwork) { artwork = defaults.artwork }
    }

    /// Clamps every field to a valid value; used by the app before writing the payload.
    func normalised() -> WidgetAppearance {
        var copy = self
        copy.lockScreen = LockScreenAppearance(rectangular: copy.lockScreen.rectangular,
                                              circular: copy.lockScreen.circular,
                                              inline: copy.lockScreen.inline)
        if !PulseThemes.contains(id: copy.themeID) { copy.themeID = PulseThemes.fallbackID }
        if !WidgetDesign.smallFamily.contains(copy.smallDesign) { copy.smallDesign = .aurora }
        if !WidgetDesign.mediumFamily.contains(copy.mediumDesign) { copy.mediumDesign = .dashboard }
        if !PulseThemes.artworkOptions.contains(copy.artwork) { copy.artwork = "gradient" }
        return copy
    }
}
