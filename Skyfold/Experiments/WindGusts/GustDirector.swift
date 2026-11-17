import Foundation

/// Runs the wind gusts of one flight (experiment `windGusts`) for the engine: steps the pure
/// `WindGusts` clock, turns its outcomes into a lane push, sound and haptics, and writes the few
/// values the HUD needs into the session. Lives in the engine; the engine calls it from a few
/// marked hooks and the rest of the game never sees it.
final class GustDirector {
    private var gusts = WindGusts(seed: 1)
    /// While no safe push exists the check is repeated a few times a second, not every frame.
    private var lookTimer: Float = 0
    private static let lookInterval: Float = 0.25

    /// A fresh leg.
    func reset(seed: UInt64, session: RunSession) {
        gusts.reset(seed: seed)
        publish(session)
    }

    /// Drops a running warning and keeps the wind quiet for `seconds` of flying (a revive, a pause,
    /// a crash or a landing).
    func hold(session: RunSession, for seconds: Float = WindGusts.holdAfterRevive) {
        gusts.hold(for: seconds)
        lookTimer = 0
        publish(session)
    }

    /// Steps the gusts for one flying frame. Call once per frame while the phase is `.flying`.
    func tick(dt: Float, sim: inout FlightSimulation, speed: Float, session: RunSession) {
        var ctx: GustContext?
        if gusts.pushDue(within: dt) {
            ctx = sim.gustContext(speed: speed)
        } else if gusts.needsContext {
            lookTimer -= dt
            if lookTimer <= 0 { ctx = sim.gustContext(speed: speed) }
        }
        switch gusts.advance(dt: dt, context: ctx) {
        case .none:
            if ctx != nil { lookTimer = Self.lookInterval }
            return
        case .announced:
            session.gustSerial += 1
            Services.sound.play(.uiTap)
            Services.haptics.play(.warning)
        case .pushed(_, let lane):
            // The lane-change event plays the usual sound and haptic on the next step.
            sim.setTargetLane(lane)
            session.gustPushes += 1
        case .passed:
            break
        }
        publish(session)
    }

    /// Extra plane roll (radians) while a warning runs: the plane rocks, more as the gust nears.
    func roll(time: Float) -> Float {
        let k = gusts.warningProgress
        guard k > 0 else { return 0 }
        return sinf(time * 15) * 0.075 * (0.35 + 0.65 * k)
    }

    private func publish(_ session: RunSession) {
        if session.gustWarning != gusts.direction { session.gustWarning = gusts.direction }
    }
}
