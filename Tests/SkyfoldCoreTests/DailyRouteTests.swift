import Foundation
import Testing
@testable import SkyfoldCore

private func day(_ iso: String) -> DailyRoute {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withTimeZone]
    return DailyRoute(date: f.date(from: iso + "T12:00:00Z")!)
}

@Test func sameDateGivesSameRouteSeedsAndGates() {
    let a = day("2026-11-17"), b = DailyRoute(date: a.startDate.addingTimeInterval(80_000))
    #expect(a == b)
    #expect(a.startRoute == b.startRoute)
    for leg in 0..<6 {
        #expect(a.legSeed(leg) == b.legSeed(leg))
        #expect(a.sceneSeed(leg) == b.sceneSeed(leg))
        #expect(a.gateOffer(afterLeg: leg, allowSecondChances: true)
                == b.gateOffer(afterLeg: leg, allowSecondChances: true))
    }
}

@Test func differentDatesDiffer() {
    let days = (0..<30).map { DailyRoute(day: 20_400 + $0) }
    #expect(Set(days.map { $0.legSeed(0) }).count == 30)
    #expect(Set(days.map(\.startRoute)).count > 1)
    #expect(days.allSatisfy { DailyRoute.airports.contains($0.startRoute) })
    let offers = days.map { $0.gateOffer(afterLeg: 1, allowSecondChances: true).options }
    #expect(Set(offers.map { $0.map(\.rawValue).joined(separator: ",") }).count > 5)
}

@Test func legsOfOneDayUseDifferentSeeds() {
    let d = day("2026-11-17")
    #expect(Set((0..<8).map { d.legSeed($0) }).count == 8)
}

@Test func gateOfferHasOneBlessingAndOneCurse() {
    for n in 0..<40 {
        let offer = DailyRoute(day: 20_000 + n).gateOffer(afterLeg: n % 4, allowSecondChances: false)
        #expect(offer.options.count == 2)
        #expect(Set(offer.options.map(\.kind)) == [.blessing, .curse])
        #expect(!offer.options.contains(.paperShield) && !offer.options.contains(.secondWind))
    }
}

@Test func dateTextUsesUTCDay() {
    let d = day("2026-11-17")
    #expect(d.key == "2026-11-17")
    #expect(d.shortDate == "17 NOV")
    #expect(DailyRoute(date: Date(timeIntervalSince1970: d.startDate.timeIntervalSince1970 - 1)).key == "2026-11-16")
}

@Test func twoDailyLegsWithSameInputsProduceSameObstacles() {
    let route = day("2026-11-17")
    let leg = LegPlan.plan(fromRoute: route.startRoute, legsCompleted: 0, startRoute: route.startRoute,
                           difficulty: route.difficulty, tuning: RunTuning())
    func layout() -> [String] {
        var sim = FlightSimulation(config: FlightConfig(leg: leg, tuning: RunTuning()),
                                   startDistance: -10, seed: route.legSeed(0))
        var seen: [String] = []
        for _ in 0..<1500 {
            sim.step(dt: 1.0 / 60.0, speed: leg.startSpeed, collisions: false)
            seen.append(sim.obstacles.filter(\.isActive).map { "\($0.kind)@\($0.lane):\($0.x)" }.joined(separator: ","))
        }
        return seen
    }
    let first = layout()
    #expect(first == layout())
    #expect(first.contains { !$0.isEmpty })
    var other = FlightSimulation(config: FlightConfig(leg: leg, tuning: RunTuning()),
                                 startDistance: -10, seed: DailyRoute(day: route.day + 1).legSeed(0))
    var otherSeen: [String] = []
    for _ in 0..<1500 {
        other.step(dt: 1.0 / 60.0, speed: leg.startSpeed, collisions: false)
        otherSeen.append(other.obstacles.filter(\.isActive).map { "\($0.kind)@\($0.lane):\($0.x)" }.joined(separator: ","))
    }
    #expect(otherSeen != first)
}

@Test func dailyBestKeepsTheHighestScorePerDate() {
    let suite = "daily-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = DailyBestStore(defaults: defaults)
    let a = DailyRoute(day: 20_400), b = DailyRoute(day: 20_401)
    #expect(store.best(for: a) == nil)
    #expect(store.record(score: 300, for: a))
    #expect(!store.record(score: 200, for: a))
    #expect(store.record(score: 450, for: a))
    #expect(store.best(for: a) == 450)
    #expect(store.best(for: b) == nil)
}
