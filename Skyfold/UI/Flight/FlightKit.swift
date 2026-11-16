import SwiftUI

// Small pieces shared by the flight screen: cut-paper shapes, the stamp, the print-style
// buttons and the wrapping row used for the HUD marks. Everything here is private to the
// flight slice (prefix Flight) so it cannot collide with the other UI folders.

// MARK: - Shapes

/// A folded paper plane seen from the side, nose to the right. `facet` picks one of the two
/// folds so the two halves can be filled in different shades.
nonisolated struct FlightPlaneShape: Shape {
    enum Facet { case whole, upper, lower }
    var facet: Facet = .whole

    func path(in r: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height)
        }
        let nose = pt(1, 0.5), wingTip = pt(0.02, 0.04), fold = pt(0.36, 0.56), keel = pt(0.15, 0.98)
        var p = Path()
        p.move(to: nose)
        switch facet {
        case .whole:
            p.addLine(to: wingTip); p.addLine(to: fold); p.addLine(to: keel)
        case .upper:
            p.addLine(to: wingTip); p.addLine(to: fold)
        case .lower:
            p.addLine(to: fold); p.addLine(to: keel)
        }
        p.closeSubpath()
        return p
    }
}

/// A flat five-point star, like one cut from card.
nonisolated struct FlightStarShape: Shape {
    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY + r.height * 0.03)
        let outer = min(r.width, r.height) / 2
        let inner = outer * 0.44
        var p = Path()
        for i in 0..<10 {
            let a = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5
            let radius = i.isMultiple(of: 2) ? outer : inner
            let point = CGPoint(x: c.x + cos(a) * radius, y: c.y + sin(a) * radius)
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        p.closeSubpath()
        return p
    }
}

/// The ring between a rectangle and a smaller one inside it (fill with the even-odd rule).
nonisolated struct FlightFrameShape: Shape {
    var inset: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRect(rect)
        p.addRect(rect.insetBy(dx: inset, dy: inset))
        return p
    }
}

/// The two bars of a pause mark, drawn rather than taken from a symbol set.
struct FlightPauseMark: View {
    var color: Color
    var body: some View {
        HStack(spacing: 5) {
            Rectangle().frame(width: 5, height: 18)
            Rectangle().frame(width: 5, height: 18)
        }
        .foregroundStyle(color)
        .accessibilityHidden(true)
    }
}

/// A small flat paper plane in two shades of one color.
struct FlightPlaneMark: View {
    var color: Color
    var shade: Color
    var body: some View {
        ZStack {
            FlightPlaneShape(facet: .upper).fill(color)
            FlightPlaneShape(facet: .lower).fill(shade)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Palette roles

extension Palette {
    /// Hairline around HUD paper: the normal paper edge by day, a lighter ink line by night so
    /// a tag still reads against the dark sky.
    var flightEdge: Color {
        isDark ? inkSoft.withAlpha(0.6).color : paperEdge.color
    }
}

// MARK: - Stamp

/// A rubber stamp: double outline, tracked capitals, a few degrees off true.
struct FlightStamp: View {
    let text: String
    var color: Color
    var tilt: Angle = .degrees(-4)

    var body: some View {
        Text(text)
            .signage(12, weight: .heavy)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .overlay { RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(color, lineWidth: 2) }
            .padding(3)
            .overlay { RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(color, lineWidth: 1) }
            .rotationEffect(tilt)
            .opacity(0.9)
    }
}

// MARK: - Buttons

/// The main action on an overlay: a flat accent block with a hard shadow that the button
/// presses into, like a rubber key.
struct FlightPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FlightPrimaryFace(configuration: configuration)
    }
}

private struct FlightPrimaryFace: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.palette) private var palette

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        let d: CGFloat = configuration.isPressed ? 2 : 0
        configuration.label
            .font(.skyfold(16, weight: .bold))
            .textCase(.uppercase)
            .tracking(1.5)
            .foregroundStyle(palette.accentInk.color)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(shape.fill(palette.accent.color))
            .background { shape.fill(palette.printShadow).offset(x: 3 - d, y: 3 - d) }
            .offset(x: d, y: d)
            .contentShape(shape)
    }
}

/// A plain underlined text action (Give up, End flight).
struct FlightTextButtonStyle: ButtonStyle {
    var tint: Color? = nil
    func makeBody(configuration: Configuration) -> some View {
        FlightTextFace(configuration: configuration, tint: tint)
    }
}

private struct FlightTextFace: View {
    let configuration: ButtonStyle.Configuration
    let tint: Color?
    @Environment(\.palette) private var palette

    var body: some View {
        configuration.label
            .font(.skyfold(15, weight: .semibold))
            .underline(true, color: (tint ?? palette.ink.color).opacity(0.5))
            .foregroundStyle(tint ?? palette.ink.color)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}

/// A square paper key for the HUD (pause).
struct FlightSquareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FlightSquareFace(configuration: configuration)
    }
}

private struct FlightSquareFace: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.palette) private var palette

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        let d: CGFloat = configuration.isPressed ? 2 : 0
        configuration.label
            .frame(width: 46, height: 46)
            .background(shape.fill(palette.paper.color))
            .overlay(shape.strokeBorder(palette.flightEdge, lineWidth: 1))
            .background { shape.fill(palette.printShadow).offset(x: 3 - d, y: 3 - d) }
            .offset(x: d, y: d)
            .contentShape(shape)
    }
}

// MARK: - Wrapping row

/// Lays children left to right and wraps to a new row when the width runs out.
struct FlightFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Formatting

enum FlightFormat {
    /// Distance left on the leg: whole tens of meters below a kilometer, then one decimal.
    static func toGo(_ meters: Double) -> String {
        if meters < 1000 { return "\(Int((meters / 10).rounded(.up)) * 10) m" }
        return (meters / 1000).formatted(.number.precision(.fractionLength(1))) + " km"
    }
}
