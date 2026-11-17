import SwiftUI

/// The first-flight hint: how to change altitude. It appears when the first flight starts,
/// goes as soon as the player changes lane, and fades by itself after a few seconds.
struct FlightHint: View {
    let session: RunSession
    let settings: GameSettings
    let progress: ProgressStore
    let landscape: Bool
    @State private var started = false
    @State private var visible = false
    @State private var hideTask: Task<Void, Never>?
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The hint is for new pilots: it shows on the first few flights, if Hints is on.
    private static let hintedRuns = 3

    private var text: String {
        switch settings.controlScheme {
        case .swipe: "Swipe up or down to change altitude"
        case .tapZones: "Tap the top or bottom half to change altitude"
        }
    }

    var body: some View {
        ZStack {
            if visible {
                let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
                HStack(spacing: 12) {
                    FlightHintArrows(tapZones: settings.controlScheme == .tapZones)
                        .frame(width: 22, height: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("How to fly")
                            .signage(10, weight: .bold)
                            .foregroundStyle(palette.accent.color)
                        Text(text)
                            .font(.skyfold(15, weight: .medium))
                            .foregroundStyle(palette.ink.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: landscape ? 380 : 330, alignment: .leading)
                .background(shape.fill(palette.paper.color))
                .overlay(shape.stroke(palette.flightEdge, lineWidth: 1))
                .printShadow(shape)
                .rotationEffect(.degrees(-1.4))
                .padding(.horizontal, 18)
                .padding(.bottom, landscape ? 18 : 64)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: visible)
        .onChange(of: session.phase, initial: true) { _, phase in
            // The hint belongs to the air. A pause, crash, airport or game over card replaces it.
            if visible, phase != .flying, phase != .countdown {
                hideTask?.cancel()
                visible = false
            }
            guard phase == .flying, !started, settings.showHints,
                  progress.data.runsPlayed < Self.hintedRuns else { return }
            started = true
            visible = true
            schedule(after: 5.5)
        }
        .onChange(of: session.lane) { _, _ in
            guard visible else { return }
            schedule(after: 1.0)
        }
    }

    private func schedule(after seconds: Double) {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            visible = false
        }
    }
}

/// A dashed vertical line with a head at each end. For tap controls the heads are boxed.
private struct FlightHintArrows: View {
    let tapZones: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        let ink = palette.ink.color
        Canvas { ctx, size in
            let x = size.width / 2
            var line = Path()
            line.move(to: CGPoint(x: x, y: 8))
            line.addLine(to: CGPoint(x: x, y: size.height - 8))
            ctx.stroke(line, with: .color(ink), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            var up = Path()
            up.move(to: CGPoint(x: x - 6, y: 9))
            up.addLine(to: CGPoint(x: x, y: 1))
            up.addLine(to: CGPoint(x: x + 6, y: 9))
            ctx.stroke(up, with: .color(ink), style: StrokeStyle(lineWidth: 2, lineCap: .square, lineJoin: .miter))
            var down = Path()
            down.move(to: CGPoint(x: x - 6, y: size.height - 9))
            down.addLine(to: CGPoint(x: x, y: size.height - 1))
            down.addLine(to: CGPoint(x: x + 6, y: size.height - 9))
            ctx.stroke(down, with: .color(ink), style: StrokeStyle(lineWidth: 2, lineCap: .square, lineJoin: .miter))
            if tapZones {
                let mid = size.height / 2
                var split = Path()
                split.move(to: CGPoint(x: 0, y: mid))
                split.addLine(to: CGPoint(x: size.width, y: mid))
                ctx.stroke(split, with: .color(ink), lineWidth: 1.5)
            }
        }
        .accessibilityHidden(true)
    }
}
