import Foundation

/// Where to draw the ghost this frame, relative to the player's plane at x = 0.
struct GhostFrame {
    /// Meters ahead of the plane (negative: behind).
    var x: Float
    var y: Float
    var pitch: Float
}

/// The ghost flight experiment for one run: records the player's track, replays the saved ghost for
/// the same departure airport and difficulty, and saves the track when the run sets a new best.
///
/// Created by the engine only when the switch is on (and the run is not a daily route). It reads the
/// numbers it is handed and writes only `ghostNote` and `ghostSaved` on the session.
final class GhostFlightRun {
    private let session: RunSession
    private var recorder = GhostRecorder()
    private let saved: GhostRun?
    private var leg = 0
    private var note: String?
    private var noteMeters: Int?

    init?(session: RunSession) {
        guard ExperimentStore.shared.isOn(.ghostFlight), session.daily == nil else { return nil }
        self.session = session
        #if DEBUG
        GhostStore.plantDebugGhost(startRoute: session.startRoute, difficulty: session.difficulty)
        #endif
        saved = GhostStore.load(route: session.startRoute, difficulty: session.difficulty.id.rawValue)
    }

    /// A takeoff: start recording the leg the session now holds.
    func beginLeg() {
        leg = session.legsCompleted
        recorder.beginLeg(length: session.leg.length)
        setNote(nil)
    }

    /// Every flying frame: moves the leg clock and samples the plane.
    func advance(dt: Float, distance: Double, altitude: Float) {
        recorder.advance(dt: dt, distance: distance, altitude: altitude)
    }

    /// The ghost for this frame, or nil when there is none to draw. Also keeps the off-screen note.
    func frame(distance: Double, landscape: Bool, aspect: Float) -> GhostFrame? {
        guard let saved, leg < saved.legs.count, recorder.legTime > 0 else { setNote(nil); return nil }
        switch session.phase {
        case .flying, .paused, .crashed, .countdown: break
        default: setNote(nil); return nil
        }
        let track = saved.legs[leg]
        let time = recorder.legTime
        let p = GhostReplay.place(track, time: time, playerLegLength: session.leg.length, playerDistance: distance)
        // After its last sample the ghost has landed: it settles onto the ground and waits.
        var y = p.altitude
        var pitch = p.pitch
        if p.landed {
            let u = min((time - track.duration) / 1.2, 1)
            let s = u * u * (3 - 2 * u)
            y += (World.groundY + 0.2 - y) * s
            pitch = 0
        }
        let reachAhead: Double
        let reachBehind: Double
        if landscape {
            let w = Double(RigMath.sideWidth(aspect: aspect))
            reachAhead = 0.77 * w - 2
            reachBehind = 0.23 * w - 1.5
        } else {
            reachAhead = 55
            reachBehind = 5
        }
        setNoteMeters(GhostReplay.offscreenMeters(ahead: p.ahead, visibleAhead: reachAhead, visibleBehind: reachBehind))
        return GhostFrame(x: Float(p.ahead), y: y, pitch: pitch)
    }

    /// The run ended: keep its tracks if the score is the best for this airport and difficulty.
    func finish() {
        let score = session.result?.score ?? session.score
        let run = recorder.finish(score: score, startRoute: session.startRoute,
                                  difficulty: session.difficulty.id.rawValue)
        if GhostStore.saveIfBest(run) { session.ghostSaved = true }
        setNote(nil)
    }

    private func setNote(_ text: String?) {
        guard text != note else { return }
        note = text
        noteMeters = nil
        session.ghostNote = text
    }

    /// Builds the note text only when the number of meters changes (not every frame).
    private func setNoteMeters(_ meters: Int?) {
        guard meters != noteMeters || (meters == nil) != (note == nil) else { return }
        noteMeters = meters
        let text = meters.map { $0 > 0 ? "GHOST +\($0) m" : "GHOST \u{2212}\(-$0) m" }
        guard text != note else { return }
        note = text
        session.ghostNote = text
    }
}
