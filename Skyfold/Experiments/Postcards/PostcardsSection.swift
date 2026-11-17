import SwiftUI

// The Flight log's Postcards section (a rack of cards, blank outlines for the ones not mailed
// yet, a large view of each) and the line on the arrival card.

// MARK: - Flight log section

struct PostcardsSection: View {
    let progress: ProgressStore

    @Environment(\.palette) private var palette
    @State private var store = PostcardStore.shared
    @State private var open: City?

    private var cities: [City] { Array(Route.cities.dropFirst()) }

    var body: some View {
        let mailed = cities.filter { progress.hasVisited($0.index) }.count
        VStack(alignment: .leading, spacing: 0) {
            LibrarySectionHead(title: "Postcards", note: "\(mailed) of \(cities.count) mailed",
                               tint: palette.secondary.color)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 148, maximum: 230), spacing: 20, alignment: .top)],
                      alignment: .leading, spacing: 22) {
                ForEach(cities) { city in slot(city) }
            }
            .padding(.top, 18)
            .padding(.trailing, 4)
        }
        .onAppear {
            store.reconcile(visited: progress.data.visitedCities)
            #if DEBUG
            // Screenshots: `-SkyfoldPostcardOpen 2` opens that city's card.
            if open == nil, let i = UserDefaults.standard.string(forKey: "SkyfoldPostcardOpen").flatMap(Int.init),
               progress.hasVisited(i) { open = Route.city(i) }
            #endif
        }
        .fullScreenCover(item: $open) { city in
            PostcardDetail(city: city, date: store.date(for: city.index)) { open = nil }
        }
    }

    @ViewBuilder
    private func slot(_ city: City) -> some View {
        if progress.hasVisited(city.index) {
            let date = store.date(for: city.index)
            Button {
                UIFeedback.tap()
                open = city
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    PostcardFront(city: city, date: date, shadow: 3)
                        .rotationEffect(Seeded.tilt("pc-" + city.code, min: 0.3, max: 1.6))
                    HStack(spacing: 8) {
                        Text(city.code).font(.ticket(11.5, weight: .bold))
                        Spacer(minLength: 0)
                        Text(date.map { UIFormat.stampDate($0) } ?? "")
                            .font(.ticket(11.5))
                            .foregroundStyle(palette.inkSoft.color)
                    }
                    .padding(.horizontal, 2)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Postcard of \(city.name)")
            .accessibilityHint("Shows the card and its back")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .strokeBorder(palette.inkSoft.withAlpha(0.7).color,
                                      style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(city.code)
                            .font(.ticket(22, weight: .bold))
                            .foregroundStyle(palette.inkSoft.color)
                        Text("Not mailed yet")
                            .font(.display(15, weight: .regular).italic())
                            .foregroundStyle(palette.inkSoft.color)
                    }
                    .padding(12)
                }
                .aspectRatio(3 / 2, contentMode: .fit)
                Color.clear.frame(height: 16)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(city.name) postcard. Not mailed yet.")
        }
    }
}

// MARK: - Large view

private struct PostcardDetail: View {
    let city: City
    let date: Date?
    let onClose: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            ZStack {
                palette.paper.color.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(city.country).signage(10.5).foregroundStyle(palette.inkSoft.color)
                            Text(city.name)
                                .font(.display(wide ? 30 : 36, weight: .bold))
                                .tracking(-0.6)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        Spacer(minLength: 8)
                        Button(action: onClose) { Text("Close") }
                            .buttonStyle(SecondaryButtonStyle(size: .regular))
                            .accessibilityLabel("Close postcard")
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    AirmailStripe(stripe: 6)
                        .frame(height: 7)
                        .padding(.top, 12)
                        .ignoresSafeArea(edges: .horizontal)
                    ScrollView {
                        Group {
                            if wide {
                                HStack(alignment: .top, spacing: 26) { cards }
                            } else {
                                VStack(alignment: .leading, spacing: 26) { cards }
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.top, 24)
                        .padding(.bottom, 32)
                        .frame(maxWidth: 940)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
        }
        .font(.skyfold(16))
        .foregroundStyle(palette.ink.color)
    }

    @ViewBuilder private var cards: some View {
        PostcardFront(city: city, date: date, shadow: 4)
            .rotationEffect(.degrees(-0.8))
        PostcardBack(city: city, date: date, shadow: 4)
            .rotationEffect(.degrees(0.7))
    }
}

// MARK: - Arrival line

/// "A postcard is in the mail", with the card in miniature. Shown on the arrival card the first
/// time a city is landed in; it also writes the first-landing date.
struct PostcardArrivalNote: View {
    let city: City

    @Environment(\.palette) private var palette
    @State private var landed = Date.now

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        HStack(spacing: 14) {
            PostcardFront(city: city, date: landed, shadow: 2)
                .frame(width: 92)
                .rotationEffect(Seeded.tilt("pcn-" + city.code, min: 2, max: 4))
            VStack(alignment: .leading, spacing: 3) {
                Text("A postcard is in the mail")
                    .font(.display(17, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(city.name) goes in the Flight log.")
                    .font(.skyfold(13))
                    .foregroundStyle(palette.inkSoft.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(shape.fill(palette.paper.color))
        .overlay(shape.strokeBorder(palette.paperEdge.color, lineWidth: 1))
        .printShadow(shape)
        .rotationEffect(Seeded.tilt("pcnote-" + city.code, min: 0.3, max: 0.9))
        .onAppear { PostcardStore.shared.recordLanding(city.index, on: landed) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("A postcard is in the mail. \(city.name) goes in the Flight log.")
    }
}
