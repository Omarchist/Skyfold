import RealityKit


/// Heights (m above the ground card) of the flat printed layers that lie on the ground. Every top
/// face sits at its own height, a few centimeters apart, so no two coplanar faces fight in the depth buffer.
enum Layer {
    static let field: Float = 0.02
    static let river: Float = 0.035
    static let apron: Float = 0.05
    static let runway: Float = 0.075
    static let line: Float = 0.105
    static let shadow: Float = 0.135
}

// MARK: - Night ground

extension Palette {
    /// 0 by day and dusk, 1 at full night (window glow runs 0.6 to 1 between dusk and night).
    var nightLift: Double { min(max((windowGlow - 0.6) / 0.4, 0), 1) }
    /// The ground card as printed: the night palette's near-black ground is lifted to a readable ink blue.
    var printGround: RGBA { ground.mixed(with: RGBA(hex: 0x222B44), nightLift) }
    var printGroundFar: RGBA { groundFar.mixed(with: RGBA(hex: 0x30395A), nightLift) }
}

// MARK: - Material slots

/// One shared paper material. Materials are value types in RealityKit, so a "shared" material is
/// a slot that every user re-applies when `version` moves. Users only re-apply while visible
/// (see `StyledPart.sync`), so a palette change never touches hundreds of idle entities.
final class MaterialSlot {
    enum Kind { case lit, unlit }

    let kind: Kind
    private(set) var material: any Material
    private(set) var version = 1
    private(set) var color: RGBA
    private(set) var opacity: Float
    private let roughness: Float

    init(kind: Kind, color: RGBA, opacity: Float = 1, roughness: Float = 0.92) {
        self.kind = kind
        self.color = color
        self.opacity = opacity
        self.roughness = roughness
        material = Self.build(kind: kind, color: color, opacity: opacity, roughness: roughness)
    }

    /// Rebuilds the material only when the color moved enough to be seen (the change adds up, so a slow
    /// fade still arrives, in steps of about 1% brightness).
    func set(_ c: RGBA, opacity o: Float? = nil) {
        let newOpacity = o ?? opacity
        let d = abs(c.r - color.r) + abs(c.g - color.g) + abs(c.b - color.b)
        guard d > 0.02 || abs(newOpacity - opacity) > 0.004 else { return }
        color = c
        opacity = newOpacity
        material = Self.build(kind: kind, color: c, opacity: newOpacity, roughness: roughness)
        version += 1
    }

    private static func build(kind: Kind, color c: RGBA, opacity: Float, roughness: Float) -> any Material {
        switch kind {
        case .lit:
            var m = PhysicallyBasedMaterial()
            m.baseColor = .init(tint: c.platformColor)
            m.roughness = .init(floatLiteral: roughness)
            m.metallic = .init(floatLiteral: 0)
            m.specular = .init(floatLiteral: 0.15)
            if opacity < 0.999 { m.blending = .transparent(opacity: .init(floatLiteral: opacity)) }
            return m
        case .unlit:
            var m = UnlitMaterial(color: c.platformColor)
            if opacity < 0.999 { m.blending = .transparent(opacity: .init(floatLiteral: opacity)) }
            return m
        }
    }
}

/// How many already-styled parts may take a new material this frame. The renderer refills it at the
/// start of every frame. Palette steps are small, so a part that waits a frame or two is not seen.
enum SyncBudget {
    /// About 1200 parts a second, whatever the frame rate: 20 a frame at 60 Hz, 10 at 120 Hz.
    static var remaining = 20
    static func refill(frameDt: Float) { remaining = min(max(Int(frameDt * 1200), 6), 48) }
}

/// A model part bound to a slot. `sync()` is a single integer compare when nothing changed.
final class StyledPart {
    let entity: Entity
    var slot: MaterialSlot
    private var applied = 0
    private let count: Int

    init?(entity: Entity, slot: MaterialSlot) {
        guard let mc = entity.components[ModelComponent.self] else { return nil }
        self.entity = entity
        self.slot = slot
        count = max(1, mc.materials.count)
    }

    func sync() {
        guard applied != slot.version else { return }
        // A part that already wears an older shade of its slot waits its turn when the frame's
        // budget is spent, so a palette step reaches the scene over a few frames instead of
        // re-assigning every visible material in one. A part never styled (applied == 0) is
        // exempt: it must not show up in the wrong color.
        if applied != 0 {
            guard SyncBudget.remaining > 0 else { return }
            SyncBudget.remaining -= 1
        }
        applied = slot.version
        guard var mc = entity.components[ModelComponent.self] else { return }
        mc.materials = Array(repeating: slot.material, count: count)
        entity.components.set(mc)
    }

    /// Rebinds to another slot (e.g. a skyline slot re-dressed for another city).
    func rebind(_ s: MaterialSlot) {
        slot = s
        applied = 0
    }
}

/// All the parts of one visual that need keeping in step with the palette.
struct StyledParts {
    var parts: [StyledPart] = []

    func sync() { for p in parts { p.sync() } }

    /// Walks `root` and binds every mesh to the slot `resolve` gives for its name (or for the
    /// nearest named ancestor). Meshes nothing resolves are bound to `fallback`.
    static func bind(_ root: Entity, fallback: MaterialSlot, resolve: (String) -> MaterialSlot?) -> StyledParts {
        var out = StyledParts()
        func visit(_ e: Entity, inherited: MaterialSlot?) {
            let own = resolve(e.name) ?? inherited
            if e.components[ModelComponent.self] != nil, let p = StyledPart(entity: e, slot: own ?? fallback) {
                out.parts.append(p)
            }
            for c in e.children { visit(c, inherited: own) }
        }
        visit(root, inherited: nil)
        return out
    }
}

// MARK: - Roles

/// Every flat color the scene uses. The style turns a palette into one color per role.
enum RenderRole: CaseIterable {
    // plane
    case planePaper, planeCrease, planeInk
    // obstacles
    case birdBody, birdWing, birdBeak
    case balloonA, balloonB, balloonC, balloonString
    case kiteSail, kiteSpar, kiteTail
    case stormCloud, stormBolt
    case towerWall, towerBeacon
    case star
    // scenery
    case groundCard, fieldA, fieldB, fieldC, river, hillNear, hillFar, tree, cloudPuff, houseWall, houseRoof
    // shared parts
    case window
    case runway, runwayLine, apron, windsock, windsockStripe
    case gateFrame, gateDoor, gateSign
    // overlays
    case shadow, trail, fog, ring
    case misc
}

/// Palette-driven materials for the whole scene. Built once; `apply` only moves slot colors.
final class RenderStyle {
    private(set) var slots: [RenderRole: MaterialSlot] = [:]
    /// Per city group: wall, roof, and the two gate glows.
    final class CitySlots {
        let wall = MaterialSlot(kind: .lit, color: RGBA(hex: 0xE5D5BD))
        let roof = MaterialSlot(kind: .lit, color: RGBA(hex: 0xB89F88))
        let glowA = MaterialSlot(kind: .unlit, color: RGBA(hex: 0xF4ECDD))
        let glowB = MaterialSlot(kind: .unlit, color: RGBA(hex: 0xF4ECDD))
    }
    let cityA = CitySlots()
    let cityB = CitySlots()

    private(set) var palette = Palette.day
    private(set) var nightness: Double = 0
    private(set) var skin: PlaneSkin = PlaneSkin.get(.classic)
    private(set) var fogAmount: Float = 0
    private var cityColors: [(wall: RGBA, roof: RGBA)] = [(RGBA(hex: 0xE5D5BD), RGBA(hex: 0xB89F88)), (RGBA(hex: 0xE5D5BD), RGBA(hex: 0xB89F88))]

    init(realtimeShadows: Bool) {
        for role in RenderRole.allCases {
            let kind: MaterialSlot.Kind
            switch role {
            case .window, .planeInk, .towerBeacon, .runway, .runwayLine, .apron, .shadow, .trail, .fog, .ring,
                 .groundCard, .fieldA, .fieldB, .fieldC, .river:
                // Ground pieces are flat print, unless a real shadow has to fall on them.
                kind = (realtimeShadows && (role == .groundCard || role == .fieldA || role == .fieldB
                                            || role == .fieldC || role == .river)) ? .lit : .unlit
            default:
                kind = .lit
            }
            slots[role] = MaterialSlot(kind: kind, color: RGBA(hex: 0xF4ECDD))
        }
    }

    func slot(_ r: RenderRole) -> MaterialSlot { slots[r]! }

    func setSkin(_ s: PlaneSkin) {
        skin = s
        apply(palette: palette, nightness: nightness)
    }

    func setCityColors(group: Int, wall: RGBA, roof: RGBA) {
        cityColors[group] = (wall, roof)
        apply(palette: palette, nightness: nightness)
    }

    func setFog(_ f: Float) {
        fogAmount = f
        apply(palette: palette, nightness: nightness)
    }

    func citySlots(_ group: Int) -> CitySlots { group == 0 ? cityA : cityB }

    /// Pushes a palette into every slot.
    func apply(palette p: Palette, nightness n: Double) {
        palette = p
        nightness = n
        let night = RenderStyle.smooth(n)
        let tint = p.obstacleTint

        func lit(_ day: UInt32, _ nite: UInt32) -> RGBA {
            let d = RGBA(hex: day)
            let dayTinted = RGBA(d.r * tint.r, d.g * tint.g, d.b * tint.b)
            return dayTinted.mixed(with: RGBA(hex: nite), night)
        }
        func set(_ r: RenderRole, _ c: RGBA, _ o: Float? = nil) { slots[r]!.set(c, opacity: o) }

        // Plane: the skin colors, lifted a touch at night so the player stays readable.
        let lift = 1 + 0.35 * night
        set(.planePaper, skin.paper.scaled(lift))
        set(.planeCrease, skin.crease.scaled(lift))

        set(.birdBody, lit(0x3A3F4B, 0xC4C8D6))
        set(.birdWing, lit(0x4A4A58, 0xAEB3C4))
        set(.birdBeak, lit(0xC48A1E, 0xE5A03A))
        set(.balloonA, lit(0xD6402B, 0xE8715B))
        set(.balloonB, lit(0xC48A1E, 0xE8B866))
        set(.balloonC, lit(0x2C4F9E, 0x8EA6DA))
        set(.balloonString, lit(0x76655A, 0xB5AD9E))
        set(.kiteSail, lit(0xD6402B, 0xE8715B))
        set(.kiteSpar, lit(0x2A211B, 0xD9D1BF))
        set(.kiteTail, lit(0xC48A1E, 0xE8B866))
        set(.stormCloud, lit(0x5B5F6B, 0x9097AD))
        set(.stormBolt, lit(0xE5A03A, 0xF0BE62))
        set(.towerWall, lit(0xE5D5BD, 0x98A2BE))
        set(.towerBeacon, p.accent)
        set(.star, lit(0xE5A03A, 0xF2C46A))

        set(.planeInk, RGBA(hex: 0x2A211B).mixed(with: RGBA(hex: 0x070A14), night))

        let g = p.printGround, gf = p.printGroundFar
        set(.groundCard, g)
        // Fields seen from the air, like a survey map: three close tints of the ground card
        // (pale stubble, a darker ploughed strip, a terracotta one) and a muted airmail-blue river.
        // At night they become ink-blue, slate green and plum plots, still flat and printed.
        set(.fieldA, g.mixed(with: gf, 0.6).mixed(with: RGBA(hex: 0x2E3B5E), night))
        set(.fieldB, g.mixed(with: p.ink, 0.09 * (1 - night)).mixed(with: RGBA(hex: 0x27404A), night))
        set(.fieldC, g.mixed(with: p.accent, 0.16 * (1 - night)).mixed(with: RGBA(hex: 0x342F4E), night))
        set(.river, p.secondary.mixed(with: g, 0.42 + 0.2 * night))
        set(.hillNear, gf.mixed(with: g, 0.55).scaled(1.05))
        set(.hillFar, gf.scaled(1.06))
        set(.tree, p.secondary.mixed(with: p.groundFar, 0.52 - 0.2 * night))
        set(.cloudPuff, p.cloud.scaled(1.05))
        set(.houseWall, RGBA(hex: 0xF0E3CC).mixed(with: p.cityTint, 0.0).scaled(1).mixed(with: RGBA(hex: 0x8C95B0), night))
        set(.houseRoof, p.accent.mixed(with: p.ground, 0.25))

        // Windows: dark punched card by day, flat sodium amber when lit. Never a glow.
        let amber = RGBA(hex: 0xF2B24E)
        let dark = RGBA(hex: 0x6E5F52).mixed(with: p.ink, 0.25)
        set(.window, dark.mixed(with: amber, p.windowGlow))

        // Asphalt is always darker than card stock by day and a shade lighter than the black ground
        // at night, so the runway reads in both. Painted lines are cream, then bone.
        let asphalt = p.ground.mixed(with: RGBA(hex: 0x2A211B), 0.55).mixed(with: RGBA(hex: 0x131828), night)
        set(.runway, asphalt)
        set(.runwayLine, RGBA(hex: 0xEFE4CC).mixed(with: RGBA(hex: 0xB9B2A2), night))
        set(.apron, asphalt.mixed(with: g, 0.5))
        set(.windsock, p.accent)
        set(.windsockStripe, p.paper)
        set(.gateFrame, lit(0xE5D5BD, 0x98A2BE))
        set(.gateDoor, lit(0x2C4F9E, 0x7D93C6))
        set(.gateSign, lit(0x2A211B, 0x2A2F44))

        set(.shadow, p.ink.mixed(with: g.scaled(0.4), night), 0.2)
        set(.trail, p.ink.mixed(with: p.paper, 0.1), 0.38)
        let f = min(max(fogAmount, 0), 0.9)
        set(.fog, p.fog, f > 0 ? 0.28 * f / 0.45 : 0)
        set(.ring, p.secondary)
        set(.misc, RGBA(hex: 0xF4ECDD))

        // City groups: wall and roof by the city, tinted by the time of day.
        for g in 0..<2 {
            let c = citySlots(g)
            let cw = cityColors[g]
            let t = p.cityTint
            c.wall.set(RGBA(cw.wall.r * t.r, cw.wall.g * t.g, cw.wall.b * t.b).scaled(1 + 0.25 * night))
            c.roof.set(RGBA(cw.roof.r * t.r, cw.roof.g * t.g, cw.roof.b * t.b).scaled(1 + 0.25 * night))
        }
    }

    /// Gate glow colors for a group: cream while closed, then the blessing or curse tint.
    func setGlow(group: Int, gate: Int, kind: ModifierKind?) {
        let c = citySlots(group)
        let slot = gate == 0 ? c.glowA : c.glowB
        switch kind {
        case .blessing?: slot.set(palette.blessing)
        case .curse?: slot.set(palette.curse)
        case nil: slot.set(palette.paper)
        }
    }

    static func smooth(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }

    // MARK: Part names

    /// The slot for a named part of a model, or nil when the name means nothing to the style.
    func resolve(model: ModelName, part: String, city: CitySlots?) -> MaterialSlot? {
        switch (model, part) {
        case (.plane, "Paper"): return slot(.planePaper)
        case (.plane, "Crease"): return slot(.planeCrease)
        case (.bird, "Body"): return slot(.birdBody)
        case (.bird, "WingL"), (.bird, "WingR"): return slot(.birdWing)
        case (.bird, "Beak"): return slot(.birdBeak)
        case (.balloons, "BalloonA"): return slot(.balloonA)
        case (.balloons, "BalloonB"): return slot(.balloonB)
        case (.balloons, "BalloonC"): return slot(.balloonC)
        case (.balloons, "String"): return slot(.balloonString)
        case (.kite, "Sail"): return slot(.kiteSail)
        case (.kite, "Spar"): return slot(.kiteSpar)
        case (.kite, "Tail"): return slot(.kiteTail)
        case (.stormCloud, "Cloud"), (.thunderhead, "Cloud"): return slot(.stormCloud)
        case (.stormCloud, "Bolt"), (.thunderhead, "Bolt"): return slot(.stormBolt)
        case (.tower, "Wall"): return slot(.towerWall)
        case (.tower, "Window"): return slot(.window)
        case (.tower, "Beacon"): return slot(.towerBeacon)
        case (.star, "Star"): return slot(.star)
        case (.cloudPuff, "Cloud"): return slot(.cloudPuff)
        case (.buildingA, "Wall"), (.buildingB, "Wall"), (.buildingC, "Wall"), (.buildingD, "Wall"),
             (.landmarkDome, "Wall"):
            return city?.wall ?? slot(.houseWall)
        case (.buildingA, "Roof"), (.buildingB, "Roof"), (.buildingC, "Roof"), (.buildingD, "Roof"),
             (.landmarkDome, "Dome"):
            return city?.roof ?? slot(.houseRoof)
        case (.buildingA, "Window"), (.buildingB, "Window"), (.buildingC, "Window"), (.buildingD, "Window"),
             (.landmarkDome, "Window"):
            return slot(.window)
        case (.gate, "Frame"): return slot(.gateFrame)
        case (.gate, "DoorL"), (.gate, "DoorR"): return slot(.gateDoor)
        case (.gate, "Sign"): return slot(.gateSign)
        default: return nil
        }
    }
}
