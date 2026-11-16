import SwiftUI

// Ticket pieces: a two-part pass with a perforated tear line, a barcode, and the little
// folded-paper plane used as a glyph.

// MARK: - Ticket panel

/// A pass in two parts. `main` sits above a perforated tear line with a notch on each edge,
/// `stub` below it. Corners are small, the shadow is a hard print offset, and the whole
/// thing is clipped to the ticket outline so a header band can run to the corners.
struct TicketPanel<Main: View, Stub: View>: View {
    var cornerRadius: CGFloat = 5
    var notchRadius: CGFloat = 8
    var fill: Color? = nil
    @ViewBuilder var main: Main
    @ViewBuilder var stub: Stub

    @Environment(\.palette) private var palette
    /// Height of the main part, measured, so the notches land on the tear line.
    @State private var split: CGFloat = -100

    var body: some View {
        let shape = TicketShape(cornerRadius: cornerRadius, notch: .horizontal(fromTop: split),
                                notchRadius: notchRadius)
        VStack(spacing: 0) {
            main
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { split = $0 }
            stub
        }
        .background(shape.fill(fill ?? palette.paper.color))
        .clipShape(shape)
        .overlay(shape.stroke(palette.paperEdge.color, lineWidth: 1))
        .overlay(alignment: .top) {
            Perforation()
                .padding(.horizontal, notchRadius + 5)
                .offset(y: split - 1)
                .opacity(split > 0 ? 1 : 0)
        }
        .printShadow(shape)
    }
}

// MARK: - Barcode

/// A decorative barcode. The same seed always prints the same bars.
struct Barcode: View {
    var seed: String
    var color: Color? = nil
    @Environment(\.palette) private var palette

    var body: some View {
        let ink = color ?? palette.ink.color
        Canvas { ctx, size in
            var rng = SeededRandom("barcode." + seed)
            var x: CGFloat = 0
            while x < size.width {
                let w: CGFloat = [1, 1, 2, 3][min(3, Int(rng.next() * 4))]
                let gap: CGFloat = [1, 2, 2, 3][min(3, Int(rng.next() * 4))]
                let bar = min(w, size.width - x)
                ctx.fill(Path(CGRect(x: x, y: 0, width: bar, height: size.height)), with: .color(ink))
                x += w + gap
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Paper plane glyph

/// A folded paper plane in three flat facets, nose pointing right. Aspect ratio 1.7 : 1.
/// Used for the skin swatches, the Fly button and route marks.
struct PaperPlaneGlyph: View {
    var paper: RGBA
    var crease: RGBA
    /// Hairline around each facet, so a pale plane still reads on pale card.
    var outline: Color? = nil

    var body: some View {
        Canvas { ctx, size in
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size.width, y: y * size.height) }
            let nose = pt(1.0, 0.417)
            let tip = pt(0, 0)
            let fold = pt(0.293, 0.583)
            let belly = pt(0.22, 1.0)
            let tail = pt(0.049, 0.75)

            func facet(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ color: RGBA) {
                var p = Path()
                p.move(to: a)
                p.addLine(to: b)
                p.addLine(to: c)
                p.closeSubpath()
                ctx.fill(p, with: .color(color.color))
                if let outline { ctx.stroke(p, with: .color(outline), style: StrokeStyle(lineWidth: 0.8, lineJoin: .round)) }
            }
            facet(nose, tip, fold, paper)
            facet(nose, fold, belly, crease)
            facet(nose, belly, tail, paper.scaled(0.9))
        }
        .aspectRatio(1.7, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
