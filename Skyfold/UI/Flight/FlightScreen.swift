import SwiftUI

/// The whole flight: the 3D view with the HUD and every phase overlay on top of it.
///
///   FlightView            full-screen, owns the flight gestures
///   FlightEdgeFlash       the airmail border that blinks when a shield takes a hit
///   FlightHUDLayer        score, route, marks, pause key, countdown, first-run hint
///   FlightPhaseLayer      pause, second wind, airport and game over
///
/// Everything the player does not need to touch is hit-test transparent so swipes and taps
/// fall through to the flight view. Only real buttons and the overlays take touches.
struct FlightScreen: View {
    let session: RunSession
    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                FlightView(session: session, settings: model.settings)
                    .ignoresSafeArea()
                FlightEdgeFlash(session: session)
                FlightHUDLayer(session: session, settings: model.settings, progress: model.progress, landscape: landscape)
                FlightPhaseLayer(session: session, landscape: landscape)
            }
            .environment(\.isLandscape, landscape)
        }
        .modifier(FlightPaletteScope(session: session))
        .task { await runDebugScript() }
        .background(Color.black.ignoresSafeArea())
        #if os(iOS)
        .modifier(FlightChrome())
        #endif
    }
}

extension FlightScreen {
    /// DEBUG launch argument -SkyfoldFlightScript: drives one phase for screenshots.
    @MainActor fileprivate func runDebugScript() async {
        #if DEBUG
        guard let script = DebugFlags.flightScript else { return }
        try? await Task.sleep(for: .seconds(6))
        guard session.phase == .flying else { return }
        switch script {
        case "pause": session.pause()
        case "crash": session.revives = 1; session.registerHit()
        case "shield":
            session.shields = 1
            session.registerHit()
        case "newbest": session.score = 98_765; session.stars = 12; session.quit()
        case "gameover": session.quit()
        default: break
        }
        #endif
    }
}

#if os(iOS)
/// No status bar and no home indicator in flight. From iOS 27 the status bar has its own
/// toolbar placement (the old `statusBarHidden` no longer takes effect there). RootView does the
/// same for the whole flight route; doing it here too keeps FlightScreen correct on its own.
private struct FlightChrome: ViewModifier {
    func body(content: Content) -> some View {
        Group {
            if #available(iOS 27.0, *) {
                content.toolbarVisibility(.hidden, for: .statusBar)
            } else {
                content.statusBarHidden(true)
            }
        }
        .persistentSystemOverlays(.hidden)
    }
}
#endif

/// Gives every flight view the palette for the sky outside the window right now.
private struct FlightPaletteScope: ViewModifier {
    let session: RunSession

    func body(content: Content) -> some View {
        // Rounded to 1/100 like RootView does, so the palette only changes when the sky visibly does.
        let night = (session.nightness * 100).rounded() / 100
        content
            .environment(\.palette, Palette.at(nightness: night))
            .environment(\.uiNightness, night)
    }
}

// MARK: - HUD layer

private struct FlightHUDLayer: View {
    let session: RunSession
    let settings: GameSettings
    let progress: ProgressStore
    let landscape: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsHUD: Bool {
        switch session.phase {
        case .countdown, .flying, .landing, .paused, .crashed: true
        case .airport, .gameOver: false
        }
    }

    var body: some View {
        ZStack {
            if showsHUD {
                FlightHUD(session: session, settings: settings, landscape: landscape,
                          countdownInColumn: !landscape && session.phase == .countdown)
                    .transition(.opacity)
            }
            if landscape, session.phase == .countdown {
                FlightCountdown(session: session, landscape: landscape)
                    .transition(.opacity)
            }
            FlightHint(session: session, settings: settings, progress: progress, landscape: landscape)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: showsHUD)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: session.phase == .countdown)
    }
}

// MARK: - Phase layer

private struct FlightPhaseLayer: View {
    let session: RunSession
    let landscape: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch session.phase {
            case .paused:
                FlightPauseOverlay(session: session, landscape: landscape)
                    .transition(.opacity)
            case .crashed:
                FlightCrashedOverlay(session: session, landscape: landscape)
                    .transition(.opacity)
            case .airport:
                AirportOverlay(session: session)
                    .transition(.opacity)
            case .gameOver:
                GameOverOverlay(session: session)
                    .transition(.opacity)
            case .countdown, .flying, .landing:
                EmptyView()
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28).delay(0.08), value: session.phase)
    }
}

// MARK: - Edge flash

/// When a Paper Shield takes a hit the screen gets an airmail border for half a second.
private struct FlightEdgeFlash: View {
    let session: RunSession
    @State private var level: Double = 0
    @State private var fade: Task<Void, Never>?

    var body: some View {
        ZStack {
            if level > 0.01 {
                AirmailStripe(stripe: 11)
                    .mask { FlightFrameShape(inset: 15).fill(style: FillStyle(eoFill: true)) }
                    .opacity(level)
                    .ignoresSafeArea()
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: session.shieldHits) { _, _ in
            fade?.cancel()
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { level = 1 }
            fade = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(140))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.45)) { level = 0 }
            }
        }
    }
}
