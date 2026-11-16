import SwiftUI

// Shared pieces for the airport and game-over screens. Every type here is prefixed
// `Airport` so it cannot collide with another slice's private helpers.

// MARK: - Layout

/// The screen as the overlay sees it: full-bleed size plus the safe-area insets, so content
/// can keep clear of notches while the paper pieces still line up with the 3D halves.
struct AirportMetrics: Equatable {
    var size: CGSize
    var insets: EdgeInsets

    var isLandscape: Bool { size.width > size.height }
    var left: CGFloat { insets.leading + (isLandscape ? 14 : 20) }
    var right: CGFloat { insets.trailing + (isLandscape ? 14 : 20) }
    var top: CGFloat { insets.top + (isLandscape ? 10 : 14) }
    var bottom: CGFloat { insets.bottom + (isLandscape ? 10 : 18) }
    var contentWidth: CGFloat { max(0, size.width - left - right) }

    var edgeInsets: EdgeInsets {
        EdgeInsets(top: top, leading: left, bottom: bottom, trailing: right)
    }
}

/// Lays its content out full-bleed (edge to edge, under the notch and home indicator) and hands
/// it the real safe-area insets, so paper can keep clear of the Dynamic Island and the side
/// insets while the scrim and the gate halves still cover the whole screen.
///
/// The insets are measured, not read from `GeometryProxy.safeAreaInsets`: that reads zero inside
/// `.ignoresSafeArea()`, which is how the gate signs ended up under the status bar. A reader that
/// respects the safe area and one that ignores it are compared in global coordinates instead.
struct AirportScreenReader<Content: View>: View {
    @ViewBuilder var content: (AirportMetrics) -> Content

    var body: some View {
        GeometryReader { safe in
            let safeFrame = safe.frame(in: .global)
            GeometryReader { full in
                let fullFrame = full.frame(in: .global)
                content(AirportMetrics(size: full.size,
                                       insets: Self.insets(safe: safeFrame, full: fullFrame)))
                    .frame(width: full.size.width, height: full.size.height, alignment: .topLeading)
            }
            .ignoresSafeArea()
        }
    }

    private static func insets(safe: CGRect, full: CGRect) -> EdgeInsets {
        EdgeInsets(top: max(0, safe.minY - full.minY),
                   leading: max(0, safe.minX - full.minX),
                   bottom: max(0, full.maxY - safe.maxY),
                   trailing: max(0, full.maxX - safe.maxX))
    }
}

// MARK: - Buttons

nonisolated enum AirportButtonKind: Sendable { case primary, secondary }

/// A hard-shadowed paper button. Pressing it pushes the card into its own shadow.
struct AirportButtonStyle: ButtonStyle {
    var kind: AirportButtonKind = .primary

    func makeBody(configuration: Configuration) -> some View {
        AirportButtonBody(configuration: configuration, kind: kind)
    }
}

private struct AirportButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: AirportButtonKind
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let pressed = configuration.isPressed
        let primary = kind == .primary
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        configuration.label
            .font(.skyfold(primary ? 18 : 16, weight: .semibold))
            .foregroundStyle(primary ? palette.accentInk.color : palette.ink.color)
            .padding(.horizontal, primary ? 18 : 16)
            .frame(minHeight: primary ? 54 : 44)
            .background(shape.fill(primary ? palette.accent.color : palette.paper.color))
            .overlay(shape.strokeBorder(primary ? Color.clear : palette.ink.color, lineWidth: 1.5))
            .printShadow(shape, offset: pressed ? 1 : 3)
            .offset(x: pressed ? 2 : 0, y: pressed ? 2 : 0)
            .opacity(isEnabled ? 1 : 0.55)
            .contentShape(shape)
            .animation(.linear(duration: 0.06), value: pressed)
    }
}

/// Title left, optional direction mark right, like the call-to-action on a boarding pass.
struct AirportButton: View {
    let title: String
    var kind: AirportButtonKind = .primary
    var trailing: String? = nil
    let action: () -> Void

    var body: some View {
        Button {
            UIFeedback.tap()
            action()
        } label: {
            HStack(spacing: 10) {
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing).font(.ticket(19, weight: .bold))
                }
            }
        }
        .buttonStyle(AirportButtonStyle(kind: kind))
    }
}

/// A button with no look of its own (the 3D gate behind it is the picture). It only reports
/// the pressed state so the sign above it can dip when touched.
struct AirportGateStyle: ButtonStyle {
    var onPress: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .onChange(of: configuration.isPressed) { _, now in onPress(now) }
    }
}

// MARK: - Shapes

/// A ticket whose leading tab is separated by a perforation: half-circle bites top and bottom.
nonisolated struct AirportTabTicketShape: Shape {
    var tabWidth: CGFloat
    var cornerRadius: CGFloat = 4
    var biteRadius: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        var bites = Path()
        for y in [rect.minY, rect.maxY] {
            bites.addEllipse(in: CGRect(x: rect.minX + tabWidth - biteRadius, y: y - biteRadius,
                                        width: biteRadius * 2, height: biteRadius * 2))
        }
        return Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous).subtracting(bites)
    }
}

/// A printed slip: flat top, zig-zag cut along the bottom. `ragged` makes the teeth uneven,
/// the way a hand-torn edge would be.
nonisolated struct AirportSlipShape: Shape {
    var seed: String
    var ragged = false
    var tooth: CGFloat = 9
    var depth: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        var rng = SeededRandom(seed)
        var p = Path()
        let base = rect.maxY - depth
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: base))
        var x = rect.maxX
        while x > rect.minX + 0.5 {
            let w = ragged ? tooth * (0.6 + 0.9 * rng.next()) : tooth
            let d = ragged ? depth * (0.45 + 0.55 * rng.next()) : depth
            let nx = max(rect.minX, x - w)
            p.addLine(to: CGPoint(x: (x + nx) / 2, y: base + d))
            p.addLine(to: CGPoint(x: nx, y: base))
            x = nx
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - Print effects

/// Knocks small seeded specks out of whatever it masks, so a stamp reads as pressed ink
/// that did not take evenly. Use as `.mask { AirportInkDropout(seed:) }`.
struct AirportInkDropout: View {
    let seed: String
    var density: CGFloat = 1

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            var rng = SeededRandom(seed)
            let count = Int(size.width * size.height / 380 * density)
            ctx.blendMode = .destinationOut
            for _ in 0..<count {
                let x = rng.next() * size.width
                let y = rng.next() * size.height
                let r = 0.5 + rng.next() * rng.next() * 3.4
                let strength = 0.35 + 0.65 * Double(rng.next())
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r * 0.7, width: r * 2, height: r * 1.4)),
                         with: .color(.white.opacity(strength)))
            }
            // One streak where the stamp was pressed unevenly.
            let sx = rng.next() * size.width * 0.6
            let sy = rng.next() * size.height
            ctx.fill(Path(CGRect(x: sx, y: sy, width: size.width * 0.28, height: 1.4)),
                     with: .color(.white.opacity(0.7)))
        }
        .allowsHitTesting(false)
    }
}

/// Slides a view down out of a slot above it while clipping at the slot, like a receipt
/// being printed. `progress` 0 hides it, 1 shows it whole.
struct AirportPrintOut: ViewModifier {
    var progress: CGFloat

    func body(content: Content) -> some View {
        content
            .visualEffect { view, proxy in
                view.offset(y: -proxy.size.height * (1 - progress))
            }
            .clipped()
    }
}

/// A short barcode, seeded so a given ticket always prints the same one.
struct AirportBarcode: View {
    let seed: String
    var color: Color

    var body: some View {
        Canvas { ctx, size in
            var rng = SeededRandom(seed)
            var x: CGFloat = 0
            while x < size.width {
                let bar = CGFloat(1 + Int(rng.next() * 3))
                let gap = CGFloat(1 + Int(rng.next() * 3))
                let w = min(bar, size.width - x)
                ctx.fill(Path(CGRect(x: x, y: 0, width: w, height: size.height)), with: .color(color))
                x += bar + gap
            }
        }
        .accessibilityHidden(true)
    }
}

/// Counts a number up while animated (`withAnimation` on the value).
struct AirportCounter: View, Animatable {
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(UIFormat.number(Int(value.rounded())))
    }
}
