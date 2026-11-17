import SwiftUI

/// The end of a flight, drawn as the torn stub of a ticket over the crash: score with a
/// "New best" mark, distance, cities, stars, then the blessings and curses taken on the way.
/// Appears about 0.8 s after the run ends so the crash has time to read.
struct GameOverOverlay: View {
    let session: RunSession

    var body: some View {
        if let result = session.result {
            GameOverStub(session: session, result: result)
        }
    }
}

private struct GameOverStub: View {
    let session: RunSession
    let result: RunResult

    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var scrimIn = false
    @State private var shown = false
    @State private var counted: Double = 0
    @State private var markShown = false
    @State private var ready = false
    @State private var chose = false

    var body: some View {
        AirportScreenReader { metrics in
            ViewThatFits(in: .vertical) {
                layout(metrics)
                ScrollView(showsIndicators: false) { layout(metrics) }
                    .defaultScrollAnchor(.center)
            }
            .padding(metrics.edgeInsets)
            .frame(width: metrics.size.width, height: metrics.size.height, alignment: .center)
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : -28)
            .allowsHitTesting(ready)
            // The scrim bleeds under the notch and home indicator; the stub stays inside the safe
            // area. It swallows touches so nothing reaches the flight view behind.
            .background {
                Rectangle()
                    .fill(palette.scrim)
                    .opacity(scrimIn ? 0.75 : 0)
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
            }
        }
        .task { await timeline() }
    }

    @ViewBuilder private func layout(_ metrics: AirportMetrics) -> some View {
        if metrics.isLandscape {
            landscape(metrics)
        } else {
            portrait(metrics)
        }
    }

    // MARK: Timeline

    private func timeline() async {
        if reduceMotion {
            scrimIn = true
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            shown = true
            counted = Double(result.score)
            markShown = true
            ready = true
            return
        }
        withAnimation(.easeIn(duration: 0.5).delay(0.3)) { scrimIn = true }
        try? await Task.sleep(for: .seconds(0.8))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.32)) { shown = true }
        withAnimation(.easeOut(duration: 0.9).delay(0.2)) { counted = Double(result.score) }
        try? await Task.sleep(for: .seconds(0.4))
        guard !Task.isCancelled else { return }
        ready = true
        guard result.isNewBest else { return }
        try? await Task.sleep(for: .seconds(0.8))
        guard !Task.isCancelled else { return }
        withAnimation(.easeIn(duration: 0.12)) { markShown = true }
        Services.haptics.play(.success)
    }

    // MARK: Actions

    private func flyAgain() {
        guard !chose else { return }
        chose = true
        model.restartRun()
    }

    private func toMenu() {
        guard !chose else { return }
        chose = true
        model.exitToMenu()
    }

    // MARK: Pieces

    private var sector: String {
        "\(session.leg.from.code) → \(session.leg.to.code)"
    }

    private var flightNumber: String {
        UIFormat.flightNumber(from: session.leg.fromRoute, to: session.leg.toRoute)
    }

    private var best: Int { model.progress.data.bestScore }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Flight ended")
                .font(.display(26, weight: .bold))
                .foregroundStyle(palette.ink.color)
            Text("\(flightNumber)  ·  \(sector)  ·  \(Difficulty.get(result.difficulty).name)")
                .textCase(.uppercase)
                .font(.ticket(11, weight: .medium))
                .tracking(1)
                .foregroundStyle(palette.inkSoft.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func scoreBlock(size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Score")
                .signage(11)
                .foregroundStyle(palette.inkSoft.color)
            AirportCounter(value: counted)
                .font(.ticket(size, weight: .heavy))
                .foregroundStyle(palette.ink.color)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottomTrailing) {
                    // Stamped beside the number, so it reads as an overprint rather than a label.
                    if result.isNewBest {
                        AirportBestMark(tilt: Seeded.tilt("best-\(result.score)", min: 4, max: 8).degrees)
                            .scaleEffect(markShown || reduceMotion ? 1 : 1.5)
                            .opacity(markShown ? 1 : 0)
                            .offset(x: 2, y: 2)
                    }
                }
            if !result.isNewBest {
                Text("Best  \(UIFormat.number(max(best, result.score)))")
                    .textCase(.uppercase)
                    .font(.ticket(12, weight: .medium))
                    .tracking(1)
                    .foregroundStyle(palette.inkSoft.color)
            }
        }
    }

    @ViewBuilder private var bestStreak: some View {
        if ExperimentStore.shared.isOn(.nearMissBonus) { BestStreakLine(session: session) }
    }

    private var fields: some View {
        HStack(alignment: .top, spacing: 0) {
            field("Distance", UIFormat.distance(result.distance))
            field("Cities", "\(result.citiesReached)")
            field("Stars", UIFormat.number(result.stars))
        }
    }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .signage(10)
                .foregroundStyle(palette.inkSoft.color)
            Text(value)
                .font(.ticket(22, weight: .semibold))
                .foregroundStyle(palette.ink.color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func modifierList(_ title: String, kind: ModifierKind) -> some View {
        let ids = result.modifiers.filter { $0.kind == kind }
        let tally = UIFormat.tally(ids)
        let line = tally.map { $0.count > 1 ? "\($0.id.info.name) ×\($0.count)" : $0.id.info.name }
            .joined(separator: "  ·  ")
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(title)
                    .signage(10)
                    .foregroundStyle(palette.inkSoft.color)
                Text("\(ids.count)")
                    .font(.ticket(10, weight: .semibold))
                    .foregroundStyle(palette.inkSoft.color)
            }
            if ids.isEmpty {
                Text("None taken")
                    .font(.display(15, weight: .regular).italic())
                    .foregroundStyle(palette.inkSoft.color)
            } else {
                Text(line)
                    .font(.display(16, weight: .semibold))
                    .foregroundStyle(palette.kindInk(kind))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func barcode(stacked: Bool = false) -> some View {
        let code = Text("\(flightNumber)  \(String(format: "%04d", result.score % 10_000))")
            .font(.ticket(10, weight: .medium))
            .tracking(1)
            .foregroundStyle(palette.inkSoft.color)
        let bars = AirportBarcode(seed: "\(result.score)-\(result.distance)",
                                  color: palette.ink.withAlpha(0.8).color)
            .frame(width: stacked ? 120 : 96, height: 22)
        return Group {
            if stacked {
                VStack(alignment: .leading, spacing: 4) { bars; code }
            } else {
                HStack(alignment: .bottom, spacing: 10) { bars; code }
            }
        }
    }

    // MARK: Portrait: a torn stub with the buttons below the perforation

    private func portrait(_ metrics: AirportMetrics) -> some View {
        let width = min(metrics.contentWidth, 380)
        let tearZone: CGFloat = 89
        let shape = TornStubShape(seed: "over-\(result.score)", tooth: 9, depth: 6,
                                  notchFromBottom: tearZone + 1, notchRadius: 8)
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                header
                scoreBlock(size: 62)
                RuleLine()
                fields
                bestStreak
                RuleLine()
                VStack(alignment: .leading, spacing: 12) {
                    modifierList("Blessings", kind: .blessing)
                    modifierList("Curses", kind: .curse)
                }
                barcode()
            }
            .padding(.horizontal, 22)
            .padding(.top, 28)
            .padding(.bottom, 18)
            Perforation()
                .padding(.horizontal, 14)
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    AirportButton(title: "Fly again", trailing: "→", action: flyAgain)
                    AirportButton(title: "Menu", kind: .secondary, action: toMenu)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(.horizontal, 22)
            .frame(height: tearZone, alignment: .center)
        }
        .frame(width: width)
        .background(shape.fill(palette.paper.color))
        .overlay(shape.stroke(palette.paperEdge.color, lineWidth: 1))
        .printShadow(shape)
        .rotationEffect(Seeded.tilt("stub-\(result.score)", min: 0.6, max: 1.4))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 0)
    }

    // MARK: Landscape: a horizontal ticket, main part and tear-off

    private func landscape(_ metrics: AirportMetrics) -> some View {
        let width = min(metrics.contentWidth, 760)
        let stubWidth: CGFloat = 188
        let shape = TicketShape(cornerRadius: 4, notch: .vertical(fromTrailing: stubWidth), notchRadius: 9)
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                header
                scoreBlock(size: 54)
                fields
                bestStreak
                HStack(alignment: .top, spacing: 16) {
                    modifierList("Blessings", kind: .blessing)
                    modifierList("Curses", kind: .curse)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            Perforation(vertical: true)
                .padding(.vertical, 14)
            VStack(alignment: .leading, spacing: 12) {
                barcode(stacked: true)
                Spacer(minLength: 0)
                AirportButton(title: "Fly again", trailing: "→", action: flyAgain)
                AirportButton(title: "Menu", kind: .secondary, action: toMenu)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
            .frame(width: stubWidth - 1)
        }
        .frame(width: width)
        .background(shape.fill(palette.paper.color))
        .overlay(shape.stroke(palette.paperEdge.color, lineWidth: 1))
        .printShadow(shape)
        .rotationEffect(Seeded.tilt("stub-\(result.score)", min: 0.4, max: 0.9))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
