import SwiftUI

// A postcard, front and back. Drawn at 300 x 200 units and scaled to whatever width it is given.

private enum PostcardColor {
    static let stock = RGBA(hex: 0xF3E8CF)
    static let stockEdge = RGBA(hex: 0xD8C9A8)
    static let night = RGBA(hex: 0x0E1324)
    static let airmailRed = RGBA(hex: 0xD6402B)
    static let airmailBlue = RGBA(hex: 0x2C4F9E)
}

/// How the printed card looks in the current light: the same stock, a little under-lit at night.
private struct PostcardLight {
    let dim: Double

    init(_ palette: Palette) { dim = palette.isDark ? 0.2 : 0 }

    func ink(_ c: RGBA) -> Color { c.mixed(with: PostcardColor.night, dim).color }
    var stock: Color { ink(PostcardColor.stock) }
    var edge: Color { ink(PostcardColor.stockEdge) }
}

// MARK: - Front

struct PostcardFront: View {
    let city: City
    let date: Date?
    var shadow: CGFloat = 3

    @Environment(\.palette) private var palette

    var body: some View {
        let light = PostcardLight(palette)
        let inks = PostcardArt.inks(for: city.index)
        let plate = PostcardArt.plate(for: city.index)
        let shape = Rectangle()
        GeometryReader { geo in
            let s = geo.size.width / 300
            ZStack(alignment: .topLeading) {
                shape.fill(light.stock)
                Canvas { ctx, _ in
                    ctx.scaleBy(x: s, y: s)
                    ctx.clip(to: Path(PostcardArt.window))
                    for item in plate.items {
                        var c = ctx
                        c.translateBy(x: item.ink.offset.x, y: item.ink.offset.y)
                        let color: Color
                        switch item.ink {
                        case .a: color = light.ink(inks.a)
                        case .b: color = light.ink(inks.b)
                        case .c: color = light.ink(inks.c)
                        case .k:
                            color = light.ink(inks.k)
                            c.blendMode = .multiply
                        case .paper: color = light.stock
                        }
                        c.fill(item.path, with: .color(color))
                    }
                }
                Rectangle()
                    .strokeBorder(light.ink(inks.k).opacity(0.55), lineWidth: max(0.5, 0.6 * s))
                    .frame(width: 280 * s, height: 180 * s)
                    .offset(x: 10 * s, y: 10 * s)
                nameLabel(s: s, inks: inks, light: light)
                    .offset(x: 18 * s, y: 156 * s)
                PostcardStampView(city: city, width: 42 * s)
                    .rotationEffect(.degrees(3))
                    .offset(x: 240 * s, y: 16 * s)
                PostcardPostmark(city: city, date: date, size: 40 * s, waves: true)
                    .rotationEffect(.degrees(-9))
                    .offset(x: 146 * s, y: 30 * s)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .overlay(shape.strokeBorder(light.edge, lineWidth: 0.8))
        }
        // A scaled drawing: its type follows the card width, not the text-size setting.
        .dynamicTypeSize(.large)
        .aspectRatio(3 / 2, contentMode: .fit)
        .printShadow(shape, offset: shadow)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Postcard of \(city.name), \(city.country)")
    }

    private func nameLabel(s: CGFloat, inks: PostcardInks, light: PostcardLight) -> some View {
        Text(city.name)
            .font(.display(21 * s, weight: .bold))
            .tracking(-0.3 * s)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(light.stock)
            .padding(.horizontal, 7 * s)
            .padding(.vertical, 2.5 * s)
            .background(Rectangle().fill(light.ink(inks.k)))
            .background(Rectangle().fill(light.ink(inks.c)).offset(x: 2.4 * s, y: 2.4 * s))
            .rotationEffect(.degrees(-1.6), anchor: .bottomLeading)
            .frame(maxWidth: 190 * s, alignment: .leading)
    }
}

// MARK: - Back

struct PostcardBack: View {
    let city: City
    let date: Date?
    var shadow: CGFloat = 3

    @Environment(\.palette) private var palette

    var body: some View {
        let light = PostcardLight(palette)
        let inks = PostcardArt.inks(for: city.index)
        let key = light.ink(inks.k)
        let shape = Rectangle()
        GeometryReader { geo in
            let s = geo.size.width / 300
            ZStack(alignment: .topLeading) {
                shape.fill(light.stock)
                // Airmail edge along the bottom.
                Canvas { ctx, _ in
                    ctx.scaleBy(x: s, y: s)
                    var x: CGFloat = -6
                    var red = true
                    while x < 306 {
                        var q = Path()
                        q.move(to: CGPoint(x: x, y: 200))
                        q.addLine(to: CGPoint(x: x + 5, y: 193))
                        q.addLine(to: CGPoint(x: x + 13, y: 193))
                        q.addLine(to: CGPoint(x: x + 8, y: 200))
                        q.closeSubpath()
                        ctx.fill(q, with: .color(light.ink(red ? PostcardColor.airmailRed : PostcardColor.airmailBlue)))
                        red.toggle()
                        x += 8
                    }
                    var rule = Path()
                    rule.move(to: CGPoint(x: 150, y: 22)); rule.addLine(to: CGPoint(x: 150, y: 176))
                    ctx.stroke(rule, with: .color(key.opacity(0.7)), lineWidth: 0.8)
                }
                // Message side.
                VStack(alignment: .leading, spacing: 5 * s) {
                    Text(UIFormat.stampDate(date ?? .now))
                        .font(.ticket(9 * s, weight: .bold))
                        .tracking(0.8 * s)
                        .foregroundStyle(light.ink(inks.c))
                    Text(PostcardCopy.message(for: city.index))
                        .font(.display(11.6 * s, weight: .regular).italic())
                        .lineSpacing(2.6 * s)
                        .foregroundStyle(key)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Skyfold")
                        .font(.display(10.5 * s, weight: .semibold).italic())
                        .foregroundStyle(key)
                        .padding(.top, 3 * s)
                }
                .frame(width: 118 * s, alignment: .topLeading)
                .offset(x: 17 * s, y: 18 * s)
                // Address side.
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(["Flight log", "c/o the pilot", "Lisbon, Portugal"].enumerated()), id: \.offset) { i, line in
                        Text(line)
                            .font(i == 0 ? .display(11 * s, weight: .semibold).italic() : .ticket(8.4 * s, weight: .medium))
                            .foregroundStyle(key)
                            .frame(maxWidth: .infinity, minHeight: 19 * s, alignment: .bottomLeading)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(key.opacity(0.6)).frame(height: max(0.5, 0.7 * s))
                            }
                    }
                }
                .frame(width: 118 * s)
                .offset(x: 164 * s, y: 100 * s)
                Text("Post card")
                    .signage(7 * s, weight: .bold)
                    .foregroundStyle(light.ink(inks.c))
                    .offset(x: 164 * s, y: 20 * s)
                Text(city.code)
                    .font(.ticket(8.4 * s, weight: .medium))
                    .foregroundStyle(key.opacity(0.75))
                    .offset(x: 164 * s, y: 32 * s)
                PostcardStampView(city: city, width: 36 * s)
                    .rotationEffect(.degrees(-2.5))
                    .offset(x: 250 * s, y: 15 * s)
                PostcardPostmark(city: city, date: date, size: 42 * s, waves: true)
                    .rotationEffect(.degrees(-7))
                    .offset(x: 150 * s, y: 40 * s)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .overlay(shape.strokeBorder(light.edge, lineWidth: 0.8))
        }
        // A scaled drawing: its type follows the card width, not the text-size setting.
        .dynamicTypeSize(.large)
        .aspectRatio(3 / 2, contentMode: .fit)
        .printShadow(shape, offset: shadow)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Back of the \(city.name) postcard, \(UIFormat.stampDate(date ?? .now)). \(PostcardCopy.message(for: city.index))")
    }
}

// MARK: - Stamp

private struct PerforatedRect: Shape {
    func path(in rect: CGRect) -> Path {
        var base = Path(rect)
        let r = min(rect.width, rect.height) * 0.055
        func bites(count: Int, along horizontal: Bool, at fixed: CGFloat) {
            let len = horizontal ? rect.width : rect.height
            let step = len / CGFloat(count)
            for i in 0..<count {
                let t = (CGFloat(i) + 0.5) * step
                let c = horizontal ? CGPoint(x: rect.minX + t, y: fixed) : CGPoint(x: fixed, y: rect.minY + t)
                base = base.subtracting(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)))
            }
        }
        bites(count: 7, along: true, at: rect.minY)
        bites(count: 7, along: true, at: rect.maxY)
        bites(count: 9, along: false, at: rect.minX)
        bites(count: 9, along: false, at: rect.maxX)
        return base
    }
}

/// A printed stamp: perforated edge, one ink panel, the city code and a folded plane.
struct PostcardStampView: View {
    let city: City
    var width: CGFloat = 36

    @Environment(\.palette) private var palette

    var body: some View {
        let light = PostcardLight(palette)
        let inks = PostcardArt.inks(for: city.index)
        let h = width * 1.22
        let u = width / 36
        ZStack {
            PerforatedRect().fill(light.ink(RGBA(hex: 0xF8F1DE)))
            Rectangle()
                .fill(light.ink(inks.c))
                .frame(width: width - 7 * u, height: h - 7 * u)
            Canvas { ctx, size in
                // A paper plane, two flat folds.
                let o = CGPoint(x: size.width * 0.5, y: size.height * 0.36)
                var left = Path()
                left.move(to: CGPoint(x: o.x - 11 * u, y: o.y + 2 * u))
                left.addLine(to: CGPoint(x: o.x + 11 * u, y: o.y - 7 * u))
                left.addLine(to: CGPoint(x: o.x + 1 * u, y: o.y + 8 * u))
                left.closeSubpath()
                var right = Path()
                right.move(to: CGPoint(x: o.x + 11 * u, y: o.y - 7 * u))
                right.addLine(to: CGPoint(x: o.x + 1 * u, y: o.y + 8 * u))
                right.addLine(to: CGPoint(x: o.x + 3 * u, y: o.y + 3 * u))
                right.closeSubpath()
                ctx.fill(left, with: .color(light.stock))
                ctx.fill(right, with: .color(light.ink(inks.k)))
            }
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Text(city.code)
                    .font(.display(9.5 * u, weight: .bold))
                    .tracking(0.6 * u)
                    .foregroundStyle(light.stock)
                Text("AIR MAIL")
                    .font(.skyfold(3.4 * u, weight: .heavy))
                    .tracking(0.9 * u)
                    .foregroundStyle(light.stock.opacity(0.9))
                    .padding(.bottom, 4.5 * u)
            }
            .frame(width: width - 7 * u, height: h - 7 * u)
        }
        .frame(width: width, height: h)
        .accessibilityHidden(true)
    }
}

// MARK: - Postmark

/// A round date stamp with wavy cancelling lines running off one side.
struct PostcardPostmark: View {
    let city: City
    let date: Date?
    var size: CGFloat = 40
    var waves = false

    @Environment(\.palette) private var palette

    var body: some View {
        let light = PostcardLight(palette)
        let ink = light.ink(PostcardArt.inks(for: city.index).k).opacity(0.82)
        let u = size / 40
        let parts = (date.map { UIFormat.stampDate($0) } ?? "-- --- --").split(separator: " ").map(String.init)
        let waveWidth = waves ? size * 1.5 : 0
        ZStack(alignment: .trailing) {
            if waves {
                Canvas { ctx, canvas in
                    for row in 0..<5 {
                        var w = Path()
                        let y = canvas.height * (0.3 + 0.1 * CGFloat(row))
                        w.move(to: CGPoint(x: 0, y: y))
                        var x: CGFloat = 0
                        while x < canvas.width {
                            w.addLine(to: CGPoint(x: x, y: y + sin(x / (3.4 * u) + CGFloat(row)) * 1.7 * u))
                            x += 1.5 * u
                        }
                        ctx.stroke(w, with: .color(ink), lineWidth: max(0.5, 1.1 * u))
                    }
                }
                .frame(width: waveWidth, height: size)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            ZStack {
                Circle().strokeBorder(ink, lineWidth: 1.7 * u)
                Circle().strokeBorder(ink, lineWidth: 0.7 * u).padding(3.4 * u)
                VStack(spacing: 0.8 * u) {
                    Text(city.code)
                        .font(.ticket(5.6 * u, weight: .bold))
                        .tracking(0.6 * u)
                    Rectangle().fill(ink).frame(height: max(0.5, 0.7 * u))
                    Text(parts.count > 1 ? parts[0] + " " + parts[1] : "")
                        .font(.ticket(6.2 * u, weight: .bold))
                        .lineLimit(1)
                    Text(parts.count > 2 ? "20" + parts[2] : "")
                        .font(.ticket(5.2 * u, weight: .medium))
                }
                .padding(.horizontal, 6 * u)
                .foregroundStyle(ink)
            }
            .frame(width: size, height: size)
        }
        .frame(width: size + waveWidth, height: size, alignment: .trailing)
        .blendMode(.multiply)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
