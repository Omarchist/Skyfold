import SwiftUI

enum MenuLibraryScreen: String, Identifiable {
    case journal, hangar, atlas, settings
    var id: String { rawValue }
}

/// The title screen. Portrait is one column: wordmark, the plane, the boarding pass, Fly,
/// and a directional sign along the bottom. Landscape is two columns: title and plane on
/// the left, pass and Fly on the right.
struct MainMenuView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.uiNightness) private var night
    @Environment(\.isLandscape) private var landscape
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var library: MenuLibraryScreen?
    @State private var picker: MenuPickerKind?
    /// Where the plane preview sits on screen, so the sun can sit just behind it.
    @State private var stage: CGRect = .zero
    /// The 3D preview is taken out of the tree while a full-screen page covers it.
    @State private var planeLive = true
    @State private var planeTask: Task<Void, Never>?
    @State private var didRunLaunchSwitches = false

    var body: some View {
        ZStack {
            MenuBackdrop(sun: sunCenter, sunRadius: sunRadius, horizon: landscape ? 0.72 : 0.56,
                         covered: library != nil || picker != nil)

            if landscape { landscapeLayout } else { portraitLayout }

            if let kind = picker {
                MenuPickerScrim(onTap: closePicker)
                    .transition(.opacity)
                    .zIndex(4)
                MenuPickerSlip(kind: kind, settings: model.settings, progress: model.progress, onClose: closePicker)
                    .transition(slipTransition)
                    .zIndex(5)
            }
        }
        .fullScreenCover(item: $library) { screen in
            switch screen {
            case .journal: JournalView(onClose: { library = nil })
            case .hangar: HangarView(onClose: { library = nil })
            case .atlas: AtlasView(onClose: { library = nil })
            case .settings: SettingsView(onClose: { library = nil })
            }
        }
        .onChange(of: library) { _, now in updatePlane(covered: now != nil) }
        .task { await runLaunchSwitches() }
    }

    // MARK: Layouts

    private var portraitLayout: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        planeStage.frame(minHeight: 150)
                        MenuBoardingPass(settings: model.settings, progress: model.progress, openPicker: openPicker)
                            .rotationEffect(.degrees(-0.9))
                            .padding(.bottom, 16)
                        flyButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 18)
                    .frame(minHeight: geo.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            MenuSignBar(items: signItems)
        }
    }

    private var landscapeLayout: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    planeStage
                }
                .padding(.leading, 6)
                .padding(.trailing, 14)
                .padding(.top, 6)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)

                VStack(spacing: 0) {
                    ScrollView {
                        MenuBoardingPass(settings: model.settings, progress: model.progress,
                                         compact: true, openPicker: openPicker)
                            .rotationEffect(.degrees(-0.9))
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                            .padding(.bottom, 10)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    // Fly stays put above the sign; a short phone scrolls the pass, never the key.
                    flyButton
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                    MenuSignBar(items: signItems)
                }
                .frame(width: min(430, geo.size.width * 0.47))
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text("Skyfold")
                    .font(.display(landscape ? 54 : 68, weight: .bold))
                    .tracking(-1.5)
                    .foregroundStyle(palette.ink.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                ParAvionLabel()
                    .rotationEffect(.degrees(-4))
                    .padding(.top, landscape ? 4 : 12)
            }
            // The airmail border, running off the right edge like the edge of an envelope.
            AirmailStripe(stripe: 7)
                .frame(height: 10)
                .padding(.trailing, landscape ? -14 : -20)
            Text("One sheet of paper. Ten cities.")
                .font(.display(landscape ? 14 : 16, weight: .regular).italic())
                .foregroundStyle(palette.inkSoft.color)
        }
    }

    private var planeStage: some View {
        let skin = PlaneSkin.get(model.settings.selectedSkin)
        return Group {
            if planeLive {
                PlanePreviewView(skin: skin, nightness: night)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { stage = $0 }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A paper plane, \(skin.name)")
    }

    private var flyButton: some View {
        Button { model.startRun() } label: {
            HStack {
                Text("Fly").font(.display(32, weight: .bold))
                Spacer()
                PaperPlaneGlyph(paper: palette.accentInk, crease: palette.accentInk.mixed(with: palette.accent, 0.35))
                    .frame(width: 44)
            }
        }
        .buttonStyle(PrimaryButtonStyle(size: .large, fullWidth: true))
        .accessibilityLabel("Fly")
        .accessibilityHint("Starts a flight from \(Route.city(model.settings.selectedAirport).name)")
    }

    private var signItems: [MenuSignItem] {
        let progress = model.progress.data
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
        return [
            MenuSignItem(id: "journal", title: "Flight log",
                         detail: "\(model.progress.discoveredModifierCount)/\(ModifierID.allCases.count)") { library = .journal },
            MenuSignItem(id: "hangar", title: "Hangar",
                         detail: "\(progress.unlockedSkins.count)/\(SkinID.allCases.count)") { library = .hangar },
            MenuSignItem(id: "atlas", title: "Departures",
                         detail: "\(progress.visitedCities.count)/\(Route.count)") { library = .atlas },
            MenuSignItem(id: "settings", title: "Settings", detail: "v\(version)") { library = .settings },
        ]
    }

    // MARK: Sun

    private var sunCenter: CGPoint? {
        guard stage.width > 10, stage.height > 10 else { return nil }
        return CGPoint(x: stage.midX + stage.width * (landscape ? 0.16 : 0.2),
                       y: stage.minY + stage.height * (landscape ? 0.4 : 0.34))
    }

    private var sunRadius: CGFloat {
        guard stage.width > 10 else { return 64 }
        return min(max(min(stage.width, stage.height) * 0.3, 42), 92)
    }

    // MARK: Picker

    private var slipTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .move(edge: landscape ? .trailing : .bottom)
    }

    private func openPicker(_ kind: MenuPickerKind) {
        withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.24)) { picker = kind }
    }

    private func closePicker() {
        withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.2)) { picker = nil }
    }

    // MARK: Plane lifetime

    private func updatePlane(covered: Bool) {
        planeTask?.cancel()
        if covered {
            // Keep it until the page has finished sliding over, then free the 3D view.
            planeTask = Task {
                try? await Task.sleep(for: .milliseconds(700))
                if !Task.isCancelled { planeLive = false }
            }
        } else {
            withAnimation(.easeOut(duration: 0.3)) { planeLive = true }
        }
    }

    // MARK: Launch switches

    private func runLaunchSwitches() async {
        guard !didRunLaunchSwitches else { return }
        didRunLaunchSwitches = true
        if let raw = DebugFlags.screen, let screen = MenuLibraryScreen(rawValue: raw) {
            try? await Task.sleep(for: .milliseconds(350))
            library = screen
        }
        #if DEBUG
        // Screenshots only: -SkyfoldStartAirport N (with -SkyfoldUnlockAll YES) starts a run from route N.
        if UserDefaults.standard.object(forKey: "SkyfoldStartAirport") != nil {
            model.settings.selectedAirport = UserDefaults.standard.integer(forKey: "SkyfoldStartAirport")
            model.startRun()
            return
        }
        // Screenshots only: -SkyfoldMenuPicker airport|difficulty|skin opens that list.
        if let raw = UserDefaults.standard.string(forKey: "SkyfoldMenuPicker"),
           let kind = MenuPickerKind(rawValue: raw) {
            try? await Task.sleep(for: .milliseconds(350))
            openPicker(kind)
        }
        #endif
    }
}
