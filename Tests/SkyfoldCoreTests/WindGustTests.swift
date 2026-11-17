import Testing
@testable import SkyfoldCore

// MARK: - Helpers

private func context(lane: Int = 1, distance: Double = 200, legLength: Double = 900, speed: Float = 20,
                     rows: [GustRow] = [], isProtected: Bool = false) -> GustContext {
    GustContext(lane: lane, distance: distance, legLength: legLength, clearApproach: 60, speed: speed,
                laneSwitchTime: 0.14, designReaction: 0.47, isProtected: isProtected, rows: rows)
}

/// Runs the gust clock alone for `seconds` of flying at 60 fps, with a context that never blocks.
private func timeline(seed: UInt64, seconds: Float, lane: Int = 1) -> [(t: Float, outcome: WindGusts.Outcome)] {
    var gusts = WindGusts(seed: seed)
    var out: [(Float, WindGusts.Outcome)] = []
    var plane = lane
    var t: Float = 0
    let dt: Float = 1.0 / 60
    while t < seconds {
        let ctx = context(lane: plane)
        let o = gusts.advance(dt: dt, context: (gusts.needsContext || gusts.pushDue(within: dt)) ? ctx : nil)
        if case .pushed(_, let l) = o { plane = l }
        if o != .none { out.append((t, o)) }
        t += dt
    }
    return out
}

// MARK: - Spacing and warning

@Test func gustsAreSpacedTwelveToTwentyFiveSecondsApart() {
    for seed in 1...20 as ClosedRange<UInt64> {
        let events = timeline(seed: seed, seconds: 400)
        let pushes = events.filter { if case .pushed = $0.outcome { true } else { false } }.map(\.t)
        #expect(pushes.count >= 10, "seed \(seed)")
        var previous: Float = 0
        for (i, t) in pushes.enumerated() {
            let gap = t - previous
            // Push to push is the gap plus the warning; the first one counts from the start.
            let lo = WindGusts.minGap + WindGusts.warning - 0.1
            let hi = WindGusts.maxGap + WindGusts.warning + 0.1
            #expect(gap >= lo && gap <= hi, "seed \(seed) gust \(i): \(gap)")
            previous = t
        }
    }
}

@Test func warningLeadsThePushByAboutOnePointTwoSeconds() {
    let events = timeline(seed: 7, seconds: 120)
    var announcedAt: Float?
    var seen = 0
    for e in events {
        switch e.outcome {
        case .announced: announcedAt = e.t
        case .pushed:
            let lead = e.t - (announcedAt ?? -99)
            #expect(abs(lead - WindGusts.warning) < 0.05, "lead \(lead)")
            seen += 1
        default: break
        }
    }
    #expect(seen >= 3)
}

@Test func sameSeedReplaysTheSameGusts() {
    let a = timeline(seed: 42, seconds: 200)
    let b = timeline(seed: 42, seconds: 200)
    #expect(a.map(\.t) == b.map(\.t))
    #expect(a.map(\.outcome) == b.map(\.outcome))
    let c = timeline(seed: 43, seconds: 200)
    #expect(a.map(\.t) != c.map(\.t))
}

@Test func bothSidesAppear() {
    var up = 0, down = 0
    for seed in 1...10 as ClosedRange<UInt64> {
        for e in timeline(seed: seed, seconds: 200) {
            if case .announced(let d) = e.outcome { if d > 0 { up += 1 } else { down += 1 } }
        }
    }
    #expect(up > 5 && down > 5)
}

// MARK: - Fairness

@Test func edgeLanesOnlyPushInward() {
    let top = context(lane: 2)
    #expect(WindGusts.safeDirections(in: top, ahead: 0) == [-1])
    let bottom = context(lane: 0)
    #expect(WindGusts.safeDirections(in: bottom, ahead: 0) == [1])
    #expect(!WindGusts.isSafePush(to: 3, in: top))
    #expect(!WindGusts.isSafePush(to: -1, in: bottom))
    #expect(Set(WindGusts.safeDirections(in: context(lane: 1), ahead: 0)) == [1, -1])
}

@Test func noPushIntoALaneBlockedInsideTheReactionWindow() {
    let window = WindGusts.reactionWindow(context())
    let metersInWindow = window * 20
    // A row blocking the top lane just inside the window, and one just outside it.
    let near = GustRow(x: metersInWindow - 1 + 1.5, reach: 1.5, blocked: Lanes.bit(2))
    let far = GustRow(x: metersInWindow + 3 + 1.5, reach: 1.5, blocked: Lanes.bit(2))
    #expect(!WindGusts.isSafePush(to: 2, in: context(rows: [near])))
    #expect(WindGusts.isSafePush(to: 2, in: context(rows: [far])))
    // The other lane is not affected, and a row blocking the plane's own lane does not matter.
    #expect(WindGusts.isSafePush(to: 0, in: context(rows: [near])))
    let own = GustRow(x: 5, reach: 1.5, blocked: Lanes.bit(1))
    #expect(WindGusts.isSafePush(to: 0, in: context(rows: [own])))
    // A row the plane is inside right now, in the pushed lane.
    let inside = GustRow(x: 0, reach: 1.5, blocked: Lanes.bit(2))
    #expect(!WindGusts.isSafePush(to: 2, in: context(rows: [inside])))
    // A row already behind is no concern.
    let behind = GustRow(x: -4, reach: 1.5, blocked: Lanes.bit(2))
    #expect(WindGusts.isSafePush(to: 2, in: context(rows: [behind])))
}

@Test func theWarningLookaheadCountsTheMetersFlownBeforeThePush() {
    // A row 30 m ahead blocks the top lane: outside the window now, but inside it when the push lands.
    let row = GustRow(x: 30, reach: 1.5, blocked: Lanes.bit(2))
    let c = context(rows: [row])
    #expect(WindGusts.isSafePush(to: 2, in: c, ahead: 0))
    #expect(!WindGusts.isSafePush(to: 2, in: c, ahead: 20))
}

@Test func neverPushesDuringTheClearApproachOrWhileProtected() {
    let approachStart = 900.0 - 60
    #expect(WindGusts.isSafePush(to: 2, in: context(distance: approachStart - 1)))
    #expect(!WindGusts.isSafePush(to: 2, in: context(distance: approachStart + 1)))
    #expect(!WindGusts.isSafePush(to: 2, in: context(distance: approachStart - 5), ahead: 24))
    #expect(!WindGusts.isSafePush(to: 2, in: context(distance: -10)))
    #expect(!WindGusts.isSafePush(to: 2, in: context(isProtected: true)))
}

@Test func aGustWaitsUntilASafePushExistsThenAnnounces() {
    var gusts = WindGusts(seed: 3)
    let blocked = context(rows: [GustRow(x: 40, reach: 1.5, blocked: Lanes.bit(0) | Lanes.bit(2))])
    var t: Float = 0
    var firstAnnounce: Float?
    while t < 60 {
        let o = gusts.advance(dt: 0.1, context: gusts.needsContext ? blocked : nil)
        if case .announced = o { firstAnnounce = t }
        t += 0.1
    }
    #expect(firstAnnounce == nil)          // both neighbours blocked: it keeps waiting
    #expect(gusts.needsContext)
    let o = gusts.advance(dt: 0.1, context: context())
    guard case .announced = o else { Issue.record("expected a warning, got \(o)"); return }
}

@Test func aWarningThatTurnsUnsafePassesWithoutAPush() {
    var gusts = WindGusts(seed: 5)
    var o = WindGusts.Outcome.none
    while o == .none { o = gusts.advance(dt: 0.1, context: gusts.needsContext ? context(lane: 0) : nil) }
    guard case .announced(let dir) = o else { Issue.record("no warning"); return }
    #expect(dir == 1)                       // from the bottom lane it can only push up
    let blocked = context(lane: 0, rows: [GustRow(x: 8, reach: 1.5, blocked: Lanes.bit(1))])
    var last = WindGusts.Outcome.none
    for _ in 0..<20 where last == .none {
        last = gusts.advance(dt: 0.1, context: gusts.pushDue(within: 0.1) ? blocked : nil)
    }
    #expect(last == .passed)
    #expect(gusts.passes == 1 && gusts.pushes == 0)
}

@Test func holdQuietsTheWindAfterARevive() {
    var gusts = WindGusts(seed: 9)
    var o = WindGusts.Outcome.none
    while o == .none { o = gusts.advance(dt: 0.1, context: gusts.needsContext ? context() : nil) }
    #expect(gusts.isWarning)
    gusts.hold()
    #expect(!gusts.isWarning)
    var quiet: Float = 0
    while true {
        let r = gusts.advance(dt: 0.1, context: gusts.needsContext ? context() : nil)
        if r != .none { break }
        quiet += 0.1
    }
    #expect(quiet >= WindGusts.holdAfterRevive - 0.2)
}

// MARK: - Soak

/// Flies the autopilot through full legs with gusts on. It reacts to a push the way a player would:
/// it notices the plane is in a lane the rows ahead do not allow and flies back out. No hits allowed.
@Test(arguments: DifficultyID.allCases)
@MainActor
func autopilotFliesThroughGustsWithoutAHit(_ id: DifficultyID) {
    let difficulty = Difficulty.get(id)
    let rough = RunTuning.combine([.stormFront, .stormFront, .headwind, .restlessFlock, .restlessFlock, .luckyDraw])
    var seconds = 0.0
    var pushes = 0, passes = 0, announced = 0, hits = 0
    for (tier, tuning) in [(0, RunTuning()), (4, RunTuning()), (8, rough), (12, rough)] {
        let leg = LegPlan.plan(fromRoute: tier, legsCompleted: tier, startRoute: 0,
                               difficulty: difficulty, tuning: tuning)
        for seed in 1...6 {
            let config = FlightConfig(leg: leg, tuning: tuning)
            var sim = FlightSimulation(config: config, lane: seed % World.laneCount, seed: UInt64(seed))
            var autopilot = Autopilot()
            autopilot.anticipatesWanderers = seed.isMultiple(of: 2)
            var gusts = WindGusts(seed: UInt64(seed) &* 77)
            let frameTime: Float = 1.0 / 60
            let maxFrames = Int(leg.length / Double(leg.startSpeed * frameTime)) + 1
            for frame in 0..<maxFrames where sim.distance < leg.length {
                let dt = frame.isMultiple(of: 11) ? 2 * frameTime : frameTime
                let speed = leg.speed(atProgress: sim.distance / leg.length)
                if let lane = autopilot.decide(sim, speed: speed, dt: dt) { sim.setTargetLane(lane) }
                let ctx = (gusts.needsContext || gusts.pushDue(within: dt)) ? sim.gustContext(speed: speed) : nil
                if case .pushed(_, let lane) = gusts.advance(dt: dt, context: ctx) { sim.setTargetLane(lane) }
                sim.step(dt: dt, speed: speed)
                seconds += Double(dt)
            }
            let scenario = "\(difficulty.name), leg \(tier + 1), seed \(seed)"
            #expect(sim.distance >= leg.length, "\(scenario)")
            #expect(sim.stats.hits == 0, "\(scenario)")
            hits += sim.stats.hits
            pushes += gusts.pushes
            passes += gusts.passes
            announced += gusts.announced
        }
    }
    #expect(pushes > 0)
    #expect(hits == 0)
    print("\(difficulty.name): \(Int(seconds)) s flown, \(pushes) pushes (\(String(format: "%.2f", Double(pushes) * 60 / seconds)) per minute), \(announced) warnings, \(passes) passed, \(hits) hits")
}
