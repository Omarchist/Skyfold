import SwiftUI
import RealityKit

/// A small, cheap RealityView of the paper plane turning slowly in a skin's colors, on a
/// transparent background. Used in the menu and the hangar.
struct PlanePreviewView: View {
    let skin: PlaneSkin
    let nightness: Double

    @State private var scene = PlanePreviewScene()

    init(skin: PlaneSkin, nightness: Double) {
        self.skin = skin
        self.nightness = nightness
    }

    var body: some View {
        RealityView { content in
            await scene.build(into: &content, skin: skin, nightness: nightness)
        } update: { _ in
            scene.apply(skin: skin, nightness: nightness)
        }
    }
}

/// Owns the preview's entities. One plane, one key light, one camera; nothing else.
final class PlanePreviewScene {
    private var style: RenderStyle?
    private var parts = StyledParts()
    private let pivot = Entity()
    private let light = Entity()
    private var subscriptions: [EventSubscription] = []
    private var lastKey = ""

    func build(into content: inout RealityViewCameraContent, skin: PlaneSkin, nightness: Double) async {
        guard style == nil else { return }
        await ModelLibrary.shared.load([.plane])
        let style = RenderStyle(realtimeShadows: false)
        self.style = style
        let model = ModelLibrary.shared.make(.plane)
        model.name = "planePreview"
        parts = StyledParts.bind(model, fallback: style.slot(.misc)) { style.resolve(model: .plane, part: $0, city: nil) }
        // A little nose-down so the fold reads from above, wings level.
        model.orientation = simd_quatf(angle: -0.2, axis: [0, 0, 1])
        pivot.addChild(model)

        let cam = PerspectiveCamera()
        cam.camera = PerspectiveCameraComponent(near: 0.1, far: 20, fieldOfViewInDegrees: 30)
        cam.look(at: [0, -0.02, 0], from: [0, 0.78, 2.25], relativeTo: nil)

        content.camera = .virtual
        content.renderingEffects.motionBlur = .disabled
        content.renderingEffects.depthOfField = .disabled
        content.renderingEffects.cameraGrain = .disabled
        content.renderingEffects.antialiasing = .multisample4X
        content.add(pivot)
        content.add(cam)
        content.add(light)

        apply(skin: skin, nightness: nightness)

        let sub = content.subscribe(to: SceneEvents.Update.self, on: nil, componentType: nil) { [weak self] event in
            guard let self else { return }
            let dt = min(Float(event.deltaTime), 1.0 / 20.0)
            var q = self.pivot.orientation
            q = simd_quatf(angle: dt * 0.55, axis: [0, 1, 0]) * q
            self.pivot.orientation = q
        }
        subscriptions.append(sub)
    }

    func apply(skin: PlaneSkin, nightness: Double) {
        guard let style else { return }
        let key = "\(skin.id.rawValue)|\(Int(nightness * 50))"
        guard key != lastKey else { return }
        lastKey = key
        let p = Palette.at(nightness: nightness)
        style.setSkin(skin)
        style.apply(palette: p, nightness: nightness)
        parts.sync()
        var comp = DirectionalLightComponent(color: p.lightColor.platformColor,
                                             intensity: Float(p.lightIntensity) * 3000 + 400)
        comp.isRealWorldProxy = false
        light.components.set(comp)
        light.look(at: .zero, from: [-1.4, 3.2, 3.4], relativeTo: nil)
    }
}
