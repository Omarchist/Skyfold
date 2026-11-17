#if canImport(SwiftUI)
import CoreGraphics
import SwiftUI
#endif

/// A platform-neutral sRGB color that can feed SwiftUI, CoreGraphics and RealityKit.
nonisolated struct RGBA: Hashable, Sendable, Codable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(hex: UInt32, alpha: Double = 1) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
        a = alpha
    }

    func mixed(with other: RGBA, _ t: Double) -> RGBA {
        let t = min(max(t, 0), 1)
        return RGBA(r + (other.r - r) * t,
                    g + (other.g - g) * t,
                    b + (other.b - b) * t,
                    a + (other.a - a) * t)
    }

    func withAlpha(_ alpha: Double) -> RGBA { RGBA(r, g, b, alpha) }

    /// Multiplies RGB by `factor` (keeps alpha).
    func scaled(_ factor: Double) -> RGBA {
        RGBA(min(r * factor, 1), min(g * factor, 1), min(b * factor, 1), a)
    }

    /// Relative luminance (sRGB approximation), handy for picking text color.
    var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }
}

/// Every color the game and UI use, for one moment of the day/night cycle.
/// Use `Palette.at(nightness:)`, where 0 = day, 0.5 = dusk, 1 = night.
///
/// Art direction: airmail and travel paper. Days are cream card stock, warm ochre ground,
/// airmail red and blue. Nights are printed in ink blue with sodium-lamp amber, like a
/// city seen from a late flight. Flat colors only: no neon, no glows.
nonisolated struct Palette: Equatable, Sendable {
    // Sky & world
    var skyTop: RGBA
    var skyBottom: RGBA
    var horizonGlow: RGBA      // the band just above the horizon (draw as a flat band, not a glow)
    var sun: RGBA              // flat sun disc by day, bone-white moon by night
    var ground: RGBA
    var groundFar: RGBA
    var cloud: RGBA
    var fog: RGBA
    var cityTint: RGBA         // multiplied over city building colors
    var obstacleTint: RGBA     // multiplied over obstacle colors
    var lightColor: RGBA       // key (sun/moon) light color
    var lightIntensity: Double // 0...1, renderer maps to lux
    var ambient: Double        // 0...1 fill light
    var windowGlow: Double     // 0 = windows dark, 1 = windows lit (sodium amber)
    var starsVisible: Double   // 0...1 opacity of night-sky stars

    // UI
    var ink: RGBA              // primary text and rules
    var inkSoft: RGBA          // secondary text
    var paper: RGBA            // card stock / panel background
    var paperEdge: RGBA        // card border, perforations, dividers
    var accent: RGBA           // airmail red by day, sodium amber by night
    var accentInk: RGBA        // text on accent
    var secondary: RGBA        // airmail blue (stripes, links, secondary marks)
    var blessing: RGBA
    var curse: RGBA

    static let day = Palette(
        skyTop: RGBA(hex: 0xEFC39B), skyBottom: RGBA(hex: 0xF7E6CC),
        horizonGlow: RGBA(hex: 0xF3D3AE), sun: RGBA(hex: 0xFBF1DE),
        ground: RGBA(hex: 0xD6A473), groundFar: RGBA(hex: 0xE5C199),
        cloud: RGBA(hex: 0xFBF6EC), fog: RGBA(hex: 0xEFDDC4),
        cityTint: RGBA(hex: 0xFFFFFF), obstacleTint: RGBA(hex: 0xFFFFFF),
        lightColor: RGBA(hex: 0xFFF0DA), lightIntensity: 1.0, ambient: 0.85,
        windowGlow: 0, starsVisible: 0,
        ink: RGBA(hex: 0x2A211B), inkSoft: RGBA(hex: 0x76655A),
        paper: RGBA(hex: 0xF4ECDD), paperEdge: RGBA(hex: 0xD6C7AE),
        accent: RGBA(hex: 0xD6402B), accentInk: RGBA(hex: 0xFBF4E8),
        secondary: RGBA(hex: 0x2C4F9E),
        blessing: RGBA(hex: 0xC48A1E), curse: RGBA(hex: 0x6B3A5A))

    static let dusk = Palette(
        skyTop: RGBA(hex: 0x6B5C86), skyBottom: RGBA(hex: 0xE8957A),
        horizonGlow: RGBA(hex: 0xF0AE82), sun: RGBA(hex: 0xF08A5A),
        ground: RGBA(hex: 0x7E5552), groundFar: RGBA(hex: 0xA6716C),
        cloud: RGBA(hex: 0xEDC3B2), fog: RGBA(hex: 0xB98A8E),
        cityTint: RGBA(hex: 0xD3B3B0), obstacleTint: RGBA(hex: 0xE2C7C2),
        lightColor: RGBA(hex: 0xFFB58A), lightIntensity: 0.6, ambient: 0.55,
        windowGlow: 0.6, starsVisible: 0.2,
        ink: RGBA(hex: 0x2B1E22), inkSoft: RGBA(hex: 0x725A60),
        paper: RGBA(hex: 0xF0DDD0), paperEdge: RGBA(hex: 0xD3B5A8),
        accent: RGBA(hex: 0xC9432E), accentInk: RGBA(hex: 0xFBF0E6),
        secondary: RGBA(hex: 0x3A4F8A),
        blessing: RGBA(hex: 0xC9901F), curse: RGBA(hex: 0x6E3E63))

    static let night = Palette(
        skyTop: RGBA(hex: 0x0E1324), skyBottom: RGBA(hex: 0x252E46),
        horizonGlow: RGBA(hex: 0x353A55), sun: RGBA(hex: 0xE6DEC7),
        ground: RGBA(hex: 0x11141D), groundFar: RGBA(hex: 0x1B2131),
        cloud: RGBA(hex: 0x2D3447), fog: RGBA(hex: 0x20283A),
        cityTint: RGBA(hex: 0x58627C), obstacleTint: RGBA(hex: 0x8790A8),
        lightColor: RGBA(hex: 0x9FB0D6), lightIntensity: 0.35, ambient: 0.3,
        windowGlow: 1, starsVisible: 1,
        ink: RGBA(hex: 0xE4DCCB), inkSoft: RGBA(hex: 0x8C887E),
        paper: RGBA(hex: 0x161B28), paperEdge: RGBA(hex: 0x2E3546),
        accent: RGBA(hex: 0xE5A03A), accentInk: RGBA(hex: 0x161B28),
        secondary: RGBA(hex: 0x7D93C6),
        blessing: RGBA(hex: 0xE2BE68), curse: RGBA(hex: 0x9CB87A))

    /// 0 = day, 0.5 = dusk, 1 = night. Interpolates through dusk so the sky
    /// passes through sunset colors instead of a muddy straight blend.
    static func at(nightness: Double) -> Palette {
        let t = min(max(nightness, 0), 1)
        if t <= 0.5 { return day.mixed(with: dusk, t / 0.5) }
        return dusk.mixed(with: night, (t - 0.5) / 0.5)
    }

    func mixed(with o: Palette, _ t: Double) -> Palette {
        func m(_ a: RGBA, _ b: RGBA) -> RGBA { a.mixed(with: b, t) }
        func d(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        return Palette(
            skyTop: m(skyTop, o.skyTop), skyBottom: m(skyBottom, o.skyBottom),
            horizonGlow: m(horizonGlow, o.horizonGlow), sun: m(sun, o.sun),
            ground: m(ground, o.ground), groundFar: m(groundFar, o.groundFar),
            cloud: m(cloud, o.cloud), fog: m(fog, o.fog),
            cityTint: m(cityTint, o.cityTint), obstacleTint: m(obstacleTint, o.obstacleTint),
            lightColor: m(lightColor, o.lightColor),
            lightIntensity: d(lightIntensity, o.lightIntensity), ambient: d(ambient, o.ambient),
            windowGlow: d(windowGlow, o.windowGlow), starsVisible: d(starsVisible, o.starsVisible),
            ink: m(ink, o.ink), inkSoft: m(inkSoft, o.inkSoft),
            paper: m(paper, o.paper), paperEdge: m(paperEdge, o.paperEdge),
            accent: m(accent, o.accent), accentInk: m(accentInk, o.accentInk),
            secondary: m(secondary, o.secondary),
            blessing: m(blessing, o.blessing), curse: m(curse, o.curse))
    }

    var isDark: Bool { paper.luminance < 0.4 }
}

#if canImport(SwiftUI)
nonisolated extension RGBA {
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    #if canImport(UIKit)
    var platformColor: UIColor { UIColor(red: r, green: g, blue: b, alpha: a) }
    #elseif canImport(AppKit)
    var platformColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    #endif
}

extension EnvironmentValues {
    /// The current UI palette. RootView injects it from the menu/run nightness.
    @Entry var palette: Palette = .day
}

/// A type spec that follows the user's text size. A plain `Font` cannot read the environment,
/// so `.font(_: SkyFont)` (below) resolves the size per view with `@ScaledMetric`, which reacts
/// live to a change of the Dynamic Type setting and respects `.dynamicTypeSize(...limit)`.
/// At the default size (Large) the result is exactly `size`.
///
/// Scaling: text that can reflow (body, notes, rows) scales fully. Text inside fixed paper
/// shapes (HUD ticket, countdown slip, gate letters, wordmark, split-flap board, big score)
/// sits under `.limitedTypeSize()`, which caps the environment at `xxxLarge` (about 1.3x).
struct SkyFont {
    var size: CGFloat
    var weight: Font.Weight
    var design: Font.Design
    var isItalic = false

    func italic() -> SkyFont { var f = self; f.isItalic = true; return f }

    /// Body and controls: the plain system face. Deliberately not Rounded.
    static func skyfold(_ size: CGFloat, weight: Font.Weight = .regular) -> SkyFont {
        SkyFont(size: size, weight: weight, design: .default)
    }

    /// Titles, city names, the wordmark: New York (the system serif), like a printed
    /// timetable or guidebook heading.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> SkyFont {
        SkyFont(size: size, weight: weight, design: .serif)
    }

    /// Anything a machine would print: scores, distances, flight codes, gate letters,
    /// times. Monospaced, like a boarding pass or a departures board.
    static func ticket(_ size: CGFloat, weight: Font.Weight = .medium) -> SkyFont {
        SkyFont(size: size, weight: weight, design: .monospaced)
    }

    /// The text style whose scaling curve fits this size (big type grows less, like Apple's styles).
    fileprivate var style: Font.TextStyle {
        switch size {
        case ..<12: .caption2
        case ..<14: .footnote
        case ..<18: .body
        case ..<24: .title3
        case ..<32: .title2
        default: .largeTitle
        }
    }
}

private struct SkyFontModifier: ViewModifier {
    let spec: SkyFont
    @ScaledMetric private var size: CGFloat

    init(_ spec: SkyFont) {
        self.spec = spec
        _size = ScaledMetric(wrappedValue: spec.size, relativeTo: spec.style)
    }

    func body(content: Content) -> some View {
        let font = Font.system(size: size, weight: spec.weight, design: spec.design)
        return content.font(spec.isItalic ? font.italic() : font)
    }
}

extension View {
    /// Sets a Skyfold type spec that scales with the text-size setting.
    func font(_ spec: SkyFont) -> some View { modifier(SkyFontModifier(spec)) }

    /// For display-like text in fixed paper shapes: grows with the setting, but by about 1.3x at most.
    func limitedTypeSize() -> some View { dynamicTypeSize(...DynamicTypeSize.xxxLarge) }
}
#endif
