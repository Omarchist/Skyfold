import RealityKit
import simd

private let axisX = SIMD3<Float>(1, 0, 0)
private let axisY = SIMD3<Float>(0, 1, 0)
private let axisZ = SIMD3<Float>(0, 0, 1)

@inline(__always) private func smooth01(_ x: Float) -> Float {
    let t = min(max(x, 0), 1)
    return t * t * (3 - 2 * t)
}

/// Shared geometry for hard-edged print shadows.
final class RenderShapes {
    let disc = PaperMesh.disc(sides: 20)
    let dash = PaperMesh.box([0.55, 0.045, 0.045])
    let ring = PaperMesh.ring(inner: 0.86, outer: 1.0)

    func shadowEntity(slot: MaterialSlot) -> Entity {
        let e = Entity()
        e.name = "shadow"
        e.components.set(ModelComponent(mesh: disc, materials: [slot.material]))
        return e
    }
}

// MARK: - Plane

struct PlanePose {
    var y: Float = World.laneY(World.middleLane)
    var pitch: Float = 0
    var roll: Float = 0
    var yaw: Float = 0
    var scale = SIMD3<Float>(repeating: 1)
    var visible = true
    /// 0...1 multiplier for the ground shadow (fades as the plane tumbles away).
    var shadow: Float = 1
}

/// The player's plane: model, hard print shadow.
final class PlaneActor {
    let root = Entity()
    let model: Entity
    private let shadow: Entity
    private let outline: Entity
    private var parts: StyledParts
    private var outlineParts: StyledParts
    private var shadowPart: StyledPart?
    static let baseScale: Float = 1.25
    /// Per aircraft, so a jet covers the same screen area as the paper plane.
    private let footprint: Float

    init(library: ModelLibrary, style: RenderStyle, shapes: RenderShapes, skin: PlaneSkin) {
        root.name = "plane"
        let name = skin.aircraft.model
        footprint = skin.aircraft.footprintScale
        model = library.make(name)
        model.name = "planeModel"
        root.addChild(model)
        parts = StyledParts.bind(model, fallback: style.slot(.misc)) { style.resolve(model: name, part: $0, city: nil) }
        // A printed ink outline: a slightly larger flat dark copy just behind the plane, so the pale
        // dart stays readable against cream sky. Only the side camera shows it.
        outline = library.make(name)
        outline.name = "planeOutline"
        root.addChild(outline)
        let ink = style.slot(.planeInk)
        outlineParts = StyledParts.bind(outline, fallback: ink) { _ in ink }
        outline.isEnabled = false
        shadow = shapes.shadowEntity(slot: style.slot(.shadow))
        shadowPart = StyledPart(entity: shadow, slot: style.slot(.shadow))
        root.addChild(shadow)
    }

    /// `side`: 1 for the side camera (bigger plane, outlined), 0 for the chase camera.
    func apply(_ p: PlanePose, shadowsOn: Bool, side: Float = 0) {
        root.position = [0, p.y, 0]
        let q = simd_quatf(angle: p.yaw, axis: axisY) * simd_quatf(angle: p.pitch, axis: axisZ)
            * simd_quatf(angle: p.roll, axis: axisX)
        let k = Self.baseScale * footprint * (1 + 0.55 * side)
        model.transform = Transform(scale: p.scale * k, rotation: q, translation: .zero)
        model.isEnabled = p.visible
        let showOutline = p.visible && side > 0.5
        outline.isEnabled = showOutline
        if showOutline {
            outline.transform = Transform(scale: p.scale * k * 1.16, rotation: q, translation: [-0.02, 0, -0.07])
            outlineParts.sync()
        }
        let show = shadowsOn && p.shadow > 0.02
        shadow.isEnabled = show
        if show {
            let h = max(p.y - World.groundY, 0)
            let s = (1 - min(h * 0.045, 0.3)) * p.shadow
            shadow.transform = Transform(scale: [0.45 * s, 1, 0.78 * s], rotation: .init(angle: 0, axis: axisY),
                                         translation: [0.35, World.groundY + Layer.shadow - p.y, 0])
        }
        parts.sync()
        shadowPart?.sync()
    }
}

// MARK: - Obstacles

final class ObstacleActor {
    let kind: ObstacleKind
    let holder = Entity()
    let model: Entity
    var wingL: Entity?
    var wingR: Entity?
    let shadow: Entity?
    var parts: StyledParts
    var shadowPart: StyledPart?
    var boundID: UInt32 = 0
    var yawJitter: Float = 0
    var rollJitter: Float = 0
    var sizeJitter: Float = 1

    init(kind: ObstacleKind, library: ModelLibrary, style: RenderStyle, shapes: RenderShapes) {
        self.kind = kind
        holder.name = "obstacle"
        let name = Self.modelName(kind)
        model = library.make(name)
        holder.addChild(model)
        if kind == .bird {
            wingL = model.findEntity(named: "WingL")
            wingR = model.findEntity(named: "WingR")
        }
        parts = StyledParts.bind(model, fallback: style.slot(.misc)) { style.resolve(model: name, part: $0, city: nil) }
        if kind != .tower {
            let s = shapes.shadowEntity(slot: style.slot(.shadow))
            holder.addChild(s)
            shadow = s
            shadowPart = StyledPart(entity: s, slot: style.slot(.shadow))
        } else {
            shadow = nil
        }
        holder.isEnabled = false
    }

    static func modelName(_ k: ObstacleKind) -> ModelName {
        switch k {
        case .bird: .bird
        case .balloons: .balloons
        case .kite: .kite
        case .stormCloud: .stormCloud
        case .tower: .tower
        case .thunderhead: .thunderhead
        }
    }

    /// Flat cut-card things are turned to face the chase camera in portrait.
    var isFlat: Bool { kind == .kite || kind == .stormCloud || kind == .thunderhead }
}

/// Pools of obstacle visuals, one set per kind, sized so that nothing is created in normal flight.
/// The rules simulation never put more than 6 obstacles of one kind (12 in all) in the world at once,
/// at any difficulty with Storm Front twice and Restless Flock three times, but it can hold 48. So a
/// kind that runs dry grows by one visual instead of leaving a solid obstacle invisible.
final class ObstaclePool {
    private let library: ModelLibrary
    private let style: RenderStyle
    private let shapes: RenderShapes
    private var all: [ObstacleActor] = []
    private var free: [[ObstacleActor]] = Array(repeating: [], count: ObstacleKind.allCases.count)
    private var bound: [ObstacleActor?] = Array(repeating: nil, count: FlightSimulation.obstacleCapacity)
    let root = Entity()

    static func count(for kind: ObstacleKind) -> Int {
        switch kind {
        case .bird: 12
        case .balloons: 9
        case .kite: 9
        case .stormCloud: 12
        case .tower: 7
        case .thunderhead: 7
        }
    }

    init(library: ModelLibrary, style: RenderStyle, shapes: RenderShapes) {
        self.library = library
        self.style = style
        self.shapes = shapes
        root.name = "obstacles"
        for kind in ObstacleKind.allCases {
            for _ in 0..<Self.count(for: kind) { addVisual(kind) }
        }
    }

    private func addVisual(_ kind: ObstacleKind) {
        let a = ObstacleActor(kind: kind, library: library, style: style, shapes: shapes)
        a.holder.isEnabled = false
        root.addChild(a.holder)
        all.append(a)
        free[kind.rawValue].append(a)
    }

    func releaseAll() {
        for i in bound.indices {
            if let a = bound[i] { release(a); bound[i] = nil }
        }
    }

    private func release(_ a: ObstacleActor) {
        a.holder.isEnabled = false
        a.boundID = 0
        free[a.kind.rawValue].append(a)
    }

    private func acquire(_ kind: ObstacleKind, id: UInt32) -> ObstacleActor? {
        if free[kind.rawValue].isEmpty { addVisual(kind) } // never leave a solid obstacle unseen
        guard let a = free[kind.rawValue].popLast() else { return nil }
        a.boundID = id
        a.yawJitter = (FlightMath.hash01(id, 11) - 0.5) * 0.26
        a.rollJitter = (FlightMath.hash01(id, 23) - 0.5) * 0.16
        a.sizeJitter = 0.95 + FlightMath.hash01(id, 37) * 0.1
        a.holder.isEnabled = true
        return a
    }

    /// Places every active obstacle. `blend` is the portrait blend (0 side camera, 1 chase camera).
    func sync(sim: FlightSimulation, time: Float, blend: Float, shadowsOn: Bool) {
        for i in 0..<FlightSimulation.obstacleCapacity {
            let o = sim.obstacles[i]
            if !o.isActive {
                if let a = bound[i] { release(a); bound[i] = nil }
                continue
            }
            var actor = bound[i]
            if let a = actor, a.boundID != o.id { release(a); actor = nil; bound[i] = nil }
            if actor == nil {
                actor = acquire(o.kind, id: o.id)
                bound[i] = actor
            }
            guard let a = actor else { continue }
            place(a, o, time: time, blend: blend, shadowsOn: shadowsOn)
        }
        for a in all where a.holder.isEnabled {
            a.parts.sync()
            a.shadowPart?.sync()
        }
    }

    private func place(_ a: ObstacleActor, _ o: Obstacle, time: Float, blend: Float, shadowsOn: Bool) {
        let t = time + o.phase
        var y = o.kind == .tower ? World.groundY : o.y
        var yaw = a.yawJitter
        var roll = a.rollJitter
        var pitch: Float = 0
        switch o.kind {
        case .bird:
            let flap = sinf(t * 13) * 0.62
            a.wingL?.orientation = simd_quatf(angle: flap, axis: axisX)
            a.wingR?.orientation = simd_quatf(angle: -flap, axis: axisX)
            y += sinf(t * 13) * 0.025
            pitch = sinf(t * 2.2) * 0.05
        case .balloons:
            roll += sinf(t * 1.6) * 0.07
        case .kite:
            roll += sinf(t * 1.9) * 0.13
            pitch = sinf(t * 1.3) * 0.05
        default: break
        }
        if a.isFlat { yaw -= blend * (.pi / 2) }
        // Pop up as it enters at the spawn distance, like a card unfolding.
        let grow = smooth01((World.spawnAheadDistance - o.x) / 7)
        let s = a.sizeJitter * (0.04 + 0.96 * grow)
        let q = simd_quatf(angle: yaw, axis: axisY) * simd_quatf(angle: roll, axis: axisZ)
            * simd_quatf(angle: pitch, axis: axisX)
        a.holder.transform = Transform(scale: [s, s, s], rotation: q, translation: [o.x, y, 0])
        if let sh = a.shadow {
            sh.isEnabled = shadowsOn && grow > 0.01
            if sh.isEnabled {
                let h = max(y - World.groundY, 0)
                let r: Float = o.kind == .thunderhead ? 0.95 : (o.kind == .stormCloud ? 0.7 : 0.45)
                let k = (1 - min(h * 0.04, 0.3)) * grow / s
                // Counter the holder's rotation and scale so the shadow stays flat on the ground.
                sh.transform = Transform(scale: [r * 0.75 * k, 1, r * 1.1 * k], rotation: q.inverse,
                                         translation: q.inverse.act([0.4, World.groundY + Layer.shadow - y, 0] / s))
            }
        }
    }
}

// MARK: - Stars

final class StarActor {
    let holder = Entity()
    var parts: StyledParts
    var boundID: UInt32 = 0

    init(library: ModelLibrary, style: RenderStyle) {
        holder.name = "star"
        let m = library.make(.star)
        holder.addChild(m)
        parts = StyledParts.bind(m, fallback: style.slot(.star)) { style.resolve(model: .star, part: $0, city: nil) }
        holder.isEnabled = false
    }
}

final class StarPool {
    let root = Entity()
    private var all: [StarActor] = []
    private var free: [StarActor] = []
    private var bound: [StarActor?] = Array(repeating: nil, count: FlightSimulation.starCapacity)
    static let capacity = 44

    init(library: ModelLibrary, style: RenderStyle) {
        root.name = "stars"
        for _ in 0..<Self.capacity {
            let a = StarActor(library: library, style: style)
            root.addChild(a.holder)
            all.append(a)
            free.append(a)
        }
    }

    func releaseAll() {
        for i in bound.indices {
            if let a = bound[i] { release(a); bound[i] = nil }
        }
    }

    private func release(_ a: StarActor) {
        a.holder.isEnabled = false
        a.boundID = 0
        free.append(a)
    }

    func sync(sim: FlightSimulation, time: Float, blend: Float) {
        for i in 0..<FlightSimulation.starCapacity {
            let s = sim.stars[i]
            if !s.isActive {
                if let a = bound[i] { release(a); bound[i] = nil }
                continue
            }
            var actor = bound[i]
            if let a = actor, a.boundID != s.id { release(a); actor = nil; bound[i] = nil }
            if actor == nil, let a = free.popLast() {
                a.boundID = s.id
                a.holder.isEnabled = true
                bound[i] = a
                actor = a
            }
            guard let a = actor else { continue }
            let t = time + s.phase
            let yaw = sinf(t * 1.7) * 0.5 - blend * (.pi / 2)
            let roll = sinf(t * 1.1) * 0.16
            var size: Float = 1 + 0.04 * sinf(t * 3)
            var y = s.y + sinf(t * 2.0) * 0.04
            if s.collectAge >= 0 {
                let u = min(s.collectAge / 0.35, 1)
                size = (1 + s.collectAge * 5) * powf(1 - u, 0.6)
                y += s.collectAge * 1.1
            }
            let grow = smooth01((World.spawnAheadDistance - s.x) / 6)
            size *= 0.05 + 0.95 * grow
            let q = simd_quatf(angle: yaw, axis: axisY) * simd_quatf(angle: roll, axis: axisZ)
            a.holder.transform = Transform(scale: [size, size, size], rotation: q, translation: [s.x, y, 0])
        }
        for a in all where a.holder.isEnabled { a.parts.sync() }
    }
}

// MARK: - Trail

/// A dashed route line drawn behind the plane, like a flight path on a map. Dashes are pooled in
/// a ring, born at the plane's position and carried backward with the world.
final class TrailPool {
    let root = Entity()
    private var dashes: [Entity] = []
    private var xs: [Float]
    private var ys: [Float]
    private var pitches: [Float]
    private var live: [Bool]
    private var head = 0
    private var sinceSpawn: Float = 0
    private var parts: [StyledPart] = []
    static let capacity = 30
    private static let spacing: Float = 1.15
    private static let tail: Float = -0.55

    init(shapes: RenderShapes, style: RenderStyle) {
        root.name = "trail"
        xs = Array(repeating: 0, count: Self.capacity)
        ys = xs
        pitches = xs
        live = Array(repeating: false, count: Self.capacity)
        for _ in 0..<Self.capacity {
            let e = Entity()
            e.components.set(ModelComponent(mesh: shapes.dash, materials: [style.slot(.trail).material]))
            e.isEnabled = false
            root.addChild(e)
            dashes.append(e)
            if let p = StyledPart(entity: e, slot: style.slot(.trail)) { parts.append(p) }
        }
    }

    func reset() {
        for i in 0..<Self.capacity { live[i] = false; dashes[i].isEnabled = false }
        sinceSpawn = 0
    }

    func update(dx: Float, planeY: Float, vy: Float, speed: Float, enabled: Bool, portraitBlend: Float) {
        guard enabled else {
            if live.contains(true) { reset() }
            return
        }
        // Carry existing dashes back with the world.
        let limit: Float = -7.2
        for i in 0..<Self.capacity where live[i] {
            xs[i] -= dx
            if xs[i] < limit {
                live[i] = false
                dashes[i].isEnabled = false
            }
        }
        // Spawn a new dash every `spacing` meters flown.
        sinceSpawn += dx
        while sinceSpawn >= Self.spacing, speed > 1 {
            sinceSpawn -= Self.spacing
            live[head] = true
            xs[head] = Self.tail - sinceSpawn
            ys[head] = planeY
            pitches[head] = atan2f(vy, max(speed, 1))
            head = (head + 1) % Self.capacity
        }
        for i in 0..<Self.capacity where live[i] {
            let e = dashes[i]
            e.isEnabled = true
            // Shorter and thinner as it ages toward the edge of the screen.
            let fade = smooth01((xs[i] - limit) / 4.5)
            e.transform = Transform(scale: [0.5 + 0.5 * fade, 1, 1],
                                    rotation: simd_quatf(angle: pitches[i], axis: axisZ),
                                    translation: [xs[i], ys[i], 0])
        }
        for p in parts { p.sync() }
    }
}

// MARK: - Shield pop

/// A flat blue ring that expands where a paper shield gave way.
final class PopRing {
    let root = Entity()
    private var age: Float = 99
    private let part: StyledPart?
    private static let life: Float = 0.38

    init(shapes: RenderShapes, style: RenderStyle) {
        root.name = "ring"
        root.components.set(ModelComponent(mesh: shapes.ring, materials: [style.slot(.ring).material]))
        part = StyledPart(entity: root, slot: style.slot(.ring))
        root.isEnabled = false
    }

    func fire() { age = 0 }

    func update(dt: Float, at y: Float, blend: Float) {
        guard age < Self.life else {
            if root.isEnabled { root.isEnabled = false }
            return
        }
        age += dt
        let u = min(age / Self.life, 1)
        root.isEnabled = true
        let s = 0.7 + 2.4 * (1 - (1 - u) * (1 - u))
        root.transform = Transform(scale: [s, s * (1 - 0.6 * u), 1],
                                   rotation: simd_quatf(angle: -blend * (.pi / 2), axis: axisY),
                                   translation: [0, y, 0.2])
        root.components.set(OpacityComponent(opacity: 1 - u))
        part?.sync()
    }
}
