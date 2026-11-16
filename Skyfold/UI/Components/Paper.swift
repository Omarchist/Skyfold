import SwiftUI

// Paper and print primitives: card stock, tickets with notches and perforations,
// torn stubs, hard print shadows, rules and the airmail stripe.

// MARK: - Seeded random

/// A tiny deterministic generator (LCG) for hand-made irregularities.
nonisolated struct SeededRandom {
    private var state: UInt64

    init(_ key: String) {
        var h: UInt64 = 0xcbf29ce484222325
        for b in key.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        state = h | 1
    }

    /// 0 ..< 1
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((state >> 33) % 100_000) / 100_000
    }
}

// MARK: - Shapes

nonisolated enum TicketNotch: Equatable, Sendable {
    case none
    /// Half-circle bites in the top and bottom edges, this far from the trailing edge.
    case vertical(fromTrailing: CGFloat)
    /// Half-circle bites in the leading and trailing edges, this far from the top.
    case horizontal(fromTop: CGFloat)
    /// Half-circle bites in the leading and trailing edges, this far from the bottom.
    case horizontalFromBottom(CGFloat)
}

/// A ticket: small corners plus optional notches where it would tear.
nonisolated struct TicketShape: Shape {
    var cornerRadius: CGFloat = 4
    var notch: TicketNotch = .none
    var notchRadius: CGFloat = 7

    func path(in rect: CGRect) -> Path {
        let base = Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
        return base.subtracting(notchPath(in: rect, radius: notchRadius))
    }

    func notchPath(in rect: CGRect, radius r: CGFloat) -> Path {
        var bites = Path()
        func bite(_ c: CGPoint) { bites.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)) }
        switch notch {
        case .none: break
        case .vertical(let d):
            bite(CGPoint(x: rect.maxX - d, y: rect.minY))
            bite(CGPoint(x: rect.maxX - d, y: rect.maxY))
        case .horizontal(let d):
            bite(CGPoint(x: rect.minX, y: rect.minY + d))
            bite(CGPoint(x: rect.maxX, y: rect.minY + d))
        case .horizontalFromBottom(let d):
            bite(CGPoint(x: rect.minX, y: rect.maxY - d))
            bite(CGPoint(x: rect.maxX, y: rect.maxY - d))
        }
        return bites
    }
}

/// A stub torn off along its top edge (seeded, so it tears the same way every time).
nonisolated struct TornStubShape: Shape {
    var seed: String = "stub"
    var tooth: CGFloat = 9
    var depth: CGFloat = 5
    var notchFromBottom: CGFloat? = nil
    var notchRadius: CGFloat = 7

    func path(in rect: CGRect) -> Path {
        var rng = SeededRandom(seed)
        var p = Path()
        let top = rect.minY + depth
        p.move(to: CGPoint(x: rect.minX, y: top))
        var x = rect.minX
        while x < rect.maxX {
            let w = tooth * (0.6 + 0.8 * rng.next())
            let nx = min(rect.maxX, x + w)
            p.addLine(to: CGPoint(x: (x + nx) / 2, y: top - depth * (0.35 + 0.65 * rng.next())))
            p.addLine(to: CGPoint(x: nx, y: top - depth * 0.15 * rng.next()))
            x = nx
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 3))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - 3, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + 3, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - 3), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        guard let d = notchFromBottom else { return p }
        let r = notchRadius
        var bites = Path()
        bites.addEllipse(in: CGRect(x: rect.minX - r, y: rect.maxY - d - r, width: 2 * r, height: 2 * r))
        bites.addEllipse(in: CGRect(x: rect.maxX - r, y: rect.maxY - d - r, width: 2 * r, height: 2 * r))
        return p.subtracting(bites)
    }
}

/// A straight line through the middle of its frame (for perforations and leaders).
nonisolated struct MidLine: Shape {
    var vertical = false
    func path(in rect: CGRect) -> Path {
        var p = Path()
        if vertical {
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        } else {
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
        return p
    }
}

// MARK: - Print shadow

extension View {
    /// A hard offset print shadow (no blur) in the shape of `shape`.
    func printShadow<S: Shape>(_ shape: S, offset: CGFloat = 3) -> some View {
        modifier(PrintShadowModifier(shape: shape, offset: offset))
    }
}

private struct PrintShadowModifier<S: Shape>: ViewModifier {
    let shape: S
    let offset: CGFloat
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content.background {
            shape.fill(palette.printShadow).offset(x: offset, y: offset)
        }
    }
}

// MARK: - Card stock

/// A flat piece of card: paper fill, hairline edge, hard print shadow, small corners.
struct CardStock<Content: View>: View {
    var padding: CGFloat = 18
    var cornerRadius: CGFloat = 4
    @ViewBuilder var content: Content
    @Environment(\.palette) private var palette

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .padding(padding)
            .background(shape.fill(palette.paper.color))
            .overlay(shape.strokeBorder(palette.paperEdge.color, lineWidth: 1))
            .printShadow(shape)
    }
}

// MARK: - Lines

/// Dashed tear line.
struct Perforation: View {
    var vertical = false
    var color: Color? = nil
    @Environment(\.palette) private var palette

    var body: some View {
        MidLine(vertical: vertical)
            .stroke(color ?? palette.paperEdge.color,
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 5]))
            .frame(width: vertical ? 2 : nil, height: vertical ? nil : 2)
    }
}

/// A 1 pt ruled line.
struct RuleLine: View {
    var color: Color? = nil
    var weight: CGFloat = 1
    @Environment(\.palette) private var palette

    var body: some View {
        Rectangle()
            .fill(color ?? palette.paperEdge.color)
            .frame(height: weight)
    }
}

/// Dotted leader between a label and its value, like a printed receipt.
struct DottedLeader: View {
    @Environment(\.palette) private var palette

    var body: some View {
        MidLine()
            .stroke(palette.inkSoft.withAlpha(0.7).color,
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [0.1, 4.5]))
            .frame(height: 2)
            .frame(minWidth: 12)
    }
}

/// Red and blue diagonal airmail border stripes on paper.
struct AirmailStripe: View {
    var stripe: CGFloat = 9
    @Environment(\.palette) private var palette

    var body: some View {
        let palette = palette
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.paper.color))
            let h = size.height
            var x: CGFloat = -h - stripe
            var i = 0
            while x < size.width + h {
                var p = Path()
                p.move(to: CGPoint(x: x, y: h))
                p.addLine(to: CGPoint(x: x + h, y: 0))
                p.addLine(to: CGPoint(x: x + h + stripe, y: 0))
                p.addLine(to: CGPoint(x: x + stripe, y: h))
                p.closeSubpath()
                ctx.fill(p, with: .color(i.isMultiple(of: 2) ? palette.accent.color : palette.secondary.color))
                x += stripe * 2
                i += 1
            }
        }
        .accessibilityHidden(true)
    }
}
