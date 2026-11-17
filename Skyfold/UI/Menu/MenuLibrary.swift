import SwiftUI

private struct MenuLibraryPage<Content: View>: View {
    let title: String
    let onClose: () -> Void
    @ViewBuilder var content: Content

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.display(34, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: onClose) {
                    Text("Done").frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(LinkButtonStyle())
            }
            .padding(.horizontal, 20)
            AirmailStripe(stripe: 7).frame(height: 6)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    content
                }
                .frame(maxWidth: 620)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .font(.skyfold(16))
        .foregroundStyle(palette.ink.color)
        .tint(palette.secondary.color)
        .background(palette.paper.color.ignoresSafeArea())
    }
}

private struct MenuLibrarySection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .signage()
                .accessibilityAddTraits(.isHeader)
            RuleLine()
            content
        }
    }
}

private struct MenuLibraryGrid<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let column: GridItem = typeSize.isAccessibilitySize
            ? GridItem(.flexible())
            : GridItem(.adaptive(minimum: 146), spacing: 12, alignment: .top)
        LazyVGrid(columns: [column], alignment: .leading, spacing: 12) {
            content
        }
    }
}

struct JournalView: View {
    let onClose: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        let progress = model.progress.data
        MenuLibraryPage(title: "Flight log", onClose: onClose) {
            MenuLibrarySection(title: "Records") {
                LabeledContent("Gate rewards",
                               value: "\(model.progress.discoveredModifierCount) of \(ModifierID.allCases.count)")
                LabeledContent("Best score", value: UIFormat.number(progress.bestScore))
                LabeledContent("Longest flight", value: UIFormat.distance(progress.bestDistance))
                LabeledContent("Runs flown", value: UIFormat.number(progress.runsPlayed))
                LabeledContent("Stars collected", value: UIFormat.number(progress.totalStars))
                LabeledContent("Cities visited", value: "\(progress.visitedCities.count) of \(Route.count)")
            }
            entries("Blessings", ids: ModifierID.blessings)
            entries("Curses", ids: ModifierID.curses)
        }
    }

    private func entries(_ title: String, ids: [ModifierID]) -> some View {
        MenuLibrarySection(title: title) {
            VStack(spacing: 0) {
                ForEach(ids) { id in
                    reward(id, count: model.progress.timesCollected(id))
                }
            }
        }
    }

    private func reward(_ id: ModifierID, count: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if count > 0 {
                    Glyph(id.info.symbol, size: 17).foregroundStyle(palette.kindInk(id.kind))
                } else {
                    Text("?")
                        .font(.ticket(17, weight: .bold))
                        .foregroundStyle(palette.inkSoft.color)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 24)
            .padding(.top, 2)
            if count > 0 {
                let info = id.info
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent {
                        Text("×\(count)").font(.ticket(13))
                            .accessibilityLabel("Collected \(count) times")
                    } label: {
                        Text(info.name).font(.display(19))
                    }
                    Text(info.effect).font(.skyfold(14))
                    Text(info.lore)
                        .font(.display(14, weight: .regular).italic())
                        .foregroundStyle(palette.inkSoft.color)
                }
            } else {
                Text("Not logged yet")
                    .font(.display(17))
                    .foregroundStyle(palette.inkSoft.color)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        .padding(.vertical, 7)
        .background(alignment: .bottom) { RuleLine() }
        .accessibilityElement(children: .combine)
    }
}

struct HangarView: View {
    let onClose: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.uiNightness) private var nightness

    var body: some View {
        let skin = PlaneSkin.get(model.settings.selectedSkin)
        MenuLibraryPage(title: "Hangar", onClose: onClose) {
            CardStock(padding: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(skin.name).font(.display(24))
                        .accessibilityAddTraits(.isHeader)
                    PlanePreviewView(skin: skin, nightness: nightness)
                        .frame(height: 170)
                        .frame(maxWidth: .infinity)
                        .background(palette.skyBottom.color)
                        .accessibilityHidden(true)
                }
            }
            MenuLibraryGrid {
                ForEach(PlaneSkin.all) { skin in
                    skinCard(skin)
                }
            }
        }
    }

    private func skinCard(_ skin: PlaneSkin) -> some View {
        let unlocked = model.progress.isUnlocked(skin.id)
        let selected = model.settings.selectedSkin == skin.id
        return Button {
            UIFeedback.select()
            model.settings.selectedSkin = skin.id
        } label: {
            CardStock(padding: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        PaperPlaneGlyph(paper: skin.paper, crease: skin.crease, outline: palette.ink.color)
                            .frame(width: 54)
                            .opacity(unlocked ? 1 : 0.5)
                        Spacer(minLength: 4)
                        if selected {
                            Glyph("checkmark").foregroundStyle(palette.accent.color)
                        } else if !unlocked {
                            Glyph("lock").foregroundStyle(palette.inkSoft.color)
                        }
                    }
                    Text(skin.name).font(.display(18))
                    Text(UnlockHint.skin(skin, unlocked: unlocked))
                        .font(.skyfold(13))
                        .foregroundStyle(palette.inkSoft.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay {
                if selected { TicketShape().stroke(palette.accent.color, lineWidth: 2) }
            }
        }
        .buttonStyle(PressableStyle(tapSound: false))
        .disabled(!unlocked)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct AtlasView: View {
    let onClose: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        MenuLibraryPage(title: "Departures", onClose: onClose) {
            departuresBoard
            MenuLibrarySection(title: "Departure airports") {
                ForEach(Route.airportCities) { city in
                    let open = model.progress.isAirportUnlocked(city.index)
                    PickerRow(title: city.name,
                              subtitle: open ? city.country : UnlockHint.airport(city.index),
                              selected: model.settings.selectedAirport == city.index,
                              locked: !open,
                              choose: { model.settings.selectedAirport = city.index }) {
                        Text(city.code)
                            .font(.ticket(18, weight: .bold))
                            .frame(width: 46, alignment: .leading)
                    }
                }
            }
        }
    }

    private var departuresBoard: some View {
        VStack(spacing: 2) {
            ForEach(Route.cities) { city in boardRow(city) }
        }
        .padding(6)
        .background(TicketShape().fill(palette.boardBackground.color))
        .printShadow(TicketShape(), offset: 2)
    }

    private func boardRow(_ city: City) -> some View {
        let departure = model.settings.selectedAirport == city.index
        let visited = model.progress.hasVisited(city.index)
        let status = departure ? "Boarding" : visited ? "Visited" : "Locked"
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(city.code)
                    .font(.ticket(16, weight: .bold))
                    .frame(width: 35, alignment: .leading)
                Text(city.name).font(.ticket(15))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if city.hasAirport { Glyph("airplane.departure", size: 12) }
                Text(status.uppercased())
                    .font(.ticket(11, weight: .bold))
                    .foregroundStyle(departure ? palette.boardAccent.color : palette.boardText.color)
            }
            if visited && !city.unlocks.isEmpty {
                Text(city.unlocks.map(\.title).joined(separator: " · "))
                    .font(.ticket(12))
                    .opacity(0.85)
                    .padding(.leading, 43)
            }
        }
        .foregroundStyle(palette.boardText.color)
        .padding(.vertical, 8)
        .padding(.horizontal, 9)
        .background(palette.boardTile.color)
        .accessibilityElement(children: .combine)
    }
}

struct SettingsView: View {
    let onClose: () -> Void
    @Environment(AppModel.self) private var model
    @State private var confirmsReset = false

    var body: some View {
        @Bindable var settings = model.settings
        return MenuLibraryPage(title: "Settings", onClose: onClose) {
            MenuLibrarySection(title: "Sound and feel") {
                volume("Music", value: $settings.musicVolume)
                volume("Effects", value: $settings.effectsVolume)
                Toggle("Haptics", isOn: $settings.hapticsEnabled)
            }
            MenuLibrarySection(title: "Graphics") {
                choice("Quality", selection: $settings.graphicsQuality) {
                    ForEach(GraphicsQuality.allCases) { Text($0.title).tag($0) }
                }
                choice("Shadows", selection: $settings.shadowMode) {
                    ForEach(ShadowMode.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Plane trail", isOn: $settings.trailEffects)
                Toggle("Show FPS", isOn: $settings.showFPS)
            }
            MenuLibrarySection(title: "Flight") {
                choice("Time of day", selection: $settings.timeOfDay) {
                    ForEach(TimeOfDayMode.allCases) { Text($0.title).tag($0) }
                }
                choice("Controls", selection: $settings.controlScheme) {
                    ForEach(ControlScheme.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Show hints", isOn: $settings.showHints)
            }
            MenuLibrarySection(title: "Difficulty") {
                VStack(spacing: 0) {
                    ForEach(Difficulty.all) { difficulty in
                        let unlocked = model.progress.isUnlocked(difficulty.id)
                        PickerRow(title: difficulty.name,
                                  subtitle: unlocked ? difficulty.blurb : UnlockHint.difficulty(difficulty.id),
                                  selected: settings.selectedDifficulty == difficulty.id,
                                  locked: !unlocked,
                                  choose: { settings.selectedDifficulty = difficulty.id }) {
                            Text(UIFormat.multiplier(difficulty.scoreMultiplier))
                                .font(.ticket(14, weight: .semibold))
                                .frame(width: 46, alignment: .leading)
                        }
                    }
                }
            }
            MenuLibrarySection(title: "Data") {
                PaperButton("Reset progress", kind: .secondary) { confirmsReset = true }
                #if DEBUG
                PaperButton("Unlock everything", kind: .link) { model.progress.unlockEverything() }
                #endif
            }
        }
        .confirmationDialog("Reset flight progress?", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Reset progress", role: .destructive) { model.resetProgress() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears flight records, journal entries and unlocks.")
        }
    }

    private func volume(_ title: String, value: Binding<Double>) -> some View {
        LabeledContent(title) {
            Slider(value: value) { Text(title) }
                .labelsHidden()
                .frame(maxWidth: 200)
        }
    }

    private func choice<Value: Hashable, Options: View>(
        _ title: String, selection: Binding<Value>, @ViewBuilder options: () -> Options
    ) -> some View {
        LabeledContent(title) {
            Picker(title, selection: selection, content: options)
                .labelsHidden()
                .pickerStyle(.menu)
        }
    }
}
