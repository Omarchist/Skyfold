import Foundation

/// Shared world dimensions. The 2D rules and the 3D renderer both read these, and
/// the Blender models (Tools/Blender) are sized against the same numbers.
///
/// Coordinate system (RealityKit, right-handed, meters, Y up):
///   +X = forward (direction of flight). The plane stays at x = 0 and the world
///        scrolls toward -X, so obstacle x is "meters ahead of the plane".
///   +Y = altitude. The three lanes are stacked heights.
///   +Z = toward the side camera (landscape). Depth is decoration only; the
///        rules ignore it.
enum World {
    static let laneCount = 3
    /// Vertical distance between lane centers.
    static let laneSpacing: Float = 1.6
    /// Lane centers: 0.0, 1.6, 3.2
    static func laneY(_ lane: Int) -> Float { Float(lane) * laneSpacing }
    static let middleLane = 1

    /// Ground height (towers stand on it, city skylines sit on it).
    static let groundY: Float = -1.8

    /// Collision radius of the plane (a circle in the X/Y plane).
    static let planeRadius: Float = 0.32

    /// Obstacles are spawned this far ahead and removed this far behind.
    static let spawnAheadDistance: Float = 60
    static let despawnBehindDistance: Float = -8

    /// Game distance shown to the player: 1 world meter = 1 m.
    static let metersPerWorldUnit: Double = 1
}

/// Names of the bundled USDZ models (Skyfold/Resources/Models/<name>.usdz).
/// Recolorable parts are child entities named exactly as listed in `Tools/Blender/README.md`.
enum ModelName: String, CaseIterable, Sendable {
    case plane
    case jet
    case bird
    case balloons
    case kite
    case stormCloud = "storm_cloud"
    case thunderhead
    case tower
    case star
    case cloudPuff = "cloud_puff"
    case buildingA = "building_a"
    case buildingB = "building_b"
    case buildingC = "building_c"
    case buildingD = "building_d"
    case landmarkDome = "landmark_dome"
    case gate
}
