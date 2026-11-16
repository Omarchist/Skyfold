import SwiftUI

/// The big 3, 2, 1. Printed twice slightly out of register, the way a two-color poster is,
/// with the flight number and the sector above it like a gate board.
struct FlightCountdown: View {
    let session: RunSession
    let landscape: Bool
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let n = min(3, max(1, session.countdown))
        let resuming = session.legDistance > 1
        VStack(alignment: .leading, spacing: landscape ? 0 : 2) {
            Text(resuming ? "Resuming in" : "Takeoff in")
                .signage(13, weight: .bold)
                .foregroundStyle(palette.accent.color)
            numeral(n)
                .id(n)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .scale(scale: 1.3, anchor: .leading).combined(with: .opacity),
                    removal: .opacity))
            HStack(spacing: 8) {
                Text(UIFormat.flightNumber(from: session.leg.fromRoute, to: session.leg.toRoute))
                    .font(.ticket(13, weight: .bold))
                Text("\(session.origin.code) to \(session.destination.code)")
                    .font(.ticket(13, weight: .medium))
            }
            .foregroundStyle(palette.ink.color)
            .padding(.top, landscape ? 0 : 4)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: n)
        // Portrait: a block in the HUD column. Landscape: centered, to the right of the plane.
        .frame(maxWidth: landscape ? .infinity : nil, maxHeight: landscape ? .infinity : nil,
               alignment: landscape ? .center : .leading)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(n)")
    }

    private func numeral(_ n: Int) -> some View {
        let size: CGFloat = landscape ? 120 : 140
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
    }
}
