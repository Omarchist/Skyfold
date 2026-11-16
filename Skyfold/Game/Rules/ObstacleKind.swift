import Foundation

/// Lane bit masks: bit `n` set means lane `n` (0 = lowest) is blocked.
typealias LaneMask = UInt8

nonisolated enum Lanes {
    static let all: LaneMask = 0b111

    @inline(__always) static func bit(_ lane: Int) -> LaneMask { LaneMask(1) << LaneMask(lane) }
    @inline(__always) static func contains(_ mask: LaneMask, _ lane: Int) -> Bool { mask & bit(lane) != 0 }
}

/// Everything that can block a lane. The rules only care about the 2D hitbox (X = forward
/// distance, Y = altitude); the renderer maps each kind to a model.
enum ObstacleKind: Int, CaseIterable {
    case bird, balloons, kite, stormCloud, tower, thunderhead

    /// Two-lane obstacles have a fixed base lane and block it plus the lane above.
    var spansTwoLanes: Bool { self == .tower || self == .thunderhead }

    /// The lane a two-lane obstacle always occupies (tower: lanes 0+1, thunderhead: lanes 1+2).
    var fixedBaseLane: Int? {
        switch self {
        case .tower: 0
        case .thunderhead: 1
        default: nil
        }
    }

    func blockedMask(lane: Int) -> LaneMask {
        spansTwoLanes ? (Lanes.bit(lane) | Lanes.bit(lane + 1)) : Lanes.bit(lane)
    }

    /// Hitbox half extents in meters, about 15% smaller than the visual so near misses feel fair.
    var halfWidth: Float {
        switch self {
        case .bird: 0.22        // origami bird, ~0.45 m long
        case .balloons: 0.38    // ~0.9 m wide bunch
        case .kite: 0.34        // ~0.8 m sail
        case .stormCloud: 0.60  // ~1.4 m
        case .tower: 0.51       // ~1.2 m
        case .thunderhead: 0.77 // ~1.8 m
        }
    }

    var halfHeight: Float {
        switch self {
        case .bird: 0.20
        case .balloons: 0.50
        case .kite: 0.42
        case .stormCloud: 0.42
        case .tower: Self.towerTop.halfSpan(from: World.groundY)
        case .thunderhead: 1.32
        }
    }

    /// Vertical center of the hitbox (before bobbing) for an obstacle in `lane`.
    func centerY(lane: Int) -> Float {
        switch self {
        case .tower: (World.groundY + Self.towerTop) * 0.5
        case .thunderhead: (World.laneY(1) + World.laneY(2)) * 0.5
        default: World.laneY(lane)
        }
    }

    /// Top of the tower's hitbox: the 4.1 m model minus a forgiving margin. Still well above
    /// lane 1 (1.6 + plane radius) and well below lane 2 (3.2 - plane radius).
    static let towerTop: Float = World.groundY + 4.1 - 0.25

    /// Gentle idle bob amplitude (m). Kept small so a single-lane obstacle never reaches
    /// into a neighbouring lane's flight path.
    var bobAmplitude: Float {
        switch self {
        case .bird: 0.05
        case .balloons: 0.07
        case .kite: 0.08
        default: 0
        }
    }

    var isSingleLane: Bool { !spansTwoLanes }
}

private extension Float {
    /// Half the distance between `self` (a top) and `bottom`.
    func halfSpan(from bottom: Float) -> Float { (self - bottom) * 0.5 }
}
