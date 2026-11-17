import SwiftUI

// Step two and three of the airport: two hanging gate signs over the left and right halves
// (the whole half is the tap target), then the printed slip and the boarding buttons.

nonisolated enum AirportSignState: Sendable {
    case idle, open, passed
}

/// Where the signs hang. Sign A hangs a little higher than sign B, like real ones do.
struct AirportGateGeometry {
    let metrics: AirportMetrics

    var signSize: CGSize {
        let half = metrics.size.width / 2
        if metrics.isLandscape { return CGSize(width: min(half - 40, 164), height: 96) }
        return CGSize(width: min(half - 30, 176), height: 114)
    }

    /// Distance from the top of the screen to the top of the sign board.
    func hang(_ index: Int) -> CGFloat {
        let base = metrics.insets.top + (metrics.isLandscape ? 8 : 14)
        return base + (index == 0 ? 0 : (metrics.isLandscape ? 8 : 18))
    }

    var signsBottom: CGFloat { max(hang(0), hang(1)) + signSize.height }
}

struct AirportGateLayer: View {
    let session: RunSession
    let arrival: ArrivalReport
    let metrics: AirportMetrics
    let slipShown: Bool
    let printed: CGFloat
    let leaving: Bool
    let onOpen: (Int) -> Void
    let onBoard: () -> Void
    let onEnd: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var swaying = false
    @State private var pressedGate: Int?

    private var chosen: Int? { session.gateOffer?.chosenIndex }
    private var geometry: AirportGateGeometry { AirportGateGeometry(metrics: metrics) }
    private var nextCity: City { Route.city(arrival.routeIndex + 1) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            halves
            if chosen == nil {
                instruction
                    .transition(.opacity)
            } else if slipShown {
                reveal
                    .transition(.opacity)
            }
        }
        .frame(width: metrics.size.width, height: metrics.size.height, alignment: .topLeading)
        .onAppear { if !reduceMotion { swaying = true } }
    }

    // MARK: Gate halves

    /// Two layers: the tap targets, which are the whole left and right halves of the screen
    /// edge to edge (the 3D gates sit in those halves), and the signs, which hang inside the
    /// safe area and let every touch through to the halves below.
    private var halves: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                ForEach(0..<2, id: \.self) { index in
                    Button {
                        onOpen(index)
                    } label: {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(AirportGateStyle { down in
                        if down { pressedGate = index } else if pressedGate == index { pressedGate = nil }
                    })
                    .disabled(chosen != nil || leaving)
                    .accessibilityLabel("Gate \(letter(index))")
                    .accessibilityHint("Opens the gate. One gate is a blessing and the other a curse.")
                }
            }
            .ignoresSafeArea()

            HStack(spacing: 0) {
                ForEach(0..<2, id: \.self) { index in
                    AirportHangingSign(letter: letter(index), size: geometry.signSize,
                                       hang: geometry.hang(index), state: signState(index),
                                       pressed: pressedGate == index && chosen == nil,
                                       swaying: swaying, restTilt: index == 0 ? -1.1 : 0.8,
                                       period: index == 0 ? 3.1 : 3.7)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .frame(width: metrics.size.width, height: metrics.size.height, alignment: .top)
            .allowsHitTesting(false)
        }
    }

    private func letter(_ index: Int) -> String { index == 0 ? "A" : "B" }

    private func signState(_ index: Int) -> AirportSignState {
        guard let chosen else { return .idle }
        return chosen == index ? .open : .passed
    }

    // MARK: Before a gate is open

    private var instruction: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Pick a gate.")
                .font(.display(metrics.isLandscape ? 22 : 25, weight: .bold))
                .foregroundStyle(palette.ink.color)
            Text("One is a blessing, one is a curse.")
                .font(.skyfold(metrics.isLandscape ? 14 : 15, weight: .medium))
                .foregroundStyle(palette.inkSoft.color)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(TicketShape(cornerRadius: 3, notch: .horizontal(fromTop: 22), notchRadius: 6)
            .fill(palette.paper.color))
        .overlay(TicketShape(cornerRadius: 3, notch: .horizontal(fromTop: 22), notchRadius: 6)
            .stroke(palette.paperEdge.color, lineWidth: 1))
        .printShadow(TicketShape(cornerRadius: 3, notch: .horizontal(fromTop: 22), notchRadius: 6))
        .rotationEffect(.degrees(metrics.isLandscape ? 0.8 : -0.9))
        .padding(.leading, metrics.isLandscape ? 0 : metrics.left)
        .padding(.bottom, metrics.bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: metrics.isLandscape ? .bottom : .bottomLeading)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }

    // MARK: After a gate is open

    @ViewBuilder private var reveal: some View {
        if metrics.isLandscape { revealLandscape } else { revealPortrait }
    }

    private var revealPortrait: some View {
        VStack(alignment: .leading, spacing: 0) {
            slip
                .frame(width: min(340, metrics.contentWidth - 12))
                .frame(maxWidth: .infinity, alignment: chosen == 0 ? .leading : .trailing)
                .padding(.top, geometry.signsBottom + 18)
            Spacer(minLength: 12)
            controls
        }
        .padding(.leading, metrics.left)
        .padding(.trailing, metrics.right)
        .padding(.bottom, metrics.bottom)
        .frame(width: metrics.size.width, height: metrics.size.height, alignment: .top)
    }

    private var revealLandscape: some View {
        VStack(alignment: .leading, spacing: 10) {
            slip
            controls
        }
        .frame(width: min(316, max(220, metrics.size.width / 2 - geometry.signSize.width - 18)))
        .padding(.top, metrics.top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private var slip: some View {
        if let id = session.gateOffer?.chosen, let index = chosen {
            VStack(spacing: 0) {
                AirportSlot()
                    .zIndex(1)
                // Padded so the clip leaves room for the tilt and the hard shadow.
                AirportSlip(info: id.info, gate: letter(index), nextLine: nextLine,
                            compact: metrics.isLandscape)
                    .padding(.horizontal, 9)
                    .padding(.bottom, 11)
                    .modifier(AirportPrintOut(progress: reduceMotion ? 1 : printed))
                    .padding(.horizontal, -9)
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            AirportButton(title: "Board to \(nextCity.name)", trailing: "→", action: onBoard)
            AirportButton(title: "End flight", kind: .secondary, action: onEnd)
                .fixedSize(horizontal: true, vertical: false)
        }
        .disabled(leaving)
        .opacity(printed > 0.55 || reduceMotion ? 1 : 0)
    }

    /// "NEXT  UKY → SYD  ·  1.2 km", planned exactly the way `depart()` will plan it.
    private var nextLine: String {
        let plan = LegPlan.plan(fromRoute: arrival.routeIndex, legsCompleted: session.legsCompleted + 1,
                                startRoute: session.startRoute, difficulty: session.difficulty,
                                tuning: session.tuning)
        return "NEXT  \(arrival.city.code) → \(nextCity.code)  ·  \(UIFormat.distance(plan.length))"
    }
}

// MARK: - Hanging sign

/// A dark airport board hung from a hook by two wires, with the gate letter in sign type.
struct AirportHangingSign: View {
    let letter: String
    let size: CGSize
    let hang: CGFloat
    let state: AirportSignState
    var pressed = false
    let swaying: Bool
    let restTilt: Double
    let period: Double

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let board = RoundedRectangle(cornerRadius: 3, style: .continuous)
        let swing = reduceMotion ? 0 : (swaying ? 0.9 : -0.9)
        ZStack(alignment: .top) {
            wires
            sign(board)
                .padding(.top, hang)
                .offset(y: pressed ? 3 : 0)
        }
        .frame(width: size.width, height: hang + size.height, alignment: .top)
        .rotationEffect(.degrees(restTilt + swing), anchor: .top)
        .animation(reduceMotion ? nil : .easeInOut(duration: period).repeatForever(autoreverses: true),
                   value: swaying)
        .animation(.easeOut(duration: 0.15), value: pressed)
        .opacity(state == .passed ? 0.5 : 1)
        .animation(.easeOut(duration: 0.3), value: state)
        .accessibilityElement(children: .ignore)
    }

    private var wires: some View {
        let line = palette.ink.withAlpha(0.7).color
        let width = size.width
        let top = hang
        return Canvas { ctx, size in
            var p = Path()
            let hook = CGPoint(x: size.width / 2, y: 0)
            for x in [CGFloat(22), width - 22] {
                p.move(to: hook)
                p.addLine(to: CGPoint(x: x, y: top))
            }
            ctx.stroke(p, with: .color(line), lineWidth: 1.4)
        }
        .frame(width: size.width, height: hang)
        .frame(maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    private func sign(_ board: RoundedRectangle) -> some View {
        let text = palette.boardText.color
        let hot = palette.boardAccent.color
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Gate")
                    .signage(12, weight: .bold)
                    .foregroundStyle(text.opacity(0.85))
                Spacer(minLength: 4)
                if state == .open {
                    Text("Open")
                        .signage(11, weight: .bold)
                        .foregroundStyle(hot)
                } else {
                    Glyph("arrow.down", size: 15)
                        .foregroundStyle(text.opacity(0.85))
                }
            }
            Spacer(minLength: 0)
            Text(letter)
                .font(.ticket(size.height * 0.58, weight: .heavy))
                .foregroundStyle(state == .open ? text : hot)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(board.fill(palette.boardBackground.color))
        .overlay(board.inset(by: 4).strokeBorder(text.opacity(0.28), lineWidth: 1))
        .overlay(alignment: .top) {
            HStack {
                Circle().fill(text.opacity(0.7)).frame(width: 4, height: 4)
                Spacer()
                Circle().fill(text.opacity(0.7)).frame(width: 4, height: 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, -1)
        }
        .printShadow(board)
    }
}

// MARK: - Slot and slip

/// The thin dark slot the slip is printed out of.
struct AirportSlot: View {
    @Environment(\.palette) private var palette

    var body: some View {
        Rectangle()
            .fill(palette.boardBackground.color)
            .frame(height: 7)
            .overlay(alignment: .bottom) {
                Rectangle().fill(palette.boardText.withAlpha(0.25).color).frame(height: 1)
            }
            .padding(.horizontal, -5)
            .accessibilityHidden(true)
    }
}

/// What the gate handed over: printed in the blessing or curse ink, with the modifier name,
/// its effect and a logbook note. Blessings have a clean cut edge, curses a ragged one.
struct AirportSlip: View {
    let info: ModifierInfo
    let gate: String
    let nextLine: String
    var compact = false

    @Environment(\.palette) private var palette

    var body: some View {
        let ink = palette.kindInk(info.kind)
        let shape = AirportSlipShape(seed: info.id.rawValue, ragged: info.kind == .curse)
        VStack(alignment: .leading, spacing: compact ? 6 : 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(info.kind == .blessing ? "Blessing" : "Curse")
                    .signage(11, weight: .bold)
                    .foregroundStyle(ink)
                Spacer(minLength: 8)
                Text("GATE \(gate)")
                    .font(.ticket(11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(palette.inkSoft.color)
            }
            RuleLine(color: ink.opacity(0.6), weight: 1.5)
            HStack(alignment: .center, spacing: 12) {
                Glyph(info.symbol, size: compact ? 17 : 21)
                    .foregroundStyle(ink)
                    .frame(width: compact ? 34 : 42, height: compact ? 34 : 42)
                    .overlay(Rectangle().strokeBorder(ink, lineWidth: 1.5))
                Text(info.name)
                    .font(.display(compact ? 24 : 30, weight: .bold))
                    .foregroundStyle(ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            Text(info.effect)
                .font(.skyfold(compact ? 14 : 16, weight: .medium))
                .foregroundStyle(palette.ink.color)
                .fixedSize(horizontal: false, vertical: true)
            Perforation(color: ink.opacity(0.55))
            Text(info.lore)
                .font(.display(compact ? 14 : 16, weight: .regular).italic())
                .foregroundStyle(palette.inkSoft.color)
                .fixedSize(horizontal: false, vertical: true)
            if !compact {
                Text(nextLine)
                    .font(.ticket(11, weight: .medium))
                    .tracking(1)
                    .foregroundStyle(palette.inkSoft.color)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, compact ? 11 : 14)
        .padding(.bottom, compact ? 17 : 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(palette.paper.color))
        .overlay(shape.stroke(ink.opacity(0.75), lineWidth: 1.2))
        .printShadow(shape)
        .rotationEffect(Seeded.tilt("slip-" + info.id.rawValue, min: 0.6, max: 1.6))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(info.kind == .blessing ? "Blessing" : "Curse"): \(info.name). \(info.effect)")
    }
}
