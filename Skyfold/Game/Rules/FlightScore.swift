import Foundation

/// Score bookkeeping for a run, kept apart from `RunSession` so the engine can unit-test it and
/// so the maths lives next to the rules.
///
/// - Distance: +1 point per meter, times the session's score multiplier. Accumulated as a
///   `Double` so slow frames never lose fractions.
/// - Stars: each star adds a fixed number of points (`RunSession.starPoints`), already scaled.
///
/// Usage from the engine, once per frame:
/// ```
/// score.addDistance(Double(speed * dt), multiplier: session.scoreMultiplier)
/// for case .starCollected in sim.events { score.addStar(points: session.starPoints) }
/// if score.points != session.score { session.score = score.points }
/// ```
struct FlightScore {
    /// Fractional points earned by distance so far.
    private(set) var distancePoints: Double = 0
    /// Whole points earned from stars.
    private(set) var starPoints: Int = 0
    /// Stars picked up.
    private(set) var stars: Int = 0
    /// Whole points from the near-miss bonus experiment (always 0 with the switch off).
    private(set) var bonusPoints: Int = 0
    /// Points carried in from before this struct existed (resuming a run).
    private let carried: Int

    init(carriedPoints: Int = 0) {
        carried = max(0, carriedPoints)
    }

    /// The whole-number score to show.
    var points: Int { carried + starPoints + bonusPoints + Int(min(distancePoints + 1e-6, 1e15)) }

    mutating func addDistance(_ meters: Double, multiplier: Double) {
        guard meters > 0, multiplier > 0 else { return }
        distancePoints += meters * multiplier * World.metersPerWorldUnit
    }

    mutating func addStar(points: Int) {
        stars += 1
        starPoints += max(0, points)
    }

    mutating func addBonus(points: Int) {
        bonusPoints += max(0, points)
    }

    /// Resets everything (a fresh run).
    mutating func reset() {
        distancePoints = 0
        starPoints = 0
        stars = 0
        bonusPoints = 0
    }
}
