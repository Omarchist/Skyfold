import SwiftUI

/// "Hangar": the selected plane turning on a flat paper sky, and every skin hanging below as
/// a luggage tag showing its two colors. Locked skins say what unlocks them.
struct HangarView: View {
    let onClose: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.uiNightness) private var nightness
    var body: some View {
        let skin = PlaneSkin.get(model.settings.selectedSkin)
        LibraryPage(kicker: "Aircraft on hand", title: "Hangar", pinSide: true, onClose: onClose) {
            LibraryHangarStage(skin: skin, nightness: nightness)
        } content: {
            LibraryTagGrid(progress: model.progress, settings: model.settings)
        }
    }
}

// MARK: - Stage

/// A flat paper sky with the live 3D plane over it and a placard along the bottom.
private struct LibraryHangarStage: View {
    let skin: PlaneSkin
    let nightness: Double
    @Environment(\.palette) private var palette
    @Environment(\.isLandscape) private var wide

    var body: some View {
        let height: CGFloat = wide ? 260 : 190
        ZStack(alignment: .bottomLeading) {
            sky
            PlanePreviewView(skin: skin, nightness: nightness)
                .padding(.bottom, 30)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            placard
        }
        .frame(height: height)
        .clipShape(Rectangle())
        .overlay(Rectangle().strokeBorder(palette.ink.color, lineWidth: 1.5))
        .printShadow(Rectangle(), offset: 4)
        .padding(.trailing, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Selected plane: \(skin.name)")
    }

    /// Stepped sky bands, a flat sun or moon and two cut-paper clouds.
    private var sky: some View {
        let palette = palette
        return Canvas { ctx, size in
            let bands = 5
            for i in 0..<bands {
                let r = CGRect(x: 0, y: size.height * CGFloat(i) / CGFloat(bands),
                               width: size.width, height: size.height / CGFloat(bands) + 1)
                ctx.fill(Path(r), with: .color(palette.skyBand((Double(i) + 0.5) / Double(bands), bands: bands).color))
            }
            let r = min(size.width, size.height) * 0.16
            ctx.fill(Path(ellipseIn: CGRect(x: size.width * 0.74 - r, y: size.height * 0.26 - r, width: 2 * r, height: 2 * r)),
                     with: .color(palette.sun.color))
            func cloud(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ variant: Int) {
                let rect = CGRect(x: x, y: y, width: w, height: w * 0.42)
                ctx.fill(FlatCloudShape(variant: variant).path(in: rect), with: .color(palette.cloud.color))
            }
            cloud(size.width * 0.06, size.height * 0.2, size.width * 0.26, 1)
            cloud(size.width * 0.56, size.height * 0.52, size.width * 0.3, 3)
        }
        .accessibilityHidden(true)
    }

    private var placard: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(skin.name).font(.display(22, weight: .bold)).lineLimit(1)
            Text(UnlockHint.skin(skin, unlocked: true))
                .font(.skyfold(12.5))
                .foregroundStyle(palette.inkSoft.color)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .background(palette.paper.color)
        .overlay(alignment: .top) { RuleLine(color: palette.ink.color, weight: 1.5) }
    }
}

// MARK: - Tags

private struct LibraryTagGrid: View {
    let progress: ProgressStore
    @Bindable var settings: GameSettings
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 220 : 150), spacing: 18, alignment: .top)]
        VStack(alignment: .leading, spacing: 18) {
            LibrarySectionHead(title: "Luggage tags",
                               note: "\(progress.data.unlockedSkins.count) of \(PlaneSkin.all.count) issued")
            LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
                ForEach(Array(PlaneSkin.all.enumerated()), id: \.element.id) { index, skin in
                    LibrarySkinTag(skin: skin, number: index + 1,
                                   unlocked: progress.isUnlocked(skin.id),
                                   selected: settings.selectedSkin == skin.id) {
                        settings.selectedSkin = skin.id
                    }
                }
            }
            .padding(.top, 10)
        }
    }
}

/// A luggage tag: cut top corners, a punched hole with a string loop, the paper color on top
/// and the crease color along the bottom.
private struct LibraryTagShape: Shape {
    var cut: CGFloat = 20
    var hole: CGFloat = 6.5

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cut))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 2))
        p.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + 2, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - 2))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cut))
        p.closeSubpath()
        var bite = Path()
        bite.addEllipse(in: CGRect(x: rect.midX - hole, y: rect.minY + 14 - hole, width: hole * 2, height: hole * 2))
        return p.subtracting(bite)
    }
}

private struct LibrarySkinTag: View {
    let skin: PlaneSkin
    let number: Int
    let unlocked: Bool
    let selected: Bool
    let choose: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        let shape = LibraryTagShape()
        let tilt = selected ? Angle.zero : Seeded.tilt("tag." + skin.id.rawValue, min: 1, max: 3)
        Button {
            if unlocked {
                if !selected { UIFeedback.select() }
                choose()
            } else {
                Services.haptics.play(.warning)
            }
        } label: {
            ZStack(alignment: .top) {
                tag
                    .clipShape(shape)
                    .background { shape.fill(palette.printShadow).offset(x: 3.5, y: 3.5) }
                    .overlay {
                        shape.stroke(selected ? palette.accent.color : palette.ink.color.opacity(0.7),
                                     style: StrokeStyle(lineWidth: selected ? 3 : 1.2,
                                                        dash: unlocked ? [] : [5, 4]))
                    }
                string
            }
            .padding(.top, 20)
            .rotationEffect(tilt, anchor: .top)
            .offset(y: selected ? -3 : 0)
        }
        .buttonStyle(PressableStyle(pressedOpacity: 0.7, tapSound: false))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(unlocked ? skin.name : "\(skin.name), locked")
        .accessibilityValue(selected ? "In use" : UnlockHint.skin(skin, unlocked: unlocked))
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    private var tag: some View {
        // Locked stock is washed out with the page color; the lettering stays in full ink.
        let top = unlocked ? skin.paper : skin.paper.mixed(with: palette.paper, 0.6)
        let bottom = unlocked ? skin.crease : skin.crease.mixed(with: palette.paper, 0.6)
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Spacer(minLength: 24)
                Text(String(format: "No. %02d", number))
                    .font(.ticket(10.5, weight: .semibold))
                    .opacity(0.75)
                Text(skin.name)
                    .font(.display(19, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(palette.readableInk(on: top))
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(top.color)

            Group {
                if selected {
                    Text("In use").signage(10.5, weight: .bold)
                } else {
                    Text(UnlockHint.skin(skin, unlocked: unlocked))
                        .font(.skyfold(12.5, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(palette.readableInk(on: bottom))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(bottom.color)
        }
        .overlay(alignment: .topTrailing) {
            if !unlocked {
                Text("Locked").signage(9.5, weight: .bold)
                    .foregroundStyle(palette.ink.color)
                    .padding(.top, 30)
                    .padding(.trailing, 10)
            }
        }
    }

    /// The string: two strands through the hole that end in a knot above the tag. The canvas
    /// starts 20 pt above the tag, so the hole is at y = 34 here.
    private var string: some View {
        Canvas { ctx, size in
            let cx = size.width / 2
            let ink = palette.inkSoft.color
            var p = Path()
            p.move(to: CGPoint(x: cx + 1, y: 35))
            p.addCurve(to: CGPoint(x: cx + 11, y: 6),
                       control1: CGPoint(x: cx + 8, y: 28), control2: CGPoint(x: cx + 15, y: 14))
            p.move(to: CGPoint(x: cx - 1, y: 35))
            p.addCurve(to: CGPoint(x: cx + 11, y: 6),
                       control1: CGPoint(x: cx - 9, y: 22), control2: CGPoint(x: cx + 2, y: 8))
            ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: cx + 8, y: 3, width: 6, height: 6)), with: .color(ink))
        }
        .frame(height: 50)
        .offset(y: -20)
        .allowsHitTesting(false)
    }
}
