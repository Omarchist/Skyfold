import RealityKit
import simd

/// Hand-built flat-shaded geometry: cut-card shapes with real thickness, folded pyramids and
/// faceted mounds. Used for scenery and as stand-ins when a bundled model is missing.
/// Everything is built once at load time; nothing here runs per frame.
enum PaperMesh {

    /// Collects flat-shaded triangles (one normal per triangle, nothing shared).
    struct Builder {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        /// Adds a triangle. Counter-clockwise seen from the front; the normal follows the winding.
        mutating func tri(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) {
            let c3 = simd_cross(b - a, c - a)
            let len = simd_length(c3)
            guard len > 1e-9 else { return }
            let n = c3 / len
            let base = UInt32(positions.count)
            positions.append(contentsOf: [a, b, c])
            normals.append(contentsOf: [n, n, n])
            indices.append(contentsOf: [base, base + 1, base + 2])
        }

        mutating func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>) {
            tri(a, b, c)
            tri(a, c, d)
        }

        /// Axis-aligned box from `lo` to `hi`.
        mutating func box(lo: SIMD3<Float>, hi: SIMD3<Float>) {
            let (x0, y0, z0) = (lo.x, lo.y, lo.z)
            let (x1, y1, z1) = (hi.x, hi.y, hi.z)
            quad([x0, y0, z1], [x1, y0, z1], [x1, y1, z1], [x0, y1, z1]) // +Z
            quad([x1, y0, z0], [x0, y0, z0], [x0, y1, z0], [x1, y1, z0]) // -Z
            quad([x1, y0, z1], [x1, y0, z0], [x1, y1, z0], [x1, y1, z1]) // +X
            quad([x0, y0, z0], [x0, y0, z1], [x0, y1, z1], [x0, y1, z0]) // -X
            quad([x0, y1, z1], [x1, y1, z1], [x1, y1, z0], [x0, y1, z0]) // +Y
            quad([x0, y0, z0], [x1, y0, z0], [x1, y0, z1], [x0, y0, z1]) // -Y
        }

        /// A card cut to `outline` (counter-clockwise, star-shaped around `center`), given real thickness.
        mutating func card(_ outline: [SIMD2<Float>], center: SIMD2<Float>, thickness: Float,
                           z: Float = 0, offset: SIMD2<Float> = .zero) {
            let n = outline.count
            guard n >= 3 else { return }
            let zf = z + thickness * 0.5, zb = z - thickness * 0.5
            let c = center + offset
            let cf = SIMD3<Float>(c.x, c.y, zf), cb = SIMD3<Float>(c.x, c.y, zb)
            for i in 0..<n {
                let p = outline[i] + offset, q = outline[(i + 1) % n] + offset
                let pf = SIMD3<Float>(p.x, p.y, zf), qf = SIMD3<Float>(q.x, q.y, zf)
                let pb = SIMD3<Float>(p.x, p.y, zb), qb = SIMD3<Float>(q.x, q.y, zb)
                tri(cf, pf, qf)
                tri(cb, qb, pb)
                quad(pf, pb, qb, qf)
            }
        }

        /// A card whose outline is `bottom(x)...top(x)` over increasing x (any x-monotone shape).
        mutating func profileCard(xs: [Float], top: [Float], bottom: [Float], thickness: Float,
                                  z: Float = 0, offset: SIMD2<Float> = .zero) {
            let n = xs.count
            guard n >= 2, top.count == n, bottom.count == n else { return }
            let zf = z + thickness * 0.5, zb = z - thickness * 0.5
            func P(_ i: Int, _ y: Float, _ zz: Float) -> SIMD3<Float> { [xs[i] + offset.x, y + offset.y, zz] }
            for i in 0..<(n - 1) {
                let j = i + 1
                quad(P(i, bottom[i], zf), P(j, bottom[j], zf), P(j, top[j], zf), P(i, top[i], zf))
                quad(P(j, bottom[j], zb), P(i, bottom[i], zb), P(i, top[i], zb), P(j, top[j], zb))
                // top wall (faces up)
                quad(P(i, top[i], zf), P(j, top[j], zf), P(j, top[j], zb), P(i, top[i], zb))
                // bottom wall (faces down)
                quad(P(i, bottom[i], zb), P(j, bottom[j], zb), P(j, bottom[j], zf), P(i, bottom[i], zf))
            }
            quad(P(0, bottom[0], zb), P(0, bottom[0], zf), P(0, top[0], zf), P(0, top[0], zb))
            quad(P(n - 1, bottom[n - 1], zf), P(n - 1, bottom[n - 1], zb), P(n - 1, top[n - 1], zb), P(n - 1, top[n - 1], zf))
        }

        /// A pyramid with a regular `sides`-gon base at `y0`, apex at `y0 + height`.
        mutating func pyramid(sides: Int, radius: Float, y0: Float, height: Float,
                              center: SIMD2<Float> = .zero, twist: Float = 0, apexShift: SIMD2<Float> = .zero) {
            let apex = SIMD3<Float>(center.x + apexShift.x, y0 + height, center.y + apexShift.y)
            for i in 0..<sides {
                let a0 = twist + Float(i) / Float(sides) * 2 * .pi
                let a1 = twist + Float(i + 1) / Float(sides) * 2 * .pi
                let p0 = SIMD3<Float>(center.x + cosf(a0) * radius, y0, center.y + sinf(a0) * radius)
                let p1 = SIMD3<Float>(center.x + cosf(a1) * radius, y0, center.y + sinf(a1) * radius)
                tri(apex, p1, p0)
            }
            // Base (faces down).
            let b = SIMD3<Float>(center.x, y0, center.y)
            for i in 0..<sides {
                let a0 = twist + Float(i) / Float(sides) * 2 * .pi
                let a1 = twist + Float(i + 1) / Float(sides) * 2 * .pi
                let p0 = SIMD3<Float>(center.x + cosf(a0) * radius, y0, center.y + sinf(a0) * radius)
                let p1 = SIMD3<Float>(center.x + cosf(a1) * radius, y0, center.y + sinf(a1) * radius)
                tri(b, p0, p1)
            }
        }

        func mesh() -> MeshResource {
            var d = MeshDescriptor(name: "paper")
            d.positions = MeshBuffers.Positions(positions)
            d.normals = MeshBuffers.Normals(normals)
            d.primitives = .triangles(indices)
            if let m = try? MeshResource.generate(from: [d]) { return m }
            return MeshResource.generateBox(size: 0.1)
        }
    }

    // MARK: Shapes

    /// Top profile of a cloud: the union of circular bumps, (center x, radius, height squash).
    static func scallopTop(bumps: [(x: Float, r: Float, k: Float)], samples: Int = 40) -> (xs: [Float], top: [Float]) {
        var lo = Float.greatestFiniteMagnitude, hi = -Float.greatestFiniteMagnitude
        for b in bumps { lo = min(lo, b.x - b.r); hi = max(hi, b.x + b.r) }
        var xs: [Float] = [], top: [Float] = []
        for i in 0...samples {
            let x = lo + (hi - lo) * Float(i) / Float(samples)
            var y: Float = 0
            for b in bumps {
                let u = (x - b.x) / b.r
                if abs(u) < 1 { y = max(y, sqrtf(1 - u * u) * b.r * b.k) }
            }
            xs.append(x); top.append(y)
        }
        return (xs, top)
    }

    /// A five-point folded star (two shallow pyramids back to back).
    static func foldedStar(outer: Float, inner: Float, depth: Float) -> MeshResource {
        var b = Builder()
        let n = 10
        func p(_ i: Int) -> SIMD3<Float> {
            let a = Float(i) / Float(n) * 2 * .pi + .pi / 2
            let r = i % 2 == 0 ? outer : inner
            return [cosf(a) * r, sinf(a) * r, 0]
        }
        for i in 0..<n {
            let a = p(i), c = p((i + 1) % n)
            b.tri([0, 0, depth], a, c)
            b.tri([0, 0, -depth], c, a)
        }
        return b.mesh()
    }

    /// A faceted mound: a few rings with seeded jitter, like a hill folded from card.
    static func mound(sides: Int, radius: Float, height: Float, seed: UInt64) -> MeshResource {
        var rng = SplitMix64(seed: seed)
        var b = Builder()
        let rings: [(r: Float, h: Float)] = [(1.0, 0), (0.78, 0.42), (0.46, 0.78), (0.14, 1.0)]
        func ringPoint(_ ring: Int, _ i: Int, _ jit: [Float]) -> SIMD3<Float> {
            let a = Float(i % sides) / Float(sides) * 2 * .pi
            let r = rings[ring].r * radius * (ring == 0 ? 1 : jit[ring * sides + (i % sides)])
            let h = rings[ring].h * height * (ring == 0 ? 1 : jit[(ring + 3) * sides + (i % sides)])
            return [cosf(a) * r, h, sinf(a) * r]
        }
        var jit: [Float] = []
        for _ in 0..<(7 * sides) { jit.append(rng.range(0.9, 1.1)) }
        for ring in 0..<(rings.count - 1) {
            for i in 0..<sides {
                let a = ringPoint(ring, i, jit), c = ringPoint(ring, i + 1, jit)
                let d = ringPoint(ring + 1, i + 1, jit), e = ringPoint(ring + 1, i, jit)
                b.quad(a, e, d, c)
            }
        }
        // Top cap.
        let top = SIMD3<Float>(0, height * 1.02, 0)
        for i in 0..<sides {
            let a = ringPoint(rings.count - 1, i, jit), c = ringPoint(rings.count - 1, i + 1, jit)
            b.tri(top, c, a)
        }
        return b.mesh()
    }

    /// A flat disc lying in the XZ plane facing up (hard-edged print shadow).
    static func disc(sides: Int = 18) -> MeshResource {
        var b = Builder()
        for i in 0..<sides {
            let a0 = Float(i) / Float(sides) * 2 * .pi
            let a1 = Float(i + 1) / Float(sides) * 2 * .pi
            b.tri([0, 0, 0], [cosf(a1), 0, sinf(a1)], [cosf(a0), 0, sinf(a0)])
        }
        return b.mesh()
    }

    /// A flat ring in the XY plane facing +Z (shield pop).
    static func ring(inner: Float, outer: Float, sides: Int = 24) -> MeshResource {
        var b = Builder()
        for i in 0..<sides {
            let a0 = Float(i) / Float(sides) * 2 * .pi
            let a1 = Float(i + 1) / Float(sides) * 2 * .pi
            let o0 = SIMD3<Float>(cosf(a0) * outer, sinf(a0) * outer, 0)
            let o1 = SIMD3<Float>(cosf(a1) * outer, sinf(a1) * outer, 0)
            let i0 = SIMD3<Float>(cosf(a0) * inner, sinf(a0) * inner, 0)
            let i1 = SIMD3<Float>(cosf(a1) * inner, sinf(a1) * inner, 0)
            b.quad(i0, o0, o1, i1)
        }
        return b.mesh()
    }

    /// A paper fir: three stacked four-sided pyramids with a bit of lean.
    static func fir(height: Float, radius: Float, seed: UInt64) -> MeshResource {
        var rng = SplitMix64(seed: seed)
        var b = Builder()
        let tiers = 3
        for t in 0..<tiers {
            let f = Float(t) / Float(tiers)
            let r = radius * (1 - f * 0.45)
            let y0 = height * (0.16 + f * 0.30)
            let h = height * (0.52 - f * 0.1)
            b.pyramid(sides: 4, radius: r, y0: y0, height: h, twist: .pi / 4 + rng.range(-0.1, 0.1),
                      apexShift: [rng.range(-0.04, 0.04), rng.range(-0.04, 0.04)])
        }
        // Trunk.
        b.box(lo: [-radius * 0.09, 0, -radius * 0.09], hi: [radius * 0.09, height * 0.2, radius * 0.09])
        return b.mesh()
    }

    /// A faceted hemisphere used for domes (stand-in model only).
    static func dome(radius: Float, sides: Int = 9) -> MeshResource {
        var b = Builder()
        let rings: [(r: Float, h: Float)] = [(1, 0), (0.92, 0.38), (0.7, 0.72), (0.34, 0.94)]
        func pt(_ ring: Int, _ i: Int) -> SIMD3<Float> {
            let a = Float(i % sides) / Float(sides) * 2 * .pi
            return [cosf(a) * rings[ring].r * radius, rings[ring].h * radius, sinf(a) * rings[ring].r * radius]
        }
        for ring in 0..<(rings.count - 1) {
            for i in 0..<sides {
                b.quad(pt(ring, i), pt(ring + 1, i), pt(ring + 1, i + 1), pt(ring, i + 1))
            }
        }
        for i in 0..<sides { b.tri([0, radius * 1.02, 0], pt(rings.count - 1, i + 1), pt(rings.count - 1, i)) }
        return b.mesh()
    }

    static func box(_ size: SIMD3<Float>, center: SIMD3<Float> = .zero) -> MeshResource {
        var b = Builder()
        b.box(lo: center - size * 0.5, hi: center + size * 0.5)
        return b.mesh()
    }
}
