import Foundation

/// Everything the rules need from the run for one leg.
struct FlightConfig {
    var leg: LegPlan
    /// Stars within one lane drift toward the plane (Lucky Draw).
    var magnet = false
    /// Chance (0...1) that a bird drifts one lane while approaching (Restless Flock).
    var wanderingBirds: Float = 0
    /// Seconds a player needs before a lane change starts. Row spacing always leaves room for it.
    var reactionTime: Float = 0.35
    /// Extra seconds the spawner adds on top of `reactionTime` when it spaces rows, so a player
    /// who reacts a little slower than the model (or swipes a beat late) is still safe.
    /// The autopilot plans with `reactionTime` only, so it always has this much to spare.
    var graceTime: Float = 0.12

    init(leg: LegPlan, tuning: RunTuning = RunTuning()) {
        self.leg = leg
        magnet = tuning.magnet
        wanderingBirds = tuning.wanderingBirds
    }

    /// The reaction time rows are designed for: model reaction plus grace.
    var designReaction: Float { reactionTime + graceTime }

    /// No rows are placed closer than this to the end of the leg, so the city approach is clear.
    /// (Shorter on very short debug legs, so they still get a few rows.)
    var clearApproach: Double { min(60, leg.length * 0.3) }
    /// Seconds a wandering bird takes to drift one lane.
    static let wanderDuration: Float = 0.5
}

/// Counters for tests and debugging.
struct FlightStats {
    var rows = 0
    var obstacles = 0
    var twoLaneRows = 0
    var wanderers = 0
    var starsSpawned = 0
    var starsCollected = 0
    var nearMisses = 0
    var hits = 0
    /// Smallest spare time (s) any row left beyond `reactionTime` + lane switching, for the
    /// worst-placed lane. The spawner aims for at least `graceTime`.
    var minSlack: Float = .greatestFiniteMagnitude
    /// Times the spawner found no reachable free lane (must stay 0).
    var unfairRows = 0
    /// Star lines and arcs placed.
    var starGroups = 0
    /// Star groups that were shortened or skipped because the first stars could not be reached in time.
    var starGroupsTrimmed = 0
    /// Obstacles or stars that found no free slot (must stay 0 at the shipped capacities).
    var droppedObstacles = 0
    var droppedStars = 0
    /// Rows pushed out of the ring before they passed (must stay 0).
    var rowOverflows = 0
}

/// The 2D rules of a leg: plane, obstacles, stars, spawner, collisions, magnet and wandering birds.
///
/// A value type stepped with `dt`. All storage is fixed-capacity and preallocated in `init`;
/// `step` never allocates. Obstacle `x` is meters ahead of the plane (the plane stays at x = 0).
struct FlightSimulation {
    static let obstacleCapacity = 48
    static let starCapacity = 96
    static let rowCapacity = 24
    /// Room reserved for one step's events (a step can pick up several stars and pass several obstacles).
    static let eventCapacity = 64
    /// Longest slice of time a single `step` will simulate; longer frames are clipped.
    static let maxStep: Float = 1.0 / 20.0

    private(set) var config: FlightConfig
    private(set) var plane = PlaneState()
    /// Fixed-size slot arrays; check `isActive`.
    private(set) var obstacles: [Obstacle]
    private(set) var stars: [Star]
    /// Leg distance flown (m).
    private(set) var distance: Double = 0
    /// Events produced by the last `step` (cleared at the start of each step).
    private(set) var events: [FlightEvent]
    private(set) var stats = FlightStats()
    /// While positive, obstacles pass through the plane (after a shield pop or a revive).
    ///
    /// Granting more of it (a shield pop, a revive: however the engine does it) re-checks the rows
    /// ahead for the moment the protection ends, when the plane may be in any lane. See `replanAfterGrace`.
    /// The sim keeps this above zero for as long as `isProtected`, so a blink driven by it never stops early.
    var invulnerability: Float = 0 {
        didSet { if !suspendReplan, invulnerability > oldValue + 1e-6 { replanAfterGrace() } }
    }
    /// True while obstacles cannot hit the plane: invulnerability time is left, or the plane is still
    /// inside the stretch of rows that `replanAfterGrace` protected it through.
    var isProtected: Bool { invulnerability > 0 || distance < guardUntil }
    /// Leg distance up to which hits are ignored whatever the clock says (the clock runs in seconds,
    /// but what matters for fairness is which rows the plane has passed).
    private var guardUntil: Double = -.infinity
    private var suspendReplan = false

    // Rows, oldest first, in a ring buffer.
    private var rowRing: [ObstacleRow]
    private var rowHead = 0
    private(set) var rowCount = 0

    private var rng: SplitMix64
    private var nextID: UInt32 = 1
    /// Set by `setTargetLane`, reported as an event by the next `step`.
    private var laneChangePending = false
    private var spawner = SpawnerState()

    init(config: FlightConfig, startDistance: Double = 0, lane: Int = World.middleLane, seed: UInt64 = 1) {
        self.config = config
        obstacles = Array(repeating: Obstacle(), count: Self.obstacleCapacity)
        stars = Array(repeating: Star(), count: Self.starCapacity)
        rowRing = Array(repeating: ObstacleRow(), count: Self.rowCapacity)
        events = []
        events.reserveCapacity(Self.eventCapacity)
        rng = SplitMix64(seed: seed)
        reset(config: config, startDistance: startDistance, lane: lane, seed: seed)
    }

    /// Starts a new leg (or restarts this one): clears everything and replans from `startDistance`.
    mutating func reset(config: FlightConfig, startDistance: Double = 0, lane: Int = World.middleLane,
                        seed: UInt64) {
        self.config = config
        for i in obstacles.indices { obstacles[i] = Obstacle() }
        for i in stars.indices { stars[i] = Star() }
        rowHead = 0
        rowCount = 0
        events.removeAll(keepingCapacity: true)
        laneChangePending = false
        stats = FlightStats()
        guardUntil = -.infinity
        invulnerability = 0
        rng = SplitMix64(seed: seed)
        distance = startDistance
        let l = min(max(lane, 0), World.laneCount - 1)
        plane = PlaneState()
        plane.lane = l
        plane.y = World.laneY(l)
        plane.moveFrom = plane.y
        plane.moveTo = plane.y
        spawner = SpawnerState()
        // A negative start distance is the takeoff run: rows are still planned from the leg's zero.
        spawner.prevDistance = max(0, startDistance)
        spawner.prevReach = 0
        spawner.prevReachable = Lanes.all
        spawner.breatherIn = 8 + rng.int(4)
        spawner.isFirst = true
        planNextRow()
    }

    // MARK: - Rows (read access for the autopilot)

    func row(_ i: Int) -> ObstacleRow { rowRing[(rowHead + i) % Self.rowCapacity] }

    // MARK: - Input

    /// Points the plane at `lane` (clamped). Returns false if it already was the target.
    @discardableResult
    mutating func setTargetLane(_ lane: Int) -> Bool {
        let l = min(max(lane, 0), World.laneCount - 1)
        guard l != plane.lane else { return false }
        plane.lane = l
        plane.moveFrom = plane.y
        plane.moveTo = World.laneY(l)
        plane.moveElapsed = 0
        plane.moveDuration = abs(plane.moveTo - plane.moveFrom) / World.laneSpacing * config.leg.laneSwitchTime
        laneChangePending = true
        return true
    }

    /// Snaps the plane to a lane with no movement (new leg, revive).
    mutating func placePlane(lane: Int) {
        let l = min(max(lane, 0), World.laneCount - 1)
        plane = PlaneState()
        plane.lane = l
        plane.y = World.laneY(l)
        plane.moveFrom = plane.y
        plane.moveTo = plane.y
    }

    // MARK: - Engine hooks

    /// Removes one obstacle (a shield absorbed it).
    mutating func removeObstacle(slot: Int) {
        guard obstacles.indices.contains(slot) else { return }
        obstacles[slot].id = 0
    }

    /// A shield absorbed the hit reported for `slot`: removes that obstacle and gives a moment
    /// of invulnerability so a neighbouring obstacle in the same row cannot hit in the same breath.
    mutating func absorbHit(slot: Int, invulnerableFor seconds: Float = 1) {
        removeObstacle(slot: slot)
        invulnerability = max(invulnerability, seconds)
    }

    /// Clears obstacles (and their rows) closer than `meters` ahead, e.g. after a revive.
    mutating func clearObstacles(within meters: Float) {
        // A row's obstacles all sit at the row's x, so an obstacle goes with its row. (Clearing by the
        // obstacle's own edge would leave an orphan in the band where the row's reach, which includes
        // the plane radius, is popped but the obstacle's edge is not: an obstacle no row knows about,
        // which the spawner's chain and the autopilot would both fly into.)
        var poppedX = -Float.greatestFiniteMagnitude
        while rowCount > 0, rowRing[rowHead].x - rowRing[rowHead].reach < meters {
            poppedX = max(poppedX, rowRing[rowHead].x)
            popRow()
        }
        for i in obstacles.indices where obstacles[i].isActive {
            if obstacles[i].x - obstacles[i].halfWidth < meters || obstacles[i].x <= poppedX + 0.01 {
                obstacles[i].id = 0
            }
        }
    }

    /// After a revive: clears what is close ahead and gives a couple of seconds of invulnerability.
    /// The rows beyond `meters` were planned with the whole reachable set in mind, so the leg
    /// stays fair from the moment play resumes.
    mutating func revive(clearAhead meters: Float = 25, invulnerableFor seconds: Float = 2) {
        clearObstacles(within: meters)
        invulnerability = max(invulnerability, seconds)
    }

    /// Called whenever invulnerability is granted (a shield pop, a revive: however the engine does it).
    ///
    /// When the protection ends the plane can be in ANY lane: the one it was hit in, or wherever the
    /// player left it. The rows ahead were planned on the assumption that the plane comes through each
    /// row in a lane the row before it leaves reachable, so that chain is rebuilt from "any lane" at
    /// the moment the protection ends:
    ///  - the protection is counted in meters as well as seconds (`guardUntil`), so it covers the
    ///    distance this grant is worth even if the plane is slower than the clock assumes;
    ///  - a row that starts inside the protected stretch is flown through, and so is the rest of it;
    ///  - after that a row keeps its place only if a player in any lane can still reach one of its free
    ///    lanes in time, by the spawner's own spacing rule. A row that fails is flown through as well
    ///    (the protection runs to its far edge) and the chain starts over after it.
    /// The spawner then carries on from the last row. Nothing is ever removed, so no obstacle pops out
    /// of the sky; the plane just keeps blinking a moment longer in the rare case a row is too close.
    private mutating func replanAfterGrace() {
        let leg = config.leg
        let length = max(leg.length, 1)
        let lst = max(leg.laneSwitchTime, 0.01)
        let react = config.designReaction
        let here = distance
        let v0 = max(leg.speed(atProgress: min(1, max(0, here) / length)), 0.5)
        // Upper bound on the distance covered while protected (speed only rises within a leg).
        let vGrace = leg.speed(atProgress: min(1, max(0, here + Double(v0 * invulnerability) * 1.2) / length)) * 1.04
        var graceEnd = max(vGrace, 0.5) * invulnerability

        var prevX = graceEnd
        var prevReach: Float = 0
        var prevReachable = Lanes.all
        for i in 0..<rowCount {
            let slot = (rowHead + i) % Self.rowCapacity
            var r = rowRing[slot]
            if r.x + r.reach <= graceEnd { continue }              // passed while protected
            if r.x - r.reach <= graceEnd {                         // starts inside the protected stretch
                graceEnd = r.x + r.reach
                prevX = graceEnd; prevReach = 0; prevReachable = Lanes.all
                continue
            }
            let v = max(leg.speed(atProgress: min(1, max(0, here + Double(r.x)) / length)) * 1.04, 0.5)
            let need = Self.lanesNeeded(from: prevReachable, to: r.free)
            let gap = r.x - prevX
            if gap >= prevReach + r.reach + v * (react + lst * Float(need)) + 0.6 {
                let gapTime = (gap - prevReach - r.reach) / v
                let maxLanes = max(0, Int(((gapTime - react) / lst + 1e-4).rounded(.down)))
                var reachable: LaneMask = 0
                for b in 0..<World.laneCount where Lanes.contains(r.free, b) {
                    for a in 0..<World.laneCount where Lanes.contains(prevReachable, a) && abs(a - b) <= maxLanes {
                        reachable |= Lanes.bit(b)
                    }
                }
                r.reachable = reachable
                rowRing[slot] = r
                prevX = r.x; prevReach = r.reach; prevReachable = reachable
            } else {
                graceEnd = r.x + r.reach                           // too close for a player in any lane: protect through it
                prevX = graceEnd; prevReach = 0; prevReachable = Lanes.all
            }
        }
        guardUntil = max(guardUntil, here + Double(graceEnd) + 0.5)
        spawner.prevDistance = here + Double(prevX)
        spawner.prevReach = prevReach
        spawner.prevReachable = prevReachable
        planNextRow()
    }

    /// Puts one obstacle at `x` meters ahead, outside the spawner's fairness planning. For tests,
    /// tutorials and scripted sequences; returns the slot used, or nil if the array is full.
    @discardableResult
    mutating func placeObstacle(kind: ObstacleKind, lane: Int, x: Float) -> Int? {
        guard let slot = obstacles.firstIndex(where: { !$0.isActive }) else { return nil }
        var o = Obstacle()
        o.id = nextID; nextID &+= 1
        o.kind = kind
        o.x = x
        o.lane = kind.fixedBaseLane ?? min(max(lane, 0), World.laneCount - 1)
        o.y = kind.centerY(lane: o.lane)
        obstacles[slot] = o
        return slot
    }

    /// Obstacles currently alive.
    var activeObstacleCount: Int {
        var n = 0
        for o in obstacles where o.isActive { n += 1 }
        return n
    }

    /// Stars currently alive (including ones playing their pickup pop).
    var activeStarCount: Int {
        var n = 0
        for s in stars where s.isActive { n += 1 }
        return n
    }

    // MARK: - Step

    /// Advances the world by `dt` seconds at `speed` m/s.
    /// - Parameters:
    ///   - spawning: place new rows and stars (off while landing).
    ///   - collisions: detect hits (off while landing).
    mutating func step(dt rawDt: Float, speed: Float, spawning: Bool = true, collisions: Bool = true) {
        events.removeAll(keepingCapacity: true)
        guard rawDt > 0 else { return }
        let dt = min(rawDt, Self.maxStep)
        if laneChangePending {
            laneChangePending = false
            events.append(.laneChanged(lane: plane.lane))
        }
        let dx = max(speed, 0) * dt
        distance += Double(dx)
        if invulnerability > 0 { invulnerability = max(0, invulnerability - dt) }
        if distance < guardUntil, invulnerability < 0.05 {
            suspendReplan = true
            invulnerability = 0.05
            suspendReplan = false
        }

        stepPlane(dt: dt)
        stepRows(dx: dx)
        stepObstacles(dt: dt, dx: dx, collisions: collisions)
        stepStars(dt: dt, dx: dx)
        if spawning { spawnDue() }
    }

    private mutating func stepPlane(dt: Float) {
        let prevY = plane.y
        if plane.moveElapsed < plane.moveDuration {
            plane.moveElapsed = min(plane.moveDuration, plane.moveElapsed + dt)
            let t = plane.moveDuration > 0 ? plane.moveElapsed / plane.moveDuration : 1
            plane.y = FlightMath.lerp(plane.moveFrom, plane.moveTo, FlightMath.smoothstep(t))
        } else {
            plane.y = plane.moveTo
        }
        plane.vy = (plane.y - prevY) / dt
        let maxV = World.laneSpacing / max(config.leg.laneSwitchTime, 0.05)
        let target = min(max(plane.vy / maxV, -1), 1)
        plane.tilt += (target - plane.tilt) * min(1, dt * 14)
    }

    private mutating func stepRows(dx: Float) {
        for i in 0..<rowCount {
            rowRing[(rowHead + i) % Self.rowCapacity].x -= dx
        }
        while rowCount > 0, rowRing[rowHead].x + rowRing[rowHead].reach < -2 {
            popRow()
        }
    }

    private mutating func stepObstacles(dt: Float, dx: Float, collisions: Bool) {
        let r = World.planeRadius
        let py = plane.y
        var hitThisStep = false
        for i in obstacles.indices where obstacles[i].isActive {
            var o = obstacles[i]
            let oldX = o.x
            o.x -= dx
            o.phase += dt
            if o.x < World.despawnBehindDistance {
                obstacles[i].id = 0
                continue
            }
            // Wandering bird: drift one lane once close enough.
            var baseY = o.kind.centerY(lane: o.lane)
            if o.wanderTo >= 0, o.x <= o.wanderStartX {
                o.wanderT = min(1, o.wanderT + dt / FlightConfig.wanderDuration)
                baseY = FlightMath.lerp(World.laneY(o.lane), World.laneY(o.wanderTo),
                                        FlightMath.smoothstep(o.wanderT))
                if o.wanderT >= 1 {
                    o.lane = o.wanderTo
                    o.wanderTo = -1
                    baseY = World.laneY(o.lane)
                }
            }
            o.y = baseY + o.kind.bobAmplitude * sinf(o.phase * 2.1)

            let hw = o.halfWidth, hh = o.halfHeight
            // Swept test: the obstacle moved from oldX to o.x this step, so test it where it was
            // closest to the plane. A long frame at top speed can never tunnel through a hitbox.
            let sampleX = min(max(0, o.x), oldX)
            if abs(sampleX) < hw + r {
                o.closest = min(o.closest, abs(py - o.y) - hh - r)
                if collisions, !hitThisStep, invulnerability <= 0,
                   FlightMath.circleHitsBox(cx: 0, cy: py, r: r, bx: sampleX, by: o.y, hw: hw, hh: hh) {
                    hitThisStep = true
                    stats.hits += 1
                    events.append(.hit(slot: i))
                }
            }
            if !o.passed, o.x + hw + r < 0 {
                o.passed = true
                if o.closest >= 0, o.closest < 0.3, collisions {
                    stats.nearMisses += 1
                    events.append(.nearMiss)
                }
            }
            obstacles[i] = o
        }
    }

    private mutating func stepStars(dt: Float, dx: Float) {
        let py = plane.y
        let grab = World.planeRadius + 0.34
        for i in stars.indices where stars[i].isActive {
            var s = stars[i]
            let oldX = s.x
            s.x -= dx
            s.phase += dt
            if s.collectAge >= 0 {
                s.collectAge += dt
                if s.collectAge > 0.35 { s.id = 0 }
                stars[i] = s
                continue
            }
            if s.x < World.despawnBehindDistance {
                stars[i].id = 0
                continue
            }
            if config.magnet, s.x > -0.5, s.x < 9, abs(s.y - py) < World.laneSpacing + 0.25 {
                let pull = min(1, dt * (s.x < 4 ? 9 : 4))
                s.y += (py - s.y) * pull
                s.x -= dx * 0.35 // a little eager to arrive
            }
            let ddx = min(max(0, s.x), oldX), ddy = s.y - py   // swept, like the obstacles
            if ddx * ddx + ddy * ddy < grab * grab {
                s.collectAge = 0
                stats.starsCollected += 1
                events.append(.starCollected)
            }
            stars[i] = s
        }
    }

    // MARK: - Spawner

    /// A row the spawner has decided on but not yet placed in the world.
    private struct PlannedRow {
        var distance: Double = 0
        var count = 0
        var kind0: ObstacleKind = .bird, lane0 = 0, wander0 = -1
        var kind1: ObstacleKind = .bird, lane1 = 0
        var blocked: LaneMask = 0
        var reach: Float = 0
        var reachable: LaneMask = Lanes.all
        var maxLanes = 0
        var speedBound: Float = 0
        // The previous row, for star placement.
        var fromDistance: Double = 0
        var fromReach: Float = 0
        var fromReachable: LaneMask = Lanes.all
    }

    private struct SpawnerState {
        var prevDistance: Double = 0
        var prevReach: Float = 0
        var prevReachable: LaneMask = Lanes.all
        var planned: PlannedRow?
        var breatherIn = 10
        var isFirst = true
        /// The last single-lane kind placed, so the same silhouette is not served three times running.
        var lastKind: ObstacleKind?
        var lastKindRun = 0
    }

    private mutating func spawnDue() {
        while let p = spawner.planned, p.distance - distance <= Double(World.spawnAheadDistance) {
            materialize(p)
            spawner.prevDistance = p.distance
            spawner.prevReach = p.reach
            spawner.prevReachable = p.reachable
            planNextRow()
        }
    }

    /// Picks the next row's pattern and distance so that every lane the player could be in at
    /// the previous row can still reach a free lane of this one (no traps, ever).
    private mutating func planNextRow() {
        let leg = config.leg
        let length = max(leg.length, 1)
        let from = spawner.prevDistance
        let p = Float(min(1, max(0, from / length)))
        let lst = leg.laneSwitchTime
        let react = config.designReaction
        let density = min(max(leg.density, 0.4), 2.4)

        // Speed only rises within a leg, so the speed further on bounds the speed at the row.
        var vBound = leg.speed(atProgress: min(1, (from + 90) / length)) * 1.04

        var row = PlannedRow()
        row.fromDistance = from
        row.fromReach = spawner.prevReach
        row.fromReachable = spawner.prevReachable
        choosePattern(&row, progress: p, speed: vBound)

        let free = ~row.blocked & Lanes.all
        let need = Self.lanesNeeded(from: spawner.prevReachable, to: free)

        // How long the player would like to wait between rows: shrinks as the leg goes on.
        let ramp = FlightMath.smoothstep(p)
        var seconds = FlightMath.lerp(2.0, 1.05, ramp) / density * rng.range(0.85, 1.3)
        spawner.breatherIn -= 1
        if spawner.breatherIn <= 0 {
            seconds += 1.3
            spawner.breatherIn = 8 + rng.int(5)
        }

        // Spacing in meters. A long gap means the row sits further along the leg, where the plane
        // is faster, so bound the speed over the whole gap (two passes settle it).
        var gap: Float = 0
        for _ in 0..<3 {
            let required = spawner.prevReach + row.reach + vBound * (react + lst * Float(need)) + 0.6
            gap = max(vBound * seconds, required)
            if spawner.isFirst { gap = max(gap, max(32, vBound * 2.6)) }
            let vAtRow = leg.speed(atProgress: min(1, (from + Double(gap)) / length)) * 1.04
            if vAtRow <= vBound + 1e-3 { break }
            vBound = vAtRow
        }
        spawner.isFirst = false
        row.distance = from + Double(gap)
        row.speedBound = vBound

        // Lanes reachable at this row from any lane reachable at the previous one.
        let gapTime = (gap - spawner.prevReach - row.reach) / vBound
        row.maxLanes = max(0, Int(((gapTime - react) / lst + 1e-4).rounded(.down)))
        var reachable: LaneMask = 0
        for b in 0..<World.laneCount where Lanes.contains(free, b) {
            for a in 0..<World.laneCount where Lanes.contains(spawner.prevReachable, a) && abs(a - b) <= row.maxLanes {
                reachable |= Lanes.bit(b)
            }
        }
        row.reachable = reachable
        stats.minSlack = min(stats.minSlack, gapTime - config.reactionTime - lst * Float(need))
        if reachable == 0 || need > row.maxLanes { stats.unfairRows += 1 }

        if row.distance > length - config.clearApproach {
            spawner.planned = nil
        } else {
            spawner.planned = row
        }
    }

    /// For the worst-placed lane in `from`, how many lanes it must move to reach any lane in `to`.
    static func lanesNeeded(from: LaneMask, to: LaneMask) -> Int {
        var worst = 0
        for a in 0..<World.laneCount where Lanes.contains(from, a) {
            var best = Int.max
            for b in 0..<World.laneCount where Lanes.contains(to, b) { best = min(best, abs(a - b)) }
            worst = max(worst, best == .max ? World.laneCount : best)
        }
        return worst
    }

    private mutating func choosePattern(_ row: inout PlannedRow, progress p: Float, speed: Float) {
        let density = min(max(config.leg.density, 0.4), 2.4)
        let twoLaneChance = min(0.72, (0.1 + 0.5 * p) * min(density, 1.7))
        if rng.chance(twoLaneChance) {
            let r = rng.unit()
            if r < 0.24 {
                setRow(&row, kind: .tower, lane: 0)
            } else if r < 0.46 {
                setRow(&row, kind: .thunderhead, lane: 1)
            } else {
                // Two single-lane obstacles, one lane left open.
                let open = rng.int(World.laneCount)
                let a = (open + 1) % World.laneCount, b = (open + 2) % World.laneCount
                row.count = 2
                row.kind0 = singleKind(allowWander: false); row.lane0 = min(a, b)
                row.kind1 = singleKind(allowWander: false); row.lane1 = max(a, b)
                row.blocked = Lanes.bit(a) | Lanes.bit(b)
                row.reach = max(row.kind0.halfWidth, row.kind1.halfWidth) + World.planeRadius
            }
        } else {
            let kind = singleKind(allowWander: true)
            let lane = rng.int(World.laneCount)
            setRow(&row, kind: kind, lane: lane)
            if kind == .bird, config.wanderingBirds > 0, rng.chance(config.wanderingBirds),
               wanderLeadDistance(speed: speed * 1.05) <= World.spawnAheadDistance - 2 {
                // Drift one lane (up or down). Both lanes count as blocked for fairness, which
                // always leaves the third lane free.
                let to = lane == 0 ? 1 : lane == 2 ? 1 : (rng.chance(0.5) ? 0 : 2)
                row.wander0 = to
                row.blocked |= Lanes.bit(to)
            }
        }
    }

    /// How far ahead a wandering bird must start its drift so that a player sitting in the lane it
    /// drifts into can still react and move two lanes before reaching it.
    private func wanderLeadDistance(speed: Float) -> Float {
        ObstacleKind.bird.halfWidth + World.planeRadius
            + speed * (config.designReaction + 2 * config.leg.laneSwitchTime + FlightConfig.wanderDuration) + 3
    }

    /// Where (m ahead of the plane) a wandering bird starts to drift. Early enough that a player
    /// who sat in the destination lane can still react and move two lanes before reaching the bird.
    private func wanderStart(kind: ObstacleKind, x: Float, speedBound: Float) -> Float {
        let needed = kind.halfWidth + World.planeRadius
            + speedBound * (config.designReaction + 2 * config.leg.laneSwitchTime + FlightConfig.wanderDuration) + 3
        return min(x - 1, max(18, needed))
    }

    private func setRow(_ row: inout PlannedRow, kind: ObstacleKind, lane: Int) {
        row.count = 1
        row.kind0 = kind
        row.lane0 = kind.fixedBaseLane ?? lane
        row.blocked = kind.blockedMask(lane: row.lane0)
        row.reach = kind.halfWidth + World.planeRadius
    }

    private mutating func singleKind(allowWander: Bool) -> ObstacleKind {
        var kind = weightedSingleKind(allowWander: allowWander)
        // Variety: never the same silhouette three rows running.
        if kind == spawner.lastKind, spawner.lastKindRun >= 2 {
            kind = weightedSingleKind(allowWander: allowWander)
            if kind == spawner.lastKind { kind = ObstacleKind(rawValue: (kind.rawValue + 1 + rng.int(3)) % 4) ?? .bird }
        }
        if kind == spawner.lastKind { spawner.lastKindRun += 1 } else { spawner.lastKind = kind; spawner.lastKindRun = 1 }
        return kind
    }

    private mutating func weightedSingleKind(allowWander: Bool) -> ObstacleKind {
        // Restless Flock brings more birds so the curse is noticeable.
        let birdWeight: Float = 0.3 + (allowWander ? config.wanderingBirds * 0.4 : 0)
        let total = birdWeight + 0.22 + 0.2 + 0.26
        var r = rng.unit() * total
        r -= birdWeight; if r < 0 { return .bird }
        r -= 0.22; if r < 0 { return .balloons }
        r -= 0.2; if r < 0 { return .kite }
        return .stormCloud
    }

    private mutating func materialize(_ p: PlannedRow) {
        let x = Float(p.distance - distance)
        let rowID = nextID; nextID &+= 1
        stats.rows += 1
        if p.count == 2 || p.kind0.spansTwoLanes { stats.twoLaneRows += 1 }
        spawnObstacle(kind: p.kind0, lane: p.lane0, x: x, wanderTo: p.wander0, speedBound: p.speedBound)
        if p.count == 2 {
            spawnObstacle(kind: p.kind1, lane: p.lane1, x: x, wanderTo: -1, speedBound: p.speedBound)
        }
        var latent: LaneMask = 0
        var latentStart: Float = 0
        if p.wander0 >= 0 {
            latent = Lanes.bit(p.wander0)
            latentStart = wanderStart(kind: p.kind0, x: x, speedBound: p.speedBound)
        }
        pushRow(ObstacleRow(id: rowID, x: x, reach: p.reach, blocked: p.blocked, reachable: p.reachable,
                            latent: latent, latentStartX: latentStart))
        placeStars(for: p)
    }

    private mutating func spawnObstacle(kind: ObstacleKind, lane: Int, x: Float, wanderTo: Int, speedBound: Float) {
        guard let slot = obstacles.firstIndex(where: { !$0.isActive }) else {
            stats.droppedObstacles += 1
            return
        }
        var o = Obstacle()
        o.id = nextID; nextID &+= 1
        o.kind = kind
        o.x = x
        o.lane = lane
        o.phase = rng.range(0, 6.28)
        o.wanderTo = wanderTo
        if wanderTo >= 0 {
            o.wanderStartX = wanderStart(kind: kind, x: x, speedBound: speedBound)
            stats.wanderers += 1
        }
        o.y = kind.centerY(lane: lane)
        obstacles[slot] = o
        stats.obstacles += 1
    }

    /// Stars in a line or an arc that trace a safe path into this row's free lane.
    ///
    /// Every star can be collected by a player who starts in a lane the previous row left
    /// reachable, reacts in `reactionTime` and then flies the path: lines are shortened so their
    /// first star comes after the lane change would be finished, and an arc's curve starts no
    /// earlier than the moment that player can first start moving.
    private mutating func placeStars(for p: PlannedRow) {
        guard rng.chance(0.55), p.reachable != 0 else { return }
        let v = p.speedBound
        let lst = config.leg.laneSwitchTime
        let react = config.reactionTime
        let spacing = 1.9
        // Destination: a reachable free lane. Source: a lane the player can be in after the previous row.
        let b = randomLane(in: p.reachable)
        var sources: LaneMask = 0
        for a in 0..<World.laneCount where Lanes.contains(p.fromReachable, a) && abs(a - b) <= p.maxLanes {
            sources |= Lanes.bit(a)
        }
        guard sources != 0 else { return }
        let a = randomLane(in: sources)
        let clear = p.fromDistance + Double(p.fromReach)   // where the plane has just cleared the previous row
        let end = p.distance                                // the last star sits in the row, in the free lane
        let lanesMoved = abs(a - b)
        stats.starGroups += 1

        if lanesMoved > 0, rng.chance(0.6) {
            // An arc: hold lane a, curve across, finish in lane b. One lane change, flown in step with the stars.
            let moveMeters = Double(v * lst * Float(lanesMoved))
            let nCurve = max(2, Int((moveMeters / spacing).rounded()))
            let nHold = 1 + rng.int(2)
            let nTail = 2
            let total = nHold + nCurve + nTail
            let first = end - Double(total - 1) * spacing
            let curveStart = first + Double(nHold) * spacing
            if first >= clear + 0.8, curveStart >= clear + Double(v * react) + 0.4 {
                for i in 0..<total {
                    let d = first + Double(i) * spacing
                    var y = World.laneY(a)
                    if i >= nHold + nCurve {
                        y = World.laneY(b)
                    } else if i >= nHold {
                        let t = Float(i - nHold + 1) / Float(nCurve + 1)
                        y = FlightMath.lerp(World.laneY(a), World.laneY(b), FlightMath.smoothstep(t))
                    }
                    addStar(atDistance: d, y: y)
                }
                return
            }
        }

        // A straight line in lane b. If the player has to change lane first, only the stars that
        // come after the move (a bit before it ends, the plane is already near enough to grab).
        let lineFrom = Lanes.contains(sources, b) ? b : a
        let move = abs(lineFrom - b)
        let arrive = clear + Double(v * (react + 0.7 * lst * Float(move))) + 0.3
        let lowest = max(clear + 0.8, arrive)
        var count = 0
        let wanted = 3 + rng.int(4)
        while count < wanted, end - Double(count) * spacing >= lowest { count += 1 }
        if count < wanted { stats.starGroupsTrimmed += 1 }
        guard count >= 3 else { return }
        for i in 0..<count {
            addStar(atDistance: end - Double(i) * spacing, y: World.laneY(b))
        }
    }

    private mutating func randomLane(in mask: LaneMask) -> Int {
        let count = mask.nonzeroBitCount
        guard count > 0 else { return World.middleLane }
        var k = rng.int(count)
        for lane in 0..<World.laneCount where Lanes.contains(mask, lane) {
            if k == 0 { return lane }
            k -= 1
        }
        return World.middleLane
    }

    private mutating func addStar(atDistance d: Double, y: Float) {
        let x = Float(d - distance)
        guard x > 2 else { return }
        guard let slot = stars.firstIndex(where: { !$0.isActive }) else {
            stats.droppedStars += 1
            return
        }
        stars[slot] = Star(id: nextID, x: x, y: y, phase: rng.range(0, 6.28), collectAge: -1)
        nextID &+= 1
        stats.starsSpawned += 1
    }

    // MARK: Row ring

    private mutating func pushRow(_ row: ObstacleRow) {
        if rowCount == Self.rowCapacity {
            stats.rowOverflows += 1
            popRow()
        }
        rowRing[(rowHead + rowCount) % Self.rowCapacity] = row
        rowCount += 1
    }

    private mutating func popRow() {
        guard rowCount > 0 else { return }
        rowHead = (rowHead + 1) % Self.rowCapacity
        rowCount -= 1
    }
}
