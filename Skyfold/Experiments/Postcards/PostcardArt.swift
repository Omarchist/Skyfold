import SwiftUI

// The pictures on the postcards. Each is a stack of flat shapes in three or four inks on a
// 300 x 200 card, drawn in order. Every ink is printed a hair off register, and the dark key
// ink overprints (multiply), the way a screen print does.

enum PostcardInk {
    case a, b, c, k, paper

    /// Misregistration in card units.
    var offset: CGPoint {
        switch self {
        case .a, .paper: CGPoint(x: 0, y: 0)
        case .b: CGPoint(x: 0.9, y: 0.5)
        case .c: CGPoint(x: -0.7, y: 0.8)
        case .k: CGPoint(x: 0.5, y: -0.6)
        }
    }
}

struct PostcardInks {
    var a: RGBA
    var b: RGBA
    var c: RGBA
    var k: RGBA
}

struct PostcardPlate {
    var items: [(ink: PostcardInk, path: Path)] = []

    mutating func add(_ ink: PostcardInk, _ path: Path) { items.append((ink, path)) }

    mutating func rect(_ ink: PostcardInk, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
        add(ink, Path(CGRect(x: x, y: y, width: w, height: h)))
    }

    mutating func circle(_ ink: PostcardInk, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
        add(ink, Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)))
    }

    mutating func ellipse(_ ink: PostcardInk, _ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) {
        add(ink, Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry)))
    }

    mutating func poly(_ ink: PostcardInk, _ pts: [(CGFloat, CGFloat)]) {
        guard let first = pts.first else { return }
        var p = Path()
        p.move(to: CGPoint(x: first.0, y: first.1))
        for q in pts.dropFirst() { p.addLine(to: CGPoint(x: q.0, y: q.1)) }
        p.closeSubpath()
        add(ink, p)
    }

    mutating func line(_ ink: PostcardInk, _ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat,
                       _ width: CGFloat) {
        var p = Path()
        p.move(to: CGPoint(x: x1, y: y1))
        p.addLine(to: CGPoint(x: x2, y: y2))
        add(ink, p.strokedPath(StrokeStyle(lineWidth: width)))
    }

    mutating func stroke(_ ink: PostcardInk, _ path: Path, _ width: CGFloat, round: Bool = false) {
        add(ink, path.strokedPath(StrokeStyle(lineWidth: width, lineCap: round ? .round : .butt)))
    }

    /// Ground that follows a smooth line through `pts` and fills down to `base`.
    mutating func ridge(_ ink: PostcardInk, base: CGFloat, _ pts: [(CGFloat, CGFloat)]) {
        guard pts.count > 1 else { return }
        var p = Path()
        p.move(to: CGPoint(x: pts[0].0, y: base))
        p.addLine(to: CGPoint(x: pts[0].0, y: pts[0].1))
        for i in 1..<pts.count - 1 {
            let mid = CGPoint(x: (pts[i].0 + pts[i + 1].0) / 2, y: (pts[i].1 + pts[i + 1].1) / 2)
            p.addQuadCurve(to: mid, control: CGPoint(x: pts[i].0, y: pts[i].1))
        }
        let last = pts[pts.count - 1]
        p.addLine(to: CGPoint(x: last.0, y: last.1))
        p.addLine(to: CGPoint(x: last.0, y: base))
        p.closeSubpath()
        add(ink, p)
    }

    /// Short horizontal dashes, like ripples.
    mutating func ripples(_ ink: PostcardInk, y0: CGFloat, y1: CGFloat, rows: Int, seed: String) {
        var rng = SeededRandom(seed)
        for r in 0..<rows {
            let t = rows > 1 ? CGFloat(r) / CGFloat(rows - 1) : 0
            let y = y0 + (y1 - y0) * t
            let w = 8 + 16 * t
            var x = 10 + rng.next() * 26
            while x < 286 {
                rect(ink, x, y, w * (0.7 + rng.next() * 0.6), 1.2 + t * 0.8)
                x += 38 + rng.next() * 40
            }
        }
    }

    /// Adjacent boxes of random height: a skyline.
    mutating func blocks(_ ink: PostcardInk, x0: CGFloat, x1: CGFloat, base: CGFloat,
                         h: ClosedRange<CGFloat>, w: ClosedRange<CGFloat>, seed: String) {
        var rng = SeededRandom(seed)
        var x = x0
        while x < x1 {
            let bw = min(w.lowerBound + rng.next() * (w.upperBound - w.lowerBound), x1 - x)
            let bh = h.lowerBound + rng.next() * (h.upperBound - h.lowerBound)
            rect(ink, x, base - bh, bw, bh + 4)
            x += bw
        }
    }

    /// A grid of small window punches.
    mutating func windows(_ ink: PostcardInk, x: CGFloat, y: CGFloat, cols: Int, rows: Int,
                          w: CGFloat = 2.4, h: CGFloat = 3.2, gx: CGFloat = 3.4, gy: CGFloat = 4.4,
                          skip: String = "") {
        var rng = SeededRandom("win" + skip)
        for r in 0..<rows {
            for c in 0..<cols where rng.next() > 0.12 {
                rect(ink, x + CGFloat(c) * (w + gx), y + CGFloat(r) * (h + gy), w, h)
            }
        }
    }

    mutating func palm(_ ink: PostcardInk, x: CGFloat, base: CGFloat, height: CGFloat, lean: CGFloat,
                       size: CGFloat = 1) {
        let topX = x + lean
        let topY = base - height
        var trunk = Path()
        trunk.move(to: CGPoint(x: x, y: base))
        trunk.addQuadCurve(to: CGPoint(x: topX, y: topY),
                           control: CGPoint(x: x + lean * 0.05, y: base - height * 0.55))
        stroke(ink, trunk, 3.4 * size)
        let reach = 30 * size
        let angles: [CGFloat] = [-172, -142, -112, -80, -48, -18, 12, 168]
        for deg in angles {
            let r = deg * .pi / 180
            let dx = cos(r), dy = sin(r)
            let tip = CGPoint(x: topX + dx * reach, y: topY + dy * reach * 0.8 + reach * 0.28)
            let c1 = CGPoint(x: topX + dx * reach * 0.55, y: topY + dy * reach * 0.55 - reach * 0.3)
            let c2 = CGPoint(x: topX + dx * reach * 0.55, y: topY + dy * reach * 0.55 - reach * 0.04)
            var leaf = Path()
            leaf.move(to: CGPoint(x: topX, y: topY))
            leaf.addQuadCurve(to: tip, control: c1)
            leaf.addQuadCurve(to: CGPoint(x: topX, y: topY), control: c2)
            add(ink, leaf)
        }
    }

    /// A small flapping bird: two short strokes.
    mutating func gull(_ ink: PostcardInk, _ x: CGFloat, _ y: CGFloat, _ s: CGFloat = 1) {
        var p = Path()
        p.move(to: CGPoint(x: x - 6 * s, y: y - 2.5 * s))
        p.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: x - 3 * s, y: y - 4 * s))
        p.addQuadCurve(to: CGPoint(x: x + 6 * s, y: y - 2.5 * s), control: CGPoint(x: x + 3 * s, y: y - 4 * s))
        stroke(ink, p, 1.3 * s, round: true)
    }
}

enum PostcardArt {
    /// The picture window inside the card border.
    static let window = CGRect(x: 10, y: 10, width: 280, height: 180)

    static func inks(for city: Int) -> PostcardInks {
        func i(_ a: UInt32, _ b: UInt32, _ c: UInt32, _ k: UInt32) -> PostcardInks {
            PostcardInks(a: RGBA(hex: a), b: RGBA(hex: b), c: RGBA(hex: c), k: RGBA(hex: k))
        }
        switch city {
        case 1: return i(0xF1BE5C, 0xD2603C, 0x8A3B2C, 0x2B2233)
        case 2: return i(0xF0CF8F, 0xD98E3A, 0xB5532E, 0x32283A)
        case 3: return i(0xF0C9A6, 0x4F7A8C, 0xC4503A, 0x2A2A40)
        case 4: return i(0xC9D8D4, 0x5E8F99, 0xD9A441, 0x23323A)
        case 5: return i(0xF3D6D2, 0x6F8F7A, 0xCF3B2F, 0x3A2C36)
        case 6: return i(0xF3C99C, 0x3F6C9C, 0xE6574A, 0x1F2C4A)
        case 7: return i(0xF7C6A0, 0x2F8F8A, 0xEF6A5A, 0x24403A)
        case 8: return i(0xF6D9A8, 0x4E9A6C, 0x3470A8, 0x20322E)
        case 9: return i(0xF0CCA8, 0x6C7F99, 0xC8513A, 0x232838)
        default: return i(0xF3D9C2, 0xD9774A, 0x8A4B3A, 0x2A211B)
        }
    }

    static func plate(for city: Int) -> PostcardPlate {
        var p = PostcardPlate()
        p.rect(.a, 10, 10, 280, 180)
        switch city {
        case 1: marrakesh(&p)
        case 2: cairo(&p)
        case 3: istanbul(&p)
        case 4: mumbai(&p)
        case 5: kyoto(&p)
        case 6: sydney(&p)
        case 7: honolulu(&p)
        case 8: rio(&p)
        case 9: newYork(&p)
        default: generic(&p)
        }
        return p
    }

    // MARK: Scenes

    private static func marrakesh(_ p: inout PostcardPlate) {
        p.circle(.paper, 226, 52, 20)
        // Atlas mountains, left unprinted.
        p.ridge(.paper, base: 150, [(10, 112), (46, 90), (74, 104), (112, 82), (150, 108), (200, 96), (250, 112), (290, 100)])
        // The minaret.
        p.rect(.c, 138, 58, 28, 96)
        p.rect(.c, 145, 46, 14, 13)
        p.circle(.c, 152, 42, 3.6)
        p.line(.c, 152, 36, 152, 30, 1.2)
        p.rect(.paper, 138, 76, 28, 7)
        for i in 0..<5 { p.rect(.k, 140 + CGFloat(i) * 5.6, 78, 2.6, 3) }
        for y in [92.0, 110, 128] { p.rect(.k, 146, y, 3, 9); p.rect(.k, 155, y, 3, 9) }
        // Rooftops of the medina.
        p.blocks(.b, x0: 10, x1: 290, base: 150, h: 10...26, w: 18...34, seed: "rak-roofs")
        p.rect(.b, 10, 146, 280, 44)
        p.windows(.k, x: 18, y: 154, cols: 30, rows: 2, w: 3.2, h: 5, gx: 5.2, gy: 6, skip: "rak")
        p.ridge(.c, base: 190, [(10, 176), (90, 172), (180, 176), (290, 170)])
        p.palm(.k, x: 40, base: 190, height: 96, lean: 14)
        p.palm(.k, x: 262, base: 190, height: 74, lean: -12, size: 0.85)
    }

    private static func cairo(_ p: inout PostcardPlate) {
        p.circle(.c, 232, 50, 21)
        // Old city on the horizon.
        p.rect(.k, 18, 124, 52, 26)
        p.ellipse(.k, 36, 124, 11, 10)
        p.rect(.k, 54, 100, 4, 50)
        p.poly(.k, [(53, 100), (59, 100), (56, 93)])
        // The pyramids.
        p.poly(.b, [(80, 150), (118, 106), (150, 150)])
        p.poly(.c, [(118, 106), (150, 150), (124, 150)])
        p.poly(.b, [(96, 150), (172, 66), (248, 150)])
        p.poly(.c, [(172, 66), (248, 150), (178, 150)])
        p.poly(.b, [(214, 150), (250, 116), (290, 150)])
        p.poly(.c, [(250, 116), (290, 150), (256, 150)])
        p.ridge(.b, base: 190, [(10, 160), (70, 152), (140, 160), (210, 154), (290, 160)])
        p.ridge(.a, base: 190, [(10, 178), (80, 168), (160, 176), (230, 168), (290, 174)])
        for i in 0..<7 { p.rect(.k, 40 + CGFloat(i) * 6, 171 + CGFloat(i % 2), 3, 2) }
        p.ripples(.c, y0: 181, y1: 186, rows: 2, seed: "cai-dunes")
    }

    private static func istanbul(_ p: inout PostcardPlate) {
        p.circle(.paper, 64, 96, 20)
        // Far shore and old town.
        p.ridge(.c, base: 150, [(10, 120), (50, 112), (100, 120), (150, 104), (200, 118), (250, 110), (290, 120)])
        // Hagia Sophia.
        p.ellipse(.k, 150, 100, 30, 28)
        p.ellipse(.k, 112, 120, 20, 18)
        p.ellipse(.k, 188, 120, 20, 18)
        p.rect(.k, 94, 118, 112, 34)
        p.rect(.k, 146, 66, 8, 8)
        p.poly(.k, [(145, 68), (155, 68), (150, 56)])
        for x in [84.0, 214.0] {
            p.rect(.k, x, 86, 5, 66)
            p.poly(.k, [(x - 1, 87), (x + 6, 87), (x + 2.5, 70)])
            p.rect(.k, x - 1.5, 100, 8, 2.4)
        }
        for x in [104.0, 118, 132, 146, 160, 174, 188] { p.rect(.paper, x, 128, 5, 10) }
        p.rect(.paper, 140, 92, 4, 8); p.rect(.paper, 156, 92, 4, 8)
        // The strait.
        p.rect(.b, 10, 150, 280, 40)
        p.ripples(.paper, y0: 158, y1: 184, rows: 5, seed: "ist-water")
        p.poly(.k, [(40, 168), (86, 168), (80, 176), (46, 176)])
        p.rect(.k, 62, 156, 1.6, 12)
        p.poly(.paper, [(64, 158), (64, 167), (76, 167)])
        p.gull(.k, 36, 40, 1.2); p.gull(.k, 60, 54, 0.9); p.gull(.k, 226, 38, 1.1)
    }

    private static func mumbai(_ p: inout PostcardPlate) {
        // Low monsoon cloud, scalloped underneath.
        p.rect(.b, 10, 10, 280, 22)
        var x: CGFloat = 4
        var rng = SeededRandom("bom-cloud")
        while x < 296 {
            let r = 10 + rng.next() * 9
            p.circle(.b, x, 30, r)
            x += r * 1.5
        }
        // Sea.
        p.rect(.b, 10, 140, 280, 50)
        p.ripples(.paper, y0: 150, y1: 184, rows: 5, seed: "bom-sea")
        // The gateway.
        p.rect(.c, 96, 82, 108, 62)
        p.rect(.c, 88, 140, 124, 8)
        p.rect(.c, 100, 70, 100, 14)
        for dx in [100.0, 184] {
            p.rect(.c, dx, 56, 16, 18)
            p.ellipse(.c, dx + 8, 56, 8, 7)
        }
        p.ellipse(.c, 150, 70, 26, 20)
        p.rect(.c, 148, 40, 4, 12)
        p.circle(.c, 150, 40, 2.5)
        p.rect(.a, 134, 100, 32, 44)
        p.ellipse(.a, 150, 100, 16, 14)
        p.rect(.b, 134, 112, 32, 32)
        p.ellipse(.b, 150, 112, 16, 12)
        for dx in [104.0, 118, 174, 188] { p.rect(.k, dx, 96, 4, 14) }
        p.rect(.k, 88, 146, 124, 2)
        // Boats.
        p.poly(.k, [(28, 160), (60, 160), (55, 167), (33, 167)])
        p.poly(.paper, [(43, 144), (43, 159), (56, 159)])
        p.poly(.k, [(232, 170), (264, 170), (259, 177), (237, 177)])
        p.poly(.paper, [(247, 154), (247, 169), (260, 169)])
        // Rain.
        var r2 = SeededRandom("bom-rain")
        for _ in 0..<46 {
            let rx = 10 + r2.next() * 280
            let ry = 24 + r2.next() * 150
            p.line(.k, rx, ry, rx - 4, ry + 11, 0.8)
        }
    }

    private static func kyoto(_ p: inout PostcardPlate) {
        p.circle(.c, 218, 62, 26)
        p.ridge(.paper, base: 160, [(10, 128), (60, 104), (110, 124), (170, 96), (230, 122), (290, 108)])
        p.ridge(.b, base: 190, [(10, 150), (70, 128), (130, 146), (210, 122), (290, 148)])
        // The pagoda, five roofs.
        var y: CGFloat = 156
        var half: CGFloat = 34
        for _ in 0..<5 {
            let bodyH: CGFloat = 12
            p.rect(.c, 150 - half * 0.5, y - bodyH, half, bodyH)
            p.rect(.k, 150 - half * 0.5 + 3, y - bodyH + 3, 3, bodyH - 3)
            p.rect(.k, 150 + half * 0.5 - 6, y - bodyH + 3, 3, bodyH - 3)
            p.poly(.k, [(150 - half - 8, y - bodyH + 2), (150 - half * 0.5, y - bodyH - 5),
                        (150 + half * 0.5, y - bodyH - 5), (150 + half + 8, y - bodyH + 2),
                        (150 + half, y - bodyH + 4), (150 - half, y - bodyH + 4)])
            y -= bodyH + 5
            half -= 4.6
        }
        p.rect(.k, 149, y - 22, 2, 24)
        for i in 0..<4 { p.rect(.k, 146.5, y - 20 + CGFloat(i) * 5, 7, 1.6) }
        p.rect(.b, 10, 168, 280, 22)
        p.rect(.k, 10, 166, 280, 2.4)
        // Lanterns on a string.
        var s = Path()
        s.move(to: CGPoint(x: 168, y: 14))
        s.addQuadCurve(to: CGPoint(x: 290, y: 22), control: CGPoint(x: 230, y: 38))
        p.stroke(.k, s, 1)
        for (i, lx) in [182.0, 206, 230, 254, 276].enumerated() {
            let ly = 26 + sin(CGFloat(i) * 0.9) * 2 + [4.0, 8, 9, 7, 3][i]
            p.ellipse(.c, lx, ly + 5, 5, 6.5)
            p.rect(.k, lx - 3, ly - 1, 6, 1.6)
            p.rect(.k, lx - 3, ly + 10, 6, 1.6)
        }
        // A cherry branch in the corner.
        var br = Path()
        br.move(to: CGPoint(x: 10, y: 44))
        br.addQuadCurve(to: CGPoint(x: 92, y: 16), control: CGPoint(x: 40, y: 40))
        p.stroke(.k, br, 2.4)
        var rb = SeededRandom("uky-blossom")
        for _ in 0..<20 {
            let t = rb.next()
            let bx = 14 + t * 76
            let by = 42 - t * 24 - sin(t * .pi) * 10 + (rb.next() - 0.5) * 22
            p.circle(.c, bx, by, 3.4)
            p.circle(.paper, bx, by, 1.2)
        }
    }

    private static func sydney(_ p: inout PostcardPlate) {
        p.circle(.c, 78, 56, 22)
        // Harbour bridge.
        var arch = Path()
        arch.move(to: CGPoint(x: 166, y: 150))
        arch.addQuadCurve(to: CGPoint(x: 296, y: 150), control: CGPoint(x: 231, y: 58))
        p.stroke(.k, arch, 4)
        p.rect(.k, 172, 128, 118, 3)
        for i in 0..<14 {
            let hx = 178 + CGFloat(i) * 8.2
            let u = (hx - 166) / 130
            let top = 150 - 4 * u * (1 - u) * 46
            p.line(.k, hx, top, hx, 128, 0.8)
        }
        p.rect(.k, 160, 112, 6, 40)
        p.rect(.k, 292, 112, 6, 40)
        // Water.
        p.rect(.b, 10, 150, 280, 40)
        p.ripples(.paper, y0: 158, y1: 184, rows: 5, seed: "syd-water")
        // Opera house.
        p.rect(.k, 40, 146, 130, 8)
        func shell(_ x: CGFloat, _ w: CGFloat, _ h: CGFloat, lean: CGFloat) {
            var s = Path()
            let base: CGFloat = 146
            s.move(to: CGPoint(x: x, y: base))
            s.addQuadCurve(to: CGPoint(x: x + lean * w * 0.92, y: base - h),
                           control: CGPoint(x: x + (lean > 0 ? -w * 0.1 : w * 0.1), y: base - h * 0.85))
            s.addLine(to: CGPoint(x: x + lean * w, y: base))
            s.closeSubpath()
            p.add(.paper, s)
        }
        shell(48, 36, 42, lean: 1); shell(72, 42, 56, lean: 1); shell(100, 48, 68, lean: 1)
        shell(164, 36, 40, lean: -1); shell(140, 42, 52, lean: -1)
        for sx in [72.0, 100, 140] { p.line(.c, sx + 6, 146, sx + 20, 146 - 30, 0.8) }
        p.gull(.k, 40, 36, 1.1); p.gull(.k, 118, 30, 0.9)
    }

    private static func honolulu(_ p: inout PostcardPlate) {
        p.circle(.c, 226, 78, 30)
        // Diamond Head.
        p.poly(.k, [(70, 128), (118, 98), (140, 82), (154, 88), (196, 112), (214, 128)])
        p.line(.paper, 140, 83, 98, 118, 1.2)
        p.rect(.b, 10, 126, 280, 64)
        for (i, y) in [130.0, 138, 148, 160].enumerated() {
            p.rect(.paper, 10, y, 280, 1.4 + CGFloat(i) * 0.6)
        }
        p.ridge(.paper, base: 190, [(10, 170), (90, 160), (170, 168), (290, 158)])
        p.rect(.a, 10, 178, 280, 12)
        // Hibiscus.
        for k in 0..<5 {
            let a = CGFloat(k) / 5 * .pi * 2 - .pi / 2
            p.circle(.c, 150 + cos(a) * 8, 170 + sin(a) * 8, 7)
        }
        p.circle(.paper, 150, 170, 3)
        p.palm(.k, x: 38, base: 190, height: 108, lean: 22)
        p.palm(.k, x: 262, base: 190, height: 90, lean: -18, size: 0.9)
    }

    private static func rio(_ p: inout PostcardPlate) {
        p.circle(.paper, 40, 46, 17)
        // Corcovado with the statue.
        p.ridge(.b, base: 160, [(40, 160), (86, 128), (112, 84), (126, 76), (144, 96), (170, 140), (190, 160)])
        p.rect(.k, 117, 56, 5, 22)
        p.rect(.k, 106, 60, 27, 3.6)
        p.circle(.k, 119.5, 53, 3)
        p.rect(.k, 114, 76, 11, 3)
        // Sugarloaf and its neighbour.
        p.ellipse(.b, 232, 128, 34, 42)
        p.rect(.b, 198, 128, 70, 30)
        p.line(.k, 172, 96, 232, 88, 0.9)
        p.rect(.k, 226, 84, 12, 8)
        p.rect(.paper, 229, 86, 6, 4)
        p.ridge(.b, base: 160, [(10, 150), (30, 146), (50, 160)])
        // Sea and shore.
        p.rect(.c, 10, 148, 280, 30)
        p.ripples(.paper, y0: 154, y1: 172, rows: 3, seed: "gig-sea")
        p.ridge(.paper, base: 190, [(10, 176), (100, 168), (190, 176), (290, 166)])
        // Promenade paving.
        var wave = Path()
        wave.move(to: CGPoint(x: 10, y: 182))
        for i in 0..<56 {
            let x = 10 + CGFloat(i) * 5
            wave.addLine(to: CGPoint(x: x, y: 182 + sin(CGFloat(i) * 1.1) * 2.6))
        }
        p.stroke(.k, wave, 2.2)
        p.palm(.k, x: 22, base: 190, height: 70, lean: 10, size: 0.8)
    }

    private static func newYork(_ p: inout PostcardPlate) {
        p.circle(.paper, 70, 70, 20)
        p.blocks(.b, x0: 10, x1: 290, base: 150, h: 40...92, w: 14...30, seed: "jfk-far")
        // The tall one.
        p.rect(.k, 134, 104, 44, 50)
        p.rect(.k, 140, 84, 32, 22)
        p.rect(.k, 146, 66, 20, 20)
        p.rect(.k, 150, 52, 12, 16)
        p.rect(.k, 154, 44, 4, 10)
        p.line(.k, 156, 44, 156, 22, 1.4)
        p.windows(.paper, x: 138, y: 108, cols: 7, rows: 6, w: 2.2, h: 3, gx: 3, gy: 4.4, skip: "esb")
        p.windows(.paper, x: 144, y: 88, cols: 5, rows: 3, w: 2.2, h: 3, gx: 3, gy: 3.8, skip: "esb2")
        // Front blocks.
        p.blocks(.k, x0: 10, x1: 130, base: 152, h: 22...58, w: 16...26, seed: "jfk-left")
        p.blocks(.k, x0: 182, x1: 290, base: 152, h: 20...64, w: 16...26, seed: "jfk-right")
        p.windows(.paper, x: 16, y: 120, cols: 14, rows: 4, w: 2, h: 2.8, gx: 5.2, gy: 6, skip: "jl")
        p.windows(.paper, x: 188, y: 114, cols: 12, rows: 4, w: 2, h: 2.8, gx: 5.2, gy: 6, skip: "jr")
        // Water tower on the left roof.
        p.rect(.c, 36, 96, 12, 12)
        p.poly(.c, [(34, 96), (50, 96), (42, 88)])
        p.line(.c, 38, 108, 38, 116, 1.2); p.line(.c, 46, 108, 46, 116, 1.2)
        // River.
        p.rect(.b, 10, 152, 280, 38)
        p.ripples(.paper, y0: 160, y1: 184, rows: 4, seed: "jfk-river")
        p.rect(.c, 40, 166, 22, 4)
        p.rect(.c, 46, 162, 10, 4)
        p.gull(.k, 230, 40, 1.1); p.gull(.k, 252, 54, 0.8)
    }

    private static func generic(_ p: inout PostcardPlate) {
        p.circle(.paper, 224, 56, 20)
        p.ridge(.b, base: 170, [(10, 130), (80, 100), (150, 120), (220, 96), (290, 120)])
        p.blocks(.c, x0: 10, x1: 290, base: 160, h: 14...34, w: 14...26, seed: "lis")
        p.rect(.k, 10, 160, 280, 30)
    }
}
