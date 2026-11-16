import Foundation

/// One obstacle slot. Slots live in a fixed-capacity array; `id == 0` means the slot is free.
struct Obstacle {
    /// Unique per spawned obstacle (0 = inactive). The renderer uses it to notice slot reuse.
    var id: UInt32 = 0
    var kind: ObstacleKind = .bird
    /// Meters ahead of the plane (the plane is always at x = 0).
    var x: Float = 0
    /// Current lane (base lane for two-lane kinds).
    var lane: Int = 0
    /// Current hitbox center altitude (includes bob and wandering).
    var y: Float = 0
    /// Lane a wandering bird drifts into, or -1.
    var wanderTo: Int = -1
    /// The drift starts once the bird is this close (m).
    var wanderStartX: Float = 0
    /// 0...1 progress of the drift.
    var wanderT: Float = 0
    /// Free-running animation clock (s), offset per obstacle so bobs and flaps don't sync.
    var phase: Float = 0
    /// Set once the obstacle is fully behind the plane (near-miss bookkeeping).
    var passed = false
    /// Closest vertical clearance (m) seen while overlapping the plane in X.
    var closest: Float = .greatestFiniteMagnitude

    var isActive: Bool { id != 0 }
    var halfWidth: Float { kind.halfWidth }
    var halfHeight: Float { kind.halfHeight }
    /// Lanes this obstacle blocks right now (both lanes while a bird is still due to wander).
    var blockedMask: LaneMask {
        var m = kind.blockedMask(lane: lane)
        if wanderTo >= 0 { m |= Lanes.bit(wanderTo) }
        return m
    }
}

/// A collectible star. `collectAge >= 0` means it was picked up and is playing its pop.
struct Star {
    var id: UInt32 = 0
    var x: Float = 0
    var y: Float = 0
    var phase: Float = 0
    var collectAge: Float = -1

    var isActive: Bool { id != 0 }
    var isCollectable: Bool { id != 0 && collectAge < 0 }
}

/// A spawned obstacle row as the spawner and the autopilot see it.
struct ObstacleRow {
    var id: UInt32 = 0
    /// Meters ahead of the plane (row center).
    var x: Float = 0
    /// Half extent in X that the plane must clear: widest hitbox half-width + plane radius.
    var reach: Float = 0
    /// Lanes blocked by this row (including a wandering bird's destination).
    var blocked: LaneMask = 0
    /// Lanes the player can be in when passing this row, given every earlier row (spawner bookkeeping).
    var reachable: LaneMask = Lanes.all
    /// Lanes that only become blocked once a wandering bird starts to drift (subset of `blocked`).
    var latent: LaneMask = 0
    /// The drift starts once the row is this close (m ahead of the plane).
    var latentStartX: Float = 0

    var free: LaneMask { ~blocked & Lanes.all }

    /// True once every lane in `blocked` can actually be seen to be blocked.
    var isRevealed: Bool { latent == 0 || x <= latentStartX }
    /// What a player looking at the screen sees blocked: a wandering bird counts only in the lane
    /// it is in until it starts to drift. `blocked` (and `free`) assume the worst from the start.
    var visibleBlocked: LaneMask { isRevealed ? blocked : blocked & ~latent }
    var visibleFree: LaneMask { ~visibleBlocked & Lanes.all }
}

struct PlaneState {
    /// Lane the plane is in or moving to.
    var lane: Int = World.middleLane
    /// Current altitude (m).
    var y: Float = World.laneY(World.middleLane)
    /// Current move segment (smoothstep from `moveFrom` to `moveTo` over `moveDuration`).
    var moveFrom: Float = World.laneY(World.middleLane)
    var moveTo: Float = World.laneY(World.middleLane)
    var moveElapsed: Float = 0
    var moveDuration: Float = 0
    /// Vertical speed (m/s), and a smoothed -1...1 value for the renderer's pitch and bank.
    var vy: Float = 0
    var tilt: Float = 0

    var isMoving: Bool { moveElapsed < moveDuration }
}

enum FlightEvent: Equatable {
    /// The plane started moving to another lane.
    case laneChanged(lane: Int)
    case starCollected
    /// The plane touched the obstacle in `slot`.
    case hit(slot: Int)
    /// An obstacle passed within a hair of the plane.
    case nearMiss
}

/// Tiny deterministic PRNG so runs and soak tests are reproducible.
nonisolated struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in 0..<1.
    mutating func unit() -> Float { Float(next() >> 40) / Float(1 << 24) }
    mutating func range(_ lo: Float, _ hi: Float) -> Float { lo + (hi - lo) * unit() }
    mutating func chance(_ p: Float) -> Bool { unit() < p }
    mutating func int(_ upperBound: Int) -> Int { Int(next() % UInt64(max(1, upperBound))) }
}

nonisolated enum FlightMath {
    @inline(__always) static func smoothstep(_ x: Float) -> Float {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }

    @inline(__always) static func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }

    /// Circle (plane) vs axis-aligned box overlap in the X/Y plane.
    @inline(__always)
    static func circleHitsBox(cx: Float, cy: Float, r: Float,
                              bx: Float, by: Float, hw: Float, hh: Float) -> Bool {
        let dx = max(abs(cx - bx) - hw, 0)
        let dy = max(abs(cy - by) - hh, 0)
        return dx * dx + dy * dy < r * r
    }

    /// Hash an id into a stable 0..<1 value (seeded per-instance imperfections).
    @inline(__always) static func hash01(_ id: UInt32, _ salt: UInt32 = 0) -> Float {
        var h = id &* 0x9E37_79B1 ^ salt &* 0x85EB_CA6B
        h ^= h >> 15; h = h &* 0x2C1B_3C6D; h ^= h >> 12; h = h &* 0x297A_2D39; h ^= h >> 15
        return Float(h & 0xFFFF) / 65536
    }
}
