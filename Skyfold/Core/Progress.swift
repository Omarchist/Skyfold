import Foundation
import Observation

/// Everything the player has earned across runs.
nonisolated struct PlayerProgress: Codable, Equatable, Sendable {
    /// City indices (0..<Route.count) ever landed in. Lisbon counts as visited from the start.
    var visitedCities: Set<Int> = [0]
    var unlockedSkins: Set<SkinID> = [.classic, .kraft, .interceptor]
    var unlockedDifficulties: Set<DifficultyID> = [.breezy, .standard]
    /// City indices whose airport you can depart from.
    var unlockedAirports: Set<Int> = [0]
    /// Times each curse/blessing has been collected, keyed by `ModifierID.rawValue`.
    var journal: [String: Int] = [:]
    var bestScore = 0
    var bestDistance: Double = 0
    var mostCitiesInRun = 0
    var totalStars = 0
    var totalDistance: Double = 0
    var runsPlayed = 0
    var completedLaps = 0

    enum CodingKeys: String, CodingKey {
        case visitedCities, unlockedSkins, unlockedDifficulties, unlockedAirports, journal
        case bestScore, bestDistance, mostCitiesInRun, totalStars, totalDistance, runsPlayed, completedLaps
    }
}

extension PlayerProgress {
    /// Reads a save from any older or damaged version: a missing or unreadable field keeps its
    /// default, unknown skins and difficulties are dropped, and the result is made valid.
    nonisolated init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func field<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        visitedCities = field(.visitedCities, visitedCities)
        unlockedSkins = Set(field(.unlockedSkins, [String]()).compactMap(SkinID.init(rawValue:)))
        unlockedDifficulties = Set(field(.unlockedDifficulties, [String]()).compactMap(DifficultyID.init(rawValue:)))
        unlockedAirports = field(.unlockedAirports, unlockedAirports)
        journal = field(.journal, journal)
        bestScore = field(.bestScore, 0)
        bestDistance = field(.bestDistance, 0)
        mostCitiesInRun = field(.mostCitiesInRun, 0)
        totalStars = field(.totalStars, 0)
        totalDistance = field(.totalDistance, 0)
        runsPlayed = field(.runsPlayed, 0)
        completedLaps = field(.completedLaps, 0)
        normalize()
    }

    /// Drops out-of-range cities, keeps the starting unlocks, and clamps counters to sane values.
    nonisolated mutating func normalize() {
        let valid = 0..<Route.count
        visitedCities = Set(visitedCities.filter(valid.contains)).union([0])
        unlockedAirports = Set(unlockedAirports.filter(valid.contains)).union([0])
        unlockedSkins.formUnion([.classic, .kraft, .interceptor])
        unlockedDifficulties.formUnion([.breezy, .standard])
        bestScore = max(0, bestScore)
        bestDistance = bestDistance.isFinite ? max(0, bestDistance) : 0
        totalDistance = totalDistance.isFinite ? max(0, totalDistance) : 0
        mostCitiesInRun = max(0, mostCitiesInRun)
        totalStars = max(0, totalStars)
        runsPlayed = max(0, runsPlayed)
        completedLaps = max(0, completedLaps)
    }
}

/// Summary of a finished run, shown on the game-over card.
nonisolated struct RunResult: Equatable, Sendable {
    var score: Int
    var distance: Double
    var stars: Int
    var citiesReached: Int
    var modifiers: [ModifierID]
    var isNewBest: Bool
    var difficulty: DifficultyID
}

@Observable
final class ProgressStore {
    private(set) var data: PlayerProgress

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "skyfold.progress.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(PlayerProgress.self, from: raw) {
            data = decoded
        } else {
            data = PlayerProgress()
        }
    }

    // MARK: Queries

    func isUnlocked(_ skin: SkinID) -> Bool { data.unlockedSkins.contains(skin) }
    func isUnlocked(_ difficulty: DifficultyID) -> Bool { data.unlockedDifficulties.contains(difficulty) }
    func isAirportUnlocked(_ cityIndex: Int) -> Bool { data.unlockedAirports.contains(cityIndex) }
    func hasVisited(_ cityIndex: Int) -> Bool { data.visitedCities.contains(cityIndex) }
    func timesCollected(_ id: ModifierID) -> Int { data.journal[id.rawValue] ?? 0 }
    var discoveredModifierCount: Int { ModifierID.allCases.filter { timesCollected($0) > 0 }.count }

    // MARK: Recording

    /// Call when the plane lands at `routeIndex`. Returns what this landing newly unlocked.
    @discardableResult
    func recordArrival(routeIndex: Int) -> [Unlock] {
        let city = Route.city(routeIndex)
        var newUnlocks: [Unlock] = []
        data.visitedCities.insert(city.index)

        for unlock in city.unlocks where unlock.isNew(in: data) {
            data.apply(unlock)
            newUnlocks.append(unlock)
        }
        // Landing back home after a full lap unlocks the secret skin.
        if Route.lap(routeIndex) >= 1, city.index == 0 {
            data.completedLaps = max(data.completedLaps, Route.lap(routeIndex))
            let midnight = Unlock.skin(.midnight)
            if midnight.isNew(in: data) {
                data.apply(midnight)
                newUnlocks.append(midnight)
            }
        }
        save()
        return newUnlocks
    }

    func recordModifier(_ id: ModifierID) {
        data.journal[id.rawValue, default: 0] += 1
        save()
    }

    /// Returns true when the score is a new personal best.
    @discardableResult
    func recordRunEnd(score: Int, distance: Double, stars: Int, citiesReached: Int) -> Bool {
        data.runsPlayed += 1
        data.totalStars += stars
        data.totalDistance += distance
        data.bestDistance = max(data.bestDistance, distance)
        data.mostCitiesInRun = max(data.mostCitiesInRun, citiesReached)
        let isBest = score > data.bestScore
        if isBest { data.bestScore = score }
        save()
        return isBest
    }

    func resetAll() {
        data = PlayerProgress()
        save()
    }

    #if DEBUG
    /// Unlocks everything (handy for testing the hangar/atlas).
    func unlockEverything() {
        data.unlockedSkins = Set(SkinID.allCases)
        data.unlockedDifficulties = Set(DifficultyID.allCases)
        data.unlockedAirports = Set(Route.airportCities.map(\.index))
        data.visitedCities = Set(Route.cities.map(\.index))
        save()
    }
    #endif

    private func save() {
        if let raw = try? JSONEncoder().encode(data) { defaults.set(raw, forKey: Self.key) }
    }
}

private extension Unlock {
    nonisolated func isNew(in p: PlayerProgress) -> Bool {
        switch self {
        case .skin(let s): !p.unlockedSkins.contains(s)
        case .difficulty(let d): !p.unlockedDifficulties.contains(d)
        case .airport(let a): !p.unlockedAirports.contains(a)
        }
    }
}

private extension PlayerProgress {
    nonisolated mutating func apply(_ unlock: Unlock) {
        switch unlock {
        case .skin(let s): unlockedSkins.insert(s)
        case .difficulty(let d): unlockedDifficulties.insert(d)
        case .airport(let a): unlockedAirports.insert(a)
        }
    }
}
