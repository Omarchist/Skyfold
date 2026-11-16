import SwiftUI

// The menu's scenery: a sky in stepped flat bands, a red sun (a moon with stars at night),
// cut-paper clouds that drift, and two layers of card hills with a skyline behind them.
// Three canvases: the sky and the ground draw once, only the clouds are on a timeline.

struct MenuBackdrop: View {
    /// Center of the sun or moon in screen coordinates. nil puts it at a default spot.
    var sun: CGPoint?
    var sunRadius: CGFloat
    /// Where the ground starts, as a fraction of the height.
    var horizon: CGFloat
    /// True while a screen covers the menu (the clouds stop).
    var covered: Bool

    @Environment(\.palette) private var palette
    @Environment(\.uiNightness) private var night
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            MenuSky(palette: palette, night: night, horizon: horizon, sun: sun, sunRadius: sunRadius)
            MenuClouds(palette: palette, horizon: horizon, animated: !(covered || reduceMotion))
            MenuGround(palette: palette, night: night, horizon: horizon)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private func menuSmooth(_ x: Double) -> Double {
    let t = min(max(x, 0), 1)
    return t * t * (3 - 2 * t)
}

// MARK: - Sky

private struct MenuSky: View, Equatable {
    let palette: Palette
    let night: Double
    let horizon: CGFloat
    let sun: CGPoint?
    let sunRadius: CGFloat

    var body: some View {
        let palette = palette, night = night, horizon = horizon, sun = sun, sunRadius = sunRadius
        Canvas { ctx, size in
            let hy = size.height * horizon

            // Stepped bands, tighter toward the horizon like a screen-printed poster.
            let weights: [CGFloat] = [1.5, 1.25, 1.05, 0.9, 0.78, 0.66]
            let total = weights.reduce(0, +)
            var y: CGFloat = 0
            for (i, w) in weights.enumerated() {
                let h = hy * w / total
                let c = palette.skyTop.mixed(with: palette.skyBottom, Double(i) / Double(weights.count - 1))
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: h + 1)), with: .color(c.color))
                y += h
            }
            let strip = size.height * 0.035
            ctx.fill(Path(CGRect(x: 0, y: hy - strip, width: size.width, height: strip + 2)),
                     with: .color(palette.horizonGlow.color))

            // Stars: small flat diamonds, a few in amber.
            if palette.starsVisible > 0.02 {
                var rng = SeededRandom("menu.stars")
                for i in 0..<46 {
                    let x = rng.next() * size.width
                    let sy = rng.next() * hy * 0.8
                    let s = 1.4 + rng.next() * 2.3
                    let bright = 0.45 + 0.55 * rng.next()
                    let tint = i % 11 == 0 ? palette.accent : palette.sun
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: sy - s))
                    p.addLine(to: CGPoint(x: x + s * 0.7, y: sy))
                    p.addLine(to: CGPoint(x: x, y: sy + s))
                    p.addLine(to: CGPoint(x: x - s * 0.7, y: sy))
                    p.closeSubpath()
                    ctx.fill(p, with: .color(tint.withAlpha(palette.starsVisible * bright).color))
                }
            }

            // Sun by day (a flat red disc with a ring, like a postmark), crescent moon by night.
            let c = sun ?? CGPoint(x: size.width * 0.72, y: hy * 0.42)
            let r = sunRadius
            let moonT = menuSmooth((night - 0.35) / 0.4)
            let disc = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            if moonT < 0.98 {
                let ringR = r * 1.2
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - ringR, y: c.y - ringR, width: ringR * 2, height: ringR * 2)),
                           with: .color(palette.accent.withAlpha(0.6 * (1 - moonT)).color), lineWidth: 2)
                ctx.fill(Path(ellipseIn: disc.offsetBy(dx: 4, dy: 4)),
                         with: .color(palette.ink.withAlpha(0.12 * (1 - moonT)).color))
            }
            let cutDX = r * (2.4 - 1.86 * moonT)
            let crescent = Path(ellipseIn: disc)
                .subtracting(Path(ellipseIn: disc.offsetBy(dx: cutDX, dy: -r * 0.14 * moonT)))
            ctx.fill(crescent, with: .color(palette.accent.mixed(with: palette.sun, moonT).color))
        }
    }
}

// MARK: - Clouds

private struct MenuCloudSpec {
    let x: CGFloat       // start, 0...1 of the travel span
    let y: CGFloat       // 0...1 of the sky height
    let width: CGFloat
    let speed: CGFloat   // points per second
    let variant: Int
    let far: Bool

    static let all: [MenuCloudSpec] = {
        var rng = SeededRandom("menu.clouds")
        var out: [MenuCloudSpec] = []
        for i in 0..<8 {
            let far = i < 3
            out.append(MenuCloudSpec(
                x: rng.next(),
                y: far ? 0.20 + rng.next() * 0.42 : 0.08 + rng.next() * 0.7,
                width: far ? 62 + rng.next() * 40 : 104 + rng.next() * 70,
                speed: far ? 2.6 + rng.next() * 2 : 6 + rng.next() * 6,
                variant: i, far: far))
        }
        return out
    }()
}

private struct MenuClouds: View {
    let palette: Palette
    let horizon: CGFloat
    let animated: Bool

    var body: some View {
        let palette = palette, horizon = horizon
        let animated = animated
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !animated)) { timeline in
            let t = animated ? timeline.date.timeIntervalSinceReferenceDate : 0
            Canvas { ctx, size in
                let hy = size.height * horizon
                let near = palette.cloud
                let far = palette.cloud.mixed(with: palette.skyBottom, 0.5)
                for cloud in MenuCloudSpec.all {
                    let h = cloud.width * 0.5
                    let span = size.width + cloud.width * 2
                    let x = (cloud.x * span + CGFloat(t) * cloud.speed).truncatingRemainder(dividingBy: span) - cloud.width
                    let y = hy * cloud.y
                    let rect = CGRect(x: x, y: y, width: cloud.width, height: h)
                    let shape = FlatCloudShape(variant: cloud.variant).path(in: rect)
                    ctx.fill(shape.offsetBy(dx: 3, dy: 3), with: .color(palette.printShadow))
                    ctx.fill(shape, with: .color((cloud.far ? far : near).color))
                }
            }
        }
    }
}

// MARK: - Ground

private struct MenuGround: View, Equatable {
    let palette: Palette
    let night: Double
    let horizon: CGFloat

    var body: some View {
        let palette = palette, horizon = horizon
        Canvas { ctx, size in
            let hy = size.height * horizon
            var rng = SeededRandom("menu.ground")

            // A skyline of card buildings behind the far hills, lit amber at night.
            let haze = palette.groundFar.mixed(with: palette.skyBottom, 0.38)
            var x: CGFloat = -6
            var index = 0
            while x < size.width {
                let w = 15 + rng.next() * 26
                let h = 20 + rng.next() * 46
                let body = CGRect(x: x, y: hy - h + 6, width: w, height: h + 40)
                ctx.fill(Path(body), with: .color(haze.color))
                if index % 5 == 2 {
                    // A dome, as on the landmark models.
                    let dome = CGRect(x: x + w * 0.12, y: hy - h - w * 0.36 + 6, width: w * 0.76, height: w * 0.76)
                    ctx.fill(Path(ellipseIn: dome), with: .color(haze.color))
                } else if index % 3 == 0 {
                    var roof = Path()
                    roof.move(to: CGPoint(x: x - 1.5, y: hy - h + 6))
                    roof.addLine(to: CGPoint(x: x + w / 2, y: hy - h - 9 + 6))
                    roof.addLine(to: CGPoint(x: x + w + 1.5, y: hy - h + 6))
                    roof.closeSubpath()
                    ctx.fill(roof, with: .color(haze.color))
                }
                if palette.windowGlow > 0.05 {
                    let cols = max(1, Int(w / 9))
                    for col in 0..<cols {
                        for row in 0..<Int(h / 14) where rng.next() > 0.45 {
                            let wx = x + 3.5 + CGFloat(col) * 8.5
                            let wy = hy - h + 14 + CGFloat(row) * 12
                            ctx.fill(Path(CGRect(x: wx, y: wy, width: 3.4, height: 4.4)),
                                     with: .color(palette.accent.withAlpha(0.85 * palette.windowGlow).color))
                        }
                    }
                }
                x += w + 2 + rng.next() * 7
                index += 1
            }

            // Two layers of faceted card hills; each casts a hard shadow upward-left onto the one behind.
            func ridge(top: CGFloat, amp: CGFloat, step: CGFloat, seed: String) -> Path {
                var r = SeededRandom(seed)
                var p = Path()
                p.move(to: CGPoint(x: -4, y: size.height + 4))
                var px: CGFloat = -4
                var up = r.next() > 0.5
                while px < size.width + step {
                    let dy = amp * (up ? 0.15 + 0.85 * r.next() : -0.1 * r.next())
                    p.addLine(to: CGPoint(x: px, y: top - dy))
                    px += step * (0.6 + 0.8 * r.next())
                    up.toggle()
                }
                p.addLine(to: CGPoint(x: size.width + 4, y: size.height + 4))
                p.closeSubpath()
                return p
            }
            let far = ridge(top: hy + 8, amp: 20, step: 70, seed: "menu.far")
            ctx.fill(far.offsetBy(dx: 0, dy: -3), with: .color(palette.printShadow))
            ctx.fill(far, with: .color(palette.groundFar.color))
            let near = ridge(top: hy + size.height * 0.05, amp: 12, step: 90, seed: "menu.near")
            ctx.fill(near.offsetBy(dx: 0, dy: -3), with: .color(palette.printShadow))
            ctx.fill(near, with: .color(palette.ground.color))
        }
    }
}
