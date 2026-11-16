import SwiftUI

// Flat cut-paper scenery and surfaces: clouds, paper, the airmail border.

// MARK: - Cloud

/// A flat cut-paper cloud: round puffs on a flat base. `variant` (0...3) changes the
/// proportions so a sky of clouds is not a row of copies.
nonisolated struct FlatCloudShape: Shape {
    var variant = 0

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func puff(_ x: CGFloat, _ y: CGFloat, _ pw: CGFloat, _ ph: CGFloat) -> CGRect {
            CGRect(x: rect.minX + w * x, y: rect.minY + h * y, width: w * pw, height: h * ph)
        }
        var p = Path()
        p.addRoundedRect(in: puff(0, 0.58, 1, 0.42), cornerSize: CGSize(width: h * 0.21, height: h * 0.21))
        switch variant % 4 {
        case 0:
            p.addEllipse(in: puff(0.10, 0.30, 0.30, 0.56))
            p.addEllipse(in: puff(0.30, 0.00, 0.38, 0.84))
            p.addEllipse(in: puff(0.58, 0.24, 0.30, 0.60))
        case 1:
            p.addEllipse(in: puff(0.06, 0.34, 0.26, 0.50))
            p.addEllipse(in: puff(0.22, 0.06, 0.34, 0.78))
            p.addEllipse(in: puff(0.50, 0.26, 0.26, 0.58))
            p.addEllipse(in: puff(0.68, 0.38, 0.24, 0.48))
        case 2:
            p.addEllipse(in: puff(0.14, 0.12, 0.40, 0.76))
            p.addEllipse(in: puff(0.46, 0.34, 0.34, 0.54))
        default:
            p.addEllipse(in: puff(0.08, 0.40, 0.24, 0.46))
            p.addEllipse(in: puff(0.26, 0.14, 0.30, 0.72))
            p.addEllipse(in: puff(0.52, 0.00, 0.32, 0.88))
        }
        return p
    }
}

// MARK: - Paper surface

/// Flat card stock for a full-screen background, with a few seeded fibres so it is not
/// a perfectly even fill. Static: it draws once.
struct PaperBackground: View {
    var seed = "paper"
    @Environment(\.palette) private var palette

    var body: some View {
        let palette = palette
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.paper.color))
            var rng = SeededRandom(seed)
            let count = Int(size.width * size.height / 5200)
            for _ in 0..<count {
                let x = rng.next() * size.width, y = rng.next() * size.height
                let len = 3 + rng.next() * 9
                let a = rng.next() * .pi
                var p = Path()
                p.move(to: CGPoint(x: x, y: y))
                p.addLine(to: CGPoint(x: x + cos(a) * len, y: y + sin(a) * len))
                ctx.stroke(p, with: .color(palette.paperEdge.withAlpha(0.28 + 0.2 * rng.next()).color), lineWidth: 0.7)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - Stripe border

nonisolated struct StripeFrameShape: Shape {
    var thickness: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path(rect)
        p.addRect(rect.insetBy(dx: thickness, dy: thickness))
        return p
    }
}

extension View {
    /// The red and blue airmail border, drawn inside the view's bounds. Use it on one piece
    /// per screen, not on everything.
    func stripeBorder(width: CGFloat = 7, stripe: CGFloat = 9) -> some View {
        overlay {
            AirmailStripe(stripe: stripe)
                .mask { StripeFrameShape(thickness: width).fill(style: FillStyle(eoFill: true)) }
                .allowsHitTesting(false)
        }
    }
}
