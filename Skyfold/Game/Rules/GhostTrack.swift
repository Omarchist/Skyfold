import Foundation

// The ghost flight experiment (`ghostFlight`): the plane's track is recorded leg by leg, the best
// run per departure airport and difficulty is kept, and a later run replays it beside the player.
//
// Everything here is pure: no clocks, no files. Time moves only through `advance(dt:...)`, so a
// paused game never ages a recording.

/// One leg of a recorded flight. Samples are stored as whole numbers so the saved file stays small:
/// time in hundredths of a second since the leg's takeoff, distance flown in centimeters, altitude
/// in centimeters.
nonisolated struct GhostLeg: Codable, Equatable, Sendable {
    /// The leg's planned length (m) when it was recorded, for mapping onto a leg of another length.
    var length: Double
    var t: [Int] = []
    var d: [Int] = []
    var a: [Int] = []

    var count: Int { t.count }
    /// Seconds from takeoff to the last sample.
    var duration: Float { Float(t.last ?? 0) / 100 }

    /// Distance (m) and altitude (m) at `time` seconds after takeoff, interpolated and clamped to the
    /// ends of the recording.
    func sample(at time: Float) -> (distance: Double, altitude: Float) {
        guard let first = t.first, let last = t.last else { return (0, 0) }
        let c = Int((max(time, 0) * 100).rounded())
        if c <= first { return (Double(d[0]) / 100, Float(a[0]) / 100) }
        if c >= last { return (Double(d[count - 1]) / 100, Float(a[count - 1]) / 100) }
        // Last index whose time is <= c.
        var lo = 0, hi = count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if t[mid] <= c { lo = mid } else { hi = mid }
        }
        let span = Double(t[hi] - t[lo])
        let u = span > 0 ? min(max((Double(max(time, 0)) * 100 - Double(t[lo])) / span, 0), 1) : 0
        let dist = Double(d[lo]) + (Double(d[hi]) - Double(d[lo])) * u
        let alt = Double(a[lo]) + (Double(a[hi]) - Double(a[lo])) * u
        return (dist / 100, Float(alt / 100))
    }

    /// Drops samples that a straight line between their kept neighbours reproduces within
    /// `distanceTolerance` (m) and `altitudeTolerance` (m). The first and last always stay.
    func compacted(distanceTolerance: Double = 0.3, altitudeTolerance: Double = 0.04) -> GhostLeg {
        guard count > 2 else { return self }
        var keep = [0]
        var anchor = 0
        var i = 2
        while i < count {
            // Can the line anchor -> i still stand in for every sample between them?
            var ok = true
            let span = Double(t[i] - t[anchor])
            for j in (anchor + 1)..<i {
                let u = span > 0 ? Double(t[j] - t[anchor]) / span : 0
                let dd = Double(d[anchor]) + Double(d[i] - d[anchor]) * u
                let aa = Double(a[anchor]) + Double(a[i] - a[anchor]) * u
                if abs(dd - Double(d[j])) / 100 > distanceTolerance || abs(aa - Double(a[j])) / 100 > altitudeTolerance {
                    ok = false
                    break
                }
            }
            if !ok {
                keep.append(i - 1)
                anchor = i - 1
            }
            i += 1
        }
        keep.append(count - 1)
        var out = GhostLeg(length: length)
        for k in keep {
            out.t.append(t[k]); out.d.append(d[k]); out.a.append(a[k])
        }
        return out
    }
}

/// A whole saved run: one `GhostLeg` per leg flown, the last possibly cut short by the crash.
nonisolated struct GhostRun: Codable, Equatable, Sendable {
    var score: Int
    var startRoute: Int
    var difficulty: String
    var legs: [GhostLeg]

    var sampleCount: Int { legs.reduce(0) { $0 + $1.count } }

    /// The save rule: a run becomes the ghost when it beats the saved best for its airport and
    /// difficulty. A score of zero never does.
    static func shouldSave(score: Int, previousBest: Int?) -> Bool {
        score > 0 && score > (previousBest ?? 0)
    }
}

/// Records the plane while it flies. Call `beginLeg` at each takeoff, `advance` every flying frame
/// and `finish` when the run ends.
nonisolated struct GhostRecorder: Equatable, Sendable {
    /// Seconds between samples.
    static let interval: Float = 0.1
    /// A cap on a saved run, so the file stays well under a megabyte.
    static let maxSamples = 12_000

    private(set) var legs: [GhostLeg] = []
    private var open: GhostLeg?
    private var clock: Float = 0
    private var nextSample: Float = 0
    private var lastDistance: Double = 0
    private var lastAltitude: Float = 0
    private var lastClock: Float = -1

    var isRecording: Bool { open != nil }
    /// Seconds since the current leg's takeoff.
    var legTime: Float { clock }

    /// Starts a leg (closing any leg still open).
    mutating func beginLeg(length: Double) {
        closeLeg()
        open = GhostLeg(length: length)
        clock = 0
        nextSample = 0
        lastClock = -1
    }

    /// Moves the leg clock by `dt` and samples the plane's `distance` (m flown on this leg) and
    /// `altitude` (m) about ten times a second.
    mutating func advance(dt: Float, distance: Double, altitude: Float) {
        guard open != nil, dt > 0 else { return }
        clock += dt
        lastDistance = distance
        lastAltitude = altitude
        if lastClock < 0 || clock >= nextSample {
            append(at: clock)
            nextSample = clock + Self.interval
        }
    }

    /// Ends the current leg with one last sample at the exact moment it stopped.
    mutating func closeLeg() {
        guard var leg = open else { return }
        if lastClock >= 0, Int((clock * 100).rounded()) > (leg.t.last ?? -1) {
            leg.t.append(Int((clock * 100).rounded()))
            leg.d.append(Int((lastDistance * 100).rounded()))
            leg.a.append(Int((lastAltitude * 100).rounded()))
        }
        open = nil
        if leg.count > 0 { legs.append(leg.compacted()) } else { legs.append(leg) }
    }

    /// Ends the run and returns it as a saveable ghost. Compacts harder if it is still too big.
    mutating func finish(score: Int, startRoute: Int, difficulty: String) -> GhostRun {
        closeLeg()
        var run = GhostRun(score: score, startRoute: startRoute, difficulty: difficulty,
                           legs: legs.filter { $0.count > 1 })
        var tol = 1.0
        while run.sampleCount > Self.maxSamples, tol < 64 {
            tol *= 2
            run.legs = run.legs.map { $0.compacted(distanceTolerance: 0.3 * tol, altitudeTolerance: 0.04 * tol) }
        }
        return run
    }

    private mutating func append(at time: Float) {
        guard open != nil else { return }
        open!.t.append(Int((time * 100).rounded()))
        open!.d.append(Int((lastDistance * 100).rounded()))
        open!.a.append(Int((lastAltitude * 100).rounded()))
        lastClock = time
    }
}

/// Where a ghost is relative to the player, for one frame.
nonisolated struct GhostPlacement: Equatable, Sendable {
    /// Meters ahead of the player's plane (negative: behind).
    var ahead: Double
    /// Altitude (m).
    var altitude: Float
    /// Pitch the recorded climb or dive implies (radians, nose up positive).
    var pitch: Float
    /// The ghost has flown its whole recording and is waiting at the airport.
    var landed: Bool
}

nonisolated enum GhostReplay {
    /// Places the ghost for `leg` at `time` seconds after takeoff. The ghost's distance is mapped by
    /// progress through its leg onto the player's leg, so a longer or shorter leg (a blessing or a
    /// curse) still lines up at both airports.
    static func place(_ leg: GhostLeg, time: Float, playerLegLength: Double, playerDistance: Double) -> GhostPlacement {
        let s = leg.sample(at: time)
        let progress = min(max(s.distance / max(leg.length, 1), 0), 1)
        let before = leg.sample(at: max(time - 0.15, 0)).altitude
        let after = leg.sample(at: time + 0.15).altitude
        let climb = (after - before) / 0.3
        return GhostPlacement(ahead: progress * playerLegLength - playerDistance,
                              altitude: s.altitude,
                              pitch: min(max(climb * 0.1, -0.34), 0.34),
                              landed: time >= leg.duration)
    }

    /// Text for the printed note when the ghost is off screen, such as "GHOST +40 m". Nil when it
    /// is near enough to see. `visibleAhead` and `visibleBehind` are how far (m) the screen reaches.
    static func note(ahead: Double, visibleAhead: Double, visibleBehind: Double) -> String? {
        if ahead > visibleAhead { return "GHOST +\(Int(ahead.rounded())) m" }
        if ahead < -visibleBehind { return "GHOST \u{2212}\(Int((-ahead).rounded())) m" }
        return nil
    }
}
