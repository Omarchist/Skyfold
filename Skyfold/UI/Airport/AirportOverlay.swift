import SwiftUI

/// Where the airport flow is. After a gate is chosen the flow stays on `.gates` and the
/// reveal is derived from the session (`gateOffer.chosenIndex`), so it cannot drift from it.
nonisolated enum AirportStage: Equatable, Sendable {
    case arrival
    case gates
}

/// One airport visit. All the step state is keyed on this, so a new landing starts clean.
nonisolated struct AirportVisit: Hashable, Sendable {
    let session: ObjectIdentifier
    let legSerial: Int
    let route: Int
}

/// Plays the one-time arrival cue. Remembers which visits already played it, so rebuilding
/// the view (rotation, a parent re-evaluating) can never ring the bell twice.
///
/// The visit key holds an `ObjectIdentifier`, which can be reused once a session is freed
/// (a new run is often allocated at the old one's address), so each entry also keeps a weak
/// reference and only counts while that exact session is still alive.
enum AirportCue {
    private struct Entry {
        weak var session: RunSession?
        let visit: AirportVisit
    }

    private static var played: [Entry] = []

    private static var revealed: [Entry] = []

    static func unlock(for visit: AirportVisit, session: RunSession) {
        played.removeAll { $0.session == nil }
        guard !played.contains(where: { $0.session === session && $0.visit == visit }) else { return }
        played.append(Entry(session: session, visit: visit))
        Services.sound.play(.unlock)
        Services.haptics.play(.success)
    }

    /// The blessing or curse sound for the gate that was opened. Once per visit, same reasoning.
    /// Returns false when this visit already played it (the slip then just shows, silently).
    @discardableResult
    static func reveal(_ id: ModifierID, for visit: AirportVisit, session: RunSession) -> Bool {
        revealed.removeAll { $0.session == nil }
        guard !revealed.contains(where: { $0.session === session && $0.visit == visit }) else { return false }
        revealed.append(Entry(session: session, visit: visit))
        Services.sound.play(id.kind == .blessing ? .blessing : .curse)
        Services.haptics.play(id.kind == .blessing ? .success : .warning)
        return true
    }
}

/// The airport, drawn over the 3D gates (phase `.airport`):
/// arrival passport stamp (and a stub for anything unlocked), then the two gates,
/// then the printed slip with "Board to ..." and "End flight".
struct AirportOverlay: View {
    let session: RunSession
    private let startStage: AirportStage

    init(session: RunSession) {
        self.session = session
        self.startStage = .arrival
    }

    /// For previews and the test harness: begin at a later step.
    init(session: RunSession, startAt stage: AirportStage) {
        self.session = session
        self.startStage = stage
    }

    var body: some View {
        if session.phase == .airport, let arrival = session.arrival {
            let visit = AirportVisit(session: ObjectIdentifier(session), legSerial: session.legSerial,
                                     route: arrival.routeIndex)
            AirportFlow(session: session, arrival: arrival, visit: visit, startStage: startStage)
                .id(visit)
        }
    }
}

private struct AirportFlow: View {
    let session: RunSession
    let arrival: ArrivalReport
    let visit: AirportVisit

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var stage: AirportStage
    @State private var cardIn = false
    @State private var stampLanded = false
    @State private var stubShown = false
    @State private var slipShown = false
    @State private var printed: CGFloat = 0
    @State private var leaving = false
    @State private var stampDate = UIFormat.stampDate()

    init(session: RunSession, arrival: ArrivalReport, visit: AirportVisit, startStage: AirportStage) {
        self.session = session
        self.arrival = arrival
        self.visit = visit
        // Rebuilt after a gate was already opened (the parent re-created us): resume at the gates.
        let resumed = session.gateOffer?.chosenIndex != nil
        _stage = State(initialValue: resumed ? .gates : startStage)
    }

    private var chosenIndex: Int? { session.gateOffer?.chosenIndex }

    var body: some View {
        GeometryReader { geo in
            let metrics = AirportMetrics(size: geo.size, insets: geo.safeAreaInsets)
            ZStack(alignment: .topLeading) {
                switch stage {
                case .arrival:
                    AirportArrivalLayer(session: session, arrival: arrival, metrics: metrics,
                                        stampDate: stampDate, cardIn: cardIn, stampLanded: stampLanded,
                                        stubShown: stubShown, onContinue: goToGates)
                        .transition(.opacity)
                case .gates:
                    AirportGateLayer(session: session, arrival: arrival, metrics: metrics,
                                     slipShown: slipShown, printed: printed, leaving: leaving,
                                     onOpen: open, onBoard: board, onEnd: endFlight)
                        .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            // Only the scrim bleeds under the notch and home indicator; the paper stays inside
            // the safe area. It also swallows touches, so nothing reaches the flight view.
            .background {
                Rectangle()
                    .fill(palette.scrim)
                    .opacity(scrimOpacity)
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .animation(.easeOut(duration: 0.3), value: scrimOpacity)
            }
        }
        .task { await arrivalCue() }
        .task(id: chosenIndex) { await revealCue() }
        .task { await autoGates() }
    }

    private var scrimOpacity: Double {
        switch stage {
        case .arrival: 0.6
        case .gates: chosenIndex == nil ? 0 : 0.35
        }
    }

    // MARK: Steps

    private func goToGates() {
        guard stage == .arrival else { return }
        // Someone who skips straight on still gets the unlock cue, exactly once.
        if !arrival.unlocks.isEmpty { AirportCue.unlock(for: visit, session: session) }
        withAnimation(.easeOut(duration: 0.28)) { stage = .gates }
    }

    private func open(_ index: Int) {
        guard stage == .gates, !leaving, session.phase == .airport,
              session.gateOffer?.chosenIndex == nil,
              session.chooseGate(index) != nil else { return }
        Services.sound.play(.gateOpen)
        Services.haptics.play(.gate)
    }

    private func board() {
        guard !leaving, chosenIndex != nil, slipShown else { return }
        leaving = true
        session.depart()
    }

    private func endFlight() {
        guard !leaving else { return }
        leaving = true
        session.quit()
    }

    // MARK: Timelines

    /// Card, then stamp, then (if anything was unlocked) the stub with its sound.
    private func arrivalCue() async {
        guard stage == .arrival else { cardIn = true; stampLanded = true; return }
        if reduceMotion {
            cardIn = true
            stampLanded = true
        } else {
            withAnimation(.easeOut(duration: 0.3)) { cardIn = true }
            try? await Task.sleep(for: .seconds(0.38))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.13)) { stampLanded = true }
        }
        guard !arrival.unlocks.isEmpty else { return }
        try? await Task.sleep(for: .seconds(reduceMotion ? 0.15 : 0.5))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.28)) { stubShown = true }
        AirportCue.unlock(for: visit, session: session)
    }

    /// About 0.9 s after a gate opens the slip prints and the blessing or curse sound plays.
    private func revealCue() async {
        guard let id = session.gateOffer?.chosen else {
            slipShown = false
            printed = 0
            return
        }
        try? await Task.sleep(for: .seconds(0.9))
        guard !Task.isCancelled else { return }
        slipShown = true
        if reduceMotion {
            printed = 1
        } else {
            withAnimation(.easeOut(duration: 0.65)) { printed = 1 }
        }
        AirportCue.reveal(id, for: visit, session: session)
    }

    /// DebugFlags.autoGates: arrival, a gate, board, with pauses long enough to look at.
    private func autoGates() async {
        guard DebugFlags.autoGates else { return }
        if stage == .arrival {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            goToGates()
        }
        try? await Task.sleep(for: .seconds(2.2))
        guard !Task.isCancelled else { return }
        open(Int.random(in: 0...1))
        try? await Task.sleep(for: .seconds(4.2))
        guard !Task.isCancelled else { return }
        board()
    }
}
