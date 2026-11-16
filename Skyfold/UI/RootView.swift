import SwiftUI

/// The app shell. Routes between the menu and a flight, hands every screen the palette for
/// the sky outside, picks the background music, and pauses a run when the app is left.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Menu nightness, refreshed about once a minute. nil until the first refresh, so the
    /// first frame already uses the clock.
    @State private var storedMenuNightness: Double?

    private var menuNightness: Double { storedMenuNightness ?? model.menuNightness() }

    var body: some View {
        let night = menuNightness
        let menuPalette = Palette.at(nightness: night)
        ZStack {
            switch model.screen {
            case .menu:
                MainMenuView()
                    .modifier(PaletteScope(nightness: night))
                    .transition(.opacity)
            case .flight:
                if let run = model.run {
                    RootFlightHost(session: run)
                        .id(ObjectIdentifier(run))
                        .transition(.opacity)
                }
            }
        }
        // iPhones are compact in height exactly when they are landscape.
        .environment(\.isLandscape, verticalSizeClass == .compact)
        .background(menuPalette.skyBottom.color.ignoresSafeArea())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: model.screen)
        #if os(iOS)
        .modifier(RootChrome(hidden: model.screen == .flight))
        #endif
        // The status bar follows the paper: light text on the night sky, dark text by day.
        .preferredColorScheme(menuPalette.isDark ? .dark : .light)
        .background { RootMusic(menuNightness: night) }
        .task { await refreshMenuNightness() }
        .onChange(of: model.settings.timeOfDay) { _, _ in
            withAnimation(.easeInOut(duration: 0.6)) { storedMenuNightness = model.menuNightness() }
        }
        .onChange(of: scenePhase) { old, new in
            guard old == .active, new != .active else {
                if new == .active { storedMenuNightness = model.menuNightness() }
                return
            }
            // Leaving the app mid-flight: the run waits on the pause card.
            model.run?.pause()
        }
    }

    private func refreshMenuNightness() async {
        storedMenuNightness = model.menuNightness()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            if Task.isCancelled { break }
            withAnimation(.easeInOut(duration: 1.2)) { storedMenuNightness = model.menuNightness() }
        }
    }
}

// MARK: - System chrome

#if os(iOS)
/// Hides the status bar and the home indicator during a flight. From iOS 27 the status bar
/// has its own toolbar placement (the old `statusBarHidden` no longer takes effect there).
private struct RootChrome: ViewModifier {
    let hidden: Bool

    func body(content: Content) -> some View {
        Group {
            if #available(iOS 27.0, *) {
                content.toolbarVisibility(hidden ? .hidden : .automatic, for: .statusBar)
            } else {
                content.statusBarHidden(hidden)
            }
        }
        .persistentSystemOverlays(hidden ? .hidden : .automatic)
    }
}
#endif

// MARK: - Palette

/// Injects the palette for a nightness. Animatable, so a change made inside `withAnimation`
/// slides through dusk instead of snapping.
private struct PaletteScope: ViewModifier, Animatable {
    var nightness: Double

    var animatableData: Double {
        get { nightness }
        set { nightness = newValue }
    }

    func body(content: Content) -> some View {
        content
            .environment(\.palette, Palette.at(nightness: nightness))
            .environment(\.uiNightness, nightness)
    }
}

/// Reads the run's nightness (which the engine writes every frame) in a view of its own, so
/// the router above does not re-evaluate with it. The value is quantized, so the palette
/// only changes when the sky visibly does.
private struct RootFlightHost: View {
    let session: RunSession

    var body: some View {
        let night = (session.nightness * 100).rounded() / 100
        FlightScreen(session: session)
            .modifier(PaletteScope(nightness: night))
    }
}

// MARK: - Music

/// Decides which music mood is playing. It draws nothing; it only watches the screen, the
/// run phase and the sky.
///
///   menu                          menu mood (day or night by the menu clock)
///   countdown, flying, landing    flight mood, with hysteresis so dusk does not flicker
///   crashed                       stays on the flight mood
///   airport                       airport
///   game over                     menu mood
///   paused                        whatever was playing
///
/// Leaving the app silences it; coming back restores it.
private struct RootMusic: View {
    let menuNightness: Double
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    @State private var flightIsNight = false
    @State private var wanted: MusicMood?
    @State private var applied: MusicMood??

    private struct Key: Equatable {
        var screen: AppScreen
        var phase: RunPhase?
        var flightNight: Bool
        var menuNight: Bool
        var active: Bool
    }

    var body: some View {
        // Reading these registers the dependencies.
        let run = model.run
        let nightness = run?.nightness ?? 0
        let key = Key(screen: model.screen, phase: run?.phase, flightNight: flightIsNight,
                      menuNight: menuNightness > 0.5, active: scenePhase == .active)
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: key, initial: true) { _, new in apply(new) }
            .onChange(of: nightness, initial: true) { _, new in
                if new > 0.58 { flightIsNight = true } else if new < 0.42 { flightIsNight = false }
            }
            .onChange(of: run.map { ObjectIdentifier($0) }) { _, _ in
                // A new run starts from where its own sky is, not from the last run's latch.
                flightIsNight = (run?.nightness ?? 0) > 0.5
            }
            .accessibilityHidden(true)
    }

    private func apply(_ key: Key) {
        let menuMood: MusicMood = key.menuNight ? .menuNight : .menuDay
        let flightMood: MusicMood = key.flightNight ? .flightNight : .flightDay
        switch key.screen {
        case .menu:
            wanted = menuMood
        case .flight:
            switch key.phase {
            case .paused: break                       // leave the music alone
            case .airport: wanted = .airport
            case .gameOver, nil: wanted = menuMood
            case .countdown, .flying, .landing, .crashed: wanted = flightMood
            }
        }
        let target: MusicMood? = key.active ? wanted : nil
        if let applied, applied == target { return }
        applied = .some(target)
        Services.sound.setMusic(target)
    }
}
