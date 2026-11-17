import SwiftUI

/// The menu ticket for the daily route: today's date, the route, today's best, and the button.
/// A small horizontal ticket with a tear-off stub, so it sits beside the boarding pass without
/// repeating it. The date, route and best are read once when the menu appears.
struct DailyRouteTicket: View {
    /// Starts the route shown on the ticket (not whatever the date is when it is pressed).
    let onFly: (DailyRoute) -> Void

    @Environment(\.palette) private var palette
    @Environment(\.scenePhase) private var scenePhase
    @State private var route = DailyRoute.today
    @State private var best = DailyBestStore.shared.best(for: .today)

    private let stubWidth: CGFloat = 116

    var body: some View {
        let shape = TicketShape(cornerRadius: 4, notch: .vertical(fromTrailing: stubWidth), notchRadius: 7)
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Daily route")
                        .signage(9.5, weight: .heavy)
                        .foregroundStyle(palette.accent.color)
                    Text(route.shortDate)
                        .font(.ticket(11, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(palette.inkSoft.color)
                }
                Text("\(route.origin.code) → \(route.destination.code)")
                    .font(.ticket(20, weight: .bold))
                    .foregroundStyle(palette.ink.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(bestLine)
                    .signage(9.5, weight: .semibold)
                    .foregroundStyle(palette.inkSoft.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { onFly(route) } label: {
                Text("Fly today's route")
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(SecondaryButtonStyle(size: .compact, fullWidth: true))
            .padding(.horizontal, 10)
            .frame(width: stubWidth - 1)
            // Behind the stub, so the dashed line follows the ticket's height instead of setting it.
            .background(alignment: .leading) { Perforation(vertical: true).padding(.vertical, 8) }
            .accessibilityHint("Starts today's fixed route from \(route.origin.name)")
        }
        .background(shape.fill(palette.paper.color))
        .overlay(shape.stroke(palette.paperEdge.color, lineWidth: 1))
        .printShadow(shape)
        .accessibilityElement(children: .contain)
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }

    /// The date can turn over while the app waits on the menu.
    private func refresh() {
        let today = DailyRoute.today
        route = today
        best = DailyBestStore.shared.best(for: today)
    }

    private var bestLine: String {
        if let best { "Today's best  \(UIFormat.number(best))" } else { "Not flown today" }
    }
}

/// One line on the game-over ticket of a daily run: "Daily route, 17 NOV" and "Today's best".
struct DailyRouteResultLine: View {
    let session: RunSession

    @Environment(\.palette) private var palette

    var body: some View {
        if let route = session.daily {
            let best = session.dailyBest.map { UIFormat.number($0) } ?? "0"
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { title(route); Spacer(minLength: 4); bestText(best) }
                VStack(alignment: .leading, spacing: 2) { title(route); bestText(best) }
            }
        }
    }

    private func title(_ route: DailyRoute) -> some View {
        Text("Daily route, \(route.shortDate)")
            .signage(10, weight: .heavy)
            .foregroundStyle(palette.accent.color)
            .lineLimit(1)
    }

    private func bestText(_ best: String) -> some View {
        Text("Today's best  \(best)\(session.dailyIsBest ? "  New" : "")")
            .signage(10, weight: .semibold)
            .foregroundStyle(palette.inkSoft.color)
            .lineLimit(1)
    }
}

#if DEBUG
enum DailyRouteDebug {
    /// Screenshots only: `-SkyfoldDailyStart YES` starts today's daily run straight from the menu.
    static var startsDaily: Bool { UserDefaults.standard.bool(forKey: "SkyfoldDailyStart") }

    /// Starts the daily run; with `-SkyfoldDailyQuit <seconds>` it ends the flight after that long,
    /// so the game-over ticket can be photographed.
    static func runAndQuit(_ model: AppModel) async {
        model.startDailyRun()
        let seconds = UserDefaults.standard.double(forKey: "SkyfoldDailyQuit")
        guard seconds > 0 else { return }
        // Unstructured: the menu's own task is cancelled as soon as the flight screen replaces it.
        let run = model.run
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            run?.quit()
        }
    }
}
#endif
