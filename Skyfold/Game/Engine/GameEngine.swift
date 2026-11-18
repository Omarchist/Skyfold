import RealityKit
import SwiftUI

/// The glue between the run's rules and the picture. It steps the 2D simulation, runs the phase
/// timers (countdown, landing, airport), writes the live values into the session, turns rule
/// events into sound and haptics, and hands a `RenderFrame` to the renderer every frame.
///
/// Created by `FlightView` as `@State` and driven by RealityKit's per-frame update event. Nothing
/// here allocates per frame: values are copied into preallocated pools by the renderer.
final class GameEngine {
    let session: RunSession
    let settings: GameSettings
    /// The 2D sky reads this from its own timeline. Deliberately not observable.
    let clock = BackdropClock()

    private(set) var renderer: WorldRenderer?
    private var subscriptions: [EventSubscription] = []
    /// True while `build` waits for the models, so a second call cannot build a second world.
    private var building = false

    // Rules.
    private var sim: FlightSimulation
    private var autopilot = Autopilot()

    // Serials and phase tracking.
    private var seenLeg: Int
    private var seenRevive: Int
    private var lastPhase: RunPhase

    // View.
    private var viewWidth: Float = 0
    private var viewHeight: Float = 0

    // Clocks and motion.
    private var animTime: Float = 0
    private var scroll: Double = 0
    private var speedNow: Float = 0
    private var lastDx: Float = 0
    private var score: FlightScore
    private var totalDist: Double = 0

    // Near-miss bonus experiment, read once when the run starts.
    private let nearMissOn = ExperimentStore.shared.isOn(.nearMissBonus)
    private var streak = NearMissStreak()
    private var closeCalls = CloseCallDetector()

    // Ghost flight experiment: nil unless the switch is on for this run.
    private var ghostRun: GhostFlightRun?

    // Wind gusts experiment, read once when the run starts.
    private let gustsOn = ExperimentStore.shared.isOn(.windGusts)
    private let gusts: GustDirector?

    // Countdown and takeoff.
    private var countdownT: Float = 0
    private var shownCountdown = 4
    private var takeoffRun = true
    private var queuedLane = 0

    // Landing and airport.
    private var landT: Float = 0
    private var landStartSpeed: Float = 0
    private var landStartY: Float = 0
    private var landStartAnchor: Float = 0
    private var destAnchor: Float = 400
    private var originAnchor: Float = -400
    private var seenChosen: Int?
    private var doorT: Float = 0
    private var rampUp: Float = 1

    // Crash.
    private var crash = CrashState()

    // Nightness.
    private var nightness: Double
    private var nightTarget: Double
    private var nightPoll: Float = 0
    private var debugDayClock: Double = 0
    private var appliedNight: Double = -1

    // Publishing.
    private var publishTimer: Float = 0
    private var fpsSmoothed: Float = 60

    // The camera stays in the airport rig from the landing until the next takeoff run is under way.
    private var airportCamera = false

    private static let landingTime: Float = 2.5
    private static let countdownTime: Float = 3

    init(session: RunSession, settings: GameSettings) {
        self.session = session
        self.settings = settings
        sim = FlightSimulation(config: FlightConfig(leg: session.leg, tuning: session.tuning))
        score = FlightScore(carriedPoints: session.score)
        totalDist = session.totalDistance
        seenLeg = session.legSerial
        seenRevive = session.reviveSerial
        lastPhase = session.phase
        nightness = session.nightness
        nightTarget = session.nightness
        clock.nightness = session.nightness
        ghostRun = GhostFlightRun(session: session) // ghost flight
        gusts = gustsOn ? GustDirector() : nil // wind gusts
        #if DEBUG
        ExperimentDebug.armQuit(session)
        #endif
    }

    /// Fog from the Fog Bank curse. Debug builds can force it with the `HarnessFog` launch argument.
    private var effectiveFog: Float {
        #if DEBUG
        return max(session.tuning.fog, Float(UserDefaults.standard.double(forKey: "HarnessFog")))
        #else
        return session.tuning.fog
        #endif
    }

    // MARK: Setup

    /// Builds the world and starts listening to the frame event. Called once from the RealityView.
    func build(into content: inout RealityViewCameraContent) async {
        guard renderer == nil, !building else { return }
        building = true
        defer { building = false }
        await ModelLibrary.shared.load()
        let r = WorldRenderer(settings: settings, skin: session.skin)
        r.attach(to: &content)
        renderer = r
        if viewWidth > 1 { r.setView(width: viewWidth, height: viewHeight, snap: true) }
        r.applyPalette(Palette.at(nightness: nightness), nightness: nightness)
        beginLeg(first: true)
        let sub = content.subscribe(to: SceneEvents.Update.self, on: nil, componentType: nil) { [weak self] event in
            self?.update(rawDt: Float(event.deltaTime))
        }
        subscriptions.append(sub)
    }

    func setViewSize(width: Float, height: Float) {
        let snap = viewWidth < 1
        viewWidth = width
        viewHeight = height
        renderer?.setView(width: width, height: height, snap: snap)
    }

    /// Resets the world for the leg the session now holds. `first`: the run's very first leg.
    private func beginLeg(first: Bool) {
        guard let r = renderer else { return }
        let leg = session.leg
        let cfg = FlightConfig(leg: leg, tuning: session.tuning)
        let v0 = max(leg.speed(atProgress: 0), 1)
        // The takeoff run covers 1.5 x v0 meters (speed eases 0 to v0 over the countdown), so the
        // leg's zero lands exactly where the countdown ends.
        let takeoffMeters = 1.5 * v0
        sim.reset(config: cfg, startDistance: -Double(takeoffMeters), lane: World.middleLane,
                  seed: session.legSeed ?? UInt64.random(in: 1...UInt64.max))
        autopilot.reset()
        gusts?.reset(seed: session.legSeed ?? UInt64.random(in: 1...UInt64.max), session: session) // wind gusts
        if nearMissOn { closeCalls.reset() } // a new leg restarts the obstacle ids
        session.lane = World.middleLane
        queuedLane = 0
        crash = CrashState()
        takeoffRun = true
        countdownT = 0
        shownCountdown = 4
        landT = 0
        doorT = 0
        seenChosen = nil
        airportCamera = false
        r.camera.airportTarget = 0
        r.setLeg(from: leg.from, to: leg.to, swap: !first, seed: session.sceneSeed ?? UInt32(truncatingIfNeeded: session.legsCompleted &* 7 &+ leg.toRoute &* 13 &+ 3))
        r.setFog(effectiveFog)
        r.setGateResult(chosen: nil, kind: nil)
        originAnchor = first ? 7 : 0
        ghostRun?.beginLeg() // ghost flight
        destAnchor = destinationAnchor()
        speedNow = 0
    }

    /// Where the gate centre is, in meters ahead of the plane, for the current leg distance.
    private func destinationAnchor() -> Float {
        let leg = session.leg
        let x0 = leg.speed(atProgress: 1) * Self.landingTime * 0.5
        return Float(leg.length - sim.distance) + x0
    }

    // MARK: Input

    /// +1 for up, -1 for down, as the player sees it (the Mirror Sky curse flips it here).
    func requestLaneChange(_ direction: Int) {
        let d = session.tuning.invertControls ? -direction : direction
        switch session.phase {
        case .flying:
            sim.setTargetLane(sim.plane.lane + d)
        case .countdown:
            // One change may be queued during the last second of the countdown.
            if session.countdown == 1 { queuedLane = d }
        default:
            break
        }
    }

    // MARK: Frame

    func update(rawDt: Float) {
        guard let r = renderer else { return }
        let dt = min(max(rawDt, 0), 1.0 / 30.0)
        trackFPS(rawDt)

        if session.legSerial != seenLeg {
            seenLeg = session.legSerial
            beginLeg(first: false)
        }
        if session.reviveSerial != seenRevive {
            seenRevive = session.reviveSerial
            revive()
        }

        let phase = session.phase
        if phase != lastPhase {
            enter(phase, from: lastPhase)
            lastPhase = phase
        }

        var animDt = dt
        lastDx = 0
        switch phase {
        case .paused:
            animDt = 0
            speedNow = 0
        case .countdown:
            tickCountdown(dt)
        case .flying:
            tickFlying(dt)
        case .landing:
            tickLanding(dt)
        case .airport:
            tickAirport(dt)
        case .crashed, .gameOver:
            animDt = 0
            speedNow = 0
            tickCrash(dt)
        }
        animTime += animDt

        updateNightness(animDt)
        publish(dt)

        clock.scroll = scroll
        clock.speed = speedNow

        var f = RenderFrame()
        f.dt = animDt
        f.cameraDt = rawDt > 0.25 ? 0.25 : rawDt
        f.time = animTime
        f.scroll = scroll
        f.dx = lastDx
        f.speed = speedNow
        f.fog = effectiveFog
        f.plane = planePose()
        f.planeVy = sim.plane.vy
        f.destAnchor = destAnchor
        f.originAnchor = originAnchor
        f.destReveal = destinationReveal()
        f.destinationAirport = sim.distance >= session.leg.length - sim.config.clearApproach
        f.originRunway = originAnchor > -45
        f.originAirport = session.legsCompleted == 0 && originAnchor > -34
        f.gateChosen = session.gateOffer?.chosenIndex ?? (phase == .airport ? seenChosen : nil)
        f.doorOpen = smooth(doorT / 0.8)
        f.airportCamera = airportCamera
        f.ghost = ghostRun?.frame(distance: sim.distance, landscape: viewWidth > viewHeight,
                                  aspect: viewWidth / max(viewHeight, 1)) // ghost flight
        r.render(f, sim: sim)
    }

    // MARK: Phase entry

    private func enter(_ phase: RunPhase, from: RunPhase) {
        // Wind gusts: any running warning ends when the plane stops flying (pause, crash, landing).
        if let gusts, phase != .flying, phase != .countdown {
            gusts.hold(session: session, for: phase == .paused ? 3 : WindGusts.holdAfterRevive)
        }
        switch phase {
        case .countdown:
            if from != .countdown {
                countdownT = 0
                shownCountdown = 4
                if from == .paused { takeoffRun = false }
            }
        case .flying:
            takeoffRun = false
            // Near-miss bonus: what went by while the plane was not flying (takeoff run, protection
            // after a revive) is not a close call.
            if nearMissOn { _ = closeCalls.scan(sim.obstacles) }
            // A pause in the first moments of a takeoff must not leave the airport camera on.
            airportCamera = false
            // Starting from rest (after a pause or a revive): ease the world up to speed.
            rampUp = speedNow < 0.5 * session.leg.speed(atProgress: 0) ? 0 : 1
        case .airport:
            speedNow = 0
        case .gameOver:
            ghostRun?.finish() // ghost flight
        default:
            break
        }
    }

    // MARK: Countdown

    private func tickCountdown(_ dt: Float) {
        countdownT += dt
        let remaining = 3 - Int(countdownT)
        if remaining != shownCountdown, remaining >= 1 {
            shownCountdown = remaining
            if session.countdown != remaining { session.countdown = remaining }
            Services.sound.play(.countdown)
            Services.haptics.play(.selection)
        }
        if takeoffRun {
            // Speed eases from rest to the leg's opening speed; obstacles are placed but harmless.
            let v0 = session.leg.speed(atProgress: 0)
            speedNow = v0 * smooth(countdownT / Self.countdownTime)
            if airportCamera, countdownT > 0.2 { airportCamera = false }
            advanceWorld(dt: dt, spawning: true, collisions: false)
        } else {
            speedNow = 0
        }
        if countdownT >= Self.countdownTime {
            session.beginFlying()
            takeoffRun = false
            Services.sound.play(.takeoff)
            Services.haptics.play(.success)
            if queuedLane != 0 {
                sim.setTargetLane(sim.plane.lane + queuedLane)
                queuedLane = 0
            }
        }
    }

    // MARK: Flying

    private func tickFlying(_ dt: Float) {
        let leg = session.leg
        let progress = min(1, max(0, sim.distance) / max(leg.length, 1))
        rampUp = min(1, rampUp + dt / 0.7)
        let speed = leg.speed(atProgress: progress) * smooth(rampUp)
        speedNow = speed
        if DebugFlags.autopilot, let lane = autopilot.decide(sim, speed: speed, dt: dt) {
            sim.setTargetLane(lane)
        }
        gusts?.tick(dt: dt, sim: &sim, speed: speed, session: session) // wind gusts
        advanceWorld(dt: dt, spawning: true, collisions: true)
        ghostRun?.advance(dt: dt, distance: sim.distance, altitude: sim.plane.y) // ghost flight
        handleEvents()
        if nearMissOn, session.phase == .flying { tickStreak(dt) }
        guard session.phase == .flying else { return }
        if sim.distance >= leg.length {
            startLanding()
        }
    }

    /// Steps the rules and moves the world by one frame. Distance and score count only on the leg itself.
    private func advanceWorld(dt: Float, spawning: Bool, collisions: Bool) {
        let before = sim.distance
        sim.step(dt: dt, speed: speedNow, spawning: spawning, collisions: collisions)
        let dx = Float(sim.distance - before)
        lastDx = dx
        scroll += Double(dx)
        destAnchor = destinationAnchor()
        originAnchor -= dx
        if session.phase == .flying {
            let counted = min(session.leg.length, sim.distance) - max(0, before)
            if counted > 0 {
                totalDist += counted
                score.addDistance(counted, multiplier: session.scoreMultiplier)
            }
        }
    }

    private func handleEvents() {
        let events = sim.events
        for e in events {
            switch e {
            case .laneChanged(let lane):
                session.lane = lane
                Services.sound.play(.laneSwitch)
                Services.haptics.play(.laneSwitch)
            case .starCollected:
                session.stars += 1
                score.addStar(points: session.starPoints)
                Services.sound.play(.star)
                Services.haptics.play(.star)
            case .nearMiss:
                // With the bonus on, `tickStreak` feels every close call, this one included.
                if !nearMissOn { Services.haptics.play(.selection) }
            case .hit(let slot):
                endStreak()
                flushValues()
                if session.registerHit() {
                    Services.sound.play(.shieldBreak)
                    Services.haptics.play(.shield)
                    sim.absorbHit(slot: slot)
                    renderer?.firePopRing()
                    renderer?.kickCamera(0.5)
                } else {
                    Services.sound.play(.crash)
                    Services.haptics.play(.crash)
                    crash.begin(y: sim.plane.y, tilt: sim.plane.tilt)
                    renderer?.kickCamera(1)
                    return
                }
            }
        }
    }

    // MARK: Near-miss bonus (experiment)

    /// Ages the streak and pays each close pass the rules just finished counting.
    private func tickStreak(_ dt: Float) {
        if streak.advance(dt: dt) { session.streakLevel = 0 }
        let found = closeCalls.scan(sim.obstacles)
        for _ in 0..<found {
            let points = streak.registerNearMiss(multiplier: session.scoreMultiplier)
            score.addBonus(points: points)
            session.streakLevel = streak.level
            session.streakAward = points
            session.streakSerial += 1
            session.bestStreak = max(session.bestStreak, streak.best)
            Services.sound.play(.uiTap)
            Services.haptics.play(.selection)
        }
    }

    private func endStreak() {
        guard nearMissOn else { return }
        streak.end()
        if session.streakLevel != 0 { session.streakLevel = 0 }
    }

    // MARK: Landing

    private func startLanding() {
        endStreak()
        let leg = session.leg
        landT = 0
        landStartSpeed = leg.speed(atProgress: 1)
        landStartY = sim.plane.y
        landStartAnchor = destAnchor
        speedNow = landStartSpeed
        airportCamera = true
        flushValues()
        session.beginLanding()
        Services.sound.play(.landing)
        Services.haptics.play(.success)
    }

    private func tickLanding(_ dt: Float) {
        landT += dt
        let T = Self.landingTime
        let u = min(landT / T, 1)
        // Linear braking: the world covers v0 * T / 2 meters, and the gates arrive at the plane.
        speedNow = landStartSpeed * (1 - u)
        let before = sim.distance
        sim.step(dt: dt, speed: speedNow, spawning: false, collisions: false)
        let dx = Float(sim.distance - before)
        lastDx = dx
        scroll += Double(dx)
        originAnchor -= dx
        destAnchor = landStartAnchor - landStartSpeed * T * (u - u * u * 0.5)
        if landT >= T {
            destAnchor = landStartAnchor - landStartSpeed * T * 0.5
            speedNow = 0
            session.completeLanding()
        }
    }

    // MARK: Airport

    private func tickAirport(_ dt: Float) {
        speedNow = 0
        airportCamera = true
        let chosen = session.gateOffer?.chosenIndex
        if chosen != seenChosen {
            seenChosen = chosen
            if let c = chosen, let offer = session.gateOffer {
                renderer?.setGateResult(chosen: c, kind: offer.options[c].kind)
                doorT = 0
                Services.sound.play(.gateOpen)
                Services.haptics.play(.gate)
            }
        }
        if chosen != nil { doorT += dt }
    }

    // MARK: Crash and revive

    private func tickCrash(_ dt: Float) {
        crash.step(dt: dt)
    }

    private func revive() {
        gusts?.hold(session: session) // wind gusts
        endStreak()
        crash = CrashState()
        sim.revive()
        sim.placePlane(lane: sim.plane.lane)
        session.lane = sim.plane.lane
        takeoffRun = false
        speedNow = 0
    }

    // MARK: Pose

    private func planePose() -> PlanePose {
        var p = PlanePose()
        let phase = session.phase
        let tilt = sim.plane.tilt
        var y = sim.plane.y
        p.pitch = tilt * 0.34
        p.roll = sinf(animTime * 1.7) * 0.035 - tilt * 0.08
        if phase == .flying, let gusts { p.roll += gusts.roll(time: animTime) } // wind gusts
        y += sinf(animTime * 2.3) * 0.025
        let groundY = World.groundY + 0.2

        if crash.active {
            return crash.pose(base: p, groundY: groundY)
        }
        if phase == .countdown, takeoffRun {
            // Rolls along the runway, then lifts off into its lane.
            let u = countdownT / Self.countdownTime
            let rise = smooth((u - 0.4) / 0.6)
            y = groundY + (sim.plane.y - groundY) * rise
            p.pitch = sinf(.pi * rise) * 0.3 + tilt * 0.34
            p.roll = 0
            p.shadow = 1
        } else if phase == .landing {
            let u = min(landT / Self.landingTime, 1)
            let down = smooth(powf(u, 0.85))
            y = landStartY + (groundY - landStartY) * down
            p.pitch = -0.16 * (1 - u) + 0.12 * sinf(.pi * min(u * 1.25, 1))
            p.roll = 0
        } else if phase == .airport || (phase == .gameOver && lastAirportish) {
            y = groundY
            p.pitch = 0
            p.roll = 0
        }
        p.y = y
        if sim.isProtected, phase == .flying || phase == .countdown {
            p.visible = Int(animTime * 11) % 2 == 0
        }
        return p
    }

    private var lastAirportish: Bool { session.arrival != nil }

    private func destinationReveal() -> Float {
        let leg = session.leg
        let window = Float(min(max(leg.length * 0.2, 70), 170))
        let toGo = Float(leg.length - sim.distance)
        if session.phase == .landing || session.phase == .airport { return 1 }
        return smooth((window - toGo) / (window * 0.75))
    }

    // MARK: Nightness

    private func updateNightness(_ dt: Float) {
        nightPoll -= dt
        if nightPoll <= 0 {
            nightPoll = 0.25
            nightTarget = session.targetNightness()
        }
        if let secs = DebugFlags.dayCycleSeconds {
            debugDayClock += Double(dt)
            nightTarget = TimeOfDay.cycleNightness(debugDayClock / (secs / 2))
        }
        let step = Double(dt) * 0.3
        nightness += min(max(nightTarget - nightness, -step), step)
        // The sky reads the smooth value on its own timeline (no SwiftUI state involved).
        clock.nightness = nightness
        // Everything else (3D materials, the SwiftUI palette) follows in steps of 1/40: each step
        // re-colors the scene and re-renders the HUD, so it must not happen every frame. A step is
        // about 2% of the day to night range, too small to see as stepping.
        let level = (nightness * Self.nightLevels).rounded() / Self.nightLevels
        if level != appliedNight || appliedNight < 0 {
            appliedNight = level
            if session.nightness != level { session.nightness = level }
            renderer?.applyPalette(Palette.at(nightness: level), nightness: level)
        }
    }

    private static let nightLevels = 40.0

    // MARK: Live values

    private func trackFPS(_ rawDt: Float) {
        guard rawDt > 0 else { return }
        // Time-based smoothing (about a 0.4 s time constant), so 60 Hz, 120 Hz and in-between agree.
        let alpha = 1 - expf(-min(rawDt, 0.5) / 0.4)
        fpsSmoothed += (min(1 / rawDt, 125) - fpsSmoothed) * alpha
    }

    /// Writes the live values into the session, at most 15 times a second and only when they moved.
    private func publish(_ dt: Float) {
        publishTimer += dt
        guard publishTimer >= 1.0 / 15.0 else { return }
        publishTimer = 0
        flushValues()
        if settings.showFPS || DebugFlags.showFPS {
            let v = Int(fpsSmoothed.rounded())
            if session.fps != v { session.fps = v }
        }
    }

    private func flushValues() {
        let d = min(session.leg.length, max(0, sim.distance))
        if abs(session.legDistance - d) > 0.05 || (d == session.leg.length && d != session.legDistance) {
            session.legDistance = d
        }
        if abs(session.totalDistance - totalDist) > 0.05 { session.totalDistance = totalDist }
        let s = score.points
        if session.score != s { session.score = s }
        let sp = (speedNow * 20).rounded() / 20
        if abs(session.speed - sp) > 0.01 { session.speed = sp }
    }

    private func smooth(_ x: Float) -> Float {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }
}

// MARK: - Crash animation

/// The tumble and crumple when the plane hits something with no shield left.
struct CrashState {
    private(set) var active = false
    private var t: Float = 0
    private var y0: Float = 0
    private var vy: Float = 0
    private var spin: Float = 0
    private var roll: Float = 0
    private var yawRate: Float = 0
    private var yaw: Float = 0

    mutating func begin(y: Float, tilt: Float) {
        active = true
        t = 0
        y0 = y
        vy = 2.2
        spin = 11
        roll = 0
        yawRate = 2.4
        yaw = 0
    }

    mutating func step(dt: Float) {
        guard active else { return }
        t += dt
        vy -= 16 * dt
        y0 += vy * dt
        let floorY = World.groundY + 0.2
        if y0 < floorY {
            y0 = floorY
            vy = abs(vy) > 2 ? -vy * 0.28 : 0
            spin *= 0.55
            yawRate *= 0.5
        }
        roll += spin * dt
        spin *= max(0, 1 - 1.5 * dt)
        yaw += yawRate * dt
    }

    func pose(base: PlanePose, groundY: Float) -> PlanePose {
        var p = base
        let k = min(t / 0.9, 1)
        p.y = y0
        p.pitch = -0.2 - 0.9 * k
        p.roll = roll
        p.yaw = yaw * 0.35
        // Crumpled: shorter, taller, a little squashed.
        let s = k * k * (3 - 2 * k)
        p.scale = [1 - 0.28 * s, 1 + 0.25 * s, 1 - 0.12 * s]
        p.shadow = 1
        return p
    }
}
