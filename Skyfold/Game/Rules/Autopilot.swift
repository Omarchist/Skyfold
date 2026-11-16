import Foundation

/// Picks a safe lane by looking at the upcoming obstacle rows. Used when
/// `DebugFlags.autopilot` is on, for the menu attract mode, and by the headless fairness test.
///
/// It plays like a careful human with a reaction delay: after the plane clears a row it waits
/// `reactionDelay` seconds before starting a lane change, and it never changes lanes while
/// overlapping a row. If the spawner's spacing were unfair, this player would get hit.
///
/// Stars only ever break ties between lanes that are already safe: the lane is chosen from the
/// set of lanes that can still survive the next `lookahead` rows, so a greedy pilot cannot
/// fly itself into a corner.
struct Autopilot {
    var reactionDelay: Float
    /// Seconds of lane-change time the pilot will spend per star it can still catch before the
    /// next row. 0 plays purely for safety.
    var starWeight: Float
    /// true: the pilot knows from the start which lane a wandering bird will drift into (the default,
    /// and what the menu's attract mode uses). false: it only sees what a player sees, so a bird
    /// counts as blocking its own lane until it starts to drift, and the pilot only takes the drift
    /// into account `reactionDelay` seconds after it started. The fairness test flies both.
    var anticipatesWanderers = true
    private var lastClearedRow: UInt32 = 0
    private var sinceCleared: Float = 0
    /// Rows whose wandering bird has started to drift (a few most recent ids) and how long ago (s).
    private var revealedRows: [UInt32] = [0, 0, 0, 0, 0, 0, 0, 0]
    private var revealedAge: [Float] = [0, 0, 0, 0, 0, 0, 0, 0]
    private var revealedNext = 0
    /// How many rows ahead to plan through.
    static let lookahead = 8

    init(reactionDelay: Float = 0.35, starWeight: Float = 0.02) {
        self.reactionDelay = reactionDelay
        self.starWeight = starWeight
    }

    mutating func reset() {
        lastClearedRow = 0
        sinceCleared = 0
        for i in revealedRows.indices { revealedRows[i] = 0; revealedAge[i] = 0 }
        revealedNext = 0
    }

    /// Lanes the pilot believes are free in `row`.
    private func freeLanes(_ row: ObstacleRow) -> LaneMask {
        if anticipatesWanderers || row.latent == 0 { return row.free }
        if row.isRevealed, let k = revealedRows.firstIndex(of: row.id), revealedAge[k] >= reactionDelay {
            return row.free   // the drift has been noticed
        }
        return ~(row.blocked & ~row.latent) & Lanes.all   // the bird still looks like it holds its own lane
    }

    /// Keeps the clock on every drift that has started, so it is noticed `reactionDelay` seconds later.
    private mutating func trackDrifts(_ sim: FlightSimulation, from first: Int, dt: Float) {
        for k in revealedRows.indices where revealedRows[k] != 0 { revealedAge[k] += dt }
        var i = first
        while i < sim.rowCount {
            let row = sim.row(i)
            i += 1
            guard row.latent != 0, row.isRevealed, !revealedRows.contains(row.id) else { continue }
            revealedRows[revealedNext] = row.id
            revealedAge[revealedNext] = 0
            revealedNext = (revealedNext + 1) % revealedRows.count
        }
    }

    /// Returns the lane the plane should head for, or nil to keep the current target.
    mutating func decide(_ sim: FlightSimulation, speed: Float, dt: Float) -> Int? {
        let v = max(speed, 0.5)
        let lst = sim.config.leg.laneSwitchTime
        let react = sim.config.reactionTime
        sinceCleared += dt

        // The first row not yet cleared; the row just before it is the most recently cleared one.
        var first = -1
        var newestCleared: UInt32 = 0
        for i in 0..<sim.rowCount {
            let row = sim.row(i)
            if row.x + row.reach < 0 {
                newestCleared = row.id
                continue
            }
            first = i
            break
        }
        if newestCleared != 0, newestCleared != lastClearedRow {
            lastClearedRow = newestCleared
            sinceCleared = 0
        }
        guard first >= 0 else { return nil }
        if !anticipatesWanderers { trackDrifts(sim, from: first, dt: dt) }
        let next = sim.row(first)
        if next.x - next.reach <= 0 { return nil } // committed: inside this row
        guard sinceCleared >= reactionDelay else { return nil }

        // Backward DP: safe[j] = free lanes of row j from which some safe lane of row j+1 is
        // reachable in the gap (after the reaction delay).
        let last = min(sim.rowCount - 1, first + Self.lookahead - 1)
        var safeNext: LaneMask = Lanes.all
        var j = last
        var safeFirst: LaneMask = 0
        while j >= first {
            let row = sim.row(j)
            var safe: LaneMask = 0
            if j == last {
                safe = freeLanes(row)
            } else {
                let following = sim.row(j + 1)
                // Speed creeps up within a leg, so plan later gaps a touch pessimistically
                // (still inside the margin the spawner leaves).
                let gapTime = (following.x - following.reach - row.x - row.reach) / (v * 1.03) - react
                let maxLanes = gapTime < 0 ? -1 : Int((gapTime / lst + 1e-4).rounded(.down))
                for l in 0..<World.laneCount where Lanes.contains(freeLanes(row), l) {
                    for n in 0..<World.laneCount where Lanes.contains(safeNext, n) && abs(l - n) <= maxLanes {
                        safe |= Lanes.bit(l)
                    }
                }
                if safe == 0 { safe = freeLanes(row) } // shouldn't happen; fall back to anything free
            }
            safeNext = safe
            if j == first { safeFirst = safe }
            j -= 1
        }

        let timeLeft = (next.x - next.reach) / v
        let y = sim.plane.y
        let current = sim.plane.lane

        // Stars: among the safe lanes, and the moments to start moving, pick the plan that catches the most.
        if starWeight > 0 {
            let inSafeLane = Lanes.contains(safeFirst, current)
            if sim.plane.isMoving, inSafeLane { return nil }
            switch planStars(sim, safeFirst: safeFirst, speed: v, laneSwitchTime: lst, timeLeft: timeLeft,
                             rowX: next.x, mustMove: !inSafeLane) {
            case .go(let lane): return lane == current ? nil : lane
            case .wait: return nil
            case .noPlan: break
            }
        }

        // Safety only: the reachable safe lane needing the least movement; prefer the current target.
        var best = -1
        var bestCost = Float.greatestFiniteMagnitude
        for l in 0..<World.laneCount where Lanes.contains(safeFirst, l) {
            let moveTime = abs(World.laneY(l) - y) / World.laneSpacing * lst
            var cost = moveTime
            if moveTime > timeLeft { cost += 100 } // too late, only as a last resort
            if l == current { cost -= 0.01 }
            if cost < bestCost { bestCost = cost; best = l }
        }
        guard best >= 0, best != current else { return nil }
        return best
    }

    private enum StarPlan { case go(Int), wait, noPlan }

    /// Searches (safe lane, start delay) for the plan that catches the most stars before the next row.
    /// Every candidate finishes its lane change at least 30 ms before the row, so this can only
    /// pick between plans that are already safe.
    private func planStars(_ sim: FlightSimulation, safeFirst: LaneMask, speed v: Float, laneSwitchTime lst: Float,
                           timeLeft: Float, rowX: Float, mustMove: Bool) -> StarPlan {
        let y0 = sim.plane.y
        let current = sim.plane.lane
        var anyStar = false
        for s in sim.stars where s.isCollectable && s.x >= 0 && s.x <= rowX + 0.5 { anyStar = true; break }
        guard anyStar else { return .noPlan }

        func caught(target: Int, delay: Float, moveTime: Float) -> Int {
            let yT = World.laneY(target)
            var n = 0
            for s in sim.stars where s.isCollectable && s.x >= 0 && s.x <= rowX + 0.5 {
                let t = s.x / v
                var py = y0
                if t >= delay + moveTime {
                    py = yT
                } else if t > delay, moveTime > 0 {
                    py = FlightMath.lerp(y0, yT, FlightMath.smoothstep((t - delay) / moveTime))
                }
                if abs(py - s.y) < 0.55 { n += 1 }
            }
            return n
        }

        var bestCount = -1
        var bestLane = current
        var bestDelay: Float = 0
        if !mustMove {
            bestCount = caught(target: current, delay: 0, moveTime: 0)
        }
        for lane in 0..<World.laneCount where lane != current && Lanes.contains(safeFirst, lane) {
            let moveTime = abs(World.laneY(lane) - y0) / World.laneSpacing * lst
            let maxDelay = min(timeLeft - moveTime - 0.03, 1.2)
            if maxDelay < 0 { continue }
            var d: Float = 0
            while d <= maxDelay {
                let n = caught(target: lane, delay: d, moveTime: moveTime)
                if n > bestCount { bestCount = n; bestLane = lane; bestDelay = d }
                d += 0.02
            }
        }
        if bestCount < 0 { return .noPlan }              // nothing reachable in time: fall back to the safety rule
        if bestLane == current { return .wait }
        return bestDelay <= 1.0 / 60 ? .go(bestLane) : .wait
    }
}
