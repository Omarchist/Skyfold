import Foundation

/// The near-miss bonus (experiment `nearMissBonus`): close passes in a row build a streak, and
/// each close pass pays a base bonus times the streak level, scaled by the run's score multiplier.
///
/// - A near miss within `window` seconds of the previous one raises the level (x1 up to x5).
/// - The streak ends after `window` seconds without one, and on a hit, a revive, a landing or a
///   crash (the engine calls `end()`).
/// - `best` is the highest level reached, kept until `reset()`.
///
/// Pure and deterministic: time only moves through `advance(dt:)`, so a paused game never ages it.
nonisolated struct NearMissStreak: Equatable, Sendable {
    /// Seconds a streak survives without another close pass.
    static let window: Float = 3
    static let maxLevel = 5
    /// Points for a x1 close pass at score multiplier 1 (one star is worth 25).
    static let basePoints = 20.0

    /// Current streak, 0 when none is running.
    private(set) var level = 0
    /// Highest streak reached since the last `reset()`.
    private(set) var best = 0
    /// Seconds since the last close pass.
    private(set) var idle: Float = 0
    /// Close passes counted.
    private(set) var passes = 0
    /// Bonus points paid so far.
    private(set) var totalPoints = 0
    /// Points paid by the latest close pass.
    private(set) var lastPoints = 0

    var isActive: Bool { level > 0 }

    /// Points a close pass pays at `level`.
    static func points(level: Int, multiplier: Double) -> Int {
        guard level > 0, multiplier > 0 else { return 0 }
        return max(1, Int((basePoints * Double(min(level, maxLevel)) * multiplier).rounded()))
    }

    /// Ages the streak. Returns true on the call where it times out.
    @discardableResult
    mutating func advance(dt: Float) -> Bool {
        guard level > 0, dt > 0 else { return false }
        idle += dt
        if idle > Self.window {
            level = 0
            idle = 0
            return true
        }
        return false
    }

    /// A close pass. Raises the streak (or starts one) and returns the bonus points it pays.
    @discardableResult
    mutating func registerNearMiss(multiplier: Double) -> Int {
        level = min(level + 1, Self.maxLevel)
        best = max(best, level)
        idle = 0
        passes += 1
        let pts = Self.points(level: level, multiplier: multiplier)
        lastPoints = pts
        totalPoints += pts
        return pts
    }

    /// Ends the streak now (hit, revive, landing, crash). Returns true if one was running.
    @discardableResult
    mutating func end() -> Bool {
        let was = level > 0
        level = 0
        idle = 0
        return was
    }

    /// A fresh run.
    mutating func reset() { self = NearMissStreak() }
}

/// Finds close calls among the simulation's obstacles.
///
/// The rules' own `.nearMiss` event needs under 0.3 m of clearance, which only happens when a
/// player changes lane while the obstacle is on top of them: a careful pilot is never that close
/// (the tightest pass in a lane is 0.6 m, see the tests). The experiment therefore counts a pass
/// as a close call when the obstacle went by with under `clearance` meters between its box and the
/// plane's, which includes the rules' near misses and the squeeze past an obstacle in the next lane.
struct CloseCallDetector: Equatable {
    /// Largest clearance (m) that still counts.
    static let clearance: Float = 0.8

    /// Id last handled in each obstacle slot, so a pass is counted once.
    private var handled: [UInt32] = []

    init() {}

    mutating func reset() { handled.removeAll(keepingCapacity: true) }

    /// Number of obstacles that have just finished passing the plane within `clearance`.
    mutating func scan(_ obstacles: [Obstacle]) -> Int {
        if handled.count < obstacles.count {
            handled.append(contentsOf: repeatElement(0, count: obstacles.count - handled.count))
        }
        var found = 0
        for i in obstacles.indices {
            let o = obstacles[i]
            guard o.isActive, o.passed, handled[i] != o.id else { continue }
            handled[i] = o.id
            // A negative clearance means the plane overlapped the obstacle while protected (after a
            // shield or a revive): that is a free ride, not a close call.
            if o.closest >= 0, o.closest < Self.clearance { found += 1 }
        }
        return found
    }
}
