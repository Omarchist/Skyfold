import RealityKit
import Foundation

/// Loads every bundled USDZ once and hands out clones (`clone(recursive:)` shares the meshes).
/// A model that is missing, fails to load or lacks a required part is replaced by a generated
/// paper stand-in with the same part names, so the game always runs.
final class ModelLibrary {
    static let shared = ModelLibrary()

    private var prototypes: [ModelName: Entity] = [:]
    private var loading: Task<Void, Never>?
    /// Models that fell back to a generated stand-in (for logs and the harness).
    private(set) var standIns: Set<ModelName> = []

    static let requiredParts: [ModelName: [String]] = [
        .plane: ["Paper", "Crease"],
        .jet: ["Paper", "Crease", "Canopy", "Metal", "Marking"],
        .bird: ["Body", "WingL", "WingR", "Beak"],
        .balloons: ["BalloonA", "BalloonB", "BalloonC", "String"],
        .kite: ["Sail", "Spar", "Tail"],
        .stormCloud: ["Cloud", "Bolt"],
        .thunderhead: ["Cloud", "Bolt"],
        .tower: ["Wall", "Window", "Beacon"],
        .star: ["Star"],
        .cloudPuff: ["Cloud"],
        .buildingA: ["Wall", "Window", "Roof"],
        .buildingB: ["Wall", "Window", "Roof"],
        .buildingC: ["Wall", "Window", "Roof"],
        .buildingD: ["Wall", "Window", "Roof"],
        .landmarkDome: ["Wall", "Dome", "Window"],
        .gate: ["Frame", "DoorL", "DoorR", "Sign", "Glow"],
    ]

    var isLoaded: Bool { ModelName.allCases.allSatisfy { prototypes[$0] != nil } }

    /// Loads the given models (all by default). Safe to call from several views at once.
    func load(_ names: [ModelName] = ModelName.allCases) async {
        for name in names where prototypes[name] == nil {
            var proto: Entity?
            if let e = try? await Entity(named: name.rawValue) {
                let required = Self.requiredParts[name] ?? []
                if required.allSatisfy({ e.findEntity(named: $0) != nil }) { proto = e }
            }
            // Another caller may have finished the same model while we were awaiting.
            if prototypes[name] != nil { continue }
            if let p = proto {
                prototypes[name] = p
            } else {
                prototypes[name] = StandIn.make(name)
                standIns.insert(name)
            }
        }
    }

    /// A fresh copy of a model. Falls back to a stand-in if it was never loaded.
    func make(_ name: ModelName) -> Entity {
        if let p = prototypes[name] { return p.clone(recursive: true) }
        standIns.insert(name)
        let s = StandIn.make(name)
        prototypes[name] = s
        return s.clone(recursive: true)
    }
}

// MARK: - Stand-ins

/// Generated paper stand-ins. They honor the model contract (names, sizes, origins, facing) so
/// the engine never needs a special case.
enum StandIn {
    private static func part(_ name: String, _ mesh: MeshResource, at p: SIMD3<Float> = .zero) -> Entity {
        let e = Entity()
        e.name = name
        e.components.set(ModelComponent(mesh: mesh, materials: [SimpleMaterial(color: .white, isMetallic: false)]))
        e.position = p
        return e
    }

    private static func builderMesh(_ build: (inout PaperMesh.Builder) -> Void) -> MeshResource {
        var b = PaperMesh.Builder()
        build(&b)
        return b.mesh()
    }

    static func make(_ name: ModelName) -> Entity {
        let root = Entity()
        root.name = name.rawValue
        switch name {
        case .jet:
            // Stand-in for the fighter: a slim dart with swept wings and the five part names.
            root.addChild(part("Paper", builderMesh { b in
                b.tri([0.56, 0, 0], [-0.5, 0.02, 0.37], [-0.5, 0.02, -0.37])
                b.tri([0.56, 0, 0], [-0.5, 0.02, -0.37], [-0.5, 0.02, 0.37])
            }))
            root.addChild(part("Crease", builderMesh { b in
                b.tri([0.56, 0, 0], [-0.5, 0.02, 0.0], [-0.5, -0.13, 0.0])
                b.tri([0.56, 0, 0], [-0.5, -0.13, 0.0], [-0.5, 0.02, 0.0])
            }))
            for n in ["Canopy", "Metal", "Marking"] {
                root.addChild(part(n, builderMesh { b in
                    b.tri([0, 0.13, 0], [-0.01, 0.13, 0.01], [-0.01, 0.13, -0.01])
                }))
            }
        case .plane:
            root.addChild(part("Paper", builderMesh { b in
                // Top fold: a dart seen from above, nose +X, wings along Z.
                b.tri([0.45, 0, 0], [-0.4, 0.02, 0.375], [-0.4, 0.02, -0.375])
                b.tri([0.45, 0, 0], [-0.4, 0.02, -0.375], [-0.4, 0.02, 0.375])
            }))
            root.addChild(part("Crease", builderMesh { b in
                b.tri([0.45, 0, 0], [-0.4, 0.02, 0.0], [-0.4, -0.2, 0.0])
                b.tri([0.45, 0, 0], [-0.4, -0.2, 0.0], [-0.4, 0.02, 0.0])
            }))
        case .bird:
            root.addChild(part("Body", builderMesh { b in
                b.pyramid(sides: 4, radius: 0.12, y0: -0.1, height: 0.2, twist: 0)
                b.tri([-0.3, 0, 0], [0.2, 0.08, 0.04], [0.2, 0.08, -0.04])
            }))
            let wl = part("WingL", builderMesh { b in
                b.tri([0, 0, 0], [-0.25, 0, 0.1], [0.05, 0, 0.35])
                b.tri([0, 0, 0], [0.05, 0, 0.35], [-0.25, 0, 0.1])
            })
            let wr = part("WingR", builderMesh { b in
                b.tri([0, 0, 0], [0.05, 0, -0.35], [-0.25, 0, -0.1])
                b.tri([0, 0, 0], [-0.25, 0, -0.1], [0.05, 0, -0.35])
            })
            root.addChild(wl); root.addChild(wr)
            root.addChild(part("Beak", builderMesh { b in
                b.pyramid(sides: 3, radius: 0.04, y0: 0, height: 0.1, center: [0, 0])
            }, at: [-0.34, 0.02, 0]))
        case .balloons:
            for (i, n) in ["BalloonA", "BalloonB", "BalloonC"].enumerated() {
                let x = Float(i - 1) * 0.3
                root.addChild(part(n, builderMesh { b in
                    b.pyramid(sides: 6, radius: 0.22, y0: 0, height: 0.4, center: [0, 0])
                    b.pyramid(sides: 6, radius: 0.22, y0: 0, height: -0.3, center: [0, 0], twist: .pi / 6)
                }, at: [x, 0.25 + Float(i % 2) * 0.1, 0]))
            }
            root.addChild(part("String", builderMesh { b in
                b.box(lo: [-0.01, -0.6, -0.01], hi: [0.01, 0.0, 0.01])
            }))
        case .kite:
            root.addChild(part("Sail", builderMesh { b in
                b.card([[0, 0.5], [-0.4, 0], [0, -0.5], [0.4, 0]], center: [0, 0], thickness: 0.02)
            }))
            root.addChild(part("Spar", builderMesh { b in
                b.box(lo: [-0.012, -0.5, 0.012], hi: [0.012, 0.5, 0.03])
                b.box(lo: [-0.4, -0.012, 0.012], hi: [0.4, 0.012, 0.03])
            }))
            root.addChild(part("Tail", builderMesh { b in
                b.box(lo: [-0.01, -0.95, -0.01], hi: [0.01, -0.5, 0.01])
            }))
        case .stormCloud, .thunderhead:
            let tall = name == .thunderhead
            root.addChild(part("Cloud", builderMesh { b in
                let layers = 3
                for l in 0..<layers {
                    let s = 1 - Float(l) * 0.1
                    let top: (xs: [Float], top: [Float])
                    if tall {
                        // Anvil: a narrow stem under a wide scalloped cap, 3.1 m tall, centered.
                        let cap = PaperMesh.scallopTop(bumps: [(-0.55, 0.38, 0.55), (0.0, 0.5, 0.7), (0.55, 0.38, 0.55)], samples: 36)
                        var xs: [Float] = [], tops: [Float] = [], bots: [Float] = []
                        for (i, x0) in cap.xs.enumerated() {
                            let x = x0 * s
                            xs.append(x)
                            tops.append(2.35 + cap.top[i] * 1.3 * s)
                            bots.append(abs(x) < 0.4 ? 0 : 1.75 + Float(l) * 0.03)
                        }
                        b.profileCard(xs: xs, top: tops, bottom: bots, thickness: 0.05,
                                      z: Float(l - 1) * 0.28, offset: [0, -1.55])
                    } else {
                        top = PaperMesh.scallopTop(bumps: [(-0.4, 0.38, 0.9), (0.05, 0.5, 1.0), (0.45, 0.36, 0.8)])
                        b.profileCard(xs: top.xs.map { $0 * s }, top: top.top.map { $0 * s },
                                      bottom: top.xs.map { _ in 0 }, thickness: 0.05,
                                      z: Float(l - 1) * 0.22, offset: [Float(l - 1) * 0.06, -0.4])
                    }
                }
            }))
            root.addChild(part("Bolt", builderMesh { b in
                b.card([[0, 0], [0.12, 0.0], [0.02, -0.18], [0.14, -0.18], [-0.08, -0.5], [-0.02, -0.24], [-0.12, -0.24]],
                       center: [0, -0.2], thickness: 0.02, z: 0.2, offset: [0, tall ? -1.2 : -0.45])
            }))
        case .tower:
            root.addChild(part("Wall", builderMesh { b in
                b.box(lo: [-0.6, 0, -0.6], hi: [0.6, 3.7, 0.6])
                b.box(lo: [-0.03, 3.7, -0.03], hi: [0.03, 4.1, 0.03])
            }))
            root.addChild(part("Window", builderMesh { b in
                for i in 0..<5 {
                    let y = 0.5 + Float(i) * 0.65
                    b.box(lo: [-0.3, y, 0.595], hi: [0.3, y + 0.35, 0.62])
                    b.box(lo: [-0.3, y, -0.62], hi: [0.3, y + 0.35, -0.595])
                }
            }))
            root.addChild(part("Beacon", builderMesh { b in b.box(lo: [-0.09, 3.95, -0.09], hi: [0.09, 4.12, 0.09]) }))
        case .star:
            root.addChild(part("Star", PaperMesh.foldedStar(outer: 0.23, inner: 0.1, depth: 0.07)))
        case .cloudPuff:
            root.addChild(part("Cloud", builderMesh { b in
                for l in 0..<3 {
                    let s = 1 - Float(l) * 0.12
                    let top = PaperMesh.scallopTop(bumps: [(-0.7, 0.45, 0.8), (-0.1, 0.6, 1.0), (0.6, 0.5, 0.85)])
                    b.profileCard(xs: top.xs.map { $0 * s }, top: top.top.map { $0 * s },
                                  bottom: top.xs.map { _ in 0 }, thickness: 0.04,
                                  z: Float(l - 1) * 0.34, offset: [Float(l - 1) * 0.1, -0.35])
                }
            }))
        case .buildingA, .buildingB, .buildingC, .buildingD:
            let dims: SIMD3<Float>
            switch name {
            case .buildingA: dims = [2.5, 8, 2.5]
            case .buildingB: dims = [3.5, 4.5, 3]
            case .buildingC: dims = [1.6, 9, 1.6]
            default: dims = [5, 2.5, 3]
            }
            root.addChild(part("Wall", builderMesh { b in
                b.box(lo: [-dims.x / 2, 0, -dims.z / 2], hi: [dims.x / 2, dims.y, dims.z / 2])
            }))
            root.addChild(part("Roof", builderMesh { b in
                b.box(lo: [-dims.x / 2 - 0.1, dims.y, -dims.z / 2 - 0.1], hi: [dims.x / 2 + 0.1, dims.y + 0.18, dims.z / 2 + 0.1])
            }))
            root.addChild(part("Window", builderMesh { b in
                let rows = max(1, Int(dims.y / 1.1)), cols = max(1, Int(dims.x / 1.0))
                for r in 0..<rows {
                    for c in 0..<cols {
                        let x = -dims.x / 2 + (Float(c) + 0.5) * dims.x / Float(cols)
                        let y = 0.5 + Float(r) * (dims.y - 0.9) / Float(rows)
                        b.box(lo: [x - 0.2, y, dims.z / 2 - 0.01], hi: [x + 0.2, y + 0.45, dims.z / 2 + 0.03])
                        b.box(lo: [x - 0.2, y, -dims.z / 2 - 0.03], hi: [x + 0.2, y + 0.45, -dims.z / 2 + 0.01])
                    }
                }
            }))
        case .landmarkDome:
            root.addChild(part("Wall", builderMesh { b in b.box(lo: [-1.6, 0, -1.6], hi: [1.6, 2.6, 1.6]) }))
            root.addChild(part("Dome", PaperMesh.dome(radius: 2.0), at: [0, 2.6, 0]))
            root.addChild(part("Window", builderMesh { b in
                for i in 0..<3 {
                    let x = -1.0 + Float(i)
                    b.box(lo: [x - 0.18, 0.6, 1.59], hi: [x + 0.18, 1.7, 1.63])
                }
            }))
        case .gate:
            root.addChild(part("Frame", builderMesh { b in
                b.box(lo: [-0.9, 0, -0.15], hi: [-0.75, 2.2, 0.15])
                b.box(lo: [0.75, 0, -0.15], hi: [0.9, 2.2, 0.15])
                b.box(lo: [-0.9, 2.05, -0.15], hi: [0.9, 2.2, 0.15])
            }))
            let dl = part("DoorL", builderMesh { b in b.box(lo: [0, 0, -0.02], hi: [0.75, 2.05, 0.04]) }, at: [-0.75, 0, 0.02])
            let dr = part("DoorR", builderMesh { b in b.box(lo: [-0.75, 0, -0.02], hi: [0, 2.05, 0.04]) }, at: [0.75, 0, 0.02])
            root.addChild(dl); root.addChild(dr)
            root.addChild(part("Sign", builderMesh { b in b.box(lo: [-0.8, 2.25, -0.12], hi: [0.8, 2.6, 0.15]) }))
            root.addChild(part("Glow", builderMesh { b in b.box(lo: [-0.75, 0, -0.1], hi: [0.75, 2.05, -0.07]) }))
        }
        return root
    }
}
