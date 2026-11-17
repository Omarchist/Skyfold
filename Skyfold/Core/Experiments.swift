import Foundation
import Observation

/// The experimental features on the `experimental` branch. Each one is off by default and has its
/// own switch in Settings, so the game can be compared with and without it. With a switch off, the
/// game must behave exactly as it does without the feature.
nonisolated enum ExperimentID: String, CaseIterable, Identifiable, Sendable {
    case postcards
    case nearMissBonus
    case windGusts
    case ghostFlight
    case dailyRoute

    var id: String { rawValue }

    var title: String {
        switch self {
        case .postcards: "Postcards"
        case .nearMissBonus: "Near-miss bonus"
        case .windGusts: "Wind gusts"
        case .ghostFlight: "Ghost flight"
        case .dailyRoute: "Daily route"
        }
    }

    /// One line for the settings form.
    var note: String {
        switch self {
        case .postcards: "Each new city mails a postcard to the flight log."
        case .nearMissBonus: "Close passes build a streak worth extra points."
        case .windGusts: "Gusts push the plane one lane, after a warning."
        case .ghostFlight: "A paper outline of your best run flies alongside."
        case .dailyRoute: "One fixed route a day, with its own best score."
        }
    }
}

/// Which experiments are switched on, saved on the device.
///
/// `-SkyfoldExperiments postcards,nearMissBonus` (or `all`, or `none`) sets them at launch, for
/// screenshots. That choice stays until a switch changes in Settings. Read it once when a run or
/// screen starts rather than every frame.
@Observable
final class ExperimentStore {
    static let shared = ExperimentStore()

    private(set) var enabled: Set<ExperimentID>
    @ObservationIgnored private let defaults: UserDefaults
    private static let savedKey = "SkyfoldExperimentsOn"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        #if DEBUG
        if defaults.bool(forKey: "SkyfoldExperimentsReset") { ExperimentData.resetAll() }
        #endif
        if let launch = defaults.string(forKey: "SkyfoldExperiments") {
            enabled = Self.parse(launch)
        } else {
            enabled = Set((defaults.stringArray(forKey: Self.savedKey) ?? []).compactMap(ExperimentID.init))
        }
    }

    func isOn(_ id: ExperimentID) -> Bool { enabled.contains(id) }

    func set(_ id: ExperimentID, on: Bool) {
        if on { enabled.insert(id) } else { enabled.remove(id) }
        defaults.set(enabled.map(\.rawValue).sorted(), forKey: Self.savedKey)
    }

    /// Parses a comma-separated list of experiment names; `all` and `none` work too.
    nonisolated static func parse(_ raw: String) -> Set<ExperimentID> {
        let names = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if names.contains("all") { return Set(ExperimentID.allCases) }
        return Set(names.compactMap(ExperimentID.init(rawValue:)))
    }
}
