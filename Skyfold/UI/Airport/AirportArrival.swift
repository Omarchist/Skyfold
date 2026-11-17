import SwiftUI

// Step one of the airport: the passport page with the arrival stamp, and, when the landing
// opened something new, a ticket stub listing it.

struct AirportArrivalLayer: View {
    let session: RunSession
    let arrival: ArrivalReport
    let metrics: AirportMetrics
    let stampDate: String
    let cardIn: Bool
    let stampLanded: Bool
    let stubShown: Bool
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Experiment: postcards. A new city (never home) gets one line and a small card.
    private let postcardsOn = ExperimentStore.shared.isOn(.postcards)
    /// `inset`: the portrait column adds its own spacing, inside the condition so that with the
    /// switch off (or no new city) nothing is left behind, not even padding.
    @ViewBuilder private func postcardNote(inset: Bool = false) -> some View {
        if postcardsOn, arrival.firstVisit, arrival.city.index != 0 {
            PostcardArrivalNote(city: arrival.city)
                .opacity(cardIn ? 1 : 0)
                .padding(.top, inset ? 14 : 0)
                .padding(.horizontal, inset ? 6 : 0)
        }
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView(showsIndicators: false) { content }
                .defaultScrollAnchor(metrics.isLandscape ? .top : .bottom)
        }
        .padding(metrics.edgeInsets)
        .frame(width: metrics.size.width, height: metrics.size.height, alignment: .bottomLeading)
    }

    @ViewBuilder private var content: some View {
        if metrics.isLandscape { landscape } else { portrait }
    }

    private var portrait: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            card(landscape: false)
                .zIndex(1)
            if !arrival.unlocks.isEmpty {
                stub
                    .padding(.leading, 26)
                    .padding(.trailing, 10)
                    .padding(.top, -4)
            }
            postcardNote(inset: true)
            AirportButton(title: "To the gates", trailing: "→", action: onContinue)
                .padding(.top, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var landscape: some View {
        HStack(alignment: .bottom, spacing: 22) {
            card(landscape: true)
                .frame(maxWidth: 540)
            VStack(alignment: .leading, spacing: 16) {
                if !arrival.unlocks.isEmpty { stub }
                postcardNote()
                AirportButton(title: "To the gates", trailing: "→", action: onContinue)
            }
            .frame(width: 262)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func card(landscape: Bool) -> some View {
        AirportPassportCard(session: session, arrival: arrival, stampDate: stampDate,
                            landscape: landscape, stampLanded: stampLanded)
            .opacity(cardIn ? 1 : 0)
            .offset(y: cardIn || reduceMotion ? 0 : 22)
    }

    private var stub: some View {
        AirportUnlockStub(unlocks: arrival.unlocks, seed: arrival.city.code)
            .opacity(stubShown ? 1 : 0)
            .offset(x: stubShown || reduceMotion ? 0 : -26)
    }
}

// MARK: - Passport page

struct AirportPassportCard: View {
    let session: RunSession
    let arrival: ArrivalReport
    let stampDate: String
    let landscape: Bool
    let stampLanded: Bool

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var city: City { arrival.city }
    private var stampSize: CGFloat { landscape ? 158 : 172 }

    private var flightLine: String {
        let leg = session.leg
        return "\(leg.from.code) → \(city.code)  ·  \(UIFormat.flightNumber(from: leg.fromRoute, to: leg.toRoute))"
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        Group {
            if landscape { landscapeBody } else { portraitBody }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(palette.paper.color))
        .overlay(shape.strokeBorder(palette.paperEdge.color, lineWidth: 1))
        .printShadow(shape)
        .overlay(alignment: landscape ? .topLeading : .topTrailing) { stamp }
        .rotationEffect(Seeded.tilt("passport-" + city.code, min: 0.5, max: 1.3))
    }

    private var stamp: some View {
        AirportStamp(city: city, date: stampDate, diameter: stampSize)
            .rotationEffect(Seeded.tilt("stamp-" + city.code, min: 4, max: 8))
            .scaleEffect(stampLanded || reduceMotion ? 1 : 1.35)
            .opacity(stampLanded ? 1 : 0)
            .offset(x: landscape ? -6 : 12, y: landscape ? -22 : -30)
            .allowsHitTesting(false)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(flightLine)
                .font(.ticket(12, weight: .medium))
                .tracking(1)
                .foregroundStyle(palette.inkSoft.color)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(city.name)
                .font(.display(landscape ? 42 : 38, weight: .bold))
                .foregroundStyle(palette.ink.color)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
            // The tag moves under the country when the two do not fit on one line.
            FitStack(spacing: 8, rowSpacing: 6) {
                Text(city.country)
                    .signage(12)
                    .foregroundStyle(palette.inkSoft.color)
                    .lineLimit(1)
                if arrival.firstVisit {
                    Text("First visit")
                        .signage(10)
                        .foregroundStyle(palette.accent.color)
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .overlay(Rectangle().strokeBorder(palette.accent.color, lineWidth: 1))
                }
            }
        }
    }

    private var blurb: some View {
        Text(city.blurb)
            .font(.display(landscape ? 20 : 19, weight: .regular).italic())
            .foregroundStyle(palette.ink.color)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var portraitBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading
                .padding(.trailing, stampSize - 30)
                .frame(maxWidth: .infinity, minHeight: stampSize - 44, alignment: .topLeading)
            Perforation()
                .padding(.vertical, 12)
            blurb
        }
        .padding(18)
    }

    private var landscapeBody: some View {
        HStack(alignment: .top, spacing: 0) {
            Color.clear.frame(width: stampSize - 6, height: 1)
            VStack(alignment: .leading, spacing: 0) {
                heading
                Perforation()
                    .padding(.vertical, 12)
                blurb
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 18)
        .padding(.trailing, 20)
        .padding(.vertical, 20)
        .frame(minHeight: stampSize + 8, alignment: .top)
    }
}

// MARK: - Unlock stub

/// "New" on the tab, the unlocks as plain lines on the stub.
struct AirportUnlockStub: View {
    let unlocks: [Unlock]
    let seed: String

    @Environment(\.palette) private var palette

    var body: some View {
        let tab: CGFloat = 40
        let shape = AirportTabTicketShape(tabWidth: tab)
        HStack(spacing: 0) {
            Text("New")
                .signage(11)
                .foregroundStyle(palette.accent.color)
                .fixedSize()
                .rotationEffect(.degrees(-90))
                .frame(width: tab)
            Perforation(vertical: true)
                .frame(maxHeight: .infinity)
                .padding(.vertical, 9)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(unlocks, id: \.self) { unlock in
                    HStack(spacing: 10) {
                        Glyph(unlock.symbol, size: 15)
                            .foregroundStyle(palette.secondary.color)
                            .frame(width: 20)
                        Text(unlock.title)
                            .font(.skyfold(17, weight: .semibold))
                            .foregroundStyle(palette.ink.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.vertical, 15)
            .padding(.leading, 14)
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // The perforation is vertically greedy; without this the stub would stretch to fill the screen.
        .fixedSize(horizontal: false, vertical: true)
        .background(shape.fill(palette.paper.color))
        .overlay(shape.stroke(palette.paperEdge.color, lineWidth: 1))
        .printShadow(shape)
        .rotationEffect(Seeded.tilt("stub-" + seed, min: 0.4, max: 1.1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Unlocked: " + unlocks.map(\.title).joined(separator: ", "))
    }
}
