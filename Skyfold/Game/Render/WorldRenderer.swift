import RealityKit
import SwiftUI

/// Everything the renderer needs to draw one frame. The engine fills it; the renderer never
/// reads the session or the rules on its own.
struct RenderFrame {
    /// Seconds of animation to advance (0 while paused).
    var dt: Float = 0
    /// Real frame time, for the camera ease.
    var cameraDt: Float = 0
    /// Animation clock (s).
    var time: Float = 0
    /// Meters flown this run (drives the printed fields and decor).
    var scroll: Double = 0
    /// Meters the world moved this frame.
    var dx: Float = 0
    var speed: Float = 0
    var plane = PlanePose()
    var planeVy: Float = 0
    var fog: Float = 0
    /// Where the gate centre of the destination and of the airport left behind are (m ahead of the plane).
    var destAnchor: Float = 400
    var originAnchor: Float = -400
    /// 0...1: how far the destination skyline has risen.
    var destReveal: Float = 0
    var destinationAirport = false
    var originRunway = false
    var originAirport = false
    var gateChosen: Int?
    var doorOpen: Float = 0
    /// True from the landing to the end of the airport stop: the camera pulls back for the gates.
    var airportCamera = false
}

/// Builds and drives the 3D diorama. Owns every entity; the engine only hands it numbers.
final class WorldRenderer {
    let library = ModelLibrary.shared
    let style: RenderStyle
    let budget: RenderBudget
    let root = Entity()
    let camera = CameraRig()

    private let light = Entity()
    private let shapes = RenderShapes()
    private let scenery: SceneryField
    private let obstacles: ObstaclePool
    private let stars: StarPool
    private let trail: TrailPool
    private let ring: PopRing
    private let plane: PlaneActor
    private let cities: [CityGroup]
    private var destIndex = 1

    private let quality: GraphicsQuality
    private var shadowMode: ShadowMode
    private var trailOn: Bool
    private var palette = Palette.day
    private var lastLightKey: Float = -1
    private var lastBlend: Float = -1

    init(settings: GameSettings, skin: PlaneSkin) {
        quality = settings.graphicsQuality
        shadowMode = settings.shadowMode
        trailOn = settings.trailEffects
        budget = RenderBudget.make(settings.graphicsQuality)
        style = RenderStyle(realtimeShadows: settings.shadowMode == .realtime)
        scenery = SceneryField(library: library, style: style, budget: budget)
        obstacles = ObstaclePool(library: library, style: style, shapes: shapes)
        stars = StarPool(library: library, style: style)
        trail = TrailPool(shapes: shapes, style: style)
        ring = PopRing(shapes: shapes, style: style)
        plane = PlaneActor(library: library, style: style, shapes: shapes)
        cities = [CityGroup(slotIndex: 0, library: library, style: style, shapes: shapes),
                  CityGroup(slotIndex: 1, library: library, style: style, shapes: shapes)]

        root.name = "skyfold"
        root.addChild(scenery.root)
        for c in cities { root.addChild(c.root) }
        root.addChild(trail.root)
        root.addChild(obstacles.root)
        root.addChild(stars.root)
        root.addChild(plane.root)
        root.addChild(ring.root)
        root.addChild(light)
        root.addChild(camera.entity)

        style.setSkin(skin)
        if shadowMode == .realtime {
            light.components.set(DirectionalLightComponent.Shadow(maximumDistance: 70, depthBias: 1.5))
        }
        for c in cities { c.root.isEnabled = false }
    }

    func attach(to content: inout RealityViewCameraContent) {
        content.camera = .virtual
        content.renderingEffects.motionBlur = .disabled
        content.renderingEffects.depthOfField = .disabled
        content.renderingEffects.cameraGrain = .disabled
        content.renderingEffects.antialiasing = budget.msaa ? .multisample4X : .none
        content.add(root)
    }

    // MARK: Setup between legs

    var destination: CityGroup { cities[destIndex] }
    var origin: CityGroup { cities[1 - destIndex] }

    /// Dresses the two city groups. Called at run start and whenever a new leg begins.
    /// `swap`: the destination group becomes the airport left behind.
    func setLeg(from: City, to: City, swap: Bool, seed: UInt32) {
        if swap { destIndex = 1 - destIndex }
        if !swap { origin.configure(city: from, budget: budget, seed: seed &+ 5) }
        destination.configure(city: to, budget: budget, seed: seed)
        origin.root.isEnabled = true
        destination.root.isEnabled = true
        stars.releaseAll()
        obstacles.releaseAll()
        trail.reset()
    }

    func setGateResult(chosen: Int?, kind: ModifierKind?) {
        destination.setGate(chosen: chosen, kind: kind)
    }

    func clearActors() {
        stars.releaseAll()
        obstacles.releaseAll()
        trail.reset()
    }

    func setView(width: Float, height: Float, snap: Bool) {
        camera.setViewSize(width: width, height: height, snap: snap)
        let a = width / max(height, 1)
        let hl = RigMath.gateHalfSpacing(landscape: true, aspect: a)
        let hp = RigMath.gateHalfSpacing(landscape: false, aspect: a)
        for c in cities { c.setGateSpacing(landscape: hl, portrait: hp) }
    }

    func setFog(_ f: Float) { style.setFog(f) }

    // MARK: Palette

    func applyPalette(_ p: Palette, nightness: Double) {
        palette = p
        style.apply(palette: p, nightness: nightness)
        updateLight(force: true)
    }

    private func updateLight(force: Bool = false) {
        let blend = camera.blend
        let key = blend * 10 + Float(palette.lightIntensity) + Float(palette.lightColor.r)
        guard force || abs(key - lastLightKey) > 0.0005 else { return }
        lastLightKey = key
        let c = palette.lightColor
        let intensity = Float(palette.lightIntensity) * 3000 + 400
        var comp = DirectionalLightComponent(color: c.platformColor, intensity: intensity)
        comp.isRealWorldProxy = false
        light.components.set(comp)
        // Key light from the upper side facing the camera: front-right for the side view, behind the
        // camera for the chase view.
        let landscapePos = SIMD3<Float>(6, 10, 8)
        let portraitPos = SIMD3<Float>(-8, 10, 4)
        let pos = landscapePos + (portraitPos - landscapePos) * blend
        light.look(at: .zero, from: pos, relativeTo: nil)
    }

    // MARK: Frame

    func render(_ f: RenderFrame, sim: FlightSimulation) {
        camera.airportTarget = f.airportCamera ? 1 : 0
        camera.update(dt: f.cameraDt)
        let blend = camera.blend
        updateLight()

        scenery.update(scroll: f.scroll, blend: blend, fog: f.fog, quality: quality)
        destination.place(anchorX: f.destAnchor, blend: blend, reveal: f.destReveal, time: f.time,
                          showRunway: f.destinationAirport, showAirport: f.destinationAirport,
                          chosen: f.gateChosen, open: f.doorOpen)
        origin.place(anchorX: f.originAnchor, blend: blend, reveal: 1, time: f.time,
                     showRunway: f.originRunway, showAirport: f.originAirport, chosen: nil, open: 0)

        let flat = shadowMode == .flat
        obstacles.sync(sim: sim, time: f.time, blend: blend, shadowsOn: flat)
        stars.sync(sim: sim, time: f.time, blend: blend)
        trail.update(dx: f.dx, planeY: f.plane.y, vy: f.planeVy, speed: f.speed, enabled: trailOn,
                     portraitBlend: blend)
        // Seen side-on a paper dart is a sliver, so the side camera sees it banked toward the lens.
        var pose = f.plane
        pose.roll += (1 - blend) * 0.5
        plane.apply(pose, shadowsOn: flat)
        ring.update(dt: f.dt, at: f.plane.y, blend: blend)
    }

    func firePopRing() { ring.fire() }

    func kickCamera(_ amount: Float) { camera.kick(amount) }

    var horizonFractionPortrait: CGFloat { CGFloat(RigMath.horizonFraction(landscape: false, aspect: camera.aspect)) }
    var horizonFractionLandscape: CGFloat { CGFloat(RigMath.horizonFraction(landscape: true, aspect: camera.aspect)) }
}
