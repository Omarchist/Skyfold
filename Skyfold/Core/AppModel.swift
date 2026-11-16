import Foundation
import Observation

nonisolated enum AppScreen: Equatable, Sendable {
    case menu
    case flight
}

/// App-wide state: settings, saved progress, and which screen is showing.
/// Injected into SwiftUI with `.environment(model)`.
@Observable
final class AppModel {
    let settings: GameSettings
    let progress: ProgressStore

    private(set) var screen: AppScreen = .menu
    /// The current run, while `screen == .flight`.
    private(set) var run: RunSession?

    init(settings: GameSettings = GameSettings(), progress: ProgressStore = ProgressStore()) {
        self.settings = settings
        self.progress = progress
        #if DEBUG
        if DebugFlags.unlockAll { progress.unlockEverything() }
        #endif
        if let raw = DebugFlags.timeOfDay, let mode = TimeOfDayMode(rawValue: raw) {
            settings.timeOfDay = mode
        }
        sanitizeLoadout()
        if DebugFlags.autostart { startRun() }
    }

    /// Starts a new run with the current loadout (difficulty, skin, departure airport).
    func startRun() {
        sanitizeLoadout()
        run = RunSession(difficulty: Difficulty.get(settings.selectedDifficulty),
                         skin: PlaneSkin.get(settings.selectedSkin),
                         startRoute: settings.selectedAirport,
                         timeOfDayMode: settings.timeOfDay,
                         progress: progress)
        screen = .flight
    }

    /// Restarts immediately with the same loadout (from the game-over card).
    func restartRun() { startRun() }

    func exitToMenu() {
        run?.quit()
        run = nil
        screen = .menu
    }

    /// Nightness for menu screens (0 = day, 1 = night).
    func menuNightness(date: Date = .now) -> Double {
        TimeOfDay.menuNightness(mode: settings.timeOfDay, date: date)
    }

    /// Falls back to unlocked defaults if saved selections are locked (e.g. after a reset).
    private func sanitizeLoadout() {
        if !progress.isUnlocked(settings.selectedSkin) { settings.selectedSkin = .classic }
        if !progress.isUnlocked(settings.selectedDifficulty) { settings.selectedDifficulty = .standard }
        if !progress.isAirportUnlocked(settings.selectedAirport) { settings.selectedAirport = 0 }
    }
}
