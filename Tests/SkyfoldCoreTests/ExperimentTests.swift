import Foundation
import Testing
@testable import SkyfoldCore

@Test
func experimentListsParse() {
    #expect(ExperimentStore.parse("all") == Set(ExperimentID.allCases))
    #expect(ExperimentStore.parse("none").isEmpty)
    #expect(ExperimentStore.parse("postcards, nearMissBonus,unknown") == [.postcards, .nearMissBonus])
}

@Test @MainActor
func experimentSwitchesAreSavedAndLaunchListWins() throws {
    let suite = "SkyfoldExperimentTests"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = ExperimentStore(defaults: defaults)
    #expect(store.enabled.isEmpty)
    store.set(.ghostFlight, on: true)
    #expect(ExperimentStore(defaults: defaults).isOn(.ghostFlight))

    defaults.set("dailyRoute", forKey: "SkyfoldExperiments")
    #expect(ExperimentStore(defaults: defaults).enabled == [.dailyRoute])
}
