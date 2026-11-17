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
        if let mode = DebugFlags.progress { DebugProgressSeed.apply(mode, to: progress) }
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

    /// Daily route experiment: flies today's fixed route (its airport, difficulty and seeds), with the
    /// chosen skin. The departure airport is not unlocked by starting there.
    func startDailyRun(_ route: DailyRoute = .today) {
        sanitizeLoadout()
        run = RunSession(difficulty: route.difficulty,
                         skin: PlaneSkin.get(settings.selectedSkin),
                         startRoute: route.startRoute,
                         timeOfDayMode: settings.timeOfDay,
                         progress: progress,
                         daily: route)
        screen = .flight
    }

    /// Restarts immediately with the same loadout (from the game-over card).
    func restartRun() {
        if let daily = run?.daily { startDailyRun(daily) } else { startRun() }
    }

    func exitToMenu() {
        run?.quit()
        run = nil
        screen = .menu
    }

    /// Clears the logbook and unlocks, including any selected loadout that became locked.
    func resetProgress() {
        progress.resetAll()
        sanitizeLoadout()
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
