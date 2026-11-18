import SwiftUI

/// The frame the four library screens share (Flight log, Settings, Hangar, Departures): a
/// full-screen sheet of card stock, a left-aligned title over an airmail stripe, and a Close
/// control. Wide windows (landscape) put the optional `side` view in its own column on the left;
/// narrow ones stack it above the content. `pinSide` keeps it fixed above the scrolling content.
struct LibraryPage<Side: View, Content: View>: View {
    let kicker: String
    let title: String
    var pinSide = false
    let onClose: () -> Void
    @ViewBuilder var side: Side
    @ViewBuilder var content: Content

    @Environment(\.palette) private var palette

    private var hasSide: Bool { Side.self != EmptyView.self }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height && geo.size.width > 620
            ZStack {
                PaperBackground(seed: "library." + title)
                VStack(alignment: .leading, spacing: 0) {
                    header(wide: wide)
                    layout(wide: wide, size: geo.size)
                }
            }
            .environment(\.isLandscape, wide)
        }
        .font(.skyfold(16))
        .foregroundStyle(palette.ink.color)
        .tint(palette.secondary.color)
        .background(palette.paper.color.ignoresSafeArea())
    }

    private func header(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kicker)
                        .signage(10.5)
                        .foregroundStyle(palette.inkSoft.color)
                    Text(title)
                        .font(.display(wide ? 34 : 42, weight: .bold))
                        .tracking(-0.8)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: 8)
                Button(action: onClose) { Text("Close") }
                    .buttonStyle(SecondaryButtonStyle(size: .regular))
                    .accessibilityLabel("Close \(title)")
                    .padding(.trailing, 3)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            AirmailStripe(stripe: 6)
                .frame(height: 7)
                .padding(.top, 12)
                .ignoresSafeArea(edges: .horizontal)
        }
    }

    @ViewBuilder
    private func layout(wide: Bool, size: CGSize) -> some View {
        if hasSide && wide {
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    side.padding(20)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(width: min(360, size.width * 0.4))
                Rectangle().fill(palette.rule).frame(width: 1)
                    .padding(.vertical, 14)
                scrolling(content, wide: wide)
            }
        } else if hasSide && pinSide {
            VStack(spacing: 0) {
                side.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 8)
                scrolling(content, wide: wide)
            }
        } else {
            scrolling(VStack(alignment: .leading, spacing: 24) { side; content }, wide: wide)
        }
    }

    private func scrolling<V: View>(_ view: V, wide: Bool) -> some View {
        ScrollView {
            view
                .frame(maxWidth: 900, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

extension LibraryPage where Side == EmptyView {
    init(kicker: String, title: String, onClose: @escaping () -> Void,
         @ViewBuilder content: () -> Content) {
        self.init(kicker: kicker, title: title, onClose: onClose, side: { EmptyView() }, content: content)
    }
}

/// A section heading on a printed form: small tracked caps over a heavy rule.
struct LibrarySectionHead: View {
    let title: String
    var note: String? = nil
    var tint: Color? = nil
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .signage(12, weight: .bold)
                    .foregroundStyle(tint ?? palette.ink.color)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if let note {
                    Text(note).font(.ticket(11.5)).foregroundStyle(palette.inkSoft.color)
                }
            }
            RuleLine(color: tint ?? palette.ink.color, weight: 2)
        }
    }
}
