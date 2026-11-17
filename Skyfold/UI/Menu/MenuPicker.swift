import SwiftUI

/// The list behind a boarding-pass field: a slip of paper torn off a pad, one ruled row per
/// choice. Locked choices stay on the list with the reason they are locked; they cannot be
/// selected. No blur: the rest of the screen is dimmed with a flat tint.
struct MenuPickerSlip: View {
    let kind: MenuPickerKind
    @Bindable var settings: GameSettings
    let progress: ProgressStore
    let onClose: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.isLandscape) private var landscape
    @State private var listHeight: CGFloat = 0

    private var label: String {
        switch kind {
        case .airport: "Departure airport"
        case .difficulty: "Class"
        case .skin: "Aircraft"
        }
    }

    private var title: String {
        switch kind {
        case .airport: "Where from"
        case .difficulty: "How fast"
        case .skin: "Which paper"
        }
    }

    var body: some View {
        GeometryReader { geo in
            slip(maxList: max(140, landscape ? geo.size.height - 120 : geo.size.height * 0.62))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: landscape ? .trailing : .bottom)
        }
        .accessibilityAddTraits(.isModal)
    }

    private func slip(maxList: CGFloat) -> some View {
        let tear = TornStubShape(seed: "slip." + kind.rawValue, tooth: 11, depth: 5)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label).signage(10.5, weight: .semibold).foregroundStyle(palette.inkSoft.color)
                    Text(title).font(.display(26, weight: .bold)).foregroundStyle(palette.ink.color)
                }
                Spacer()
                Button("Done", action: onClose)
                    .buttonStyle(LinkButtonStyle(size: 16))
                    .padding(.vertical, 8)
            }
            .padding(.horizontal, 18)
            .padding(.top, landscape ? 16 : 22)
            .padding(.bottom, 10)

            RuleLine(color: palette.ink.color, weight: 1.5).padding(.horizontal, 18)

            ScrollView {
                VStack(spacing: 0) { rows }
                    .padding(.horizontal, 18)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(max(listHeight, 60), maxList))
            .padding(.bottom, 6)
        }
        .frame(maxWidth: landscape ? 400 : .infinity)
        .background {
            Group {
                if landscape {
                    TicketShape(cornerRadius: 4).fill(palette.paper.color)
                } else {
                    tear.fill(palette.paper.color).ignoresSafeArea(edges: .bottom)
                }
            }
        }
        .printShadow(landscape ? AnyShape(TicketShape(cornerRadius: 4)) : AnyShape(tear))
        .padding(.horizontal, landscape ? 14 : 10)
        .padding(.vertical, landscape ? 10 : 0)
    }

    // MARK: Rows

    @ViewBuilder private var rows: some View {
        switch kind {
        case .airport:
            ForEach(Route.cities.filter(\.hasAirport)) { city in
                let open = progress.isAirportUnlocked(city.index)
                PickerRow(title: city.name,
                          subtitle: open ? city.country : UnlockHint.airport(city.index),
                          selected: settings.selectedAirport == city.index,
                          locked: !open,
                          choose: { settings.selectedAirport = city.index; onClose() }) {
                    Text(city.code)
                        .font(.ticket(20, weight: .bold))
                        .foregroundStyle(palette.ink.color)
                        .frame(width: 54, alignment: .leading)
                }
            }
        case .difficulty:
            ForEach(Difficulty.all) { d in
                let open = progress.isUnlocked(d.id)
                PickerRow(title: d.name,
                          subtitle: open ? d.blurb : UnlockHint.difficulty(d.id),
                          selected: settings.selectedDifficulty == d.id,
                          locked: !open,
                          choose: { settings.selectedDifficulty = d.id; onClose() }) {
                    Text(UIFormat.multiplier(d.scoreMultiplier))
                        .font(.ticket(15, weight: .semibold))
                        .foregroundStyle(palette.inkSoft.color)
                        .frame(width: 54, alignment: .leading)
                }
            }
        case .skin:
            ForEach(PlaneSkin.all) { s in
                let open = progress.isUnlocked(s.id)
                PickerRow(title: s.name,
                          subtitle: UnlockHint.skin(s, unlocked: open),
                          selected: settings.selectedSkin == s.id,
                          locked: !open,
                          choose: { settings.selectedSkin = s.id; onClose() }) {
                    PaperPlaneGlyph(paper: s.paper, crease: s.crease, outline: palette.ink.withAlpha(0.55).color)
                        .frame(width: 42, alignment: .leading)
                        .frame(width: 54, alignment: .leading)
                }
            }
        }
    }
}

/// One ruled row: a leading mark, a name, a line of small print, and a tick box on the right.
struct PickerRow<Leading: View>: View {
    let title: String
    let subtitle: String
    let selected: Bool
    let locked: Bool
    let choose: () -> Void
    @ViewBuilder var leading: Leading

    @Environment(\.palette) private var palette

    var body: some View {
        Button {
            if locked {
                Services.haptics.play(.warning)
            } else {
                UIFeedback.select()
                choose()
            }
        } label: {
            HStack(spacing: 10) {
                leading.opacity(locked ? 0.4 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.display(19, weight: .semibold))
                        .foregroundStyle(palette.ink.color)
                        .opacity(locked ? 0.5 : 1)
                    Text(subtitle)
                        .font(.skyfold(13))
                        .foregroundStyle(palette.inkSoft.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if locked {
                    Text("Locked").signage(9.5, weight: .bold).foregroundStyle(palette.inkSoft.color)
                } else {
                    tick
                }
            }
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(alignment: .bottom) { RuleLine(weight: 1) }
        }
        .buttonStyle(PressableStyle(pressedOpacity: 0.6, tapSound: false))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(locked ? "\(title), locked. \(subtitle)" : "\(title). \(subtitle)")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    /// A printed check box: filled with the accent when chosen.
    private var tick: some View {
        let box = RoundedRectangle(cornerRadius: 3, style: .continuous)
        return ZStack {
            if selected {
                box.fill(palette.accent.color)
                Glyph("checkmark", size: 11).foregroundStyle(palette.accentInk.color)
            } else {
                box.strokeBorder(palette.inkSoft.withAlpha(0.7).color, lineWidth: 1.3)
            }
        }
        .frame(width: 22, height: 22)
    }
}

/// The flat dimming layer behind the slip. No blur.
struct MenuPickerScrim: View {
    let onTap: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        palette.scrim
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .accessibilityHidden(true)
    }
}
