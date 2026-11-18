import SwiftUI

enum MenuPickerKind: String, Identifiable {
    case airport, difficulty, skin
    var id: String { rawValue }
}

/// The loadout as a boarding pass. FROM, CLASS and AIRCRAFT are the fields you fill in
/// (departure airport, difficulty, skin); the stub below the tear line carries the records.
struct MenuBoardingPass: View {
    var settings: GameSettings
    var progress: ProgressStore
    /// Tighter spacing for landscape.
    var compact = false
    var openPicker: (MenuPickerKind) -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        let from = Route.city(settings.selectedAirport)
        let to = Route.city(settings.selectedAirport + 1)
        let difficulty = Difficulty.get(settings.selectedDifficulty)
        let skin = PlaneSkin.get(settings.selectedSkin)
        let flight = UIFormat.flightNumber(from: from.index, to: to.index)
        let blue = palette.secondary
        let onBlue = palette.readableInk(on: blue)

        TicketPanel(cornerRadius: 5, notchRadius: 8) {
            VStack(alignment: .leading, spacing: 0) {
                // Header band in airmail blue.
                // Drops the second label when the first and the flight number need the room.
                ViewThatFits(in: .horizontal) {
                    ForEach([true, false], id: \.self) { full in
                        HStack(alignment: .firstTextBaseline) {
                            Text("Skyfold Air").signage(10, weight: .heavy).lineLimit(1)
                            if full {
                                Text("Boarding pass").signage(10, weight: .regular).opacity(0.8).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Text(flight).font(.ticket(11, weight: .bold)).tracking(1).lineLimit(1)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .foregroundStyle(onBlue)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(blue.color)

                VStack(alignment: .leading, spacing: compact ? 8 : 12) {
                    // FROM and TO.
                    HStack(alignment: .top, spacing: 6) {
                        field(.airport, label: "From") {
                            codeBlock(city: from, alignment: .leading)
                        }
                        routeMark.padding(.top, compact ? 24 : 30)
                        codeBlock(city: to, label: "To", alignment: .trailing)
                            .padding(.top, 8)
                    }
                    // CLASS and AIRCRAFT.
                    HStack(spacing: 10) {
                        field(.difficulty, label: "Class") {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(difficulty.name)
                                    .font(.display(18, weight: .semibold))
                                    .foregroundStyle(palette.ink.color)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Text(UIFormat.multiplier(difficulty.scoreMultiplier))
                                    .font(.ticket(11, weight: .medium))
                                    .foregroundStyle(palette.inkSoft.color)
                            }
                        }
                        field(.skin, label: "Aircraft") {
                            HStack(spacing: 8) {
                                PaperPlaneGlyph(paper: skin.paper, crease: skin.crease, outline: palette.ink.withAlpha(0.55).color)
                                    .frame(width: 30)
                                Text(skin.name)
                                    .font(.display(18, weight: .semibold))
                                    .foregroundStyle(palette.ink.color)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, compact ? 10 : 14)
                .padding(.bottom, compact ? 12 : 16)
            }
        } stub: {
            HStack(alignment: .bottom, spacing: 18) {
                stat("Best score", UIFormat.number(progress.data.bestScore))
                stat("Most cities", "\(progress.data.mostCitiesInRun)")
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 3) {
                    Barcode(seed: "\(progress.data.bestScore).\(progress.data.mostCitiesInRun).\(flight)")
                        .frame(width: 70, height: 26)
                    Text(from.code + to.code)
                        .font(.ticket(8.5, weight: .medium))
                        .tracking(2.5)
                        .foregroundStyle(palette.inkSoft.color)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .limitedTypeSize()
        .accessibilityElement(children: .contain)
    }

    // MARK: Pieces

    private func codeBlock(city: City, label: String? = nil, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            if let label {
                Text(label).signage(9.5, weight: .semibold).foregroundStyle(palette.inkSoft.color)
            }
            Text(city.code)
                .font(.ticket(compact ? 32 : 40, weight: .bold))
                .foregroundStyle(palette.ink.color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(city.name)
                .font(.display(14, weight: .regular).italic())
                .foregroundStyle(palette.inkSoft.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    /// The dashed route between the two codes, with a small plane on it.
    private var routeMark: some View {
        HStack(spacing: 5) {
            MidLine()
                .stroke(palette.inkSoft.color, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, dash: [3, 4]))
                .frame(height: 2)
            // Fixed on both sides: left to the aspect ratio alone, this mark collapsed to a dot.
            PaperPlaneGlyph(paper: palette.paper, crease: palette.paperEdge, outline: palette.ink.color)
                .frame(width: 26, height: 26 / 1.7)
            MidLine()
                .stroke(palette.inkSoft.color, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, dash: [3, 4]))
                .frame(height: 2)
        }
        .frame(maxWidth: .infinity)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).signage(9.5, weight: .semibold).foregroundStyle(palette.inkSoft.color)
            Text(value)
                .font(.ticket(22, weight: .bold))
                .foregroundStyle(palette.ink.color)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    /// A fill-in field: dashed outline, small label, a chevron where it opens a list.
    private func field<Content: View>(_ kind: MenuPickerKind, label: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        Button { openPicker(kind) } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(label).signage(9.5, weight: .semibold)
                    Glyph("chevron.down", size: 7)
                }
                .foregroundStyle(palette.inkSoft.color)
                content()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: kind == .airport ? nil : .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(MenuFieldStyle())
        .accessibilityLabel(label)
        .accessibilityHint("Opens the list")
    }
}

/// The dashed box around a field. A press fills it with a wash of accent.
private struct MenuFieldStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MenuFieldFace(configuration: configuration)
    }
}

private struct MenuFieldFace: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.palette) private var palette

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        configuration.label
            .background(shape.fill(palette.accent.withAlpha(configuration.isPressed ? 0.16 : 0.05).color))
            .overlay(shape.strokeBorder(palette.inkSoft.withAlpha(0.7).color,
                                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(shape)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { UIFeedback.tap() }
            }
    }
}
