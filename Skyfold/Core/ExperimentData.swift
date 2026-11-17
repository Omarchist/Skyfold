import Foundation

/// What the experiments keep on the device besides the switches. "Reset progress" clears all of it,
/// whether or not the switches are on now, so an old ghost or daily best never outlives a reset.
enum ExperimentData {
    static func resetAll() {
        DailyBestStore.shared.clear()
        #if canImport(SwiftUI)
        // The app-only stores (`Skyfold/Experiments` is not part of the Linux package).
        GhostStore.clear()
        PostcardStore.shared.clear()
        #endif
    }
}
