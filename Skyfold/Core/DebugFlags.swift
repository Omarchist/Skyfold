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

    static var legLengthScale: Double { shortLegs ? 0.15 : 1 }
}
