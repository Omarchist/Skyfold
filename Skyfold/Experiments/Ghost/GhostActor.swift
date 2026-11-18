import RealityKit
import simd

/// The ghost plane: the same aircraft as the player's, drawn flat and quiet. A pale see-through fill inside a
/// thin ink outline, set a little behind the lane plane. No shadow, no trail, no collision. Its
/// materials are see-through, so they never write depth and can never hide the real plane.
final class GhostActor {
    let root = Entity()
    private let fill: Entity
    private let outline: Entity
    private var fillParts: StyledParts
    private var outlineParts: StyledParts
    private let fillSlot = MaterialSlot(kind: .unlit, color: RGBA(hex: 0xF4ECDD), opacity: 0.5)
    private let outlineSlot = MaterialSlot(kind: .unlit, color: RGBA(hex: 0x2A211B), opacity: 0.7)

    /// Matches the player's aircraft (the paper dart or the jet) at its usual footprint.
    private let footprint: Float

    init(library: ModelLibrary, aircraft: Aircraft = .paperPlane) {
        root.name = "ghost"
        footprint = aircraft.footprintScale
        outline = library.make(aircraft.model)
        outline.name = "ghostOutline"
        fill = library.make(aircraft.model)
        fill.name = "ghostFill"
        root.addChild(outline)
        root.addChild(fill)
        let f = fillSlot, o = outlineSlot
        fillParts = StyledParts.bind(fill, fallback: f) { _ in f }
        outlineParts = StyledParts.bind(outline, fallback: o) { _ in o }
        root.isEnabled = false
    }

    /// `blend`: 0 side camera, 1 chase camera. `side` view sets the ghost one step behind the lane
    /// plane; the chase view has the depth along the track, so it stays in line.
    func apply(_ frame: GhostFrame?, blend: Float, palette: Palette, nightness: Double) {
        guard let frame else {
            root.isEnabled = false
            return
        }
        // By day: bone fill, ink outline. By night the ink would vanish into the sky, so the
        // outline turns bone and the fill turns ink blue.
        let n = Float(nightness)
        let bone = RGBA(hex: 0xF4ECDD)
        let ink = RGBA(hex: 0x2A211B)
        let night = RenderStyle.smooth(nightness)
        outlineSlot.set(ink.mixed(with: RGBA(hex: 0xD9D1BF), night), opacity: 0.6)
        fillSlot.set(bone.mixed(with: RGBA(hex: 0x2B3556), night), opacity: 0.66 + 0.1 * n)

        root.isEnabled = true
        let side = 1 - blend
        let k = PlaneActor.baseScale * footprint * (1 + 0.55 * side)
        let q = simd_quatf(angle: frame.pitch, axis: [0, 0, 1]) * simd_quatf(angle: side * 0.5, axis: [1, 0, 0])
        root.position = [frame.x, frame.y, -0.6 * side]
        fill.transform = Transform(scale: SIMD3(repeating: k), rotation: q, translation: .zero)
        outline.transform = Transform(scale: SIMD3(repeating: k * 1.09), rotation: q, translation: [0, 0, -0.04])
        fillParts.sync()
        outlineParts.sync()
    }
}
