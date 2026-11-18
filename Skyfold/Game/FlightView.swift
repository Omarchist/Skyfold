import SwiftUI
import RealityKit

/// The full-screen flight view: the 2D sky behind a transparent RealityView, and all the input.
///
/// Opaque as a whole. The HUD draws on top with hit testing off except on its buttons, so this
/// view owns the gestures: swipe up or down, or tap the top or bottom half with the tap scheme,
/// or the arrow keys and W and S with a keyboard.
struct FlightView: View {
    let session: RunSession
    let settings: GameSettings

    /// Created once, on first use. `State(initialValue:)` would build a fresh engine (and its
    /// simulation arrays) on every re-render of the parent, only to throw it away.
    @State private var holder = FlightEngineHolder()
    @State private var dragFired = false
    @FocusState private var focused: Bool

    init(session: RunSession, settings: GameSettings) {
        self.session = session
        self.settings = settings
    }

    private var engine: GameEngine { holder.engine(session: session, settings: settings) }
    private var backdropPaused: Bool {
        session.phase == .paused || session.phase == .crashed || session.phase == .gameOver
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let landscape = size.width > size.height
            let aspect = Float(size.width / max(size.height, 1))
            ZStack {
                SkyBackdrop(palette: Palette.at(nightness: engine.clock.nightness),
                            clock: engine.clock,
                            quality: settings.graphicsQuality,
                            horizonFraction: CGFloat(RigMath.horizonFraction(landscape: landscape, aspect: aspect)),
                            paused: backdropPaused)
                RealityView { content in
                    await engine.build(into: &content)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(swipe)
            .simultaneousGesture(tap(height: size.height))
            .onChange(of: size, initial: true) { _, s in
                engine.setViewSize(width: Float(s.width), height: Float(s.height))
            }
        }
        .ignoresSafeArea()
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            engine.requestLaneChange(press.key == .upArrow ? 1 : -1)
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "wWsS")) { press in
            let up = press.characters.lowercased() == "w"
            engine.requestLaneChange(up ? 1 : -1)
            return .handled
        }
        .onAppear { focused = true }
    }

    /// One lane per swipe: fires as soon as the drag is clearly vertical, then waits for the next touch.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { v in
                guard !dragFired else { return }
                let dx = v.translation.width, dy = v.translation.height
                guard abs(dy) >= 18, abs(dy) > abs(dx) * 1.15 else { return }
                dragFired = true
                engine.requestLaneChange(dy < 0 ? 1 : -1)
            }
            .onEnded { _ in dragFired = false }
    }

    private func tap(height: CGFloat) -> some Gesture {
        SpatialTapGesture()
            .onEnded { e in
                guard settings.controlScheme == .tapZones else { return }
                engine.requestLaneChange(e.location.y < height / 2 ? 1 : -1)
            }
    }
}

/// Holds the one `GameEngine` of a flight. Cheap to create; the engine itself is built lazily.
final class FlightEngineHolder {
    private var made: GameEngine?

    func engine(session: RunSession, settings: GameSettings) -> GameEngine {
        if let made { return made }
        let e = GameEngine(session: session, settings: settings)
        made = e
        return e
    }
}
