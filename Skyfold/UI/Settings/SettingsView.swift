import SwiftUI

/// "Settings", laid out like a printed form: numbered sections, ruled rows, boxes to tick.
struct SettingsView: View {
    let onClose: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        LibraryPage(kicker: "Form SF-1", title: "Settings", onClose: onClose) {
            LibrarySettingsForm(model: model)
        }
    }
}

/// The form itself, in two columns when the page is wide.
private struct LibrarySettingsForm: View {
    let model: AppModel
    @Environment(\.isLandscape) private var wide

    var body: some View {
        let settings = model.settings
        Group {
            if wide {
                HStack(alignment: .top, spacing: 36) {
                    VStack(alignment: .leading, spacing: 28) {
                        graphics(settings)
                        audio(settings)
                        LibrarySettingsData(model: model)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    flight(settings)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                VStack(alignment: .leading, spacing: 28) {
                    graphics(settings)
                    audio(settings)
                    flight(settings)
                    LibrarySettingsData(model: model)
                }
            }
        }
    }

    // MARK: Sections

    private func graphics(_ settings: GameSettings) -> some View {
        @Bindable var settings = settings
        return VStack(alignment: .leading, spacing: 0) {
            LibrarySectionHead(title: "1  Graphics")
            LibraryChoiceRow(title: "Quality",
                             options: GraphicsQuality.allCases.map { ($0, $0.title) },
                             selection: $settings.graphicsQuality)
            LibraryChoiceRow(title: "Shadows",
                             options: ShadowMode.allCases.map { ($0, $0.title) },
                             selection: $settings.shadowMode)
            LibraryToggleRow(title: "Plane trail", isOn: $settings.trailEffects)
            LibraryToggleRow(title: "Show FPS", isOn: $settings.showFPS)
        }
    }

    private func audio(_ settings: GameSettings) -> some View {
        @Bindable var settings = settings
        return VStack(alignment: .leading, spacing: 0) {
            LibrarySectionHead(title: "2  Audio")
            LibraryRulerRow(title: "Music volume", value: $settings.musicVolume)
            LibraryRulerRow(title: "Effects volume", value: $settings.effectsVolume)
            LibraryToggleRow(title: "Haptics", isOn: $settings.hapticsEnabled)
        }
    }

    private func flight(_ settings: GameSettings) -> some View {
        @Bindable var settings = settings
        return VStack(alignment: .leading, spacing: 0) {
            LibrarySectionHead(title: "3  Flight")
            Text("Difficulty")
                .font(.skyfold(16, weight: .medium))
                .padding(.top, 12)
                .padding(.bottom, 2)
            ForEach(Difficulty.all) { difficulty in
                LibrarySettingsDifficultyRow(difficulty: difficulty,
                                             unlocked: model.progress.isUnlocked(difficulty.id),
                                             selected: settings.selectedDifficulty == difficulty.id) {
                    settings.selectedDifficulty = difficulty.id
                }
            }
            LibraryChoiceRow(title: "Time of day",
                             options: TimeOfDayMode.allCases.map { ($0, $0.title) },
                             selection: $settings.timeOfDay)
            LibraryChoiceRow(title: "Controls",
                             options: ControlScheme.allCases.map { ($0, $0.title) },
                             selection: $settings.controlScheme)
            LibraryToggleRow(title: "Hints", note: "Short reminders during the first seconds of a flight.",
                             isOn: $settings.showHints)
        }
    }
}

// MARK: - Difficulty

/// One difficulty: a box to tick, its name, a line of small print and its score multiplier.
/// Locked ones stay on the form, dimmed, with the landing that unlocks them.
private struct LibrarySettingsDifficultyRow: View {
    let difficulty: Difficulty
    let unlocked: Bool
    let selected: Bool
    let choose: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button {
            if unlocked {
                if !selected { UIFeedback.select() }
                choose()
            } else {
                Services.haptics.play(.warning)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                box.padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(difficulty.name).font(.display(19)).opacity(unlocked ? 1 : 0.55)
                        Spacer(minLength: 6)
                        if unlocked {
                            Text(UIFormat.multiplier(difficulty.scoreMultiplier))
                                .font(.ticket(13, weight: .semibold))
                                .foregroundStyle(palette.inkSoft.color)
                        } else {
                            Text("Locked").signage(9.5, weight: .bold).foregroundStyle(palette.inkSoft.color)
                        }
                    }
                    Text(unlocked ? difficulty.blurb : UnlockHint.difficulty(difficulty.id))
                        .font(.skyfold(13))
                        .foregroundStyle(palette.inkSoft.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(alignment: .bottom) { RuleLine(color: palette.rule.opacity(0.7)) }
        }
        .buttonStyle(PressableStyle(pressedOpacity: 0.65, tapSound: false))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(unlocked
            ? "\(difficulty.name). \(difficulty.blurb)"
            : "\(difficulty.name), locked. \(UnlockHint.difficulty(difficulty.id))")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    private var box: some View {
        let shape = Rectangle()
        return ZStack {
            if selected {
                shape.fill(palette.accent.color)
                Glyph("checkmark", size: 12).foregroundStyle(palette.accentInk.color)
            } else if unlocked {
                shape.strokeBorder(palette.ink.color, lineWidth: 1.4)
            } else {
                shape.strokeBorder(palette.inkSoft.color, style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
            }
        }
        .frame(width: 22, height: 22)
    }
}

// MARK: - Data

private struct LibrarySettingsData: View {
    let model: AppModel
    @State private var confirming = false
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LibrarySectionHead(title: "4  Data")
            VStack(alignment: .leading, spacing: 14) {
                if confirming {
                    confirmation
                } else {
                    Text("Clears flight records, logbook entries and unlocks.")
                        .font(.skyfold(13))
                        .foregroundStyle(palette.inkSoft.color)
                    PaperButton("Reset progress", kind: .secondary) {
                        withAnimation(.easeOut(duration: 0.15)) { confirming = true }
                    }
                }
                #if DEBUG
                PaperButton("Unlock everything", kind: .link) { model.progress.unlockEverything() }
                #endif
            }
            .padding(.top, 14)
        }
    }

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reset everything?").font(.display(21, weight: .bold))
            Text("Flight records, logbook entries, skins, difficulties and airports go back to a fresh start. This cannot be undone.")
                .font(.skyfold(14))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 18) {
                PaperButton("Reset progress", kind: .primary) {
                    model.resetProgress()
                    withAnimation(.easeOut(duration: 0.15)) { confirming = false }
                }
                PaperButton("Keep it", kind: .link) {
                    withAnimation(.easeOut(duration: 0.15)) { confirming = false }
                }
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(Rectangle().fill(palette.paper.color))
        .overlay(Rectangle().strokeBorder(palette.accent.color, style: StrokeStyle(lineWidth: 1.6, dash: [6, 4])))
        .accessibilityElement(children: .contain)
    }
}
