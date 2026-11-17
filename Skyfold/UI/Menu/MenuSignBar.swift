import SwiftUI

struct MenuSignItem: Identifiable {
    let id: String
    let title: String
    /// A small line of print under the title, in the board's accent.
    let detail: String
    let action: () -> Void
}

/// The four destinations as an airport directional sign: a dark board, one line of signage
/// per place, a counter underneath. It runs off the bottom (and side) edge of the screen.
struct MenuSignBar: View {
    let items: [MenuSignItem]
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Above the default size the labels get less tracking and padding so "Departures" fits.
        let large = typeSize > .large
        let text = palette.boardText
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    // A fixed height: a bare Rectangle would take every spare point of the screen.
                    Rectangle().fill(text.withAlpha(0.2).color).frame(width: 1, height: 34)
                }
                Button(action: item.action) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .signage(10.5, weight: .bold, tracking: large ? 0.8 : 1.5)
                            .foregroundStyle(text.color)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text(item.detail)
                            .font(.ticket(10, weight: .medium))
                            .foregroundStyle(palette.boardAccent.color)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, large ? 6 : 9)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                }
                .buttonStyle(MenuSignStyle())
                .accessibilityLabel(item.title)
                .accessibilityValue(item.detail)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .background {
            ZStack(alignment: .top) {
                palette.boardBackground.color
                // The colored rule along the top edge of a directional sign.
                Rectangle().fill(palette.accent.color).frame(height: 3)
            }
            .ignoresSafeArea(edges: [.bottom, .horizontal])
        }
    }
}

private struct MenuSignStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MenuSignFace(configuration: configuration)
    }
}

private struct MenuSignFace: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.palette) private var palette

    var body: some View {
        configuration.label
            .background(palette.boardText.withAlpha(configuration.isPressed ? 0.16 : 0).color)
            .contentShape(Rectangle())
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { UIFeedback.tap() }
            }
    }
}
