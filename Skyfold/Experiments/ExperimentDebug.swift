import Foundation

#if DEBUG
/// Launch arguments for screenshots of the experiments (Debug builds only).
///
/// - `-SkyfoldQuitAfter <seconds>`: ends the run that long after the world is created, so the game-over
///   ticket can be photographed after a flight that really happened (use with `-SkyfoldAutopilot YES`).
/// - `-SkyfoldExperimentsReset YES`: clears ghosts, daily bests and postcard dates at launch.
/// - `-SkyfoldGhostPlant YES` (see `GhostStore`) with `-SkyfoldGhostPace 1.12` sets how much faster
///   the planted ghost flies than the leg's speed plan.
enum ExperimentDebug {
    static func armQuit(_ session: RunSession) {
        let seconds = UserDefaults.standard.double(forKey: "SkyfoldQuitAfter")
        guard seconds > 0 else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            session.quit()
        }
    }
}
#endif
