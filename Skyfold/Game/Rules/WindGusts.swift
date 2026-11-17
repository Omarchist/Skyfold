import Foundation

/// One obstacle row as the gust check needs it.
nonisolated struct GustRow: Equatable, Sendable {
    /// Meters ahead of the plane (row center).
    var x: Float
    /// Half extent in X that the plane must clear.
    var reach: Float
    /// Lanes the row blocks, a wandering bird's destination included (the worst case).
    var blocked: LaneMask
}

/// What the gust check may look at: a copy of the few values it needs, taken from the simulation
/// by `FlightSimulation.gustContext(speed:)`. Keeps the logic pure.
nonisolated struct GustContext: Equatable, Sendable {
    var lane: Int
    var distance: Double
    var legLength: Double
    var clearApproach: Double
    var speed: Float
    var laneSwitchTime: Float
    var designReaction: Float
    var isProtected: Bool
    var rows: [GustRow]
}

extension FlightSimulation {
    /// Snapshot for `WindGusts` (the plane's target lane, the rows still ahead, the timings).
    func gustContext(speed: Float) -> GustContext {
        var rows: [GustRow] = []
        rows.reserveCapacity(rowCount)
        for i in 0..<rowCount {
            let r = row(i)
            rows.append(GustRow(x: r.x, reach: r.reach, blocked: r.blocked))
        }
        return GustContext(lane: plane.lane, distance: distance, legLength: config.leg.length,
                           clearApproach: config.clearApproach, speed: speed,
                           laneSwitchTime: config.leg.laneSwitchTime, designReaction: config.designReaction,
                           isProtected: isProtected, rows: rows)
    }
}

/// Wind gusts (experiment `windGusts`): now and then a gust is announced, and a moment later it
/// pushes the plane one lane up or down with the normal lane change. The player can steer back.
///
/// Fairness comes first. A gust only pushes the plane into a lane where no row blocks it before a
/// normal player could notice, react (the rules' reaction time plus grace) and fly back out, never
/// during the clear approach before an airport, never while the plane is protected after a hit or
/// a revive, and never off the top or bottom lane (from an edge lane it pushes inward). The check
/// is made when the gust is announced and again when it is due. When no safe push exists the gust
/// waits (before the warning) or passes without a push (after it). Row spawning is untouched.
///
/// Pure and deterministic: a seed replays the same gust timings and sides, and time moves only
/// through `advance`, so a paused game never ages it.
nonisolated struct WindGusts: Sendable {
    /// Seconds between the warning and the push.
    static let warning: Float = 1.2
    /// Flying seconds between one gust and the next warning.
    static let minGap: Float = 12
    static let maxGap: Float = 25
    /// Flying seconds before the next warning after a gust that blew past without a push.
    static let passedGapMin: Float = 5
    static let passedGapMax: Float = 9
    /// Flying seconds without a gust after a revive.
    static let holdAfterRevive: Float = 8
    /// Spare time on top of the player's switch and reaction times.
    static let safetyMargin: Float = 0.1

    enum Outcome: Equatable, Sendable {
        case none
        /// A gust was announced; `direction` is +1 up, -1 down.
        case announced(direction: Int)
        /// The gust is here: fly the plane to `lane`.
        case pushed(direction: Int, lane: Int)
        /// The warning ran out but the push was no longer safe, so the gust blew past.
        case passed
    }

    private var rng: SplitMix64
    /// Flying seconds until the next warning (stays at 0 while no safe push exists).
    private(set) var untilNext: Float
    /// Seconds left of the warning, 0 when none is running.
    private(set) var warningLeft: Float = 0
    /// +1 up, -1 down while a warning runs, else 0.
    private(set) var direction = 0
    private(set) var announced = 0
    private(set) var pushes = 0
    private(set) var passes = 0

    init(seed: UInt64) {
        rng = SplitMix64(seed: seed ^ 0x57_494E_44)
        untilNext = 0
        untilNext = Self.nextGap(&rng)
    }

    private static func nextGap(_ rng: inout SplitMix64) -> Float { rng.range(minGap, maxGap) }

    var isWarning: Bool { direction != 0 }
    /// 0...1 over the warning, 0 when none runs.
    var warningProgress: Float { isWarning ? min(max(1 - warningLeft / Self.warning, 0), 1) : 0 }
    /// True when `advance` needs a context this frame (a warning to start or a push to make).
    var needsContext: Bool { isWarning ? false : untilNext <= 0 }
    /// True when the push is due within `dt`.
    func pushDue(within dt: Float) -> Bool { isWarning && warningLeft <= dt }

    /// A fresh leg: new seed, nothing pending.
    mutating func reset(seed: UInt64) { self = WindGusts(seed: seed) }

    /// After a revive (or anything that should quiet the wind): drops a running warning and waits.
    mutating func hold(for seconds: Float = holdAfterRevive) {
        direction = 0
        warningLeft = 0
        untilNext = max(untilNext, seconds)
    }

    /// Meters of window after a push in which the plane must not meet a row in the pushed lane.
    static func reactionWindow(_ c: GustContext) -> Float {
        // Push (one lane), notice and react, fly back (up to two lanes), and a little spare.
        3 * c.laneSwitchTime + c.designReaction + safetyMargin
    }

    /// True when pushing the plane from its lane to `target` is fair `ahead` meters from now.
    static func isSafePush(to target: Int, in c: GustContext, ahead: Float = 0) -> Bool {
        guard target >= 0, target <= 2, abs(target - c.lane) == 1 else { return false }
        guard !c.isProtected, c.speed > 0.5 else { return false }
        let at = c.distance + Double(ahead)
        guard at >= 0, at < c.legLength - c.clearApproach else { return false }
        let window = reactionWindow(c)
        for r in c.rows {
            let x = r.x - ahead
            if x + r.reach < 0 { continue }                      // already behind
            guard Lanes.contains(r.blocked, target) else { continue }
            if (x - r.reach) / c.speed < window { return false }  // met too soon (or overlapping now)
        }
        return true
    }

    /// Directions (+1 up, -1 down) that are fair `ahead` meters from now.
    static func safeDirections(in c: GustContext, ahead: Float) -> [Int] {
        [1, -1].filter { isSafePush(to: c.lane + $0, in: c, ahead: ahead) }
    }

    /// Steps the gust clock by `dt` flying seconds. `context` is needed only when
    /// `needsContext` or `pushDue(within:)` says so; pass nil otherwise.
    mutating func advance(dt: Float, context: GustContext?) -> Outcome {
        guard dt > 0 else { return .none }
        if isWarning {
            warningLeft -= dt
            guard warningLeft <= 0 else { return .none }
            let dir = direction
            direction = 0
            warningLeft = 0
            if let c = context, Self.isSafePush(to: c.lane + dir, in: c) {
                untilNext = Self.nextGap(&rng)
                pushes += 1
                return .pushed(direction: dir, lane: c.lane + dir)
            }
            // The player moved or a row came close: the gust blows past, and the next one comes sooner.
            untilNext = rng.range(Self.passedGapMin, Self.passedGapMax)
            passes += 1
            return .passed
        }
        if untilNext > 0 { untilNext = max(0, untilNext - dt) }
        guard untilNext <= 0, let c = context else { return .none }
        let ahead = c.speed * Self.warning
        let options = Self.safeDirections(in: c, ahead: ahead)
        guard !options.isEmpty else { return .none }     // no safe push: wait and look again
        let dir = options[rng.int(options.count)]
        direction = dir
        warningLeft = Self.warning
        announced += 1
        return .announced(direction: dir)
    }
}
