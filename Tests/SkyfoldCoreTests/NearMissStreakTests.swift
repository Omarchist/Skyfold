import Testing
@testable import SkyfoldCore

@Test func streakBuildsWithCloseCallsInsideTheWindow() {
    var streak = NearMissStreak()
    #expect(!streak.isActive)
    for expected in 1...3 {
        streak.registerNearMiss(multiplier: 1)
        #expect(streak.level == expected)
        streak.advance(dt: 2.5)
        #expect(streak.isActive)
    }
    #expect(streak.best == 3)
    #expect(streak.passes == 3)
}

@Test func streakIsCappedAtFive() {
    var streak = NearMissStreak()
    var paid: [Int] = []
    for _ in 0..<8 { paid.append(streak.registerNearMiss(multiplier: 1)) }
    #expect(streak.level == NearMissStreak.maxLevel)
    #expect(streak.best == 5)
    let base = Int(NearMissStreak.basePoints)
    #expect(paid == [1, 2, 3, 4, 5, 5, 5, 5].map { $0 * base })
}

@Test func streakTimesOutAfterTheWindowAndRestartsAtOne() {
    var streak = NearMissStreak()
    streak.registerNearMiss(multiplier: 1)
    streak.registerNearMiss(multiplier: 1)
    let early = streak.advance(dt: 2.9)
    #expect(!early)
    #expect(streak.level == 2)
    let late = streak.advance(dt: 0.2)
    #expect(late)
    #expect(streak.level == 0)
    let again = streak.advance(dt: 5)         // nothing left to time out
    #expect(!again)
    streak.registerNearMiss(multiplier: 1)
    #expect(streak.level == 1)
    #expect(streak.best == 2)                 // the best survives the time-out
}

@Test func aCloseCallResetsTheTimer() {
    var streak = NearMissStreak()
    streak.registerNearMiss(multiplier: 1)
    streak.advance(dt: 2.9)
    streak.registerNearMiss(multiplier: 1)
    streak.advance(dt: 2.9)
    #expect(streak.level == 2)
}

@Test func endingTheStreakDropsItButKeepsTheBest() {
    var streak = NearMissStreak()
    streak.registerNearMiss(multiplier: 1)
    streak.registerNearMiss(multiplier: 1)
    let ended = streak.end()
    #expect(ended)
    #expect(streak.level == 0)
    #expect(streak.best == 2)
    let endedTwice = streak.end()
    #expect(!endedTwice)
    streak.registerNearMiss(multiplier: 1)
    #expect(streak.level == 1)
    streak.reset()
    #expect(streak.best == 0 && streak.totalPoints == 0)
}

@Test func pointsScaleWithLevelAndScoreMultiplier() {
    let base = NearMissStreak.basePoints
    #expect(NearMissStreak.points(level: 0, multiplier: 1) == 0)
    #expect(NearMissStreak.points(level: 3, multiplier: 1) == Int((base * 3).rounded()))
    #expect(NearMissStreak.points(level: 3, multiplier: 2) == Int((base * 6).rounded()))
    #expect(NearMissStreak.points(level: 9, multiplier: 1) == NearMissStreak.points(level: 5, multiplier: 1))
    var streak = NearMissStreak()
    let a = streak.registerNearMiss(multiplier: 1.3)
    let b = streak.registerNearMiss(multiplier: 1.3)
    #expect(streak.totalPoints == a + b)
    #expect(streak.lastPoints == b)
}

@Test func flightScoreAddsBonusOnTopOfDistanceAndStars() {
    var score = FlightScore()
    score.addStar(points: 25)
    score.addBonus(points: 36)
    #expect(score.points == 61)
    score.reset()
    #expect(score.points == 0)
}

/// How often autopilot legs produce close calls, and what share of the score the bonus adds.
/// Each leg is flown twice (a careful pilot and a quick one) over four distances and eight seeds.
@Test(arguments: DifficultyID.allCases)
@MainActor
func nearMissBonusOverAutopilotLegs(_ id: DifficultyID) {
    let difficulty = Difficulty.get(id)
    var seconds = 0.0, ruleNearMisses = 0, closeCalls = 0
    var scoreWithout = 0, bonus = 0, bestStreak = 0, legs = 0
    var reachedX3 = 0
    for tier in [0, 3, 6, 9] {
        let leg = LegPlan.plan(fromRoute: tier, legsCompleted: tier, startRoute: 0,
                               difficulty: difficulty, tuning: RunTuning())
        for seed in 1...8 {
            var sim = FlightSimulation(config: FlightConfig(leg: leg), lane: seed % World.laneCount, seed: UInt64(seed))
            var autopilot = Autopilot()
            var streak = NearMissStreak()
            var detector = CloseCallDetector()
            var score = FlightScore()
            let multiplier = difficulty.scoreMultiplier
            let dt: Float = 1.0 / 60
            var x3 = false
            while sim.distance < leg.length {
                let speed = leg.speed(atProgress: sim.distance / leg.length)
                if let lane = autopilot.decide(sim, speed: speed, dt: dt) { sim.setTargetLane(lane) }
                let before = sim.distance
                sim.step(dt: dt, speed: speed)
                streak.advance(dt: dt)
                score.addDistance(sim.distance - before, multiplier: multiplier)
                seconds += Double(dt)
                for e in sim.events {
                    if e == .starCollected { score.addStar(points: max(1, Int((25 * multiplier).rounded()))) }
                    if e == .nearMiss { ruleNearMisses += 1 }
                }
                for _ in 0..<detector.scan(sim.obstacles) {
                    closeCalls += 1
                    score.addBonus(points: streak.registerNearMiss(multiplier: multiplier))
                    if streak.level >= 3 { x3 = true }
                }
            }
            if x3 { reachedX3 += 1 }
            bonus += score.bonusPoints
            scoreWithout += score.points - score.bonusPoints
            bestStreak = max(bestStreak, streak.best)
            legs += 1
        }
    }
    let share = Double(bonus) / Double(scoreWithout + bonus) * 100
    print("NEARMISS \(difficulty.name): \(legs) legs, \(Int(seconds)) s, rule near misses \(ruleNearMisses), "
          + "close calls \(closeCalls) (one per \(String(format: "%.1f", seconds / Double(max(closeCalls, 1)))) s, "
          + "\(String(format: "%.1f", Double(closeCalls) / Double(legs))) per leg), legs reaching x3: \(reachedX3), "
          + "best x\(bestStreak), bonus \(bonus) of \(scoreWithout + bonus) = \(String(format: "%.1f", share))%")
    #expect(share < 25)
}

@Test @MainActor
func detectorCountsEachPassOnceAndOnlyWhenClose() {
    var close = Obstacle(); close.id = 1; close.passed = true; close.closest = 0.5
    var far = Obstacle(); far.id = 2; far.passed = true; far.closest = 1.2
    var ahead = Obstacle(); ahead.id = 3; ahead.passed = false; ahead.closest = 0.1
    var detector = CloseCallDetector()
    #expect(detector.scan([close, far, ahead]) == 1)
    #expect(detector.scan([close, far, ahead]) == 0)
    ahead.passed = true
    #expect(detector.scan([close, far, ahead]) == 1)
    close.id = 9                                   // slot reused by a new obstacle
    #expect(detector.scan([close, far, ahead]) == 1)
}
