import SwiftUI

/// The big 3, 2, 1, printed on a departure slip so it reads over any scene, day or night.
/// The numeral is set twice slightly out of register, the way a two-color poster is. The slip
/// never takes touches, so the flight gestures still work under it.
struct FlightCountdown: View {
    let session: RunSession
    let landscape: Bool
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let n = min(3, max(1, session.countdown))
        let resuming = session.legDistance > 1
        let shape = TicketShape(cornerRadius: 3, notch: .horizontal(fromTop: 40), notchRadius: 5)
        HStack(alignment: .center, spacing: 14) {
            numeral(n)
                .id(n)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .scale(scale: 1.25, anchor: .center).combined(with: .opacity),
                    removal: .opacity))
            Rectangle()
                .fill(palette.flightEdge)
                .frame(width: 1)
                .padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(resuming ? "Resuming in" : "Takeoff in")
                    .signage(12, weight: .bold)
                    .foregroundStyle(palette.accent.color)
                    .lineLimit(1)
                Text(UIFormat.flightNumber(from: session.leg.fromRoute, to: session.leg.toRoute))
                    .font(.ticket(15, weight: .bold))
                    .foregroundStyle(palette.ink.color)
                    .lineLimit(1)
                Text("\(session.origin.code) to \(session.destination.code)")
                    .font(.ticket(13, weight: .medium))
                    .foregroundStyle(palette.inkSoft.color)
                    .lineLimit(1)
            }
            .fixedSize()
        }
        .fixedSize()
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(shape.fill(palette.paper.color))
        .overlay(shape.stroke(palette.flightEdge, lineWidth: 1))
        .printShadow(shape)
        .rotationEffect(.degrees(-1.5))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: n)
        // Portrait: a block in the HUD column. Landscape: centered, to the right of the plane.
        .frame(maxWidth: landscape ? .infinity : nil, maxHeight: landscape ? .infinity : nil,
               alignment: landscape ? .center : .leading)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(n)")
    }

    private func numeral(_ n: Int) -> some View {
        let size: CGFloat = 84
        return ZStack(alignment: .topLeading) {
            Text("\(n)")
                .foregroundStyle(palette.accent.color)
                .offset(x: size * 0.045, y: size * 0.045)
            Text("\(n)")
                .foregroundStyle(palette.ink.color)
        }
        .font(.ticket(size, weight: .heavy))
        .lineLimit(1)
        .fixedSize()
        .frame(minWidth: 56)
    }
}
