import Foundation

// MARK: - Unlocks

/// Something a city unlocks the first time you land there.
nonisolated enum Unlock: Hashable, Codable, Sendable {
    case skin(SkinID)
    case difficulty(DifficultyID)
    /// An airport you can depart from, identified by its route index in `Route.cities`.
    case airport(Int)

    var title: String {
        switch self {
        case .skin(let id): "\(PlaneSkin.get(id).name) skin"
        case .difficulty(let id): "\(Difficulty.get(id).name) mode"
        case .airport(let i): "\(Route.city(i).name) airport"
        }
    }

    var symbol: String {
        switch self {
        case .skin: "paintpalette.fill"
        case .difficulty: "gauge.with.dots.needle.67percent"
        case .airport: "airplane.departure"
        }
    }
}

// MARK: - Cities & route

nonisolated struct City: Identifiable, Hashable, Sendable {
    /// Position in `Route.cities` (also its id).
    let index: Int
    let name: String
    let country: String
    /// Three-letter code shown on boarding passes and the HUD.
    let code: String
    let blurb: String
    /// Building wall color for this city's skyline (multiplied by the palette's cityTint).
    let wall: RGBA
    let roof: RGBA
    /// Skyline pieces the renderer picks from (weighted by repetition).
    let skyline: [ModelName]
    let unlocks: [Unlock]

    var id: Int { index }
    var hasAirport: Bool { index == 0 || unlocks.contains(.airport(index)) }
}

nonisolated enum Route {
    static let cities: [City] = [
        City(index: 0, name: "Lisbon", country: "Portugal", code: "LIS",
             blurb: "Home. Tiled roofs, steep hills, wind off the river.",
             wall: RGBA(hex: 0xF3D9C2), roof: RGBA(hex: 0xD9774A),
             skyline: [.buildingB, .buildingB, .buildingD, .buildingA], unlocks: []),
        City(index: 1, name: "Marrakesh", country: "Morocco", code: "RAK",
             blurb: "Dry heat over the old town. Rooftops the color of saffron.",
             wall: RGBA(hex: 0xE8A27C), roof: RGBA(hex: 0xC2643F),
             skyline: [.buildingD, .buildingB, .landmarkDome, .buildingD], unlocks: [.skin(.saffron)]),
        City(index: 2, name: "Cairo", country: "Egypt", code: "CAI",
             blurb: "Wind comes in off the desert and pushes back hard.",
             wall: RGBA(hex: 0xE9CF9F), roof: RGBA(hex: 0xC9A46A),
             skyline: [.buildingB, .landmarkDome, .buildingA, .buildingD],
             unlocks: [.difficulty(.gale), .skin(.newsprint)]),
        City(index: 3, name: "Istanbul", country: "Türkiye", code: "IST",
             blurb: "Gulls over the strait. Mind the domes on approach.",
             wall: RGBA(hex: 0xDCD3E6), roof: RGBA(hex: 0x8C7FB0),
             skyline: [.landmarkDome, .buildingC, .buildingB, .buildingC], unlocks: [.airport(3)]),
        City(index: 4, name: "Mumbai", country: "India", code: "BOM",
             blurb: "Monsoon season. The cloud sits low over the bay.",
             wall: RGBA(hex: 0xBFD6D9), roof: RGBA(hex: 0x5F8F99),
             skyline: [.buildingA, .buildingA, .buildingB, .landmarkDome], unlocks: [.skin(.monsoon)]),
        City(index: 5, name: "Kyoto", country: "Japan", code: "UKY",
             blurb: "Temple roofs and paper lanterns. Fly quietly.",
             wall: RGBA(hex: 0xF4D6DA), roof: RGBA(hex: 0x4A3F4F),
             skyline: [.buildingC, .buildingD, .buildingB, .buildingC],
             unlocks: [.skin(.sakura), .airport(5)]),
        City(index: 6, name: "Sydney", country: "Australia", code: "SYD",
             blurb: "Storms build fast down here. Keep your folds tight.",
             wall: RGBA(hex: 0xD6E4F0), roof: RGBA(hex: 0x6E8FB0),
             skyline: [.buildingA, .buildingC, .landmarkDome, .buildingB], unlocks: [.difficulty(.tempest)]),
        City(index: 7, name: "Honolulu", country: "USA", code: "HNL",
             blurb: "Trade winds and warm air. Easy to get careless.",
             wall: RGBA(hex: 0xFFE0C7), roof: RGBA(hex: 0xE86A5A),
             skyline: [.buildingD, .buildingB, .buildingD, .buildingA], unlocks: [.skin(.hibiscus)]),
        City(index: 8, name: "Rio de Janeiro", country: "Brazil", code: "GIG",
             blurb: "The mountains drop straight into the sea.",
             wall: RGBA(hex: 0xD9EBD3), roof: RGBA(hex: 0x5E9E6E),
             skyline: [.buildingB, .buildingA, .buildingD, .buildingC], unlocks: [.airport(8)]),
        City(index: 9, name: "New York", country: "USA", code: "JFK",
             blurb: "Tallest skyline on the route. Stay low or stay lucky.",
             wall: RGBA(hex: 0xD7D2CC), roof: RGBA(hex: 0x8A7F76),
             skyline: [.buildingA, .buildingC, .buildingA, .buildingC, .buildingB],
             unlocks: [.difficulty(.paperCut), .skin(.goldLeaf)]),
    ]

    static var count: Int { cities.count }

    /// Route indices keep counting past the last city (lap 2 starts at index 10),
    /// so a run can go round the world forever.
    static func city(_ routeIndex: Int) -> City {
        cities[((routeIndex % count) + count) % count]
    }

    static func lap(_ routeIndex: Int) -> Int { max(0, routeIndex) / count }

    /// Cities whose airport can be unlocked as a departure point (including home).
    static var airportCities: [City] { cities.filter(\.hasAirport) }
}

/// One flight between two cities, planned when the leg starts.
nonisolated struct LegPlan: Equatable, Sendable {
    /// Route indices (may exceed `Route.count` on later laps).
    var fromRoute: Int
    var toRoute: Int
    /// Leg length in meters.
    var length: Double
    /// Forward speed (m/s) at the start and end of the leg; the engine interpolates by progress.
    var startSpeed: Float
    var endSpeed: Float
    /// Obstacle density multiplier for the spawner (1 = normal).
    var density: Float
    /// Seconds to move one lane.
    var laneSwitchTime: Float

    var from: City { Route.city(fromRoute) }
    var to: City { Route.city(toRoute) }

    func speed(atProgress p: Double) -> Float {
        startSpeed + (endSpeed - startSpeed) * Float(min(max(p, 0), 1))
    }

    /// Metres of landscape the side camera shows ahead of the plane.
    static let visibleAhead: Float = 23
    /// Least warning (s) a player gets before something shown at the edge of the view arrives.
    static let minWarningTime: Float = 0.8
    /// No leg is flown faster than this, whatever the difficulty and however many Headwinds were taken:
    /// `visibleAhead / minWarningTime`.
    static let speedLimit: Float = visibleAhead / minWarningTime
    /// Shortest leg (m) before the debug scale; stacked Shortcuts cannot shrink a leg below it.
    static let minLength: Double = 300
    /// Bounds on seconds per lane move, so stacked Nimble Creases or Soggy Papers stay playable.
    static let laneSwitchRange: ClosedRange<Float> = 0.06...0.4

    static func plan(fromRoute: Int, legsCompleted: Int, startRoute: Int,
                     difficulty: Difficulty, tuning: RunTuning) -> LegPlan {
        // "Tier" grows with every leg flown, with later departure airports, and with each lap.
        let tier = Float(legsCompleted) + Float(startRoute) * 0.5 + Float(Route.lap(fromRoute)) * 2
        let cap = min(difficulty.maxSpeed * tuning.speed, speedLimit)
        let start = min((difficulty.baseSpeed + difficulty.speedPerLeg * tier) * tuning.speed, cap)
        let end = min(start + difficulty.speedRampInLeg * tuning.speed, cap)
        let planned = (700 + 220 * Double(legsCompleted) + 60 * Double(startRoute))
            * difficulty.legLengthScale * tuning.legLength
        let length = max(planned, minLength) * DebugFlags.legLengthScale
        let density = difficulty.density * tuning.density * (1 + 0.06 * tier)
        return LegPlan(fromRoute: fromRoute, toRoute: fromRoute + 1, length: length,
                       startSpeed: start, endSpeed: end, density: density,
                       laneSwitchTime: min(max(difficulty.laneSwitchTime * tuning.laneSwitchTime,
                                                laneSwitchRange.lowerBound), laneSwitchRange.upperBound))
    }
}

// MARK: - Difficulty

nonisolated enum DifficultyID: String, CaseIterable, Codable, Identifiable, Sendable {
    case breezy, standard, gale, tempest, paperCut
    var id: String { rawValue }
}

nonisolated struct Difficulty: Identifiable, Sendable {
    let id: DifficultyID
    let name: String
    let blurb: String
    let symbol: String
    /// m/s at the first leg.
    let baseSpeed: Float
    /// m/s added per tier (leg flown, lap, later airport).
    let speedPerLeg: Float
    /// m/s gained from start to end of a single leg.
    let speedRampInLeg: Float
    let maxSpeed: Float
    /// Obstacle density multiplier.
    let density: Float
    /// Seconds to move one lane.
    let laneSwitchTime: Float
    let legLengthScale: Double
    let scoreMultiplier: Double
    /// When false, Paper Shield and Second Wind never appear and nothing saves you from a hit.
    let allowsSecondChances: Bool

    static let all: [Difficulty] = [
        Difficulty(id: .breezy, name: "Breezy", blurb: "Slower air and fewer obstacles.",
                   symbol: "wind", baseSpeed: 9, speedPerLeg: 0.8, speedRampInLeg: 1.5, maxSpeed: 18,
                   density: 0.75, laneSwitchTime: 0.16, legLengthScale: 0.9, scoreMultiplier: 0.8,
                   allowsSecondChances: true),
        Difficulty(id: .standard, name: "Standard", blurb: "Normal speed, normal traffic.",
                   symbol: "paperplane", baseSpeed: 11, speedPerLeg: 1.1, speedRampInLeg: 2, maxSpeed: 24,
                   density: 1, laneSwitchTime: 0.14, legLengthScale: 1, scoreMultiplier: 1,
                   allowsSecondChances: true),
        Difficulty(id: .gale, name: "Gale", blurb: "Faster and busier. Unlocked in Cairo.",
                   symbol: "wind.circle", baseSpeed: 13, speedPerLeg: 1.3, speedRampInLeg: 2.5, maxSpeed: 28,
                   density: 1.2, laneSwitchTime: 0.13, legLengthScale: 1.1, scoreMultiplier: 1.3,
                   allowsSecondChances: true),
        Difficulty(id: .tempest, name: "Tempest", blurb: "Storm season. Unlocked in Sydney.",
                   symbol: "cloud.bolt", baseSpeed: 15, speedPerLeg: 1.5, speedRampInLeg: 3, maxSpeed: 32,
                   density: 1.4, laneSwitchTime: 0.12, legLengthScale: 1.2, scoreMultiplier: 1.6,
                   allowsSecondChances: true),
        Difficulty(id: .paperCut, name: "Paper Cut", blurb: "One hit ends the flight. No shields, no revives.",
                   symbol: "scissors", baseSpeed: 14, speedPerLeg: 1.4, speedRampInLeg: 3, maxSpeed: 30,
                   density: 1.3, laneSwitchTime: 0.12, legLengthScale: 1.1, scoreMultiplier: 2.0,
                   allowsSecondChances: false),
    ]

    static func get(_ id: DifficultyID) -> Difficulty { all.first { $0.id == id } ?? all[1] }
}

// MARK: - Plane skins

nonisolated enum SkinID: String, CaseIterable, Codable, Identifiable, Sendable {
    case classic, kraft, newsprint, saffron, monsoon, sakura, hibiscus, goldLeaf, midnight
    var id: String { rawValue }
}

nonisolated struct PlaneSkin: Identifiable, Sendable {
    let id: SkinID
    let name: String
    /// Main paper color (model part "Paper").
    let paper: RGBA
    /// Fold/underside color (model part "Crease").
    let crease: RGBA
    /// Speed-trail color.
    let trail: RGBA
    let unlockHint: String

    static let all: [PlaneSkin] = [
        PlaneSkin(id: .classic, name: "Classic", paper: RGBA(hex: 0xFFFDF8), crease: RGBA(hex: 0xE9DCC8),
                  trail: RGBA(hex: 0xFFFFFF), unlockHint: "Standard issue."),
        PlaneSkin(id: .kraft, name: "Kraft", paper: RGBA(hex: 0xC9A27A), crease: RGBA(hex: 0xA88460),
                  trail: RGBA(hex: 0xE8CFAF), unlockHint: "Brown bag stock. Standard issue."),
        PlaneSkin(id: .newsprint, name: "Newsprint", paper: RGBA(hex: 0xE6E3DC), crease: RGBA(hex: 0x9A978F),
                  trail: RGBA(hex: 0xD0CDC6), unlockHint: "Land in Cairo."),
        PlaneSkin(id: .saffron, name: "Saffron", paper: RGBA(hex: 0xF6B24A), crease: RGBA(hex: 0xD9852C),
                  trail: RGBA(hex: 0xFFD58A), unlockHint: "Land in Marrakesh."),
        PlaneSkin(id: .monsoon, name: "Monsoon", paper: RGBA(hex: 0x7FA7C4), crease: RGBA(hex: 0x4F7896),
                  trail: RGBA(hex: 0xB8D4E8), unlockHint: "Land in Mumbai."),
        PlaneSkin(id: .sakura, name: "Sakura", paper: RGBA(hex: 0xFFC7D4), crease: RGBA(hex: 0xE892A8),
                  trail: RGBA(hex: 0xFFE3EA), unlockHint: "Land in Kyoto."),
        PlaneSkin(id: .hibiscus, name: "Hibiscus", paper: RGBA(hex: 0xFF6B5E), crease: RGBA(hex: 0xC9433A),
                  trail: RGBA(hex: 0xFFB0A6), unlockHint: "Land in Honolulu."),
        PlaneSkin(id: .goldLeaf, name: "Gold Leaf", paper: RGBA(hex: 0xF2CB6B), crease: RGBA(hex: 0xB8902F),
                  trail: RGBA(hex: 0xFFE7A3), unlockHint: "Land in New York."),
        PlaneSkin(id: .midnight, name: "Midnight Ink", paper: RGBA(hex: 0x2B2850), crease: RGBA(hex: 0xE4DCCB),
                  trail: RGBA(hex: 0xE5A03A), unlockHint: "Land back in Lisbon after a full lap."),
    ]

    static func get(_ id: SkinID) -> PlaneSkin { all.first { $0.id == id } ?? all[0] }
}
