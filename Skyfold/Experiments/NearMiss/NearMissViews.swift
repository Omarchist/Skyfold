import SwiftUI

/// "CLOSE CALL x3 +75": a rubber stamp beside the score ticket while a close-call streak runs.
///
/// It stamps in (a short scale-down, no spring) on every close call and fades once the streak
/// ends. It reads only the streak fields of the session, and never takes touches.
struct NearMissTag: View {
    let session: RunSession
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// What the stamp shows. Kept here so the text stays readable while it fades out.
    @State private var level = 1
    @State private var award = 0
    @State private var visible = false
    @State private var stampedIn = true
    @State private var tilt = Seeded.tilt("close-call-1", min: 2, max: 4)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
        let ink = palette.accent.color
        VStack(alignment: .leading, spacing: 1) {
            Text("Close call")
                .signage(9, weight: .bold)
            Text("x\(level)  +\(UIFormat.number(award))")
                .font(.ticket(17, weight: .heavy))
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(shape.fill(palette.paper.color))
        .overlay(shape.stroke(ink, lineWidth: 2))
        .overlay(shape.inset(by: 3.5).stroke(ink.opacity(0.6), lineWidth: 0.75))
        .printShadow(shape, offset: 2)
        .rotationEffect(tilt)
        .scaleEffect(stampedIn || reduceMotion ? 1 : 1.35, anchor: .topLeading)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(visible ? "Close call, streak \(level), \(award) points" : "")
        .onChange(of: session.streakSerial) { _, serial in
            guard session.streakLevel > 0 else { return }
            level = session.streakLevel
            award = session.streakAward
            tilt = Seeded.tilt("close-call-\(serial)", min: 2, max: 4)
            visible = true
            stampedIn = false
            withAnimation(.easeOut(duration: 0.14)) { stampedIn = true }
        }
        .onChange(of: session.streakLevel) { _, now in
            guard now == 0 else { return }
            withAnimation(.easeIn(duration: 0.25)) { visible = false }
        }
    }
}

/// "Best streak x4" on the game-over stub.
struct BestStreakLine: View {
    let session: RunSession
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Best streak")
                .signage(10)
                .foregroundStyle(palette.inkSoft.color)
            Text(session.bestStreak > 0 ? "x\(session.bestStreak)" : "none")
                .font(.ticket(session.bestStreak > 0 ? 18 : 14, weight: .semibold))
                .foregroundStyle(session.bestStreak > 0 ? palette.accent.color : palette.inkSoft.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
