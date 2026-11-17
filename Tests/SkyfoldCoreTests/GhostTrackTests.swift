import Foundation
import Testing
@testable import SkyfoldCore

/// A recorder run: `seconds` of flight at `speed` m/s, altitude from `alt(t)`, in frames of `dt`.
private func record(_ r: inout GhostRecorder, seconds: Float, speed: Double, dt: Float = 1.0 / 60,
                    alt: (Float) -> Float = { _ in 1.6 }) {
    var t: Float = 0
    var dist = 0.0
    while t < seconds {
        t += dt
        dist += speed * Double(dt)
        r.advance(dt: dt, distance: dist, altitude: alt(t))
    }
}

@Test func recordsAboutTenSamplesASecond() {
    var r = GhostRecorder()
    r.beginLeg(length: 1000)
    record(&r, seconds: 10, speed: 20, alt: { 1.6 + sinf($0 * 6) })
    r.closeLeg()
    let n = r.legs[0].count
    #expect(n > 20 && n <= 105)
}

@Test func compactionKeepsStraightLinesShort() {
    var r = GhostRecorder()
    r.beginLeg(length: 1000)
    record(&r, seconds: 30, speed: 20)
    r.closeLeg()
    #expect(r.legs[0].count <= 4)
    let s = r.legs[0].sample(at: 15)
    #expect(abs(s.distance - 300) < 0.6)
    #expect(abs(s.altitude - 1.6) < 0.05)
}

@Test func compactionKeepsLaneChanges() {
    var r = GhostRecorder()
    r.beginLeg(length: 1000)
    // Climbs from 1.6 to 3.2 between 4 s and 4.4 s.
    record(&r, seconds: 8, speed: 20, alt: { t in t < 4 ? 1.6 : (t > 4.4 ? 3.2 : 1.6 + (t - 4) / 0.4 * 1.6) })
    r.closeLeg()
    let leg = r.legs[0]
    #expect(abs(leg.sample(at: 3).altitude - 1.6) < 0.06)
    #expect(abs(leg.sample(at: 4.2).altitude - 2.4) < 0.25)
    #expect(abs(leg.sample(at: 6).altitude - 3.2) < 0.06)
}

@Test func interpolationClampsAtBothEnds() {
    let leg = GhostLeg(length: 100, t: [0, 100, 300], d: [0, 1000, 3000], a: [160, 160, 320])
    #expect(leg.duration == 3)
    #expect(leg.sample(at: -1).distance == 0)
    #expect(abs(leg.sample(at: 0.5).distance - 5) < 0.001)
    #expect(abs(leg.sample(at: 2).distance - 20) < 0.001)
    #expect(abs(leg.sample(at: 2).altitude - 2.4) < 0.001)
    #expect(leg.sample(at: 99).distance == 30)
    #expect(GhostLeg(length: 1).sample(at: 1).distance == 0)
}

@Test func progressMapsOntoALongerLeg() {
    // Ghost leg is 100 m; it is 50 m along after 5 s.
    let leg = GhostLeg(length: 100, t: [0, 1000], d: [0, 10000], a: [160, 160])
    let same = GhostReplay.place(leg, time: 5, playerLegLength: 100, playerDistance: 40)
    #expect(abs(same.ahead - 10) < 0.01)
    // The player's leg is twice as long: the ghost is at 100 m of it, the player at 40 m.
    let long = GhostReplay.place(leg, time: 5, playerLegLength: 200, playerDistance: 40)
    #expect(abs(long.ahead - 60) < 0.01)
    #expect(!long.landed)
    let done = GhostReplay.place(leg, time: 12, playerLegLength: 200, playerDistance: 40)
    #expect(done.landed)
    #expect(abs(done.ahead - 160) < 0.01)
}

@Test func replayNeverPassesTheLegEnd() {
    let leg = GhostLeg(length: 100, t: [0, 100], d: [0, 12000], a: [160, 160])
    let p = GhostReplay.place(leg, time: 1, playerLegLength: 100, playerDistance: 100)
    #expect(abs(p.ahead) < 0.001)
}

@Test func saveRule() {
    #expect(GhostRun.shouldSave(score: 10, previousBest: nil))
    #expect(GhostRun.shouldSave(score: 11, previousBest: 10))
    #expect(!GhostRun.shouldSave(score: 10, previousBest: 10))
    #expect(!GhostRun.shouldSave(score: 0, previousBest: nil))
}

@Test func finishCutsOffLegsAndRoundTrips() throws {
    var r = GhostRecorder()
    r.beginLeg(length: 500)
    record(&r, seconds: 5, speed: 20)
    r.beginLeg(length: 700)
    record(&r, seconds: 3, speed: 25, alt: { 1.6 + $0 })
    let run = r.finish(score: 321, startRoute: 0, difficulty: "standard")
    #expect(run.legs.count == 2)
    #expect(run.legs[1].length == 700)
    #expect(abs(run.legs[1].duration - 3) < 0.05)
    let back = try JSONDecoder().decode(GhostRun.self, from: JSONEncoder().encode(run))
    #expect(back == run)
}

@Test func pausedTimeIsNotRecorded() {
    var r = GhostRecorder()
    r.beginLeg(length: 500)
    r.advance(dt: 0.5, distance: 10, altitude: 1.6)
    r.advance(dt: 0, distance: 10, altitude: 1.6)
    #expect(abs(r.legTime - 0.5) < 0.0001)
}

@Test func longRunsStayUnderTheSampleCap() throws {
    var r = GhostRecorder()
    for leg in 0..<20 {
        r.beginLeg(length: 3000)
        record(&r, seconds: 120, speed: 25, alt: { 1.6 + 1.5 * sinf($0 * (3 + Float(leg))) })
    }
    let run = r.finish(score: 5000, startRoute: 0, difficulty: "standard")
    #expect(run.sampleCount <= GhostRecorder.maxSamples)
    #expect((try JSONEncoder().encode(run)).count < 400_000)
}

@Test func offscreenNote() {
    #expect(GhostReplay.note(ahead: 40.4, visibleAhead: 30, visibleBehind: 8) == "GHOST +40 m")
    #expect(GhostReplay.note(ahead: -20, visibleAhead: 30, visibleBehind: 8) == "GHOST \u{2212}20 m")
    #expect(GhostReplay.note(ahead: 12, visibleAhead: 30, visibleBehind: 8) == nil)
}
