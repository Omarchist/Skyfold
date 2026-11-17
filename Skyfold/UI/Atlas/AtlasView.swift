import SwiftUI

/// "Departures": a split-flap board with one row per city. Open airports read BOARDING and a
/// tap makes one the departure point; the rest read VISITED or LOCKED with what opens them.
struct AtlasView: View {
    let onClose: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        LibraryPage(kicker: "Skyfold Air", title: "Departures", onClose: onClose) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Tap a boarding row to leave from that airport.")
                    .font(.display(16, weight: .regular).italic())
                    .modifier(LibraryAtlasCaption())
                LibraryBoard(progress: model.progress, settings: model.settings)
            }
        }
    }
}

private struct LibraryAtlasCaption: ViewModifier {
    @Environment(\.palette) private var palette
    func body(content: Content) -> some View {
        content.foregroundStyle(palette.inkSoft.color)
    }
}

// MARK: - Status

private enum LibraryStatus {
    case boarding(selected: Bool)
    case visited
    case locked

    var word: String {
        switch self {
        case .boarding: "BOARDING"
        case .visited: "VISITED"
        case .locked: "LOCKED"
        }
    }
}

// MARK: - Board

private struct LibraryBoard: View {
    let progress: ProgressStore
    @Bindable var settings: GameSettings
    @Environment(\.palette) private var palette
    @Environment(\.isLandscape) private var wide

    var body: some View {
        let board = Rectangle()
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Flight status").signage(11, weight: .bold)
                Spacer()
                Text(UIFormat.clock()).font(.ticket(15, weight: .bold))
            }
            .foregroundStyle(palette.boardText.color.opacity(0.75))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            ForEach(Route.cities) { city in
                row(for: city)
            }
        }
        .background(board.fill(palette.boardBackground.color))
        .overlay(board.strokeBorder(palette.isDark ? palette.paperEdge.color : palette.ink.color, lineWidth: 2))
        .printShadow(board, offset: 4)
        .padding(.trailing, 4)
    }

    private func status(for city: City) -> LibraryStatus {
        if progress.isAirportUnlocked(city.index) { return .boarding(selected: settings.selectedAirport == city.index) }
        return progress.hasVisited(city.index) ? .visited : .locked
    }

    private func unlocks(for city: City) -> String {
        guard progress.hasVisited(city.index) else { return "-" }
        if city.unlocks.isEmpty { return city.index == 0 ? "Home airport" : "Nothing new" }
        return city.unlocks.map(\.title).joined(separator: " · ")
    }

    private func hint(for city: City) -> String? {
        guard !progress.hasVisited(city.index) else { return nil }
        if city.hasAirport { return UnlockHint.airport(city.index) }
        return "Reached after \(Route.city(city.index - 1).name)."
    }

    @ViewBuilder
    private func row(for city: City) -> some View {
        let status = status(for: city)
        let content = LibraryBoardRow(city: city, status: status, unlocks: unlocks(for: city),
                                      hint: status.word == "LOCKED" ? hint(for: city) : nil, wide: wide)
        if case .boarding(let selected) = status {
            Button {
                if !selected { UIFeedback.select() }
                settings.selectedAirport = city.index
            } label: { content }
                .buttonStyle(PressableStyle(pressedOpacity: 0.7, tapSound: false))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(city.name), \(city.code). Boarding. \(unlocks(for: city))")
                .accessibilityValue(selected ? "Departure airport" : "")
                .accessibilityHint(selected ? "" : "Leave from here")
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(city.name), \(city.code). \(status.word.capitalized). \(unlocks(for: city)) \(hint(for: city) ?? "")")
        }
    }
}

// MARK: - Row

private struct LibraryBoardRow: View {
    let city: City
    let status: LibraryStatus
    let unlocks: String
    let hint: String?
    let wide: Bool
    @Environment(\.palette) private var palette

    private var selected: Bool {
        if case .boarding(let s) = status { return s }
        return false
    }

    private var isLocked: Bool {
        if case .locked = status { return true }
        return false
    }

    var body: some View {
        let text = selected ? palette.boardAccent.color : palette.boardText.color
        Group {
            if wide { wideRow(text) } else { narrowRow(text) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) {
            if selected { Rectangle().fill(palette.boardAccent.color).frame(width: 4) }
        }
        .overlay(alignment: .top) { Rectangle().fill(palette.boardText.color.opacity(0.14)).frame(height: 1) }
        .contentShape(Rectangle())
    }

    private func narrowRow(_ text: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                LibraryFlaps(text: city.code, cells: 3, size: 15, color: text, dim: isLocked)
                LibraryFlaps(text: city.name, cells: 14, size: 13, color: text, dim: isLocked)
            }
            HStack(alignment: .top, spacing: 8) {
                details(text)
                Spacer(minLength: 4)
                LibraryFlaps(text: status.word, cells: 8, size: 10.5, color: text, dim: isLocked)
            }
        }
    }

    private func wideRow(_ text: Color) -> some View {
        HStack(alignment: .center, spacing: 14) {
            LibraryFlaps(text: city.code, cells: 3, size: 16, color: text, dim: isLocked)
            LibraryFlaps(text: city.name, cells: 14, size: 15, color: text, dim: isLocked)
            details(text).frame(maxWidth: .infinity, alignment: .leading)
            LibraryFlaps(text: status.word, cells: 8, size: 13, color: text, dim: isLocked)
        }
    }

    private func details(_ text: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(unlocks)
                .font(.ticket(12.5))
                .foregroundStyle(palette.boardText.color.opacity(isLocked ? 0.6 : 0.95))
                .fixedSize(horizontal: false, vertical: true)
            if let hint {
                Text(hint)
                    .font(.ticket(11.5))
                    .foregroundStyle(palette.boardText.color.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Split-flap lettering

/// A fixed-width field of flap cells. Short words leave blank cells, like a real board.
private struct LibraryFlaps: View {
    let text: String
    let cells: Int
    let size: CGFloat
    let color: Color
    var dim = false

    var body: some View {
        let letters = Array(text.uppercased())
        HStack(spacing: 2) {
            ForEach(0..<cells, id: \.self) { i in
                LibraryFlapCell(char: i < letters.count ? letters[i] : nil, size: size, color: color)
            }
        }
        .opacity(dim ? 0.55 : 1)
        // Fixed-width cells: they follow the text size only a little (about 1.12x).
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }
}

private struct LibraryFlapCell: View {
    let char: Character?
    @ScaledMetric private var size: CGFloat
    let color: Color
    @Environment(\.palette) private var palette

    init(char: Character?, size: CGFloat, color: Color) {
        self.char = char
        _size = ScaledMetric(wrappedValue: size, relativeTo: .footnote)
        self.color = color
    }

    var body: some View {
        let w = size * 0.66 + 5
        let h = size * 1.5
        let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
        ZStack {
            VStack(spacing: 0) {
                Rectangle().fill(palette.boardBackground.mixed(with: palette.boardText, 0.17).color)
                Rectangle().fill(palette.boardBackground.mixed(with: palette.boardText, 0.09).color)
            }
            if let char, char != " " {
                Text(String(char))
                    .font(.system(size: size, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
            }
            Rectangle().fill(palette.boardBackground.color).frame(height: 1.2)
        }
        .frame(width: w, height: h)
        .clipShape(shape)
        .accessibilityHidden(true)
    }
}
