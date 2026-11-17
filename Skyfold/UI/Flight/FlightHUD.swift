import SwiftUI

/// The top of the screen while flying: score and stars, the route strip, the pause key, the
/// marks for blessings and curses, and the frame rate when the setting is on.
///
/// Portrait stacks the pieces in rows. Landscape has little height, so score, route strip
/// and pause key share one row and the marks sit under the route strip.
struct FlightHUD: View {
    let session: RunSession
    let settings: GameSettings
    let landscape: Bool
    /// Portrait draws the 3, 2, 1 inside the column, under the marks, so it can never run into them.
    var countdownInColumn = false
    /// Experiment: the near-miss bonus is on for this run.
    private let nearMiss = ExperimentStore.shared.isOn(.nearMissBonus)
    /// Experiment: the ghost flight is on for this run.
    private let ghost = ExperimentStore.shared.isOn(.ghostFlight)

    var body: some View {
        ZStack {
            if ghost { GhostNote(session: session, landscape: landscape) }
            Group {
                if landscape {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 14) {
                            FlightScoreTag(session: session)
                            FlightRouteStrip(session: session)
                                .frame(maxWidth: 400)
                            Spacer(minLength: 8)
                            FlightPauseButton(session: session)
                        }
                        FlightMarks(session: session)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            FlightScoreTag(session: session)
                            if nearMiss { NearMissTag(session: session).padding(.leading, 2).padding(.top, 4) }
                            Spacer(minLength: 8)
                            FlightPauseButton(session: session)
                        }
                        FlightRouteStrip(session: session)
                        FlightMarks(session: session)
                        if countdownInColumn {
                            FlightCountdown(session: session, landscape: false)
                                .padding(.top, 14)
                                .padding(.leading, 16)
                                .transition(.opacity)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .topTrailing) {
                // Landscape has no free space beside the score ticket, so the stamp sits under the pause key.
                if nearMiss, landscape {
                    NearMissTag(session: session).padding(.top, 58).padding(.horizontal, 14)
                }
            }

            if settings.showFPS {
                FlightFPSLabel(session: session)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Score

/// Score over stars, on a small ticket. Reads only score and stars so its body is the only
/// thing that re-runs as the numbers tick.
private struct FlightScoreTag: View {
    let session: RunSession
    @Environment(\.palette) private var palette

    var body: some View {
        let shape = TicketShape(cornerRadius: 3, notch: .horizontal(fromTop: 26), notchRadius: 4)
        let multiplier = session.scoreMultiplier
        VStack(alignment: .leading, spacing: 4) {
            Text(UIFormat.number(session.score))
                .font(.ticket(28, weight: .bold))
                .foregroundStyle(palette.ink.color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack(spacing: 6) {
                FlightStarShape()
                    .fill(palette.blessing.color)
                    .overlay { FlightStarShape().stroke(palette.ink.withAlpha(0.55).color, lineWidth: 1) }
                    .frame(width: 14, height: 14)
                Text("\(session.stars)")
                    .font(.ticket(15, weight: .semibold))
                    .foregroundStyle(palette.ink.color)
                if abs(multiplier - 1) > 0.005 {
                    Text(UIFormat.multiplier(multiplier))
                        .font(.ticket(12, weight: .bold))
                        .foregroundStyle(palette.accent.color)
                        .padding(.leading, 4)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 7)
        .padding(.bottom, 8)
        .frame(minWidth: 118, alignment: .leading)
        .background(shape.fill(palette.paper.color))
        .overlay(shape.stroke(palette.flightEdge, lineWidth: 1))
        .printShadow(shape)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Score \(session.score), \(session.stars) stars")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Route strip

/// "LIS ---- plane - - - - RAK" with the distance left under it. The solid part is what is
/// flown, the dashes are what is ahead, like a route drawn on a map.
///
/// The engine writes the leg distance every frame. This wrapper is the only thing that reads it,
/// and it hands the face whole tens of meters and a progress rounded to 1/512, so the face (a
/// canvas) re-renders a few times a second instead of at the frame rate.
private struct FlightRouteStrip: View {
    let session: RunSession

    var body: some View {
        let tens = Int((session.metersToGo / 10).rounded(.up))
        let steps = Int((session.legProgress * 512).rounded())
        FlightRouteFace(origin: session.origin, destination: session.destination,
                        flightNumber: UIFormat.flightNumber(from: session.leg.fromRoute, to: session.leg.toRoute),
                        tens: tens, steps: steps, landing: session.phase == .landing)
            .equatable()
    }
}

private struct FlightRouteFace: View, Equatable {
    let origin: City
    let destination: City
    let flightNumber: String
    let tens: Int
    let steps: Int
    let landing: Bool
    @Environment(\.palette) private var palette

    /// Compared by what is printed, so the canvas does not redraw on frames where nothing changed.
    nonisolated static func == (a: Self, b: Self) -> Bool {
        a.origin.index == b.origin.index && a.destination.index == b.destination.index
            && a.flightNumber == b.flightNumber && a.tens == b.tens && a.steps == b.steps
            && a.landing == b.landing
    }

    private var status: String {
        landing ? "Landing in \(destination.name)" : "\(FlightFormat.toGo(Double(tens) * 10)) to \(destination.name)"
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(origin.code)
                    .font(.ticket(13, weight: .bold))
                FlightRouteLine(progress: Double(steps) / 512)
                    .frame(height: 20)
                Text(destination.code)
                    .font(.ticket(13, weight: .bold))
            }
            HStack(alignment: .firstTextBaseline) {
                Text(status)
                    .font(.ticket(12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                Text(flightNumber)
                    .font(.ticket(10, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(palette.inkSoft.color)
            }
        }
        .foregroundStyle(palette.ink.color)
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 7)
        .background(shape.fill(palette.paper.color))
        .overlay(shape.stroke(palette.flightEdge, lineWidth: 1))
        .printShadow(shape)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(origin.name) to \(destination.name). \(status)")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

private struct FlightRouteLine: View {
    let progress: Double
    @Environment(\.palette) private var palette

    var body: some View {
        let ink = palette.ink.color
        let soft = palette.inkSoft.color
        let paper = palette.paper.color
        let accent = palette.accent
        let shade = palette.accent.scaled(0.74)
        let print = palette.printShadow
        let p = CGFloat(min(max(progress, 0), 1))
        Canvas { ctx, size in
            let inset: CGFloat = 12
            let x0 = inset, x1 = size.width - inset
            let y = size.height / 2
            let x = x0 + (x1 - x0) * p

            var flown = Path()
            flown.move(to: CGPoint(x: x0, y: y))
            flown.addLine(to: CGPoint(x: x, y: y))
            ctx.stroke(flown, with: .color(ink), style: StrokeStyle(lineWidth: 2.5))

            var ahead = Path()
            ahead.move(to: CGPoint(x: x, y: y))
            ahead.addLine(to: CGPoint(x: x1, y: y))
            ctx.stroke(ahead, with: .color(soft), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))

            let start = Path(ellipseIn: CGRect(x: x0 - 4, y: y - 4, width: 8, height: 8))
            ctx.fill(start, with: .color(paper))
            ctx.stroke(start, with: .color(ink), lineWidth: 1.5)
            ctx.fill(Path(CGRect(x: x1 - 3, y: y - 3, width: 6, height: 6)), with: .color(ink))

            let plane = CGRect(x: x - 11, y: y - 8, width: 22, height: 16)
            ctx.fill(FlightPlaneShape().path(in: plane.offsetBy(dx: 1.5, dy: 1.5)), with: .color(print))
            ctx.fill(FlightPlaneShape(facet: .upper).path(in: plane), with: .color(accent.color))
            ctx.fill(FlightPlaneShape(facet: .lower).path(in: plane), with: .color(shade.color))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Pause and FPS

private struct FlightPauseButton: View {
    let session: RunSession
    @Environment(\.palette) private var palette

    /// The session only pauses from the countdown and from flight; gliding in, it does nothing.
    private var canPause: Bool { session.phase == .flying || session.phase == .countdown }

    var body: some View {
        Button {
            UIFeedback.select()
            session.pause()
        } label: {
            FlightPauseMark(color: palette.ink.color)
        }
        .buttonStyle(FlightSquareButtonStyle())
        .disabled(!canPause)
        .opacity(canPause ? 1 : 0.4)
        .accessibilityLabel("Pause")
    }
}

private struct FlightFPSLabel: View {
    let session: RunSession
    @Environment(\.palette) private var palette

    var body: some View {
        Text("\(session.fps) FPS")
            .font(.ticket(11, weight: .semibold))
            .tracking(1)
            .foregroundStyle(palette.ink.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(palette.paper.withAlpha(0.8).color)
    }
}
