import SwiftUI

/// "GHOST +40 m": a small printed tag at the screen edge toward the ghost, while it is off screen.
/// Ahead sits on the right edge, behind on the left. Reads only `ghostNote`; never takes touches.
struct GhostNote: View {
    let session: RunSession
    let landscape: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        if let text = session.ghostNote {
            let ahead = text.contains("+")
            let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
            Text(text)
                .font(.ticket(11, weight: .semibold))
                .tracking(1)
                .foregroundStyle(palette.ink.color)
                .lineLimit(1)
                .fixedSize()
                .limitedTypeSize()
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(shape.fill(palette.paper.color))
                .overlay(shape.stroke(palette.ink.withAlpha(0.55).color, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                .printShadow(shape, offset: 2)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: ahead ? .trailing : .leading)
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(ahead ? "Ghost ahead" : "Ghost behind")
        }
    }
}

/// "Ghost saved" on the game-over ticket, stamped like a small rubber mark.
struct GhostSavedLine: View {
    let session: RunSession
    @Environment(\.palette) private var palette

    var body: some View {
        if session.ghostSaved {
            let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
            let ink = palette.secondary.color
            HStack(spacing: 0) {
                Text("Ghost saved")
                    .textCase(.uppercase)
                    .font(.ticket(11, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(ink)
                    .limitedTypeSize()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .overlay(shape.stroke(ink, lineWidth: 1.5))
                    .rotationEffect(.degrees(-1.5))
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Ghost saved")
        }
    }
}
