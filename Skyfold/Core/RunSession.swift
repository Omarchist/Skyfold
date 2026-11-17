import Foundation
import Observation

/// The run's state machine.
///
///   countdown ──▶ flying ──▶ landing ──▶ airport ──(depart)──▶ countdown …
///       ▲            │  ▲
///       │            │  └── paused ◀─┐
///       │            ├────────────────┘ (pause/resume → countdown)
///       │            └──▶ crashed ──(revive)──▶ countdown
///       │                    └──(decline)──▶ gameOver
///       └── (quit from anywhere) ──▶ gameOver
nonisolated enum RunPhase: String, Equatable, Sendable {
    /// 3-2-1 before flying (start of a leg, after resume, after revive).
    case countdown
    case flying
    case paused
    /// Hit with no shield but a revive available; waiting for the player to choose.
    case crashed
    /// Leg distance reached: obstacles stop and the plane glides into the city.
    case landing
    /// On the ground: arrival card, then the two gates.
    case airport
    case gameOver
}

nonisolated struct ArrivalReport: Equatable, Sendable {
    let routeIndex: Int
    let unlocks: [Unlock]
    let firstVisit: Bool
    var city: City { Route.city(routeIndex) }
}

/// One run from takeoff to game over. The single source of truth shared by:
///  - the 2D rules engine (Game/): steps the simulation, writes the live values below,
///    and calls the "engine → session" transitions;
///  - the RealityKit renderer (Game/): reads state to draw the world;
///  - the SwiftUI HUD and overlays (UI/): read state and call the "UI → session" intents.
///
/// Transitions guard on the current phase, so calling one at the wrong moment is a no-op.
@Observable
final class RunSession {
    // MARK: Fixed for the run
    let difficulty: Difficulty
    let skin: PlaneSkin
    /// Route index of the departure airport.
    let startRoute: Int
    let timeOfDayMode: TimeOfDayMode
    @ObservationIgnored private let progress: ProgressStore

    // MARK: State machine
    private(set) var phase: RunPhase = .countdown
    private(set) var leg: LegPlan
    /// Legs finished (landed and departed again) this run.
    private(set) var legsCompleted = 0
    /// Cities landed in this run.
    private(set) var citiesReached = 0
    private(set) var modifiers: [ModifierID] = []
    private(set) var tuning = RunTuning()
    private(set) var arrival: ArrivalReport?
    private(set) var gateOffer: GateOffer?
    private(set) var result: RunResult?

    /// Charges granted by blessings.
    var shields = 0
    var revives = 0

    /// Bumped whenever the engine must rebuild the world: a new leg started (depart) or the
    /// player revived (clear nearby obstacles). The engine compares against the last value it saw.
    private(set) var legSerial = 0
    private(set) var reviveSerial = 0

    // MARK: Live values (written by the engine)
    /// Meters flown in the current leg.
    var legDistance: Double = 0
    /// Meters flown this run.
    var totalDistance: Double = 0
    var score: Int = 0
    var stars: Int = 0
    /// Current forward speed, m/s.
    var speed: Float = 0
    /// 0 = day, 1 = night (the engine eases this toward `targetNightness`).
    var nightness: Double = 0
    /// 3, 2, 1 while in `.countdown` (the engine drives the timer).
    var countdown: Int = 3
    /// Bumped each time a shield absorbs a hit (the UI flashes).
    var shieldHits = 0
    /// Lane the plane is in or moving to (0 = lowest).
    var lane: Int = World.middleLane
    /// Frames per second, written when Settings › Show FPS is on.
    var fps: Int = 0

    // Near-miss bonus experiment (written by the engine; stays 0 with the switch off).
    /// Running close-call streak, 0 when none.
    var streakLevel = 0
    /// Points the latest close call paid.
    var streakAward = 0
    /// Bumped by each close call (the HUD tag stamps again).
    var streakSerial = 0
    /// Highest streak this run.
    var bestStreak = 0

    init(difficulty: Difficulty, skin: PlaneSkin, startRoute: Int,
         timeOfDayMode: TimeOfDayMode, progress: ProgressStore) {
        self.difficulty = difficulty
        self.skin = skin
        self.startRoute = startRoute
        self.timeOfDayMode = timeOfDayMode
        self.progress = progress
        self.leg = LegPlan.plan(fromRoute: startRoute, legsCompleted: 0, startRoute: startRoute,
                                difficulty: difficulty, tuning: RunTuning())
        self.nightness = targetNightness()
    }

    // MARK: Derived

    var origin: City { leg.from }
    var destination: City { leg.to }
    var legProgress: Double { min(1, legDistance / max(leg.length, 1)) }
    var metersToGo: Double { max(0, leg.length - legDistance) }
    var blessings: [ModifierID] { modifiers.filter { $0.kind == .blessing } }
    var curses: [ModifierID] { modifiers.filter { $0.kind == .curse } }
    var isFlightActive: Bool { phase == .flying }

    /// Where nightness should be right now; the engine eases `nightness` toward this.
    func targetNightness(date: Date = .now) -> Double {
        TimeOfDay.flightNightness(mode: timeOfDayMode,
                                  cycleT: Double(legsCompleted) + legProgress,
                                  forceNight: tuning.forceNight, date: date)
    }

    /// Score multiplier the engine applies to distance and stars.
    var scoreMultiplier: Double { difficulty.scoreMultiplier * tuning.score }
    /// Points for one star.
    var starPoints: Int { max(1, Int((25 * tuning.starValue * scoreMultiplier).rounded())) }

    // MARK: Engine → session

    /// The countdown finished.
    func beginFlying() {
        guard phase == .countdown else { return }
        phase = .flying
    }

    /// The plane hit an obstacle. Returns true if a shield absorbed it (keep flying).
    /// Otherwise the phase becomes `.crashed` (a revive is available) or `.gameOver`.
    @discardableResult
    func registerHit() -> Bool {
        guard phase == .flying else { return true }
        if shields > 0 {
            shields -= 1
            shieldHits += 1
            return true
        }
        if revives > 0 {
            phase = .crashed
        } else {
            finish()
        }
        return false
    }

    /// Leg distance reached: stop spawning and glide in.
    func beginLanding() {
        guard phase == .flying else { return }
        phase = .landing
    }

    /// The landing animation finished. Records the arrival and opens the airport.
    func completeLanding() {
        guard phase == .landing else { return }
        let routeIndex = leg.toRoute
        let city = Route.city(routeIndex)
        let firstVisit = !progress.hasVisited(city.index)
        let unlocks = progress.recordArrival(routeIndex: routeIndex)
        citiesReached += 1
        arrival = ArrivalReport(routeIndex: routeIndex, unlocks: unlocks, firstVisit: firstVisit)
        gateOffer = GateOffer.make(allowSecondChances: difficulty.allowsSecondChances)
        phase = .airport
    }

    // MARK: UI → session

    func pause() {
        guard phase == .flying || phase == .countdown else { return }
        phase = .paused
    }

    /// Resumes through a fresh countdown so the player can get ready.
    func resume() {
        guard phase == .paused else { return }
        countdown = 3
        phase = .countdown
    }

    func revive() {
        guard phase == .crashed, revives > 0 else { return }
        revives -= 1
        reviveSerial += 1
        countdown = 3
        phase = .countdown
    }

    func declineRevive() {
        guard phase == .crashed else { return }
        finish()
    }

    /// Opens gate `index` (0 = left/A, 1 = right/B), applying its curse or blessing.
    @discardableResult
    func chooseGate(_ index: Int) -> ModifierID? {
        guard phase == .airport, var offer = gateOffer, offer.chosenIndex == nil,
              offer.options.indices.contains(index) else { return nil }
        offer.chosenIndex = index
        gateOffer = offer
        let id = offer.options[index]
        modifiers.append(id)
        tuning = RunTuning.combine(modifiers)
        switch id {
        case .paperShield: shields += 1
        case .secondWind: revives += 1
        default: break
        }
        progress.recordModifier(id)
        return id
    }

    /// Leaves the airport on the next leg (only after a gate has been chosen).
    func depart() {
        guard phase == .airport, gateOffer?.chosenIndex != nil, let arrival else { return }
        legsCompleted += 1
        leg = LegPlan.plan(fromRoute: arrival.routeIndex, legsCompleted: legsCompleted,
                           startRoute: startRoute, difficulty: difficulty, tuning: tuning)
        legDistance = 0
        self.arrival = nil
        gateOffer = nil
        legSerial += 1
        countdown = 3
        phase = .countdown
    }

    /// Ends the run now (from the pause menu, or the airport).
    func quit() {
        guard phase != .gameOver else { return }
        finish()
    }

    private func finish() {
        let best = progress.recordRunEnd(score: score, distance: totalDistance,
                                         stars: stars, citiesReached: citiesReached)
        result = RunResult(score: score, distance: totalDistance, stars: stars,
                           citiesReached: citiesReached, modifiers: modifiers,
                           isNewBest: best, difficulty: difficulty.id)
        phase = .gameOver
    }
}
