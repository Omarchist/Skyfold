import SwiftUI

/// A passport entry stamp: double ring, "NOW ARRIVING" around the top, "CITY · CODE" around
/// the bottom, the date in the middle. Printed in the palette accent (airmail red by day,
/// sodium amber by night), with a slightly wobbly outline and ink that did not take everywhere.
struct AirportStamp: View {
    let city: City
    let date: String
    var diameter: CGFloat = 172

    @Environment(\.palette) private var palette

    var body: some View {
        let ink = palette.accent.color
        ZStack {
            AirportStampRings(city: city, color: ink)
            VStack(spacing: 4) {
                Glyph("airplane.arrival", size: diameter * 0.15)
                Text(date)
                    .font(.ticket(diameter * 0.092, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(ink)
        }
        .dynamicTypeSize(.large)
        .frame(width: diameter, height: diameter)
        .mask { AirportInkDropout(seed: "stamp-" + city.code) }
        .opacity(0.93)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Now arriving, \(city.name), \(city.code), \(date)")
    }
}

private struct AirportStampRings: View {
    let city: City
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = min(size.width, size.height) / 2 - 3
            let band = outer * 0.34
            let inner = outer - band
            let textRadius = outer - band / 2
            let fontSize = outer * 0.15

            // Rings: a heavy outer line and a light inner one, both a little off round.
            ctx.stroke(Self.wobblyCircle(center: c, radius: outer, seed: city.code + "o"),
                       with: .color(color), lineWidth: 3.4)
            ctx.stroke(Self.wobblyCircle(center: c, radius: inner, seed: city.code + "i"),
                       with: .color(color), lineWidth: 1.6)

            Self.arcText("NOW ARRIVING", ctx: ctx, center: c, radius: textRadius,
                         fontSize: fontSize, bottom: false, maxSpan: 2.3, color: color)
            Self.arcText(city.name.uppercased() + " · " + city.code, ctx: ctx, center: c,
                         radius: textRadius, fontSize: fontSize, bottom: true, maxSpan: 2.55, color: color)

            // Two dots where the arcs stop.
            for side in [-1.0, 1.0] {
                let p = CGPoint(x: c.x + side * textRadius, y: c.y)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2.3, y: p.y - 2.3, width: 4.6, height: 4.6)),
                         with: .color(color))
            }

            // Rules above and below the date.
            let ruleHalf = inner * 0.7
            for dy in [-inner * 0.56, inner * 0.56] {
                var rule = Path()
                rule.move(to: CGPoint(x: c.x - ruleHalf, y: c.y + dy))
                rule.addLine(to: CGPoint(x: c.x + ruleHalf, y: c.y + dy))
                ctx.stroke(rule, with: .color(color), lineWidth: 1.4)
            }
        }
    }

    /// A circle whose radius drifts by a pixel or so, like a rubber stamp pressed by hand.
    private static func wobblyCircle(center c: CGPoint, radius r: CGFloat, seed: String) -> Path {
        var rng = SeededRandom(seed)
        let a1 = rng.next() * 6.28, a2 = rng.next() * 6.28
        let m1 = 0.5 + rng.next() * 0.5, m2 = 0.3 + rng.next() * 0.5
        var p = Path()
        let steps = 96
        for i in 0...steps {
            let t = Double(i) / Double(steps) * 2 * Double.pi
            let rr = r + m1 * CGFloat(sin(2 * t + Double(a1))) + m2 * CGFloat(sin(5 * t + Double(a2)))
            let pt = CGPoint(x: c.x + rr * CGFloat(sin(t)), y: c.y - rr * CGFloat(cos(t)))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    /// Text set along a circle. Top text reads clockwise; bottom text reads left to right with
    /// its tops toward the middle, like on a real round stamp. Needs a monospaced face.
    private static func arcText(_ text: String, ctx: GraphicsContext, center c: CGPoint, radius: CGFloat,
                                fontSize: CGFloat, bottom: Bool, maxSpan: Double, color: Color) {
        let chars = Array(text)
        guard chars.count > 1 else { return }
        let natural = Double((fontSize * 0.62 + 2.4) / radius)
        let step = min(natural, maxSpan / Double(chars.count - 1))
        for (i, ch) in chars.enumerated() where ch != " " {
            let u = (Double(i) - Double(chars.count - 1) / 2) * step
            let phi = bottom ? Double.pi - u : u
            var g = ctx
            g.translateBy(x: c.x, y: c.y)
            g.rotate(by: .radians(phi))
            g.translateBy(x: 0, y: -radius)
            if bottom { g.rotate(by: .radians(Double.pi)) }
            let glyph = g.resolve(Text(String(ch)).font(.system(size: fontSize, weight: .bold, design: .monospaced)).foregroundStyle(color))
            g.draw(glyph, at: .zero, anchor: .center)
        }
    }
}

/// A small boxed stamp for "New best": double border, tracked capitals, a little crooked.
struct AirportBestMark: View {
    var text = "New best"
    var tilt: Double = -6

    @Environment(\.palette) private var palette

    var body: some View {
        let ink = palette.accent.color
        Text(text)
            .textCase(.uppercase)
            .font(.ticket(13, weight: .bold))
            .tracking(1.6)
            .foregroundStyle(ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay(Rectangle().strokeBorder(ink, lineWidth: 2.2))
            .padding(3)
            .overlay(Rectangle().strokeBorder(ink, lineWidth: 1))
            .mask { AirportInkDropout(seed: "best-" + text, density: 0.8) }
            .opacity(0.94)
            .rotationEffect(.degrees(tilt))
    }
}
