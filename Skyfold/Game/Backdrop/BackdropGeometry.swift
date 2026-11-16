import SwiftUI

// All of the sky's cut-paper shapes are generated here, once, from fixed seeds. Nothing in this file
// runs per frame. Shapes are stored as repeating "tiles" (one `period` wide) with y measured from the
// horizon line (0 = horizon, negative = up), so the painter only translates them.

/// Small deterministic generator (SplitMix64) so every launch cuts the same paper.
struct BackdropRNG {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0 ..< 1
    mutating func unit() -> CGFloat { CGFloat(next() >> 11) / CGFloat(UInt64(1) << 53) }
    mutating func range(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { lo + (hi - lo) * unit() }
    mutating func chance(_ p: CGFloat) -> Bool { unit() < p }
}

extension Path {
    /// Closed polygon wound the same way as `addRect` and `addEllipse` (clockwise on screen), so
    /// overlapping pieces fuse into one silhouette under the nonzero fill rule instead of cutting holes.
    mutating func backdropPolygon(_ points: [CGPoint]) {
        guard points.count >= 3 else { return }
        var area: CGFloat = 0
        for i in points.indices {
            let a = points[i], b = points[(i + 1) % points.count]
            area += a.x * b.y - b.x * a.y
        }
        let ordered: [CGPoint] = area >= 0 ? points : Array(points.reversed())
        move(to: ordered[0])
        for p in ordered.dropFirst() { addLine(to: p) }
        closeSubpath()
    }

    mutating func backdropCircle(_ center: CGPoint, _ r: CGFloat) {
        addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
    }

    mutating func backdropBox(x: CGFloat, top: CGFloat, width: CGFloat, bottom: CGFloat) {
        backdropPolygon([CGPoint(x: x, y: top), CGPoint(x: x + width, y: top),
                         CGPoint(x: x + width, y: bottom), CGPoint(x: x, y: bottom)])
    }
}

/// A piece of a layer that can be skipped when it is off screen: one cloud, or a run of windows.
/// `minX` and `maxX` are in tile coordinates, padded a little for the hard shadow offset.
struct BackdropChunk {
    let path: Path
    let minX: CGFloat
    let maxX: CGFloat

    init(_ path: Path) {
        self.path = path
        let r = path.boundingRect
        minX = r.minX - 1
        maxX = r.maxX + 8
    }
}

/// One star, in unit coordinates of the sky area. `size` is a dot radius in points on a 393 pt wide phone.
struct BackdropStar {
    let u: CGFloat
    let v: CGFloat
    let size: CGFloat
}

/// The cloud decks. Their heights depend on how tall the sky is (the engine's horizon differs per
/// orientation), so they are cut separately and re-cut only when the sky height moves by a whole bucket.
struct BackdropClouds {
    let skyBucket: CGFloat
    let far: [BackdropChunk]
    let mid: [BackdropChunk]
    let near: [BackdropChunk]

    /// Sky heights are bucketed so an eased horizon never re-cuts the paper every frame.
    static func bucket(_ skyHeight: CGFloat) -> CGFloat { max(40, (skyHeight / 40).rounded() * 40) }

    init(period P: CGFloat, k: CGFloat, skyBucket: CGFloat, quality: GraphicsQuality) {
        self.skyBucket = skyBucket
        // The clouds were drawn for a sky 0.80 k tall; shorter or taller skies scale the heights, not the sizes.
        let f = min(max(skyBucket / (0.80 * k), 0.55), 1.3)
        func band(_ r: ClosedRange<CGFloat>) -> ClosedRange<CGFloat> { (r.lowerBound * f)...(r.upperBound * f) }
        switch quality {
        case .low:
            far = BackdropGeometry.clouds(period: P, k: k, count: 2, width: 0.22...0.32, rise: band(0.20...0.42), streaks: 0, seed: 0xC10D1)
            mid = []
            near = BackdropGeometry.clouds(period: P, k: k, count: 1, width: 0.46...0.60, rise: band(0.46...0.62), streaks: 0, seed: 0xC10D3)
        case .balanced:
            far = BackdropGeometry.clouds(period: P, k: k, count: 2, width: 0.20...0.30, rise: band(0.20...0.44), streaks: 1, seed: 0xC10D1)
            mid = BackdropGeometry.clouds(period: P, k: k, count: 2, width: 0.30...0.44, rise: band(0.36...0.60), streaks: 0, seed: 0xC10D2)
            near = BackdropGeometry.clouds(period: P, k: k, count: 2, width: 0.46...0.64, rise: band(0.46...0.68), streaks: 0, seed: 0xC10D3)
        case .high:
            far = BackdropGeometry.clouds(period: P, k: k, count: 3, width: 0.18...0.28, rise: band(0.18...0.46), streaks: 2, seed: 0xC10D1)
            mid = BackdropGeometry.clouds(period: P, k: k, count: 3, width: 0.28...0.42, rise: band(0.34...0.62), streaks: 1, seed: 0xC10D2)
            near = BackdropGeometry.clouds(period: P, k: k, count: 2, width: 0.44...0.62, rise: band(0.46...0.70), streaks: 0, seed: 0xC10D3)
        }
    }
}

struct BackdropGeometryKey: Equatable {
    let k: CGFloat
    let m: CGFloat
    let quality: GraphicsQuality
}

struct BackdropGeometry {
    let key: BackdropGeometryKey
    /// Width of one repeating tile of every layer.
    let period: CGFloat

    let farHills: Path
    /// Mid layer: a far city outline (balanced, high) or a second ridge of hills (low).
    let midLayer: Path
    let midWindows: [BackdropChunk]
    let nearHills: Path

    let stars: [BackdropStar]
    /// Radius 1 at the origin: scaled by the painter into the sun and the moon.
    let unitCircle: Path
    /// Three flat craters in unit-disc coordinates.
    let craters: Path

    init(k: CGFloat, m: CGFloat, quality: GraphicsQuality) {
        key = BackdropGeometryKey(k: k, m: m, quality: quality)
        let P = (m * 1.25).rounded()
        period = P

        farHills = Self.facetedHills(period: P, k: k, amplitude: 0.100, spacing: 0.20, seed: 0xA11CE)
        if quality == .low {
            midLayer = Self.facetedHills(period: P, k: k, amplitude: 0.085, spacing: 0.15, seed: 0xB0B5)
            midWindows = []
        } else {
            let city = Self.city(period: P, k: k)
            midLayer = city.body
            midWindows = city.windows
        }
        nearHills = Self.roundHills(period: P, k: k, trees: quality != .low)

        stars = Self.stars(density: quality == .low ? 0.34 : (quality == .balanced ? 0.52 : 0.70))

        var disc = Path()
        disc.backdropCircle(.zero, 1)
        unitCircle = disc

        var craters = Path()
        craters.backdropCircle(CGPoint(x: -0.31, y: -0.20), 0.21)
        craters.backdropCircle(CGPoint(x: 0.29, y: 0.07), 0.14)
        craters.backdropCircle(CGPoint(x: -0.08, y: 0.43), 0.10)
        self.craters = craters
    }

    // MARK: Hills

    /// Folded-paper ridge: straight slopes, alternating peaks and valleys, a few flat tops.
    /// The right edge returns to the left edge's height so the tile repeats seamlessly.
    private static func facetedHills(period P: CGFloat, k: CGFloat, amplitude: CGFloat,
                                     spacing: CGFloat, seed: UInt64) -> Path {
        var rng = BackdropRNG(seed: seed)
        var n = max(6, Int((P / (spacing * k)).rounded()))
        if n % 2 == 1 { n += 1 }
        let step = P / CGFloat(n)
        let amp = amplitude * k
        let bottom = 0.03 * k

        var pts: [CGPoint] = []
        for i in 0..<n {
            let jitter = i == 0 ? 0 : rng.range(-0.28, 0.28) * step
            let x = CGFloat(i) * step + jitter
            let peak = i % 2 == 0
            let h = peak ? rng.range(0.50, 1.0) * amp : rng.range(0.08, 0.38) * amp
            pts.append(CGPoint(x: x, y: -h))
            // now and then a peak is cut flat, like a mesa
            if peak, i > 0, rng.chance(0.22) {
                pts.append(CGPoint(x: x + rng.range(0.25, 0.55) * step, y: -h))
            }
        }
        var path = Path()
        path.move(to: CGPoint(x: 0, y: bottom))
        path.addLine(to: pts[0])
        for p in pts.dropFirst() { path.addLine(to: p) }
        path.addLine(to: CGPoint(x: P, y: pts[0].y))
        path.addLine(to: CGPoint(x: P, y: bottom))
        path.closeSubpath()
        return path
    }

    /// Rounded cut-out hills in front, with a few paper trees. Overlapping ellipses fuse into one shape.
    private static func roundHills(period P: CGFloat, k: CGFloat, trees: Bool) -> Path {
        var rng = BackdropRNG(seed: 0xD00D)
        var path = Path()
        let bottom = 0.03 * k
        path.backdropBox(x: 0, top: -0.016 * k, width: P, bottom: bottom)

        struct Hill { let cx: CGFloat; let a: CGFloat; let b: CGFloat }
        var hills: [Hill] = []
        let count = max(3, Int((P / (0.52 * k)).rounded()))
        let slot = P / CGFloat(count)
        for i in 0..<count {
            let cx = (CGFloat(i) + 0.5) * slot + rng.range(-0.25, 0.25) * slot
            let a = rng.range(0.30, 0.52) * k
            let b = rng.range(0.045, 0.105) * k
            hills.append(Hill(cx: cx, a: a, b: b))
        }
        for h in hills {
            for wrap in [CGFloat(0), -P, P] {
                let cx = h.cx + wrap
                if cx + h.a < 0 || cx - h.a > P { continue }
                path.addEllipse(in: CGRect(x: cx - h.a, y: -h.b, width: 2 * h.a, height: 2 * h.b))
            }
        }

        guard trees else { return path }
        let treeCount = Int((P / (0.40 * k)).rounded())
        for t in 0..<treeCount {
            let h = hills[Int(rng.unit() * CGFloat(hills.count)) % hills.count]
            let x = h.cx + rng.range(-0.62, 0.62) * h.a
            guard x > 0.03 * P, x < 0.97 * P else { continue }
            let dx = (x - h.cx) / h.a
            let ground = -h.b * (1 - dx * dx).squareRoot() + 0.004 * k
            if t % 3 == 2 {
                // lollipop tree: trunk and round crown
                let trunk = rng.range(0.022, 0.032) * k
                let r = rng.range(0.013, 0.018) * k
                path.backdropBox(x: x - 0.0022 * k, top: ground - trunk, width: 0.0044 * k, bottom: ground)
                path.backdropCircle(CGPoint(x: x, y: ground - trunk - r * 0.7), r)
            } else {
                // cypress: a slim cut triangle
                let height = rng.range(0.050, 0.082) * k
                let half = rng.range(0.0085, 0.0125) * k
                path.backdropPolygon([CGPoint(x: x - half, y: ground),
                                      CGPoint(x: x + rng.range(-0.002, 0.002) * k, y: ground - height),
                                      CGPoint(x: x + half, y: ground)])
            }
        }
        return path
    }

    // MARK: City

    /// A far city outline: flat card blocks, a few gables, stepped roofs, a dome and thin towers,
    /// with punched windows (drawn flat amber at night by the painter).
    private static func city(period P: CGFloat, k: CGFloat) -> (body: Path, windows: [BackdropChunk]) {
        var rng = BackdropRNG(seed: 0xC17F)
        var body = Path()
        // Windows are grouped into slices of the tile so the painter can skip the ones off screen.
        let sliceCount = 12
        var slices = [Path](repeating: Path(), count: sliceCount)
        let bottom = 0.03 * k
        var x: CGFloat = 0
        var guardCount = 0

        while x < P - 0.004 * k, guardCount < 200 {
            guardCount += 1
            let remaining = P - x
            var w = rng.range(0.030, 0.080) * k
            if remaining - w < 0.036 * k { w = remaining }
            if x > 0, remaining > w + 0.03 * k, rng.chance(0.13) {
                x += rng.range(0.008, 0.024) * k
                continue
            }
            var h = rng.range(0.034, 0.105) * k
            let roll = rng.unit()
            var windowRows = true

            if roll < 0.10, w >= 0.058 * k {
                // domed hall
                h = rng.range(0.040, 0.066) * k
                body.backdropBox(x: x, top: -h, width: w, bottom: bottom)
                let rx = w * 0.42, ry = rx * 0.92
                body.addEllipse(in: CGRect(x: x + w / 2 - rx, y: -h - ry, width: 2 * rx, height: 2 * ry))
                body.backdropBox(x: x + w / 2 - 0.0025 * k, top: -h - ry - 0.024 * k, width: 0.005 * k, bottom: -h - ry * 0.6)
            } else if roll < 0.20 {
                // thin tower with a pointed cap
                w = min(0.020 * k, remaining)
                h = rng.range(0.115, 0.185) * k
                body.backdropBox(x: x, top: -h, width: w, bottom: bottom)
                body.backdropPolygon([CGPoint(x: x - 0.002 * k, y: -h),
                                      CGPoint(x: x + w / 2, y: -h - 0.032 * k),
                                      CGPoint(x: x + w + 0.002 * k, y: -h)])
                windowRows = false
            } else if roll < 0.46 {
                // gabled roof
                body.backdropBox(x: x, top: -h, width: w, bottom: bottom)
                body.backdropPolygon([CGPoint(x: x - 0.002 * k, y: -h),
                                      CGPoint(x: x + w * rng.range(0.35, 0.65), y: -h - w * 0.34),
                                      CGPoint(x: x + w + 0.002 * k, y: -h)])
            } else if roll < 0.72 {
                // stepped roof
                body.backdropBox(x: x, top: -h, width: w, bottom: bottom)
                let upper = h * rng.range(0.30, 0.65)
                let inset = w * rng.range(0.10, 0.30)
                body.backdropBox(x: x + inset, top: -h - upper, width: w * 0.62, bottom: -h + 1)
            } else {
                body.backdropBox(x: x, top: -h, width: w, bottom: bottom)
            }

            if windowRows, h >= 0.052 * k {
                let margin = 0.011 * k, colPitch = 0.017 * k, rowPitch = 0.021 * k
                let ww = 0.0072 * k, wh = 0.0100 * k
                let cols = max(0, Int((w - 2 * margin) / colPitch) + 1)
                let rows = max(0, Int((h - 0.016 * k) / rowPitch))
                if cols > 0, rows > 0 {
                    let totalW = CGFloat(cols - 1) * colPitch + ww
                    let startX = x + (w - totalW) / 2
                    for r in 0..<rows {
                        for c in 0..<cols where rng.chance(0.52) {
                            let wx = startX + CGFloat(c) * colPitch
                            slices[min(max(Int(wx / P * CGFloat(sliceCount)), 0), sliceCount - 1)].addRect(CGRect(x: wx,
                                                   y: -h + 0.012 * k + CGFloat(r) * rowPitch,
                                                   width: ww, height: wh))
                        }
                    }
                }
            }
            x += w
        }
        return (body, slices.filter { !$0.isEmpty }.map { BackdropChunk($0) })
    }

    // MARK: Clouds

    /// A flat cut-paper cloud: bumpy top, a row of scallops hanging off a flat base.
    /// `baseY` is the base line, `cx` the horizontal center.
    private static func addCloud(to path: inout Path, cx: CGFloat, baseY: CGFloat, width w: CGFloat,
                                 rng: inout BackdropRNG) {
        let h = w * rng.range(0.34, 0.46)

        // scalloped underside
        let s = w * 0.085
        let n = max(4, Int(((w - 2 * s) / (1.5 * s)).rounded()) + 1)
        let pitch = (w - 2 * s) / CGFloat(n - 1)
        for i in 0..<n {
            // hand-cut: every scallop a little different in size and a hair off the base line
            let rs = s * rng.range(0.84, 1.14)
            path.backdropCircle(CGPoint(x: cx - w / 2 + s + CGFloat(i) * pitch, y: baseY + rng.range(-0.10, 0.16) * s), rs)
        }
        // body between the scallops and the bumps, with rounded ends so no square corner pokes out
        let e = 0.18 * h
        path.backdropBox(x: cx - w / 2 + e, top: baseY - 0.36 * h, width: w - 2 * e, bottom: baseY)
        path.backdropCircle(CGPoint(x: cx - w / 2 + e, y: baseY - e), e)
        path.backdropCircle(CGPoint(x: cx + w / 2 - e, y: baseY - e), e)

        // bumpy top
        let m = rng.chance(0.5) ? 4 : 3
        let peakAt = rng.range(0.25, 0.6)
        for j in 0..<m {
            let t = CGFloat(j) / CGFloat(m - 1)
            let envelope = 1 - 0.55 * pow(abs(t - peakAt) * 2, 1.4)
            let r = h * (0.30 + 0.22 * envelope) * rng.range(0.92, 1.08)
            let x = cx + (t - 0.5) * 0.64 * w + rng.range(-0.02, 0.02) * w
            let top = baseY - h * (0.55 + 0.45 * envelope)
            path.backdropCircle(CGPoint(x: x, y: top + r), r)
        }
    }

    /// A thin paper strip of cloud with round ends.
    private static func addStreak(to path: inout Path, cx: CGFloat, baseY: CGFloat, width w: CGFloat, thickness t: CGFloat) {
        path.backdropBox(x: cx - w / 2 + t / 2, top: baseY - t / 2, width: w - t, bottom: baseY + t / 2)
        path.backdropCircle(CGPoint(x: cx - w / 2 + t / 2, y: baseY), t / 2)
        path.backdropCircle(CGPoint(x: cx + w / 2 - t / 2, y: baseY), t / 2)
    }

    fileprivate static func clouds(period P: CGFloat, k: CGFloat, count: Int,
                                   width: ClosedRange<CGFloat>, rise: ClosedRange<CGFloat>,
                                   streaks: Int, seed: UInt64) -> [BackdropChunk] {
        var rng = BackdropRNG(seed: seed)
        var out: [BackdropChunk] = []
        let slot = P / CGFloat(count)
        for i in 0..<count {
            var path = Path()
            let w = rng.range(width.lowerBound, width.upperBound) * k
            let cx = (CGFloat(i) + 0.5 + rng.range(-0.18, 0.18)) * slot
            let baseY = -rng.range(rise.lowerBound, rise.upperBound) * k
            addCloud(to: &path, cx: cx, baseY: baseY, width: w, rng: &rng)
            out.append(BackdropChunk(path))
        }
        for i in 0..<streaks {
            var path = Path()
            let w = rng.range(0.30, 0.46) * k
            let cx = (CGFloat(i) + 0.5 + 0.5 / CGFloat(max(streaks, 1)) + rng.range(-0.12, 0.12)) * (P / CGFloat(max(streaks, 1)))
            let baseY = -rng.range(rise.lowerBound * 0.9, rise.upperBound * 1.1) * k
            addStreak(to: &path, cx: min(max(cx, 0.5 * w), P - 0.5 * w), baseY: baseY, width: w, thickness: 0.017 * k)
            out.append(BackdropChunk(path))
        }
        return out
    }

    // MARK: Stars

    /// Jittered grid with some cells left empty, plus a few tight clusters. Sparse and uneven on purpose.
    private static func stars(density: CGFloat) -> [BackdropStar] {
        var rng = BackdropRNG(seed: 0x57A25)
        var out: [BackdropStar] = []
        let cols = 12, rows = 8

        func size() -> CGFloat {
            let r = rng.unit()
            if r < 0.66 { return rng.range(0.9, 1.35) }
            if r < 0.93 { return rng.range(1.5, 2.1) }
            return rng.range(2.3, 2.8)
        }
        for row in 0..<rows {
            for col in 0..<cols where rng.chance(density) {
                let u = (CGFloat(col) + rng.range(0.1, 0.9)) / CGFloat(cols)
                // thinner toward the horizon
                let v = (CGFloat(row) + rng.range(0.1, 0.9)) / CGFloat(rows)
                if rng.chance(v * 0.55) { continue }
                out.append(BackdropStar(u: u, v: v, size: size()))
            }
        }
        for _ in 0..<3 {
            let cu = rng.range(0.08, 0.92), cv = rng.range(0.05, 0.55)
            for _ in 0..<Int(rng.range(3, 5)) {
                let sz = rng.range(0.9, 1.7)
                out.append(BackdropStar(u: cu + rng.range(-0.045, 0.045), v: cv + rng.range(-0.05, 0.05), size: sz))
            }
        }
        return out
    }
}
