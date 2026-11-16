import RealityKit
import simd

private let axisY = SIMD3<Float>(0, 1, 0)

@inline(__always) private func smooth01(_ x: Float) -> Float {
    let t = min(max(x, 0), 1)
    return t * t * (3 - 2 * t)
}

/// How many props each graphics quality draws.
struct RenderBudget {
    var hills: Int
    var trees: Int
    var houses: Int
    var clouds: Int
    var skyline: Int
    var msaa: Bool

    static func make(_ q: GraphicsQuality) -> RenderBudget {
        switch q {
        case .low: RenderBudget(hills: 5, trees: 7, houses: 3, clouds: 3, skyline: 9, msaa: false)
        case .balanced: RenderBudget(hills: 8, trees: 13, houses: 5, clouds: 6, skyline: 14, msaa: true)
        case .high: RenderBudget(hills: 11, trees: 20, houses: 8, clouds: 9, skyline: 20, msaa: true)
        }
    }
}

/// The ground card, its printed stripes, the near decor and the fog cards.
///
/// Decor lives on a loop of track coordinates. Every item has a landscape position (all of it
/// behind the lanes, so the side camera sees an open stage) and a portrait position (flanking the
/// track, so the chase camera passes between two walls of props). Positions blend with the camera
/// rig, so rotating the phone re-folds the diorama instead of cutting.
final class SceneryField {
    let root = Entity()

    private enum Kind { case hill, tree, house, cloud }

    private final class Item {
        let kind: Kind
        let entity = Entity()
        let model: Entity
        var parts: StyledParts
        let index: Int
        var lap = Int.min
        var s: Float
        var zL: Float = 0
        var zP: Float = 0
        var y: Float = 0
        var size = SIMD3<Float>(repeating: 1)
        var yaw: Float = 0
        var drift: Float = 0

        init(kind: Kind, model: Entity, parts: StyledParts, index: Int, s: Float) {
            self.kind = kind
            self.model = model
            self.parts = parts
            self.index = index
            self.s = s
            entity.addChild(model)
        }
    }

    private static let loopStart: Float = -30
    private static let loopLength: Float = 170

    private let ground: Entity
    private let groundPart: StyledPart?
    private var stripes: [Entity] = []
    private var stripeParts: [StyledPart] = []
    private var items: [Item] = []
    private var veilsSide: [Entity] = []
    private var veilsChase: [Entity] = []
    private var veilParts: [StyledPart] = []
    private let veilXSide: [Float] = [9, 14.5, 21, 29]
    private let veilXChase: [Float] = [14, 20, 28, 38]
    private static let stripeCount = 12

    init(library: ModelLibrary, style: RenderStyle, budget: RenderBudget) {
        root.name = "scenery"

        // Ground card: one big slab whose top is the ground plane.
        let slab = PaperMesh.box([260, 1.2, 56])
        ground = Entity()
        ground.name = "ground"
        ground.components.set(ModelComponent(mesh: slab, materials: [style.slot(.groundCard).material]))
        ground.position = [60, World.groundY - 0.6, -6]
        groundPart = StyledPart(entity: ground, slot: style.slot(.groundCard))
        root.addChild(ground)

        // Printed stripes, alternate bands a shade darker. They carry the sense of speed on the ground.
        let stripeMesh = PaperMesh.box([7, 0.03, 54])
        for _ in 0..<Self.stripeCount {
            let e = Entity()
            e.components.set(ModelComponent(mesh: stripeMesh, materials: [style.slot(.groundStripe).material]))
            root.addChild(e)
            stripes.append(e)
            if let p = StyledPart(entity: e, slot: style.slot(.groundStripe)) { stripeParts.append(p) }
        }

        buildDecor(library: library, style: style, budget: budget)
        buildVeils(style: style)
    }

    // MARK: Build

    private func buildDecor(library: ModelLibrary, style: RenderStyle, budget: RenderBudget) {
        func spawn(_ kind: Kind, count: Int, makeModel: () -> (Entity, StyledParts)) {
            for i in 0..<count {
                let (m, parts) = makeModel()
                let it = Item(kind: kind, model: m, parts: parts, index: items.count,
                              s: Self.loopStart + (Float(i) + 0.5) / Float(max(count, 1)) * Self.loopLength)
                items.append(it)
                root.addChild(it.entity)
            }
        }

        // Hills: four faceted mound shapes shared by every hill.
        let moundMeshes = (0..<4).map { PaperMesh.mound(sides: 7 + $0 % 2, radius: 1, height: 1, seed: UInt64(101 + $0 * 17)) }
        var hillIndex = 0
        spawn(.hill, count: budget.hills) {
            let e = Entity()
            let far = hillIndex % 2 == 1
            let slot = style.slot(far ? .hillFar : .hillNear)
            e.components.set(ModelComponent(mesh: moundMeshes[hillIndex % moundMeshes.count], materials: [slot.material]))
            hillIndex += 1
            let parts = StyledParts(parts: StyledPart(entity: e, slot: slot).map { [$0] } ?? [])
            return (e, parts)
        }

        // Trees: paper firs.
        let firMeshes = (0..<3).map { PaperMesh.fir(height: 1, radius: 0.34, seed: UInt64(7 + $0 * 31)) }
        var treeIndex = 0
        spawn(.tree, count: budget.trees) {
            let e = Entity()
            let slot = style.slot(.tree)
            e.components.set(ModelComponent(mesh: firMeshes[treeIndex % firMeshes.count], materials: [slot.material]))
            treeIndex += 1
            let parts = StyledParts(parts: StyledPart(entity: e, slot: slot).map { [$0] } ?? [])
            return (e, parts)
        }

        // Houses: low buildings from the model set, in plain card colors.
        var houseIndex = 0
        spawn(.house, count: budget.houses) {
            let name: ModelName = houseIndex % 2 == 0 ? .buildingD : .buildingB
            houseIndex += 1
            let m = library.make(name)
            let parts = StyledParts.bind(m, fallback: style.slot(.houseWall)) { part in
                switch part {
                case "Wall": style.slot(.houseWall)
                case "Roof": style.slot(.houseRoof)
                case "Window": style.slot(.window)
                default: nil
                }
            }
            return (m, parts)
        }

        // Clouds: layered cut-paper puffs at depth.
        spawn(.cloud, count: budget.clouds) {
            let m = library.make(.cloudPuff)
            let parts = StyledParts.bind(m, fallback: style.slot(.cloudPuff)) { part in
                part == "Cloud" ? style.slot(.cloudPuff) : nil
            }
            return (m, parts)
        }
    }

    private func buildVeils(style: RenderStyle) {
        let sideMesh = MeshResource.generatePlane(width: 80, height: 18)
        let chaseMesh = MeshResource.generatePlane(width: 60, height: 26)
        let mat = style.slot(.fog)
        for k in 0..<veilXSide.count {
            let e = Entity()
            e.components.set(ModelComponent(mesh: sideMesh, materials: [mat.material]))
            e.position = [veilXSide[k] + 40, 3.5, 1.0 + Float(k) * 0.12]
            e.isEnabled = false
            root.addChild(e)
            veilsSide.append(e)
            if let p = StyledPart(entity: e, slot: mat) { veilParts.append(p) }

            let c = Entity()
            c.components.set(ModelComponent(mesh: chaseMesh, materials: [mat.material]))
            c.orientation = simd_quatf(angle: -.pi / 2, axis: axisY)
            c.position = [veilXChase[k], 3.0, 0]
            c.isEnabled = false
            root.addChild(c)
            veilsChase.append(c)
            if let p = StyledPart(entity: c, slot: mat) { veilParts.append(p) }
        }
    }

    // MARK: Per frame

    /// `blend`: 0 side camera, 1 chase camera. `fog`: RunTuning.fog.
    func update(scroll: Double, blend: Float, fog: Float, quality: GraphicsQuality) {
        let sc = Float(scroll.truncatingRemainder(dividingBy: 100_000))

        // Stripes.
        let stripeLoop = 14 * Float(Self.stripeCount)
        for (i, e) in stripes.enumerated() {
            var x = (Float(i) * 14 - sc).truncatingRemainder(dividingBy: stripeLoop)
            if x < 0 { x += stripeLoop }
            e.position = [x - 30 + 3.5, World.groundY + Layer.stripe - 0.015, -6]
        }

        // Decor.
        let xEnd = Self.loopStart + Self.loopLength
        for it in items {
            let rel = it.s - sc - Self.loopStart
            let lap = Int((rel / Self.loopLength).rounded(.down))
            var x = rel - Float(lap) * Self.loopLength
            if lap != it.lap {
                it.lap = lap
                reseed(it)
            }
            x += Self.loopStart
            let z = it.zL + (it.zP - it.zL) * blend
            let grow = smooth01((xEnd - x) / 22)
            let k = 0.02 + 0.98 * grow
            let y = it.y
            let yaw = it.yaw - (it.kind == .cloud ? blend * (.pi / 2) : 0)
            it.entity.transform = Transform(scale: it.size * k, rotation: simd_quatf(angle: yaw, axis: axisY),
                                            translation: [x, y, z])
            it.parts.sync()
        }

        // Fog cards: the side set for the side camera, the chase set for the chase camera.
        let on = fog > 0.001
        let side = on && blend < 0.5
        let chase = on && blend >= 0.5
        for e in veilsSide where e.isEnabled != side { e.isEnabled = side }
        for e in veilsChase where e.isEnabled != chase { e.isEnabled = chase }
        if on { for p in veilParts { p.sync() } }
        groundPart?.sync()
        for p in stripeParts { p.sync() }
    }

    /// Re-rolls an item's size and place for a new lap, from a stable hash so it is the same every run.
    private func reseed(_ it: Item) {
        let id = UInt32(truncatingIfNeeded: it.index * 977 + (it.lap &* 7919) &+ 13)
        func r(_ salt: UInt32) -> Float { FlightMath.hash01(id, salt) }
        let side: Float = r(5) < 0.5 ? -1 : 1
        switch it.kind {
        case .hill:
            let far = it.index % 2 == 1
            let w = far ? 11 + r(1) * 9 : 7 + r(1) * 7
            let h = far ? 3 + r(2) * 3 : 2 + r(2) * 2.6
            it.size = [w * 0.5, h, far ? 5.5 : 3.6]
            it.zL = far ? -(19 + r(3) * 11) : -(10 + r(3) * 6)
            it.zP = side * (far ? 14 + r(3) * 10 : 8.5 + r(3) * 5)
            it.y = World.groundY - 0.02
            it.yaw = (r(4) - 0.5) * 0.4
        case .tree:
            let h = 1.5 + r(1) * 2.2
            it.size = [h * 0.9, h, h * 0.9]
            it.zL = -(4.4 + r(3) * 4.5)
            it.zP = side * (5.6 + r(3) * 4)
            it.y = World.groundY - 0.02
            it.yaw = r(4) * 6.28
        case .house:
            let sc = 0.5 + r(1) * 0.25
            it.size = [sc, sc, sc]
            it.zL = -(6 + r(3) * 3)
            it.zP = side * (6.4 + r(3) * 4)
            it.y = World.groundY
            it.yaw = (r(4) - 0.5) * 0.5
        case .cloud:
            let sc = 1.3 + r(1) * 1.5
            it.size = [sc, sc * (0.9 + r(6) * 0.3), sc]
            it.y = 5.6 + r(2) * 4.4
            it.zL = -(9 + r(3) * 20)
            it.zP = side * (3 + r(3) * 14)
            it.yaw = (r(4) - 0.5) * 0.3
        }
    }
}
