import Foundation
import Testing
@testable import SkyfoldCore

@MainActor
private func freshDefaults() -> UserDefaults {
    let name = "skyfold.tests.\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

@MainActor
private func makeSession(_ difficulty: DifficultyID = .standard, startRoute: Int = 0) -> (RunSession, ProgressStore) {
    let progress = ProgressStore(defaults: freshDefaults())
    let session = RunSession(difficulty: Difficulty.get(difficulty), skin: PlaneSkin.get(.classic),
                             startRoute: startRoute, timeOfDayMode: .day, progress: progress)
    return (session, progress)
}

// MARK: Fairness

/// The side view shows `LegPlan.visibleAhead` metres, so the fastest a leg may run is the speed that
/// still leaves `minWarningTime` seconds. Headwinds stack, so check them too.
@Test(arguments: DifficultyID.allCases)
@MainActor
func topSpeedLeavesTimeToReact(_ id: DifficultyID) {
    let difficulty = Difficulty.get(id)
    let headwinds = (0...4).map { RunTuning.combine(Array(repeating: ModifierID.headwind, count: $0)) }
    for tuning in headwinds {
        for legs in [0, 5, 20, 80] {
            let leg = LegPlan.plan(fromRoute: legs, legsCompleted: legs, startRoute: 0,
                                   difficulty: difficulty, tuning: tuning)
            let top = max(leg.startSpeed, leg.endSpeed)
            #expect(LegPlan.visibleAhead / top >= LegPlan.minWarningTime - 0.001,
                    "\(difficulty.name) leg \(legs + 1) at \(top) m/s")
        }
    }
}

@Test @MainActor
func stackedModifiersKeepLegsPlayable() {
    let shortcuts = RunTuning.combine(Array(repeating: .shortcut, count: 30) + Array(repeating: .nimbleCrease, count: 30))
    let leg = LegPlan.plan(fromRoute: 3, legsCompleted: 1, startRoute: 0,
                           difficulty: Difficulty.get(.breezy), tuning: shortcuts)
    #expect(leg.length >= LegPlan.minLength * DebugFlags.legLengthScale)
    #expect(leg.laneSwitchTime >= LegPlan.laneSwitchRange.lowerBound)
}

// MARK: Route wrap-around

@Test @MainActor
func routeWrapsAfterNewYork() {
    #expect(Route.city(Route.count - 1).code == "JFK")
    #expect(Route.city(Route.count).code == "LIS")
    #expect(Route.city(-1).code == "JFK")
    let leg = LegPlan.plan(fromRoute: Route.count - 1, legsCompleted: 9, startRoute: 0,
                           difficulty: Difficulty.get(.standard), tuning: RunTuning())
    #expect(leg.to.code == "LIS")
    #expect(Unlock.airport(Route.count + 2).title.hasSuffix("airport"))
    for id in ModifierID.allCases { _ = id.info }
    for id in DifficultyID.allCases { #expect(Difficulty.get(id).id == id) }
    for id in SkinID.allCases { #expect(PlaneSkin.get(id).id == id) }
}

@Test @MainActor
func landingBackInLisbonAfterALapUnlocksMidnight() {
    let progress = ProgressStore(defaults: freshDefaults())
    let unlocks = progress.recordArrival(routeIndex: Route.count)
    #expect(unlocks == [.skin(.midnight)])
    #expect(progress.recordArrival(routeIndex: Route.count).isEmpty)
}

// MARK: Saved data

@Test @MainActor
func damagedProgressFallsBackWithoutLosingTheRest() {
    let defaults = freshDefaults()
    let json = #"{"bestScore": 1200, "unlockedSkins": ["classic", "retired", "sakura"], "unlockedAirports": [0, 3, 99, -2], "visitedCities": "oops", "runsPlayed": 4}"#
    defaults.set(Data(json.utf8), forKey: "skyfold.progress.v1")
    let store = ProgressStore(defaults: defaults)
    #expect(store.data.bestScore == 1200)
    #expect(store.data.runsPlayed == 4)
    #expect(store.isUnlocked(SkinID.sakura) && store.isUnlocked(SkinID.kraft))
    #expect(store.data.unlockedAirports == [0, 3])
    #expect(store.data.visitedCities == [0])
    #expect(store.isUnlocked(DifficultyID.standard))

    defaults.set(Data("not json".utf8), forKey: "skyfold.progress.v1")
    #expect(ProgressStore(defaults: defaults).data == PlayerProgress())
}

@Test @MainActor
func progressSurvivesASaveRoundTrip() {
    let defaults = freshDefaults()
    let store = ProgressStore(defaults: defaults)
    store.recordArrival(routeIndex: 2)
    store.recordRunEnd(score: 500, distance: 900, stars: 3, citiesReached: 2)
    let reloaded = ProgressStore(defaults: defaults)
    #expect(reloaded.data == store.data)
}

@Test @MainActor
func damagedSettingsKeepTheGoodFields() {
    let defaults = freshDefaults()
    let json = #"{"musicVolume": 7, "effectsVolume": -1, "shadowMode": "ultra", "showFPS": true, "selectedAirport": 400}"#
    defaults.set(Data(json.utf8), forKey: "skyfold.settings.v1")
    let settings = GameSettings(defaults: defaults)
    #expect(settings.musicVolume == 1)
    #expect(settings.effectsVolume == 0)
    #expect(settings.shadowMode == .flat)
    #expect(settings.showFPS)
    #expect(settings.selectedAirport == Route.count - 1)

    defaults.set(Data("[1,2".utf8), forKey: "skyfold.settings.v1")
    #expect(GameSettings(defaults: defaults).musicVolume == 0.6)
}

// MARK: Run state machine

@Test @MainActor
func pauseAndResumeInEveryPhase() {
    let (s, _) = makeSession()
    s.pause()
    #expect(s.phase == .paused)
    s.pause()
    #expect(s.phase == .paused)
    s.resume()
    #expect(s.phase == .countdown && s.countdown == 3)
    s.beginFlying()
    #expect(s.phase == .flying)
    s.pause(); s.resume(); s.beginFlying()
    s.beginLanding()
    s.pause()
    #expect(s.phase == .landing, "landing cannot be paused")
    s.resume()
    #expect(s.phase == .landing)
    s.completeLanding()
    #expect(s.phase == .airport)
    s.pause()
    #expect(s.phase == .airport)
}

@Test @MainActor
func hitsShieldsAndRevives() {
    let (s, progress) = makeSession()
    s.shields = 1
    s.revives = 1
    s.beginFlying()
    #expect(s.registerHit())
    #expect(s.phase == .flying && s.shields == 0 && s.shieldHits == 1)
    #expect(!s.registerHit())
    #expect(s.phase == .crashed)
    #expect(s.registerHit(), "a hit while crashed is ignored, not counted")
    s.pause()
    #expect(s.phase == .crashed)
    s.revive()
    #expect(s.phase == .countdown && s.revives == 0 && s.reviveSerial == 1)
    s.revive()
    #expect(s.reviveSerial == 1)
    s.beginFlying()
    s.score = 40
    #expect(!s.registerHit())
    #expect(s.phase == .gameOver)
    #expect(s.result?.score == 40)
    #expect(progress.data.runsPlayed == 1)
    s.quit(); s.declineRevive(); s.revive()
    #expect(progress.data.runsPlayed == 1, "a run is recorded once")
}

@Test @MainActor
func declineReviveAndQuitFromAirportEndTheRunOnce() {
    let (a, pa) = makeSession()
    a.revives = 1
    a.beginFlying()
    a.registerHit()
    a.declineRevive()
    #expect(a.phase == .gameOver && pa.data.runsPlayed == 1)

    let (b, pb) = makeSession()
    b.beginFlying(); b.beginLanding(); b.completeLanding()
    #expect(b.citiesReached == 1)
    b.quit()
    #expect(b.phase == .gameOver && b.result?.citiesReached == 1 && pb.data.runsPlayed == 1)
    b.quit()
    #expect(pb.data.runsPlayed == 1)
}

@Test @MainActor
func landingRecordsArrivalOnceAndGatesGateDeparture() {
    let (s, progress) = makeSession()
    s.depart()
    #expect(s.phase == .countdown, "cannot depart before arriving")
    s.beginFlying(); s.beginLanding()
    s.completeLanding(); s.completeLanding()
    #expect(s.citiesReached == 1)
    #expect(progress.hasVisited(1) && progress.isUnlocked(SkinID.saffron))
    #expect(s.arrival?.unlocks == [.skin(.saffron)])
    s.depart()
    #expect(s.phase == .airport, "a gate must be opened first")
    #expect(s.chooseGate(5) == nil)
    let id = s.chooseGate(0)
    #expect(id != nil)
    #expect(s.chooseGate(1) == nil, "one gate per airport")
    s.legDistance = 123
    s.depart()
    #expect(s.phase == .countdown && s.legsCompleted == 1 && s.legSerial == 1)
    #expect(s.legDistance == 0 && s.leg.fromRoute == 1 && s.arrival == nil && s.gateOffer == nil)
    s.depart()
    #expect(s.legsCompleted == 1)
}

@Test @MainActor
func theRouteKeepsGoingPastNewYork() {
    let (s, progress) = makeSession(.breezy, startRoute: Route.count - 1)
    for lap in 0..<3 {
        s.beginFlying(); s.beginLanding(); s.completeLanding()
        #expect(s.arrival?.city.index == (Route.count + lap) % Route.count)
        _ = s.chooseGate(0)
        s.depart()
        #expect(s.leg.length > 0 && s.leg.startSpeed > 0)
    }
    #expect(progress.isUnlocked(SkinID.midnight))
}
