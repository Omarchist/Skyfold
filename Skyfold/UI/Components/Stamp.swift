import SwiftUI

// Rubber stamps, labels and chips.

// MARK: - Passport stamp

/// A round passport stamp: a double ring, text around the top and bottom arcs, a name in the
/// middle band, and a little worn ink. Seeded, so it is crooked the same way every time.
///
///   PassportStamp(top: "NOW ARRIVING", center: "KYOTO", bottom: "UKY  15 NOV 26", seed: "UKY")
struct PassportStamp: View {
    var top: String
    var center: String
    var bottom: String
    /// Ink color. Defaults to the palette's airmail blue.
    var color: Color? = nil
    var size: CGFloat = 200
    var seed = "stamp"
    /// Defaults to a seeded tilt of 2 to 5 degrees.
    var tilt: Angle? = nil

    @Environment(\.palette) private var palette

    var body: some View {
        let ink = color ?? palette.secondary.color
        let seed = seed
        let top = top.uppercased(), center = center.uppercased(), bottom = bottom.uppercased()
        Canvas { ctx, canvas in
            let c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            let r = min(canvas.width, canvas.height) / 2 - 3
            var rng = SeededRandom(seed)

            func ring(_ center: CGPoint, _ radius: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                       width: radius * 2, height: radius * 2))
            }
            ctx.stroke(ring(c, r), with: .color(ink), lineWidth: max(2.4, r * 0.026))
            // The second ring sits a hair off center, as if the die slipped.
            let inner = CGPoint(x: c.x + (rng.next() - 0.5) * 2.6, y: c.y + (rng.next() - 0.5) * 2.6)
            ctx.stroke(ring(inner, r * 0.9), with: .color(ink), lineWidth: max(1.2, r * 0.012))

            // Text around the arcs, set in monospace so every character takes the same angle.
            let fontSize = max(8, r * 0.125)
            let advance = fontSize * 0.62 + 1.6
            let arcRadius = r * 0.9 - fontSize * 0.95
            let step = advance / arcRadius
            let font = Font.system(size: fontSize, weight: .bold, design: .monospaced)

            func arc(_ text: String, upper: Bool) {
                let chars = Array(text)
                let total = step * CGFloat(max(chars.count - 1, 0))
                for (i, ch) in chars.enumerated() {
                    guard ch != " " else { continue }
                    let theta: CGFloat = upper
                        ? -.pi / 2 - total / 2 + step * CGFloat(i)
                        : .pi / 2 + total / 2 - step * CGFloat(i)
                    var g = ctx
                    g.translateBy(x: c.x + arcRadius * cos(theta), y: c.y + arcRadius * sin(theta))
                    g.rotate(by: .radians(upper ? theta + .pi / 2 : theta - .pi / 2))
                    g.draw(Text(String(ch)).font(font).foregroundStyle(ink), at: .zero, anchor: .center)
                }
            }
            arc(top, upper: true)
            arc(bottom, upper: false)

            // The middle band: two rules and the city.
            let bandHalf = r * 0.2
            for y in [c.y - bandHalf, c.y + bandHalf] {
                var rule = Path()
                rule.move(to: CGPoint(x: c.x - r * 0.82, y: y))
                rule.addLine(to: CGPoint(x: c.x + r * 0.82, y: y))
                ctx.stroke(rule, with: .color(ink), lineWidth: max(1.2, r * 0.012))
            }
            let fit = min(r * 0.3, (r * 1.55) / (CGFloat(max(center.count, 1)) * 0.66))
            ctx.draw(Text(center).font(.system(size: fit, weight: .heavy)).tracking(1.2).foregroundStyle(ink),
                     at: c, anchor: .center)
        }
        .frame(width: size, height: size)
        .mask {
            // Worn ink: a scatter of small gaps and a couple of scratches.
            Canvas { ctx, canvas in
                var rng = SeededRandom(seed + ".wear")
                ctx.fill(Path(CGRect(origin: .zero, size: canvas)), with: .color(.black))
                ctx.blendMode = .destinationOut
                for _ in 0..<Int(size / 2.6) {
                    let s = 0.7 + rng.next() * 2.0
                    let p = CGPoint(x: rng.next() * canvas.width, y: rng.next() * canvas.height)
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x, y: p.y, width: s, height: s * (0.6 + rng.next() * 0.8))),
                             with: .color(.black))
                }
                for _ in 0..<3 {
                    var scratch = Path()
                    let a = CGPoint(x: rng.next() * canvas.width, y: rng.next() * canvas.height)
                    scratch.move(to: a)
                    scratch.addLine(to: CGPoint(x: a.x + (rng.next() - 0.5) * size * 0.35,
                                                y: a.y + (rng.next() - 0.5) * size * 0.2))
                    ctx.stroke(scratch, with: .color(.black), lineWidth: 0.9)
                }
            }
        }
        .rotationEffect(tilt ?? Seeded.tilt(seed, min: 2, max: 5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(top.capitalized), \(center.capitalized)")
    }
}

// MARK: - Par avion label

/// The blue "PAR AVION" sticker from an airmail envelope.
struct ParAvionLabel: View {
    @Environment(\.palette) private var palette

    var body: some View {
        let blue = palette.secondary.color
        VStack(spacing: 1) {
            Text("Par avion")
                .textCase(.uppercase)
                .font(.skyfold(11, weight: .heavy))
                .tracking(2)
            Text("By air mail")
                .textCase(.uppercase)
                .font(.skyfold(7.5, weight: .semibold))
                .tracking(1.6)
        }
        .foregroundStyle(blue)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Rectangle().fill(palette.paper.color))
        .overlay(Rectangle().strokeBorder(blue, lineWidth: 1.5))
        .overlay(Rectangle().strokeBorder(blue.opacity(0.7), lineWidth: 0.6).padding(3))
        .printShadow(Rectangle(), offset: 2)
        .accessibilityHidden(true)
    }
}

// MARK: - Chips

/// A small signage tag: uppercase text in a hairline box, optionally filled.
struct PaperChip: View {
    var text: String
    /// Defaults to the soft ink.
    var tint: Color? = nil
    var filled = false
    @Environment(\.palette) private var palette

    init(_ text: String, tint: Color? = nil, filled: Bool = false) {
        self.text = text
        self.tint = tint
        self.filled = filled
    }

    var body: some View {
        let tint = tint ?? palette.inkSoft.color
        let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
        Text(text)
            .signage(9.5, weight: .bold)
            .foregroundStyle(filled ? palette.paper.color : tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(shape.fill(filled ? tint : .clear))
            .overlay(shape.strokeBorder(tint, lineWidth: 1.2))
    }
}
