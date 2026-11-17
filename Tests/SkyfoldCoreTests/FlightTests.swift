import Testing
@testable import SkyfoldCore

@Test(arguments: DifficultyID.allCases)
@MainActor
func autopilotCompletesSeededLegs(_ id: DifficultyID) {
    let difficulty = Difficulty.get(id)
    let rough = RunTuning.combine([
        .stormFront, .stormFront, .headwind, .soggyPaper,
        .restlessFlock, .restlessFlock, .restlessFlock, .luckyDraw,
    ])
    let started = ContinuousClock.now
    var simulatedSeconds = 0.0
    var simulatedFrames = 0
    var rowsFlown = 0
    var wanderingBirds = 0
    for (tier, tuning) in [(0, RunTuning()), (6, rough), (12, rough)] {
        let leg = LegPlan.plan(fromRoute: tier, legsCompleted: tier, startRoute: 0,
                               difficulty: difficulty, tuning: tuning)
        for seed in 1...4 {
            let config = FlightConfig(leg: leg, tuning: tuning)
            var simulation = FlightSimulation(config: config, lane: seed % World.laneCount, seed: UInt64(seed))
            var autopilot = Autopilot()
            autopilot.anticipatesWanderers = seed.isMultiple(of: 2)
            let frameTime: Float = 1.0 / 60
            let maxFrames = Int(leg.length / Double(leg.startSpeed * frameTime)) + 1

            for frame in 0..<maxFrames where simulation.distance < leg.length {
                let dt = frame.isMultiple(of: 11) ? 2 * frameTime : frameTime
                let speed = leg.speed(atProgress: simulation.distance / leg.length)
                if let lane = autopilot.decide(simulation, speed: speed, dt: dt) {
                    simulation.setTargetLane(lane)
                }
                simulation.step(dt: dt, speed: speed)
                simulatedSeconds += Double(dt)
                simulatedFrames += 1
            }

            let stats = simulation.stats
            let scenario = "\(difficulty.name), leg \(tier + 1), seed \(seed)"
            #expect(simulation.distance >= leg.length, "\(scenario)")
            #expect(stats.rows > 0, "\(scenario)")
            #expect(stats.starsCollected > 0, "\(scenario)")
            #expect(stats.hits == 0, "\(scenario)")
            #expect(stats.unfairRows == 0, "\(scenario)")
            #expect(stats.minSlack >= config.graceTime - 0.0001, "\(scenario)")
            #expect(stats.rowOverflows == 0, "\(scenario)")
            #expect(stats.droppedObstacles == 0 && stats.droppedStars == 0, "\(scenario)")
            rowsFlown += stats.rows
            wanderingBirds += stats.wanderers
        }
    }

    #expect(wanderingBirds > 0)
    let elapsed = started.duration(to: .now).components
    let wallSeconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
    let nanosecondsPerFrame = Int(wallSeconds * 1e9 / Double(simulatedFrames))
    print("\(difficulty.name): \(Int(simulatedSeconds)) simulated seconds, \(rowsFlown) rows, \(wanderingBirds) wandering birds, \(nanosecondsPerFrame) ns/frame including autopilot")
}

@Test @MainActor
func holdingTheStartingLaneEventuallyHitsAnObstacle() {
    let leg = LegPlan.plan(fromRoute: 0, legsCompleted: 0, startRoute: 0,
                           difficulty: Difficulty.get(.standard), tuning: RunTuning())
    var simulation = FlightSimulation(config: FlightConfig(leg: leg), seed: 1)

    while simulation.distance < leg.length, simulation.stats.hits == 0 {
        let speed = leg.speed(atProgress: simulation.distance / leg.length)
        simulation.step(dt: 1.0 / 60, speed: speed)
    }
    #expect(simulation.stats.hits == 1)
}

@Test @MainActor
func resettingReplaysTheSameSeed() {
    let leg = LegPlan.plan(fromRoute: 0, legsCompleted: 0, startRoute: 0,
                           difficulty: Difficulty.get(.standard), tuning: RunTuning())
    let config = FlightConfig(leg: leg)
    var fresh = FlightSimulation(config: config, seed: 7)
    var reused = FlightSimulation(config: config, seed: 13)
    reused.step(dt: 1.0 / 60, speed: leg.startSpeed)
    reused.reset(config: config, seed: 7)

    fresh.step(dt: 1.0 / 60, speed: leg.startSpeed)
    reused.step(dt: 1.0 / 60, speed: leg.startSpeed)

    #expect(fresh.stats.rows > 0)
    #expect(fresh.obstacles.map(\.id) == reused.obstacles.map(\.id))
    #expect(fresh.stars.map(\.id) == reused.stars.map(\.id))
    #expect(fresh.row(0).id == reused.row(0).id)
}

@Test @MainActor
func fastFrameDetectsHitsAcrossAllBlockedLanes() {
    let leg = LegPlan.plan(fromRoute: 0, legsCompleted: 0, startRoute: 0,
                           difficulty: Difficulty.get(.standard), tuning: RunTuning())
    for lane in 0..<World.laneCount {
        for kind in [ObstacleKind.bird, .tower, .thunderhead] {
            let obstacleLane = kind.fixedBaseLane ?? lane
            var simulation = FlightSimulation(config: FlightConfig(leg: leg), lane: lane)
            guard let slot = simulation.placeObstacle(kind: kind, lane: obstacleLane, x: 0.9) else {
                Issue.record("Could not place \(kind) in lane \(obstacleLane)")
                continue
            }
            simulation.step(dt: 0.05, speed: 40, spawning: false)
            #expect(simulation.events.contains(.hit(slot: slot)) == Lanes.contains(kind.blockedMask(lane: obstacleLane), lane))
        }
    }
}

@Test @MainActor
func distanceKeepsFractionalScoreBetweenStars() {
    var score = FlightScore()
    score.addDistance(1, multiplier: 1.3)
    score.addStar(points: 32)
    score.addDistance(3, multiplier: 1.3)
    #expect(score.points == 37)
    #expect(score.stars == 1)
}
