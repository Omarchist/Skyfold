import RealityKit
import simd

private let axisX = SIMD3<Float>(1, 0, 0)
private let axisY = SIMD3<Float>(0, 1, 0)
private let axisZ = SIMD3<Float>(0, 0, 1)

@inline(__always) private func smooth01(_ x: Float) -> Float {
    let t = min(max(x, 0), 1)
    return t * t * (3 - 2 * t)
}

/// One city: its skyline, and the small airport with the two gates. The whole group is anchored
/// at the gate centre and carried with the world. The engine keeps two of them (the airport you
/// left and the one you are flying to) and swaps them when a new leg starts.
///
/// Like the scenery, every piece has a side-camera position and a chase-camera position and the
/// two blend, so the gates sit left and right in the screen halves in either orientation.
final class CityGroup {
    let root = Entity()
    let slotIndex: Int
    private let style: RenderStyle
    private let library: ModelLibrary
    private let shapes: RenderShapes

    private final class Block {
        let entity = Entity()
        let model: Entity
        var parts: StyledParts
        let posL: SIMD3<Float>
        let posP: SIMD3<Float>
        let size: SIMD3<Float>
        let yaw: Float
        let order: Float
        init(model: Entity, parts: StyledParts, posL: SIMD3<Float>, posP: SIMD3<Float>, size: SIMD3<Float>,
             yaw: Float, order: Float) {
            self.model = model; self.parts = parts; self.posL = posL; self.posP = posP
            self.size = size; self.yaw = yaw; self.order = order
            entity.addChild(model)
        }
    }

    private var blocks: [Block] = []
    private let skylineRoot = Entity()

    // Airport set.
    private let runwayRoot = Entity()
    private let airportRoot = Entity()
    private var gateEntities: [Entity] = []
    private var doorsL: [Entity?] = [nil, nil]
    private var doorsR: [Entity?] = [nil, nil]
    private var airportParts = StyledParts()
    private var terminal: Entity?
    private var controlTower: Entity?
    private var windsock: Entity?
    private var runway: Entity
    private var lines: Entity
    private var apron: Entity
    private var flatParts: [StyledPart] = []

    private var gateHalfL: Float = 7.5
    private var gateHalfP: Float = 2.2

    private(set) var city: City = Route.city(0)
    var anchorX: Float = 0

    init(slotIndex: Int, library: ModelLibrary, style: RenderStyle, shapes: RenderShapes) {
        self.slotIndex = slotIndex
        self.style = style
        self.library = library
        self.shapes = shapes
        root.name = "city\(slotIndex)"
        root.addChild(skylineRoot)
        root.addChild(runwayRoot)
        root.addChild(airportRoot)

        // Flat ground pieces of the airport: runway, its painted lines and the apron.
        let runwayStart: Float = -54
        let runwayEnd: Float = 24
        runway = Entity()
        runway.components.set(ModelComponent(mesh: PaperMesh.box([runwayEnd - runwayStart, 0.04, 4.4]),
                                              materials: [style.slot(.runway).material]))
        runway.position = [(runwayStart + runwayEnd) / 2, World.groundY + Layer.runway - 0.02, 0]
        apron = Entity()
        apron.components.set(ModelComponent(mesh: PaperMesh.box([34, 0.035, 13]), materials: [style.slot(.apron).material]))
        apron.position = [2, World.groundY + Layer.apron - 0.0175, -3]
        lines = Entity()
        var lb = PaperMesh.Builder()
        for i in 0..<17 {
            let x = runwayStart + 3 + Float(i) * 4.4
            lb.box(lo: [x, 0, -0.1], hi: [x + 2.0, 0.015, 0.1])
        }
        lb.box(lo: [runwayStart, 0, 1.9], hi: [runwayEnd, 0.015, 1.97])
        lb.box(lo: [runwayStart, 0, -1.97], hi: [runwayEnd, 0.015, -1.9])
        lines.components.set(ModelComponent(mesh: lb.mesh(), materials: [style.slot(.runwayLine).material]))
        lines.position = [0, World.groundY + Layer.line - 0.015, 0]
        runwayRoot.addChild(runway)
        runwayRoot.addChild(lines)
        airportRoot.addChild(apron)
        for (e, role) in [(runway, RenderRole.runway), (apron, .apron), (lines, .runwayLine)] {
            if let p = StyledPart(entity: e, slot: style.slot(role)) { flatParts.append(p) }
        }
        buildAirportModels()
    }

    private func buildAirportModels() {
        let slots = style.citySlots(slotIndex)
        // Gates.
        for g in 0..<2 {
            let e = library.make(.gate)
            e.name = "gate\(g)"
            let glow = g == 0 ? slots.glowA : slots.glowB
            let parts = StyledParts.bind(e, fallback: style.slot(.misc)) { part in
                part == "Glow" ? glow : self.style.resolve(model: .gate, part: part, city: nil)
            }
            airportParts.parts += parts.parts
            doorsL[g] = e.findEntity(named: "DoorL")
            doorsR[g] = e.findEntity(named: "DoorR")
            airportRoot.addChild(e)
            gateEntities.append(e)
        }
        // Terminal behind the gates.
        let t = library.make(.buildingD)
        airportParts.parts += StyledParts.bind(t, fallback: style.slot(.misc)) { self.style.resolve(model: .buildingD, part: $0, city: slots) }.parts
        airportRoot.addChild(t)
        terminal = t
        // Control tower.
        let c = library.make(.tower)
        airportParts.parts += StyledParts.bind(c, fallback: style.slot(.misc)) { self.style.resolve(model: .tower, part: $0, city: nil) }.parts
        airportRoot.addChild(c)
        controlTower = c
        // Windsock: a pole and a striped cone.
        let w = Entity()
        var pole = PaperMesh.Builder()
        pole.box(lo: [-0.04, 0, -0.04], hi: [0.04, 2.0, 0.04])
        let poleE = Entity()
        poleE.components.set(ModelComponent(mesh: pole.mesh(), materials: [style.slot(.windsockStripe).material]))
        w.addChild(poleE)
        var cone = PaperMesh.Builder()
        cone.pyramid(sides: 5, radius: 0.22, y0: 0, height: 0.9)
        let coneE = Entity()
        coneE.components.set(ModelComponent(mesh: cone.mesh(), materials: [style.slot(.windsock).material]))
        coneE.orientation = simd_quatf(angle: -.pi / 2, axis: axisZ)
        coneE.position = [0.05, 1.95, 0]
        w.addChild(coneE)
        for (e, role) in [(poleE, RenderRole.windsockStripe), (coneE, .windsock)] {
            if let p = StyledPart(entity: e, slot: style.slot(role)) { airportParts.parts.append(p) }
        }
        airportRoot.addChild(w)
        windsock = w
    }

    func setGateSpacing(landscape: Float, portrait: Float) {
        gateHalfL = landscape
        gateHalfP = portrait
    }

    // MARK: Configure

    /// Dresses the group for `city`: a fresh skyline from its building list, closed gates.
    func configure(city: City, budget: RenderBudget, seed: UInt32) {
        self.city = city
        style.setCityColors(group: slotIndex, wall: city.wall, roof: city.roof)
        let slots = style.citySlots(slotIndex)

        for b in blocks { b.entity.removeFromParent() }
        blocks.removeAll(keepingCapacity: true)

        let count = budget.skyline
        func r(_ i: Int, _ salt: UInt32) -> Float { FlightMath.hash01(UInt32(i) &+ seed &* 131, salt) }
        let pool = city.skyline.isEmpty ? [ModelName.buildingB] : city.skyline
        for i in 0..<count {
            let name = pool[Int(r(i, 3) * Float(pool.count)) % pool.count]
            let m = library.make(name)
            let parts = StyledParts.bind(m, fallback: style.slot(.misc)) { self.style.resolve(model: name, part: $0, city: slots) }
            let f = Float(i) / Float(max(count - 1, 1))
            let tall: Float = name == .landmarkDome ? 1.15 : 0.65 + r(i, 7) * 0.55
            let sx = tall * (0.85 + r(i, 9) * 0.3)
            // Side camera: a stage-wide strip behind the airport, two rows deep.
            let rowBack = i % 2 == 0
            let xL = -34 + f * 84 + (r(i, 11) - 0.5) * 3
            let zL = rowBack ? -(15 + r(i, 13) * 8) : -(9.5 + r(i, 13) * 3)
            let sizeBoost: Float = rowBack ? 1.25 : 1
            // Chase camera: an avenue running away down the track, both sides.
            let side: Float = i % 2 == 0 ? -1 : 1
            let xP = 20 + f * 72 + (r(i, 17) - 0.5) * 4
            let zP = side * (6.8 + r(i, 19) * 5.5 + f * 2)
            let yawP = -.pi / 2 + (r(i, 21) - 0.5) * 0.3
            let b = Block(model: m, parts: parts,
                          posL: [xL, World.groundY, zL], posP: [xP, World.groundY, zP],
                          size: [sx * sizeBoost, tall * sizeBoost, sx * sizeBoost],
                          yaw: yawP, order: f)
            skylineRoot.addChild(b.entity)
            blocks.append(b)
        }
        for g in 0..<2 {
            doorsL[g]?.orientation = simd_quatf(angle: 0, axis: axisY)
            doorsR[g]?.orientation = simd_quatf(angle: 0, axis: axisY)
            style.setGlow(group: slotIndex, gate: g, kind: nil)
        }
    }

    // MARK: Per frame

    func setGate(chosen: Int?, kind: ModifierKind?) {
        for g in 0..<2 {
            style.setGlow(group: slotIndex, gate: g, kind: g == chosen ? kind : nil)
        }
    }

    /// `open`: 0...1 swing of the chosen gate's doors.
    func place(anchorX: Float, blend: Float, reveal: Float, time: Float,
               showRunway: Bool, showAirport: Bool, chosen: Int?, open: Float) {
        self.anchorX = anchorX
        let visible = anchorX > -110 && anchorX < 230
        if root.isEnabled != visible { root.isEnabled = visible }
        guard visible else { return }
        root.position = [anchorX, 0, 0]
        if runwayRoot.isEnabled != showRunway { runwayRoot.isEnabled = showRunway }
        if airportRoot.isEnabled != showAirport { airportRoot.isEnabled = showAirport }
        if showRunway || showAirport { for p in flatParts { p.sync() } }

        // Skyline.
        for b in blocks {
            let g = smooth01(reveal * 1.6 - b.order * 0.6)
            if g < 0.01 {
                if b.entity.isEnabled { b.entity.isEnabled = false }
                continue
            }
            if !b.entity.isEnabled { b.entity.isEnabled = true }
            let p = b.posL + (b.posP - b.posL) * blend
            let yaw = b.yaw * blend
            b.entity.transform = Transform(scale: [b.size.x, b.size.y * g, b.size.z],
                                           rotation: simd_quatf(angle: yaw, axis: axisY), translation: p)
            b.parts.sync()
        }

        guard showAirport else { return }
        // Gates: A on the left half, B on the right half of the screen.
        let gateScale: Float = 1.3
        for g in 0..<2 {
            let sign: Float = g == 0 ? -1 : 1
            let pL = SIMD3<Float>(sign * gateHalfL, World.groundY, -2.6)
            let pP = SIMD3<Float>(11, World.groundY, sign * gateHalfP)
            let p = pL + (pP - pL) * blend
            gateEntities[g].transform = Transform(scale: [gateScale, gateScale, gateScale],
                                                  rotation: simd_quatf(angle: -blend * (.pi / 2), axis: axisY),
                                                  translation: p)
            let o: Float = (g == chosen) ? open : 0
            let ang = o * 1.75
            doorsL[g]?.orientation = simd_quatf(angle: -ang, axis: axisY)
            doorsR[g]?.orientation = simd_quatf(angle: ang, axis: axisY)
        }
        if let t = terminal {
            let pL = SIMD3<Float>(0, World.groundY, -7.6), pP = SIMD3<Float>(22, World.groundY, 0)
            t.transform = Transform(scale: [1.5, 1.5, 1.5], rotation: simd_quatf(angle: -blend * (.pi / 2), axis: axisY),
                                    translation: pL + (pP - pL) * blend)
        }
        if let c = controlTower {
            let pL = SIMD3<Float>(-15, World.groundY, -8.5), pP = SIMD3<Float>(15, World.groundY, 7.6)
            c.transform = Transform(scale: [1.5, 1.5, 1.5], rotation: simd_quatf(angle: 0.3, axis: axisY),
                                    translation: pL + (pP - pL) * blend)
        }
        if let w = windsock {
            let pL = SIMD3<Float>(9.2, World.groundY, -4.6), pP = SIMD3<Float>(8, World.groundY, -5.6)
            w.transform = Transform(scale: [1, 1, 1],
                                    rotation: simd_quatf(angle: sinf(time * 1.4) * 0.12, axis: axisY),
                                    translation: pL + (pP - pL) * blend)
        }
        airportParts.sync()
    }

    func hideAll() {
        root.isEnabled = false
    }
}
