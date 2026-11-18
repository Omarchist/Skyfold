import Foundation

/// Launch-argument switches for testing, e.g. in Xcode's scheme or with
/// `xcrun simctl launch <device> com.henry.skyfold -SkyfoldAutopilot YES -SkyfoldShortLegs YES`.
/// All are off in normal play.
nonisolated enum DebugFlags {
    private static let defaults = UserDefaults.standard

    /// The plane flies itself (always picks a safe lane). Also used for the menu's attract mode.
    static var autopilot: Bool { defaults.bool(forKey: "SkyfoldAutopilot") }
    /// Legs are ~15% of normal length, to reach cities and airports quickly.
    static var shortLegs: Bool { defaults.bool(forKey: "SkyfoldShortLegs") }
    /// Skip the menu and start a run on launch.
    static var autostart: Bool { defaults.bool(forKey: "SkyfoldAutostart") }
    /// Unlock every skin, difficulty and airport on launch (DEBUG builds only).
    static var unlockAll: Bool { defaults.bool(forKey: "SkyfoldUnlockAll") }

    /// At airports, advance without taps: show the arrival, open a gate, board.
    static var autoGates: Bool { defaults.bool(forKey: "SkyfoldAutoGates") }
    /// Force the time-of-day setting on launch: cycle, clock, day or night.
    static var timeOfDay: String? { defaults.string(forKey: "SkyfoldTimeOfDay") }
    /// Open a menu screen on launch: journal, hangar, atlas or settings.
    static var screen: String? { defaults.string(forKey: "SkyfoldScreen") }

    /// Scripted flight event a few seconds into the first leg, for screenshots:
    /// pause, crash (grants one revive, then hits), shield (grants a shield, then hits),
    /// gameover, newbest (gameover with a high score).
    static var flightScript: String? { defaults.string(forKey: "SkyfoldFlightScript") }

    static var legLengthScale: Double { shortLegs ? 0.15 : 1 }

    /// Show the FPS readout in the flight HUD without touching Settings (DEBUG builds only).
    static var showFPS: Bool {
        #if DEBUG
        defaults.bool(forKey: "SkyfoldShowFPS")
        #else
        false
        #endif
    }

    /// Seconds one full day (day, dusk, night, dawn) takes in flight, so a screenshot run can catch
    /// the transitions: `-SkyfoldDayCycleSeconds 20` (DEBUG builds only). nil = normal.
    static var dayCycleSeconds: Double? {
        #if DEBUG
        let v = defaults.double(forKey: "SkyfoldDayCycleSeconds")
        return v >= 4 ? v : nil
        #else
        nil
        #endif
    }
}

extension DebugFlags {
    /// Seed saved progress on launch, once (DEBUG builds only): `fresh` wipes it, `mid` is a
    /// few cities in, `all` unlocks everything and fills the logbook.
    static var progress: String? { defaults.string(forKey: "SkyfoldProgress") }
}

#if DEBUG
/// Applies `-SkyfoldProgress fresh|mid|all` through ProgressStore's public API.
enum DebugProgressSeed {
    static func apply(_ mode: String, to progress: ProgressStore) {
        switch mode {
        case "fresh":
            progress.resetAll()
        case "mid":
            progress.resetAll()
            for city in 1...3 { progress.recordArrival(routeIndex: city) }
            for id in [ModifierID.tailwind, .tailwind, .tailwind, .paperShield, .secondWind, .headwind, .fogBank, .fogBank] {
                progress.recordModifier(id)
            }
            progress.recordRunEnd(score: 2140, distance: 1650, stars: 18, citiesReached: 2)
            progress.recordRunEnd(score: 4280, distance: 3120, stars: 41, citiesReached: 3)
        case "all":
            progress.resetAll()
            progress.unlockEverything()
            for (i, id) in ModifierID.allCases.enumerated() {
                for _ in 0..<(1 + i % 4) { progress.recordModifier(id) }
            }
            progress.recordRunEnd(score: 18_450, distance: 9_870, stars: 212, citiesReached: 10)
        default:
            break
        }
    }
}
#endif

#if DEBUG
extension DebugFlags {
    /// Screenshots only: `-SkyfoldPlaneDemo stunt|drag` plays a tap-stunt or a drag-and-release
    /// on the interactive menu plane, over and over.
    static var planeDemo: String? { defaults.string(forKey: "SkyfoldPlaneDemo") }
}
#endif
