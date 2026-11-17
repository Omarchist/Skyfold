import SwiftUI

/// The gust warning: paper wind streaks across the scene and a small printed sign. Both read
/// only `session.gustWarning` (+1 a gust from below, -1 from above, 0 none), never take touches,
/// and draw nothing while no gust is announced.
struct GustLayer: View {
    let session: RunSession
    let landscape: Bool

    @State private var direction = 1
    @State private var started = Date()
    @State private var lingerUntil = Date.distantPast
    /// True from the warning until the streaks have blown out; no timeline runs outside that.
    @State private var running = false

    var body: some View {
        let warning = session.gustWarning
        ZStack(alignment: .topTrailing) {
            if running {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                    GustStreaks(direction: direction, age: timeline.date.timeIntervalSince(started),
                                live: warning != 0, fade: max(0, lingerUntil.timeIntervalSince(timeline.date)))
                }
            }
            GustSign(direction: direction)
                .padding(.top, landscape ? 118 : 168)
                .padding(.trailing, 14)
                .opacity(warning != 0 ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .onChange(of: warning) { old, new in
            if new != 0 {
                direction = new
                started = Date()
                lingerUntil = .distantPast
                running = true
            } else if old != 0 {
                lingerUntil = Date().addingTimeInterval(0.5)   // the streaks blow out after the push
                Task {
                    try? await Task.sleep(for: .milliseconds(550))
                    if session.gustWarning == 0 { running = false }
                }
            }
        }
    }
}

/// "GUST" with an arrow, printed on a small card tilted a few degrees. The arrow points the way
/// the wind will push.
private struct GustSign: View {
    let direction: Int
    @Environment(\.palette) private var palette

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
        let ink = palette.accent.color
        HStack(spacing: 7) {
            GustArrow()
                .fill(ink)
                .frame(width: 12, height: 18)
                .rotationEffect(.degrees(direction > 0 ? 0 : 180))
            VStack(alignment: .leading, spacing: 0) {
                Text("Gust").signage(14, weight: .heavy)
                Text(direction > 0 ? "Pushing up" : "Pushing down")
                    .font(.ticket(9, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(palette.inkSoft.color)
                    .fixedSize()
            }
            .foregroundStyle(ink)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(shape.fill(palette.paper.color))
        .overlay(shape.stroke(ink, lineWidth: 2))
        .overlay(shape.inset(by: 3.5).stroke(ink.opacity(0.6), lineWidth: 0.75))
        .printShadow(shape, offset: 2)
        .rotationEffect(Seeded.tilt("gust-sign", min: 2, max: 3))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(direction > 0 ? "Gust, pushing up" : "Gust, pushing down")
    }
}

/// A flat arrow pointing up: shaft and a triangular head.
private struct GustArrow: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        let shaft = w * 0.3
        let head = h * 0.5
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + head))
        p.addLine(to: CGPoint(x: r.midX + shaft / 2, y: r.minY + head))
        p.addLine(to: CGPoint(x: r.midX + shaft / 2, y: r.maxY))
        p.addLine(to: CGPoint(x: r.midX - shaft / 2, y: r.maxY))
        p.addLine(to: CGPoint(x: r.midX - shaft / 2, y: r.minY + head))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + head))
        p.closeSubpath()
        return p
    }
}

/// Cut-paper wind streaks: long pointed slips with a hard print shadow, sliding across the screen
/// from the side the gust comes from, drifting back against the plane's flight. Seeded, so every
/// gust draws the same streaks. Flat shapes only.
private struct GustStreaks: View {
    let direction: Int
    let age: TimeInterval
    let live: Bool
    let fade: TimeInterval
    @Environment(\.palette) private var palette

    private static let count = 9
    /// How long one streak takes to cross the screen.
    private static let travel = 1.15

    var body: some View {
        let paper = palette.paper.color
        let ink = palette.ink.color
        let shadow = palette.printShadow
        let up = direction > 0
        Canvas { ctx, size in
            for i in 0..<Self.count {
                let u1 = Seeded.unit("gust-x-\(i)")
                let u2 = Seeded.unit("gust-t-\(i)")
                let u3 = Seeded.unit("gust-l-\(i)")
                // Each streak starts a little later than the one before and then repeats.
                let t0 = u2 * 0.7
                let local = age - t0
                guard local >= 0 else { continue }
                let phase = local.truncatingRemainder(dividingBy: Self.travel * 1.25) / Self.travel
                guard phase <= 1 else { continue }
                // Dies off once the warning is over.
                if !live, age > 0, fade <= 0 { continue }
                let length = size.height * (0.16 + 0.14 * u3)
                let width = 11.0 + 8.0 * u3
                let x = size.width * (0.06 + 0.9 * u1) - phase * size.width * 0.12
                // From just beyond the gust's edge to just beyond the far one.
                let travelY = size.height + length * 2
                let y = up ? size.height + length - phase * travelY : -length + phase * travelY
                let lean = CGFloat(-0.16)                    // drifts back, against the flight
                let tail = CGPoint(x: x - lean * length * (up ? -1 : 1), y: y + (up ? length / 2 : -length / 2))
                let tip = CGPoint(x: x + lean * length * (up ? -1 : 1), y: y + (up ? -length / 2 : length / 2))
                let slip = Self.slip(tail: tail, tip: tip, width: width)
                ctx.fill(slip.offsetBy(dx: 3, dy: 3), with: .color(shadow))
                ctx.fill(slip, with: .color(paper.opacity(0.95)))
                ctx.stroke(slip, with: .color(ink.opacity(0.7)), lineWidth: 1.25)
            }
        }
        .accessibilityHidden(true)
    }

    /// A long pointed slip of paper from `tail` to `tip`, widest a third of the way along.
    private static func slip(tail: CGPoint, tip: CGPoint, width: CGFloat) -> Path {
        let dx = tip.x - tail.x, dy = tip.y - tail.y
        let len = max(hypot(dx, dy), 1)
        let nx = -dy / len * width / 2, ny = dx / len * width / 2
        let belly = CGPoint(x: tail.x + dx * 0.35, y: tail.y + dy * 0.35)
        var p = Path()
        p.move(to: tail)
        p.addLine(to: CGPoint(x: belly.x + nx, y: belly.y + ny))
        p.addLine(to: tip)
        p.addLine(to: CGPoint(x: belly.x - nx, y: belly.y - ny))
        p.closeSubpath()
        return p
    }
}

private extension Path {
    func offsetBy(dx: CGFloat, dy: CGFloat) -> Path { applying(CGAffineTransform(translationX: dx, y: dy)) }
}
