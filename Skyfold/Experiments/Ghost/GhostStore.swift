import Foundation

/// The saved ghost for each departure airport and difficulty: one small JSON file in Application
/// Support per pair, holding the best run's tracks. Plain file work, so it is safe off the main actor.
nonisolated enum GhostStore {
    private static func url(route: Int, difficulty: String) -> URL? {
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true) else { return nil }
        let dir = base.appendingPathComponent("Ghosts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ghost-\(route)-\(difficulty).json")
    }

    static func load(route: Int, difficulty: String) -> GhostRun? {
        guard let url = url(route: route, difficulty: difficulty),
              let data = try? Data(contentsOf: url),
              let run = try? JSONDecoder().decode(GhostRun.self, from: data),
              run.startRoute == route, run.difficulty == difficulty else { return nil }
        return run
    }

    @discardableResult
    static func save(_ run: GhostRun) -> Bool {
        guard let url = url(route: run.startRoute, difficulty: run.difficulty),
              let data = try? JSONEncoder().encode(run) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// Saves `run` when it beats the stored ghost for its pair. Returns true when it was stored.
    static func saveIfBest(_ run: GhostRun) -> Bool {
        let best = load(route: run.startRoute, difficulty: run.difficulty)?.score
        guard GhostRun.shouldSave(score: run.score, previousBest: best) else { return false }
        return save(run)
    }
}

#if DEBUG
extension GhostStore {
    /// `-SkyfoldGhostPlant YES`: stores a made-up ghost for the pair on launch, so screenshots do not
    /// need a finished run first. It flies each leg 6% faster than the leg's speed plan and changes
    /// lane every few seconds.
    static func plantDebugGhost(startRoute: Int, difficulty: Difficulty) {
        guard UserDefaults.standard.bool(forKey: "SkyfoldGhostPlant") else { return }
        var legs: [GhostLeg] = []
        for n in 0..<6 {
            let plan = LegPlan.plan(fromRoute: startRoute + n, legsCompleted: n, startRoute: startRoute,
                                    difficulty: difficulty, tuning: RunTuning())
            var rec = GhostRecorder()
            rec.beginLeg(length: plan.length)
            var dist = 0.0
            var t: Float = 0
            let dt: Float = 1.0 / 60
            let lanes: [Float] = [1, 2, 2, 0, 1, 1, 2, 1, 0, 0]
            while dist < plan.length {
                t += dt
                let speed = Double(plan.speed(atProgress: dist / plan.length)) * 1.06
                dist += speed * Double(dt)
                let k = Int(t / 3.2)
                let from = lanes[k % lanes.count], to = lanes[(k + 1) % lanes.count]
                let u = min(max((t - Float(k) * 3.2) / 0.35 - 7, 0), 1)
                rec.advance(dt: dt, distance: dist, altitude: (from + (to - from) * u) * World.laneSpacing)
            }
            rec.closeLeg()
            legs.append(contentsOf: rec.legs)
        }
        save(GhostRun(score: 1, startRoute: startRoute, difficulty: difficulty.id.rawValue, legs: legs))
    }
}
#endif
