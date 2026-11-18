import SwiftUI
import RealityKit

/// A small, cheap RealityView of the skin's aircraft (paper plane or jet) turning slowly in a skin's colors, on a
/// transparent background. Used in the menu and the hangar.
///
/// With `interactive` on, a drag on the view turns and tilts the plane (it follows the finger
/// with a little lag and springs back to its idle turn on release) and a tap does a stunt. The
/// gestures live only on this view, so nothing around it loses a touch.
struct PlanePreviewView: View {
    let skin: PlaneSkin
    let nightness: Double
    let interactive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scene = PlanePreviewScene()

    init(skin: PlaneSkin, nightness: Double, interactive: Bool = false) {
        self.skin = skin
        self.nightness = nightness
        self.interactive = interactive
    }

    var body: some View {
        RealityView { content in
            await scene.build(into: &content, skin: skin, nightness: nightness, demo: interactive)
        } update: { _ in
            scene.apply(skin: skin, nightness: nightness)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { scene.dragChanged($0.translation) }
                .onEnded { _ in scene.dragEnded() },
            isEnabled: interactive
        )
        .gesture(TapGesture().onEnded { scene.stunt() }, isEnabled: interactive)
        .accessibilityAction(named: "Do a stunt") { if interactive { scene.stunt() } }
        .onChange(of: reduceMotion, initial: true) { _, now in scene.reduceMotion = now }
    }
}

/// Owns the preview's entities. One plane, one key light, one camera; nothing else.
///
/// Hierarchy: `tilt` (the finger's turn and tilt) > `pivot` (the slow idle turn) > `stuntRig`
/// (loops and rolls, in the plane's own frame) > the model.
final class PlanePreviewScene {
    private var style: RenderStyle?
    private var parts = StyledParts()
    private let tilt = Entity()
    private let pivot = Entity()
    private let stuntRig = Entity()
    private let light = Entity()
    private var subscriptions: [EventSubscription] = []
    private var lastKey = ""
    private var model: Entity?
    private var aircraft: Aircraft = .paperPlane
    private var swapping = false

    var reduceMotion = false

    // Finger-driven turn: angle and angular speed for yaw (around the vertical) and pitch.
    private var yaw: Float = 0, yawV: Float = 0, pitch: Float = 0, pitchV: Float = 0
    private var targetYaw: Float = 0, targetPitch: Float = 0
    private var isDragging = false
    /// True while the turn is away from rest; the per-frame work stops once it settles.
    private var tiltActive = false
    private var spinScale: Float = 1

    private enum Stunt { case loop, roll, wobble }
    private var stuntKind: Stunt?
    private var stuntTime: Float = 0
    private var nextStuntIsLoop = true

    // MARK: Aircraft model

    /// The ONE place the preview's aircraft model is loaded and bound to its skin colors. A later
    /// change can load a different model here for some skins.
    private func loadAircraft(for skin: PlaneSkin, style: RenderStyle) async -> (model: Entity, parts: StyledParts) {
        let name = skin.aircraft.model
        await ModelLibrary.shared.load([name])
        let model = ModelLibrary.shared.make(name)
        model.name = "planePreview"
        model.scale = SIMD3<Float>(repeating: skin.aircraft.footprintScale)
        let parts = StyledParts.bind(model, fallback: style.slot(.misc)) { style.resolve(model: name, part: $0, city: nil) }
        // A little nose-down so the fold reads from above, wings level.
        model.orientation = simd_quatf(angle: -0.2, axis: [0, 0, 1])
        return (model, parts)
    }

    // MARK: Build

    func build(into content: inout RealityViewCameraContent, skin: PlaneSkin, nightness: Double, demo: Bool) async {
        guard style == nil else { return }
        let style = RenderStyle(realtimeShadows: false)
        self.style = style
        let aircraft = await loadAircraft(for: skin, style: style)
        parts = aircraft.parts
        model = aircraft.model
        self.aircraft = skin.aircraft
        stuntRig.addChild(aircraft.model)
        pivot.addChild(stuntRig)
        tilt.addChild(pivot)

        let cam = PerspectiveCamera()
        cam.camera = PerspectiveCameraComponent(near: 0.1, far: 20, fieldOfViewInDegrees: 30)
        cam.look(at: [0, -0.02, 0], from: [0, 0.78, 2.25], relativeTo: nil)

        content.camera = .virtual
        content.renderingEffects.motionBlur = .disabled
        content.renderingEffects.depthOfField = .disabled
        content.renderingEffects.cameraGrain = .disabled
        content.renderingEffects.antialiasing = .multisample4X
        content.add(tilt)
        content.add(cam)
        content.add(light)

        apply(skin: skin, nightness: nightness)

        let sub = content.subscribe(to: SceneEvents.Update.self, on: nil, componentType: nil) { [weak self] event in
            self?.tick(dt: min(Float(event.deltaTime), 1.0 / 20.0))
        }
        subscriptions.append(sub)

        #if DEBUG
        if demo, let mode = DebugFlags.planeDemo { runDemo(mode) }
        #endif
    }

    func apply(skin: PlaneSkin, nightness: Double) {
        guard let style else { return }
        swapAircraftIfNeeded(for: skin, style: style)
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

    /// The Hangar can pick a skin that flies another model: load it, replace the old one, rebind.
    private func swapAircraftIfNeeded(for skin: PlaneSkin, style: RenderStyle) {
        guard skin.aircraft != aircraft, !swapping else { return }
        swapping = true
        Task { @MainActor in
            let next = await loadAircraft(for: skin, style: style)
            model?.removeFromParent()
            stuntRig.addChild(next.model)
            model = next.model
            parts = next.parts
            aircraft = skin.aircraft
            swapping = false
            lastKey = ""
            apply(skin: skin, nightness: style.nightness)
        }
    }

    // MARK: Touch

    /// Finger moved: `translation` is the drag so far in points.
    func dragChanged(_ translation: CGSize) {
        let gain: Float = reduceMotion ? 0.005 : 0.012
        let range: Float = reduceMotion ? 0.6 : 0.85
        targetYaw = Float(translation.width) * gain
        targetPitch = max(-range, min(range, Float(translation.height) * gain * 0.7))
        isDragging = true
        tiltActive = true
    }

    /// Finger lifted: let the plane carry on with its speed (a flick) and spring back to rest.
    func dragEnded() {
        guard isDragging else { return }
        isDragging = false
        // Settle to the nearest whole turn so a big spin unwinds by the short way.
        yaw = yaw.remainder(dividingBy: 2 * .pi)
        if reduceMotion { yawV = 0; pitchV = 0 }
    }

    /// Tap: a loop or a barrel roll, alternating; a gentle wobble with Reduce Motion on.
    func stunt() {
        guard stuntKind == nil, !isDragging else { return }
        if reduceMotion {
            stuntKind = .wobble
        } else {
            stuntKind = nextStuntIsLoop ? .loop : .roll
            nextStuntIsLoop.toggle()
        }
        stuntTime = 0
        Services.sound.play(.laneSwitch)
        Services.haptics.play(.laneSwitch)
    }

    // MARK: Per frame

    private func tick(dt: Float) {
        guard dt > 0 else { return }
        // The idle turn, slowed while touched or mid-stunt.
        let wantSpin: Float = isDragging ? 0 : (stuntKind != nil ? 0.2 : 1)
        spinScale += (wantSpin - spinScale) * (1 - exp(-dt * 5))
        if spinScale > 0.002 {
            pivot.orientation = simd_quatf(angle: dt * 0.55 * spinScale, axis: [0, 1, 0]) * pivot.orientation
        }
        if tiltActive { stepTilt(dt: dt) }
        if stuntKind != nil { stepStunt(dt: dt) }
    }

    private func stepTilt(dt: Float) {
        if isDragging {
            // Follow the finger with a little lag, tracking speed for the flick.
            let k = 1 - exp(-dt * 14)
            let ny = yaw + (targetYaw - yaw) * k
            let np = pitch + (targetPitch - pitch) * k
            yawV = (ny - yaw) / dt
            pitchV = (np - pitch) / dt
            yaw = ny
            pitch = np
        } else {
            // A slightly under-damped spring: a small overshoot, then rest.
            let k: Float = reduceMotion ? 22 : 15
            let c: Float = 2 * k.squareRoot() * (reduceMotion ? 1.0 : 0.6)
            yawV = max(-14, min(14, yawV + (-k * yaw - c * yawV) * dt))
            pitchV = max(-14, min(14, pitchV + (-k * pitch - c * pitchV) * dt))
            yaw += yawV * dt
            pitch += pitchV * dt
            if abs(yaw) < 0.002, abs(pitch) < 0.002, abs(yawV) < 0.02, abs(pitchV) < 0.02 {
                yaw = 0; pitch = 0; yawV = 0; pitchV = 0
                tiltActive = false
            }
        }
        tilt.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: pitch, axis: [1, 0, 0])
    }

    private func stepStunt(dt: Float) {
        guard let kind = stuntKind else { return }
        stuntTime += dt
        let duration: Float = kind == .loop ? 1.5 : (kind == .roll ? 1.1 : 1.0)
        let u = min(stuntTime / duration, 1)
        if u >= 1 {
            stuntKind = nil
            stuntRig.orientation = simd_quatf(angle: 0, axis: [0, 0, 1])
            stuntRig.position = .zero
            return
        }
        let eased = u * u * (3 - 2 * u)
        switch kind {
        case .loop:
            // Nose up and over, in the plane's own side view, rising a little on the way.
            stuntRig.orientation = simd_quatf(angle: eased * 2 * .pi, axis: [0, 0, 1])
            stuntRig.position = [0, 0.1 * sin(u * .pi), 0]
        case .roll:
            stuntRig.orientation = simd_quatf(angle: eased * 2 * .pi, axis: [1, 0, 0])
            stuntRig.position = [0, 0.05 * sin(u * .pi), 0]
        case .wobble:
            stuntRig.orientation = simd_quatf(angle: 0.26 * sin(u * 3 * 2 * .pi) * (1 - u), axis: [1, 0, 0])
        }
    }

    #if DEBUG
    /// Screenshots only (`-SkyfoldPlaneDemo stunt|drag`): the touches cannot be scripted, so play
    /// them on a loop through the same entry points a finger uses.
    private func runDemo(_ mode: String) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            while let self, !Task.isCancelled {
                if mode == "drag" {
                    // Sweep out over about a second, hold, let go.
                    for step in 1...20 {
                        self.dragChanged(CGSize(width: 9 * Double(step), height: -3.5 * Double(step)))
                        try? await Task.sleep(for: .milliseconds(50))
                    }
                    try? await Task.sleep(for: .milliseconds(1200))
                    self.dragEnded()
                    try? await Task.sleep(for: .seconds(3))
                } else {
                    self.stunt()
                    try? await Task.sleep(for: .seconds(3.2))
                }
            }
        }
    }
    #endif
}
