import RealityKit
import simd

/// A camera placement: where it sits, what it looks at, and its vertical field of view.
struct RigPose {
    var eye: SIMD3<Float>
    var target: SIMD3<Float>
    var fov: Float // degrees, vertical

    static func mix(_ a: RigPose, _ b: RigPose, _ t: Float) -> RigPose {
        RigPose(eye: a.eye + (b.eye - a.eye) * t,
                target: a.target + (b.target - a.target) * t,
                fov: a.fov + (b.fov - a.fov) * t)
    }
}

/// The four camera placements and the screen math that goes with them.
///
/// Landscape is a side camera (the Dino view): it looks along -Z at the X/Y plane, with the plane
/// about 27% in from the left edge. Portrait is a chase camera behind and above the plane looking
/// down the track (+X). The airport variants pull back so the two gates sit in the two screen halves.
enum RigMath {
    static let sideDistance: Float = 26
    /// Ground slab far edges, so the 2D sky's horizon line can be matched to the 3D ground.
    static let groundFarZ: Float = -30
    static let groundFarX: Float = 190

    /// Visible width (m) of the side view at the lane plane.
    static func sideWidth(aspect: Float) -> Float { min(max(14.7 * aspect, 26), 40) }

    static func landscapeFlight(aspect: Float) -> RigPose {
        let w = sideWidth(aspect: aspect)
        let h = w / aspect
        let fov = 2 * atanf(h * 0.5 / sideDistance) * 180 / .pi
        let cx = 0.23 * w // plane at 27% from the left
        return RigPose(eye: [cx, 2.0, sideDistance], target: [cx, 2.0, 0], fov: fov)
    }

    static func landscapeAirport(aspect: Float) -> RigPose {
        let w = min(max(sideWidth(aspect: aspect) * 1.08, 30), 44)
        let h = w / aspect
        let fov = 2 * atanf(h * 0.5 / sideDistance) * 180 / .pi
        return RigPose(eye: [0, 1.5, sideDistance], target: [0, 1.5, 0], fov: fov)
    }

    static func portraitFlight(aspect: Float) -> RigPose {
        RigPose(eye: [-8.5, 4.2, 0], target: [12, 0.4, 0], fov: 54)
    }

    static func portraitAirport(aspect: Float) -> RigPose {
        RigPose(eye: [-8.5, 2.8, 0], target: [11, 0.6, 0], fov: 54)
    }

    /// Screen position (0...1, origin top left) of a world point as seen from `pose`.
    static func project(_ p: SIMD3<Float>, pose: RigPose, aspect: Float) -> SIMD2<Float> {
        let f = simd_normalize(pose.target - pose.eye)
        let r = simd_normalize(simd_cross(f, [0, 1, 0]))
        let u = simd_cross(r, f)
        let v = p - pose.eye
        let z = max(simd_dot(v, f), 0.001)
        let t = tanf(pose.fov * 0.5 * .pi / 180)
        let nx = simd_dot(v, r) / (z * t * aspect)
        let ny = simd_dot(v, u) / (z * t)
        return [0.5 + nx * 0.5, 0.5 - ny * 0.5]
    }

    /// Where the far edge of the 3D ground lands on screen, as a fraction of the height from the top.
    static func horizonFraction(landscape: Bool, aspect: Float) -> Float {
        if landscape {
            let pose = landscapeFlight(aspect: aspect)
            return project([pose.eye.x, World.groundY, groundFarZ], pose: pose, aspect: aspect).y
        }
        let pose = portraitFlight(aspect: aspect)
        return project([groundFarX, World.groundY, 0], pose: pose, aspect: aspect).y
    }

    /// Half the distance between the two gate centers so each sits mid-way across its screen half.
    static func gateHalfSpacing(landscape: Bool, aspect: Float) -> Float {
        if landscape {
            let pose = landscapeAirport(aspect: aspect)
            let d = pose.eye.z + 2.6
            let halfW = d * tanf(pose.fov * 0.5 * .pi / 180) * aspect
            return halfW * 0.5
        }
        let pose = portraitAirport(aspect: aspect)
        let d = 11 - pose.eye.x
        let halfW = d * tanf(pose.fov * 0.5 * .pi / 180) * aspect
        return halfW * 0.5
    }
}

/// Owns the camera entity and eases between the side and chase rigs (and the airport pull-back).
final class CameraRig {
    let entity = PerspectiveCamera()

    private var rawBlend: Float = 0
    private var targetBlend: Float = 0
    private var rawAirport: Float = 0
    var airportTarget: Float = 0
    private(set) var aspect: Float = 2.1
    private var lastFov: Float = 0
    private var shakeT: Float = 0
    private var shakeAmp: Float = 0
    private var time: Float = 0

    /// 0 = landscape side camera, 1 = portrait chase camera (eased).
    var blend: Float { Self.smooth(rawBlend) }
    /// 0 = flying, 1 = airport pull-back (eased).
    var airportMix: Float { Self.smooth(rawAirport) }
    var isPortrait: Bool { targetBlend > 0.5 }

    init() {
        entity.camera = PerspectiveCameraComponent(near: 0.3, far: 420, fieldOfViewInDegrees: 40,
                                                   fieldOfViewOrientation: .vertical)
    }

    /// Call when the view size changes. `snap` skips the 0.4 s ease (first layout).
    func setViewSize(width: Float, height: Float, snap: Bool) {
        guard width > 1, height > 1 else { return }
        aspect = width / height
        targetBlend = height > width ? 1 : 0
        if snap { rawBlend = targetBlend }
    }

    func snapAirport(_ v: Float) { rawAirport = v; airportTarget = v }

    func kick(_ amount: Float) { shakeAmp = amount; shakeT = 0.32 }

    func update(dt: Float) {
        time += dt
        if rawBlend != targetBlend {
            let step = dt / 0.4
            rawBlend = targetBlend > rawBlend ? min(targetBlend, rawBlend + step) : max(targetBlend, rawBlend - step)
        }
        if rawAirport != airportTarget {
            let step = dt / 1.4
            rawAirport = airportTarget > rawAirport ? min(airportTarget, rawAirport + step) : max(airportTarget, rawAirport - step)
        }
        let b = blend, a = airportMix
        let land = RigPose.mix(RigMath.landscapeFlight(aspect: aspect), RigMath.landscapeAirport(aspect: aspect), a)
        let port = RigPose.mix(RigMath.portraitFlight(aspect: aspect), RigMath.portraitAirport(aspect: aspect), a)
        var pose = RigPose.mix(land, port, b)

        if shakeT > 0 {
            shakeT = max(0, shakeT - dt)
            let k = shakeAmp * (shakeT / 0.32)
            pose.eye.y += sinf(time * 61) * 0.09 * k
            pose.eye.z += sinf(time * 47 + 1) * 0.06 * k
            pose.target.y += sinf(time * 61) * 0.09 * k
        }
        if abs(pose.fov - lastFov) > 0.001 {
            lastFov = pose.fov
            entity.camera.fieldOfViewInDegrees = pose.fov
        }
        entity.look(at: pose.target, from: pose.eye, relativeTo: nil)
    }

    private static func smooth(_ x: Float) -> Float {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }
}
