import Foundation

/// Runs the wind gusts of one flight (experiment `windGusts`) for the engine: steps the pure
/// `WindGusts` clock, turns its outcomes into a lane push, sound and haptics, and writes the few
/// values the HUD needs into the session. Lives in the engine; the engine calls it from a few
/// marked hooks and the rest of the game never sees it.
final class GustDirector {
    private var gusts = WindGusts(seed: 1)
    private var lastDt: Float = 1.0 / 60

    /// A fresh leg.
    func reset(seed: UInt64, session: RunSession) {
        gusts.reset(seed: seed)
        publish(session)
    }

    /// The player revived: no wind for a while.
    func hold(session: RunSession) {
        gusts.hold()
        publish(session)
    }

    /// Steps the gusts for one flying frame. Call once per frame while the phase is `.flying`.
    func tick(dt: Float, sim: inout FlightSimulation, speed: Float, session: RunSession) {
        lastDt = dt
        let ctx = (gusts.needsContext || gusts.pushDue(within: dt)) ? sim.gustContext(speed: speed) : nil
        switch gusts.advance(dt: dt, context: ctx) {
        case .none:
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
