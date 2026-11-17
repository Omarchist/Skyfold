import SwiftUI

/// Engine writes this every frame; the backdrop reads it from its own TimelineView.
/// Deliberately NOT @Observable so writing it never invalidates SwiftUI.
final class BackdropClock {
    var scroll: Double = 0   // meters flown this run
    var speed: Float = 0     // m/s
    init() {}
}

/// The 2D sky behind the transparent 3D view, printed like a travel poster: flat stepped bands,
/// a flat sun or moon with a hard offset shadow, flat star dots, cut-card hills and a far city
/// at three depths, and scalloped paper clouds. No gradients, no glow, no blur.
///
/// Opaque and full-bleed. Cheap by construction: every shape is generated once from fixed seeds,
/// then each frame is a few dozen flat fills and translations. Nothing is allocated per frame
/// while the palette is steady.
///
/// `horizonFraction` is where the ground line sits as a fraction of the height from the top.
/// Everything below it is filled with `palette.ground`, so a 3D ground plane that starts a little
/// higher or lower never shows a gap. Match the 3D camera's horizon: with the current rigs
/// (`RigMath.horizonFraction`) that is about 0.62 in landscape (side camera) and about 0.35 in
/// portrait (chase camera). Any value from 0.25 to 0.9 works; cloud heights follow the sky height.
struct SkyBackdrop: View {
    let palette: Palette
    let clock: BackdropClock
    let quality: GraphicsQuality
    let horizonFraction: CGFloat
    let paused: Bool

    @State private var painter = BackdropPainter()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(palette: Palette, clock: BackdropClock, quality: GraphicsQuality,
         horizonFraction: CGFloat = 0.62, paused: Bool = false) {
        self.palette = palette
        self.clock = clock
        self.quality = quality
        self.horizonFraction = horizonFraction
        self.paused = paused
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: quality == .low ? 1.0 / 30.0 : 1.0 / 60.0, paused: paused)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas(opaque: true) { context, size in
                painter.draw(into: &context, size: size, time: time, palette: palette, clock: clock,
                             quality: quality, horizonFraction: horizonFraction, reduceMotion: reduceMotion)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Debug hook: set `onDraw` to receive the main-thread seconds each Canvas pass took.
/// Inert (one nil check) in normal play.
enum BackdropProbe {
    static var onDraw: ((Double) -> Void)?
}

// MARK: - Colors

/// Every shading the painter needs, derived from one Palette. Rebuilt only when the palette changes.
struct BackdropColors {
    typealias Shading = GraphicsContext.Shading

    let bands: [Shading]
    let stars: Shading
    let drawStars: Bool
    let disc: Shading
    let discShadow: Shading
    let crater: Shading
    let drawCraters: Bool
    let hillFar: Shading, hillMid: Shading, hillNear: Shading
    let shadowFar: Shading, shadowMid: Shading, shadowNear: Shading
    let cloudFar: Shading, cloudMid: Shading, cloudNear: Shading, cloudShadow: Shading
    let windowLit: Shading
    let windowDark: Shading
    let drawLitWindows: Bool
    let drawDarkWindows: Bool
    let ground: Shading
    /// 0 = day, 0.5 = dusk, 1 = night, recovered from the palette itself.
    let night: Double

    init(_ p: Palette) {
        // Palette.at(nightness:) ramps stars 0 -> 0.2 -> 1 over day -> dusk -> night: invert that.
        let sv = min(max(p.starsVisible, 0), 1)
        night = sv <= 0.2 ? sv / 0.2 * 0.5 : 0.5 + (sv - 0.2) / 0.8 * 0.5

        // The deep ink every hard shadow is printed in: the sky's top color pushed nearly to black.
        let deep = p.skyTop.scaled(0.22)
        func flat(_ c: RGBA) -> Shading { .color(c.color) }
        let shadowAlpha = 0.16 + 0.12 * night

        // Six flat bands: four steps from skyTop to skyBottom, one more at skyBottom, then the horizon band.
        var b: [Shading] = []
        for i in 0..<5 { b.append(flat(p.skyTop.mixed(with: p.skyBottom, Double(i) / 4))) }
        b.append(flat(p.horizonGlow))
        bands = b

        let bone = Palette.night.sun
        // Stars come up late in dusk (a few faint specks at 0.1 would just look like dust on the paper).
        stars = flat(bone.withAlpha(0.85 * min(sv * 1.15, 1)))
        drawStars = sv > 0.08

        disc = flat(p.sun)
        discShadow = flat(deep.withAlpha(0.14 + 0.10 * night))
        let moonness = min(max((night - 0.62) / 0.28, 0), 1)
        crater = flat(p.sun.mixed(with: deep, 0.13).withAlpha(moonness))
        drawCraters = moonness > 0.02

        let farHill = p.printGroundFar
        let nearHill = p.printGround.mixed(with: deep, 0.12)
        hillFar = flat(farHill)
        hillMid = flat(farHill.mixed(with: p.printGround, 0.5))
        hillNear = flat(nearHill)
        let shadow = flat(deep.withAlpha(shadowAlpha))
        shadowFar = shadow
        shadowMid = shadow
        shadowNear = shadow

        cloudFar = flat(p.cloud.mixed(with: p.skyBottom, 0.30))
        cloudMid = flat(p.cloud.mixed(with: p.skyBottom, 0.12))
        cloudNear = flat(p.cloud)
        cloudShadow = shadow

        // Window light is sodium amber from the night palette, scaled by how lit the windows are.
        windowLit = flat(Palette.night.accent.withAlpha(min(max(p.windowGlow, 0), 1)))
        drawLitWindows = p.windowGlow > 0.02
        windowDark = flat(deep.withAlpha(0.13 * (1 - min(max(p.windowGlow, 0), 1))))
        drawDarkWindows = p.windowGlow < 0.98

        ground = flat(p.printGround)
    }
}

// MARK: - Size-dependent shapes

/// Shapes that depend on the canvas size and the horizon line. Rebuilt on rotation or when
/// the engine moves the horizon, never in steady state.
struct BackdropFrame {
    let size: CGSize
    let horizonKey: CGFloat
    let horizonY: CGFloat
    let bands: [Path]
    let ground: Path
    let stars: Path
    let discRadius: CGFloat
    let discHigh: CGFloat
    let discLow: CGFloat

    init(size: CGSize, horizonKey: CGFloat, geometry: BackdropGeometry) {
        self.size = size
        self.horizonKey = horizonKey
        let W = size.width, H = size.height
        let k = geometry.key.k
        let hy = (H * horizonKey).rounded()
        horizonY = hy

        // Band edges as fractions of the sky height: wide at the top, narrowing toward a thick horizon band.
        let edges: [CGFloat] = [0, 0.20, 0.38, 0.54, 0.68, 0.80, 1.0]
        var rects: [Path] = []
        for i in 0..<6 {
            let top = (hy * edges[i]).rounded()
            let bottom = i == 5 ? hy + 1 : (hy * edges[i + 1]).rounded() + 1
            rects.append(Path(CGRect(x: 0, y: top, width: W, height: bottom - top)))
        }
        bands = rects
        ground = Path(CGRect(x: 0, y: hy, width: W, height: H - hy + 2))

        let s = max(k / 393, 0.8)
        let skyH = max(hy - 0.10 * k, 1)
        var dots = Path()
        for st in geometry.stars {
            dots.backdropCircle(CGPoint(x: st.u * W, y: st.v * skyH), st.size * s)
        }
        stars = dots

        let r = (0.108 * k).rounded()
        discRadius = r
        discHigh = max(hy * 0.30, r * 1.5 + 28 * s)
        discLow = hy - r * 0.95
    }
}

// MARK: - Painter

/// Holds the cached shapes and the little bit of state a frame needs. A class, so mutating it from
/// inside the Canvas closure never touches SwiftUI state.
final class BackdropPainter {
    private var geometry: BackdropGeometry?
    private var frame: BackdropFrame?
    private var cloudDecks: BackdropClouds?
    private var colors: BackdropColors?
    private var colorsPalette: Palette?
    private var lastTime: Double = -1
    private var drift: Double = 0

    // Parallax, as a fraction of how fast the 3D world scrolls past the plane.
    private static let farHillsPar = 0.050, midPar = 0.110, nearHillsPar = 0.240
    private static let farCloudPar = 0.035, midCloudPar = 0.075, nearCloudPar = 0.150
    // Idle cloud drift in points per second, so the sky is never frozen on the pad or at a gate.
    private static let farCloudDrift = 2.5, midCloudDrift = 4.5, nearCloudDrift = 7.0

    init() {}

    func draw(into ctx: inout GraphicsContext, size: CGSize, time: Double, palette: Palette,
              clock: BackdropClock, quality: GraphicsQuality, horizonFraction: CGFloat, reduceMotion: Bool) {
        guard size.width > 1, size.height > 1 else { return }
        let probe = BackdropProbe.onDraw
        let started = probe == nil ? 0 : ProcessInfo.processInfo.systemUptime

        // Cached shapes and colors, rebuilt only when their inputs change.
        let k = min(size.width, size.height).rounded()
        let m = max(size.width, size.height).rounded()
        let key = BackdropGeometryKey(k: k, m: m, quality: quality)
        if geometry?.key != key {
            geometry = BackdropGeometry(k: k, m: m, quality: quality)
            frame = nil
            cloudDecks = nil
        }
        let horizonKey = (min(max(horizonFraction, 0.2), 0.95) * 1000).rounded() / 1000
        if frame == nil || frame?.size != size || frame?.horizonKey != horizonKey {
            frame = BackdropFrame(size: size, horizonKey: horizonKey, geometry: geometry!)
        }
        let bucket = BackdropClouds.bucket(frame!.horizonY)
        if cloudDecks == nil || cloudDecks?.skyBucket != bucket {
            cloudDecks = BackdropClouds(period: geometry!.period, k: k, skyBucket: bucket, quality: quality)
        }
        if colors == nil || colorsPalette != palette {
            colors = BackdropColors(palette)
            colorsPalette = palette
        }
        guard let geo = geometry, let fr = frame, let col = colors, let decks = cloudDecks else { return }

        // Idle drift clock: frozen while paused, never jumps after a long pause.
        if lastTime < 0 { lastTime = time }
        let dt = min(max(time - lastTime, 0), 0.1)
        lastTime = time
        if !reduceMotion { drift += dt * (1 + Double(clock.speed) * 0.02) }

        let W = size.width
        let hy = fr.horizonY
        let s = max(geo.key.k / 393, 0.8)
        let P = geo.period
        let portrait = size.height > size.width
        // Points of travel per meter flown. A chase camera barely slides the sky sideways, so portrait scrolls less.
        let travel = clock.scroll * Double(geo.key.m / 30) * (portrait ? 0.45 : 1)

        // 1. Sky bands
        ctx.transform = .identity
        for i in 0..<6 { ctx.fill(fr.bands[i], with: col.bands[i]) }

        // 2. Stars, fixed in the sky
        if col.drawStars {
            ctx.fill(fr.stars, with: col.stars)
        }

        // 3. Sun, setting into the hills, then the moon rising out of them. One disc, one role.
        let n = col.night
        let u = abs(2 * n - 1)
        let rise = u * u * (3 - 2 * u)
        let r = fr.discRadius
        let cx = W * (0.74 - 0.47 * n)
        let cy = fr.discLow + (fr.discHigh - fr.discLow) * rise
        let off = 4 * s
        ctx.transform = CGAffineTransform(a: r, b: 0, c: 0, d: r, tx: cx + off, ty: cy + off * 0.85)
        ctx.fill(geo.unitCircle, with: col.discShadow)
        ctx.transform = CGAffineTransform(a: r, b: 0, c: 0, d: r, tx: cx, ty: cy)
        ctx.fill(geo.unitCircle, with: col.disc)
        if col.drawCraters { ctx.fill(geo.craters, with: col.crater) }

        // 4. Layers, back to front
        func offset(_ par: Double, _ idle: Double) -> CGFloat {
            CGFloat(travel * par + drift * idle * Double(s))
        }
        if !decks.far.isEmpty {
            chunks(&ctx, decks.far, body: col.cloudFar, shadow: col.cloudShadow, dx: 3 * s, dy: 2.6 * s,
                  scroll: offset(Self.farCloudPar, Self.farCloudDrift), period: P, width: W, y: hy)
        }
        tiles(&ctx, geo.farHills, body: col.hillFar, shadow: col.shadowFar, dx: 2.5 * s, dy: 2 * s,
              scroll: offset(Self.farHillsPar, 0), period: P, width: W, y: hy)
        if !decks.mid.isEmpty {
            chunks(&ctx, decks.mid, body: col.cloudMid, shadow: col.cloudShadow, dx: 3.5 * s, dy: 3 * s,
                  scroll: offset(Self.midCloudPar, Self.midCloudDrift), period: P, width: W, y: hy)
        }
        let midScroll = offset(Self.midPar, 0)
        tiles(&ctx, geo.midLayer, body: col.hillMid, shadow: col.shadowMid, dx: 3 * s, dy: 2.5 * s,
              scroll: midScroll, period: P, width: W, y: hy)
        if !geo.midWindows.isEmpty {
            if col.drawDarkWindows {
                chunks(&ctx, geo.midWindows, body: col.windowDark, shadow: nil, dx: 0, dy: 0,
                       scroll: midScroll, period: P, width: W, y: hy)
            }
            if col.drawLitWindows {
                chunks(&ctx, geo.midWindows, body: col.windowLit, shadow: nil, dx: 0, dy: 0,
                       scroll: midScroll, period: P, width: W, y: hy)
            }
        }
        if !decks.near.isEmpty {
            chunks(&ctx, decks.near, body: col.cloudNear, shadow: col.cloudShadow, dx: 4 * s, dy: 3.4 * s,
                  scroll: offset(Self.nearCloudPar, Self.nearCloudDrift), period: P, width: W, y: hy)
        }
        tiles(&ctx, geo.nearHills, body: col.hillNear, shadow: col.shadowNear, dx: 4 * s, dy: 3 * s,
              scroll: offset(Self.nearHillsPar, 0), period: P, width: W, y: hy)

        // 5. Ground, flat, down to the bottom edge. The 3D ground plane draws over it.
        ctx.transform = .identity
        ctx.fill(fr.ground, with: col.ground)

        if let probe { probe(ProcessInfo.processInfo.systemUptime - started) }
    }

    /// Like `tiles`, but for layers made of separate pieces (clouds, window runs): only the pieces that
    /// touch the screen are filled. All shadows go down first so a cloud's shadow never lies over its neighbour.
    private func chunks(_ ctx: inout GraphicsContext, _ pieces: [BackdropChunk], body: GraphicsContext.Shading,
                        shadow: GraphicsContext.Shading?, dx: CGFloat, dy: CGFloat,
                        scroll: CGFloat, period: CGFloat, width: CGFloat, y: CGFloat) {
        let x0 = -scroll.truncatingRemainder(dividingBy: period)   // in (-period, 0]
        let copies = x0 + period < width ? 2 : 1
        if let shadow {
            for copy in 0..<copies {
                let ox = x0 + CGFloat(copy) * period
                ctx.transform = CGAffineTransform(translationX: ox + dx, y: y + dy)
                for piece in pieces where piece.maxX + ox + dx > 0 && piece.minX + ox + dx < width {
                    ctx.fill(piece.path, with: shadow)
                }
            }
        }
        for copy in 0..<copies {
            let ox = x0 + CGFloat(copy) * period
            ctx.transform = CGAffineTransform(translationX: ox, y: y)
            for piece in pieces where piece.maxX + ox > 0 && piece.minX + ox < width {
                ctx.fill(piece.path, with: body)
            }
        }
    }

    /// Draws a repeating tile (shadow first, then body) so it covers the full width.
    /// The tile slides left by `scroll` points and wraps every `period`.
    private func tiles(_ ctx: inout GraphicsContext, _ path: Path, body: GraphicsContext.Shading,
                       shadow: GraphicsContext.Shading?, dx: CGFloat, dy: CGFloat,
                       scroll: CGFloat, period: CGFloat, width: CGFloat, y: CGFloat) {
        let x0 = -scroll.truncatingRemainder(dividingBy: period)   // in (-period, 0]
        let second = x0 + period < width
        if let shadow {
            ctx.transform = CGAffineTransform(translationX: x0 + dx, y: y + dy)
            ctx.fill(path, with: shadow)
            if second {
                ctx.transform = CGAffineTransform(translationX: x0 + period + dx, y: y + dy)
                ctx.fill(path, with: shadow)
            }
        }
        ctx.transform = CGAffineTransform(translationX: x0, y: y)
        ctx.fill(path, with: body)
        if second {
            ctx.transform = CGAffineTransform(translationX: x0 + period, y: y)
            ctx.fill(path, with: body)
        }
    }
}
