import SwiftUI

// Shared helpers for the airmail / travel-paper UI: environment, feedback, palette roles,
// formatting and seeded imperfection.

// MARK: - Environment

extension EnvironmentValues {
    /// Nightness (0 = day, 1 = night) that matches the injected palette.
    @Entry var uiNightness: Double = 0
    /// True when the window is wider than it is tall. Screens switch to two columns.
    @Entry var isLandscape: Bool = false
}

// MARK: - Feedback

/// Tap and selection feedback shared by every control.
enum UIFeedback {
    static func tap() { Services.sound.play(.uiTap) }

    static func select() {
        Services.sound.play(.uiTap)
        Services.haptics.play(.selection)
    }
}

// MARK: - Palette roles

extension Palette {
    /// Hard print shadow: ink at ~18% by day; a deeper shade of the sky by night.
    var printShadow: Color {
        isDark ? skyTop.scaled(0.35).withAlpha(0.7).color : ink.withAlpha(0.18).color
    }

    /// A flat dimming layer behind overlays (no blur).
    var scrim: Color {
        isDark ? skyTop.withAlpha(0.62).color : ink.withAlpha(0.30).color
    }

    /// Hairlines, rules and perforations.
    var rule: Color { paperEdge.color }

    func tint(_ kind: ModifierKind) -> RGBA { kind == .blessing ? blessing : curse }

    /// The blessing/curse color used as printing ink on paper (darkened by day for contrast).
    func kindInk(_ kind: ModifierKind) -> Color {
        if isDark { return tint(kind).color }
        return (kind == .blessing ? blessing.scaled(0.74) : curse).color
    }

    /// Departures-board panel and its lettering: dark board in both palettes.
    var boardBackground: RGBA { isDark ? paper.mixed(with: skyTop, 0.5) : ink }
    var boardText: RGBA { isDark ? ink : paper }
    var boardTile: RGBA { boardBackground.mixed(with: boardText, 0.09) }

    /// Lettering that stands out on the board (BOARDING, the selected row): sodium amber by
    /// night, a lighter airmail red by day so it holds up on the dark panel.
    var boardAccent: RGBA { isDark ? accent : accent.mixed(with: paper, 0.34) }

    /// Ink or paper, whichever has more contrast on `background`.
    func legible(on background: RGBA) -> RGBA {
        ink.contrast(with: background) >= paper.contrast(with: background) ? ink : paper
    }

    /// Ink or paper, whichever reads better on `background`.
    func readableInk(on background: RGBA) -> Color { legible(on: background).color }

    /// The sky color at a height (0 = top, 1 = horizon), stepped into flat bands.
    func skyBand(_ fraction: Double, bands: Int = 5) -> RGBA {
        let i = min(bands - 1, max(0, Int(fraction * Double(bands))))
        return skyTop.mixed(with: skyBottom, Double(i) / Double(max(bands - 1, 1)))
    }
}

extension RGBA {
    /// WCAG relative luminance (linearized sRGB).
    var relativeLuminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    func contrast(with other: RGBA) -> Double {
        let a = relativeLuminance, b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

// MARK: - Formatting

enum UIFormat {
    static func number(_ n: Int) -> String { n.formatted(.number) }

    static func distance(_ meters: Double) -> String {
        if meters < 1000 { return "\(Int(meters.rounded())) m" }
        return (meters / 1000).formatted(.number.precision(.fractionLength(1))) + " km"
    }

    /// "×1.3", for score multipliers.
    static func multiplier(_ value: Double) -> String {
        "×" + value.formatted(.number.precision(.fractionLength(1)))
    }

    /// "22:41", for the departures board.
    static func clock(_ date: Date = .now) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    /// A made-up flight number for a leg, e.g. "SF 104".
    static func flightNumber(from: Int, to: Int) -> String {
        "SF \(101 + ((from * 7 + to * 3) % 90))"
    }

    /// "15 NOV 26", for stamps.
    static func stampDate(_ date: Date = .now) -> String {
        date.formatted(.dateTime.day(.twoDigits).month(.abbreviated).year(.twoDigits)).uppercased()
    }

    /// Each modifier once, in first-seen order, with how many times it was taken.
    static func tally(_ ids: [ModifierID]) -> [(id: ModifierID, count: Int)] {
        var order: [ModifierID] = []
        var counts: [ModifierID: Int] = [:]
        for id in ids {
            if counts[id] == nil { order.append(id) }
            counts[id, default: 0] += 1
        }
        return order.map { ($0, counts[$0] ?? 1) }
    }
}

// MARK: - Unlock hints

enum UnlockHint {
    /// The city whose first landing grants `unlock`.
    static func city(for unlock: Unlock) -> City? {
        Route.cities.first { $0.unlocks.contains(unlock) }
    }

    static func difficulty(_ id: DifficultyID) -> String {
        if let city = city(for: .difficulty(id)) { return "Land in \(city.name) to unlock." }
        return "Locked."
    }

    static func airport(_ index: Int) -> String {
        "Land in \(Route.city(index).name) to open."
    }

    static func skin(_ skin: PlaneSkin, unlocked: Bool) -> String {
        if !unlocked { return skin.unlockHint }
        if let city = city(for: .skin(skin.id)) { return "Unlocked in \(city.name)." }
        return skin.id == .midnight ? "Earned on a full lap." : "Standard issue."
    }
}

// MARK: - Seeded imperfection

/// Stable pseudo-random values so stamps and cards sit a little crooked, the same way every launch.
enum Seeded {
    /// FNV-1a over the key's UTF-8 bytes (String.hashValue changes per launch).
    static func unit(_ key: String) -> Double {
        var h: UInt64 = 0xcbf29ce484222325
        for b in key.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return Double(h % 10_000) / 10_000
    }

    /// An angle in degrees within ±`maxDegrees`, at least `minDegrees` away from zero.
    static func tilt(_ key: String, min minDegrees: Double = 1, max maxDegrees: Double = 4) -> Angle {
        let u = unit(key)
        let magnitude = minDegrees + (maxDegrees - minDegrees) * (u * 2).truncatingRemainder(dividingBy: 1)
        return .degrees(u < 0.5 ? -magnitude : magnitude)
    }
}

// MARK: - Symbols

/// SF Symbols appear only where an icon carries meaning, and always at this one weight.
struct Glyph: View {
    let name: String
    var size: CGFloat = 16

    init(_ name: String, size: CGFloat = 16) {
        self.name = name
        self.size = size
    }

    var body: some View {
        Image(systemName: name)
            .font(.skyfold(size, weight: .medium))
            .accessibilityHidden(true)
    }
}

// MARK: - Type helpers

extension Text {
    /// Signage style: uppercase, tracked, small.
    func signage(_ size: CGFloat = 11, weight: Font.Weight = .semibold, tracking: CGFloat = 1.5) -> some View {
        self.textCase(.uppercase)
            .font(.skyfold(size, weight: weight))
            .tracking(tracking)
    }
}

/// Puts its children side by side while each one's natural width fits its share of the row
/// (`equalColumns`) or all of them fit together, and one under another otherwise. Unlike
/// `ViewThatFits`, the decision is measured from the unconstrained size of every child, so a
/// word is never squeezed or broken.
struct FitStack: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8
    var equalColumns = false

    private func sideBySide(_ subviews: Subviews, width: CGFloat) -> Bool {
        guard width.isFinite else { return true }
        let ideals = subviews.map { $0.sizeThatFits(.unspecified).width }
        let gaps = spacing * CGFloat(max(subviews.count - 1, 0))
        if equalColumns {
            let column = (width - gaps) / CGFloat(max(subviews.count, 1))
            return ideals.allSatisfy { $0 <= column }
        }
        return ideals.reduce(0, +) + gaps <= width
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        if sideBySide(subviews, width: width) {
            let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
            let used = sizes.map(\.width).reduce(0, +) + spacing * CGFloat(max(subviews.count - 1, 0))
            return CGSize(width: equalColumns && width.isFinite ? width : used,
                          height: sizes.map(\.height).max() ?? 0)
        }
        let sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)) }
        let height = sizes.map(\.height).reduce(0, +) + rowSpacing * CGFloat(max(subviews.count - 1, 0))
        return CGSize(width: width.isFinite ? width : (sizes.map(\.width).max() ?? 0), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        if sideBySide(subviews, width: bounds.width) {
            let gaps = spacing * CGFloat(max(subviews.count - 1, 0))
            let column = (bounds.width - gaps) / CGFloat(max(subviews.count, 1))
            var x = bounds.minX
            for view in subviews {
                let size = view.sizeThatFits(.unspecified)
                let w = equalColumns ? column : size.width
                view.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                           proposal: ProposedViewSize(width: w, height: nil))
                x += w + spacing
            }
        } else {
            var y = bounds.minY
            for view in subviews {
                let size = view.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                view.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading,
                           proposal: ProposedViewSize(width: bounds.width, height: nil))
                y += size.height + rowSpacing
            }
        }
    }
}
