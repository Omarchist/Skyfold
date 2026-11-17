import SwiftUI

// Printed-form controls for the settings screen: boxes to tick, an ON/OFF pair, a ruler to
// slide along. All flat, ink outlines, one hard shadow on the part you are holding.

// MARK: - Layout

/// Left-to-right, wrapping to the next line when a row is full.
struct LibraryFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(bounds.width, subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                                  proposal: .unspecified)
        }
    }

    private func arrange(_ maxWidth: CGFloat, _ subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return (CGSize(width: width, height: y + rowHeight), origins)
    }
}

// MARK: - Choice

/// A row of boxes, one of which is filled in. For settings with a few short options.
struct LibraryChoiceRow<Value: Hashable>: View {
    let title: String
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.skyfold(16, weight: .medium))
            LibraryFlow(spacing: 10) {
                ForEach(options.indices, id: \.self) { i in
                    box(options[i])
                }
            }
            .padding(.trailing, 3)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .bottom) { RuleLine() }
        .accessibilityElement(children: .contain)
    }

    private func box(_ option: (value: Value, title: String)) -> some View {
        let on = option.value == selection
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        return Button {
            guard !on else { return }
            UIFeedback.select()
            selection = option.value
        } label: {
            Text(option.title)
                .font(.skyfold(14, weight: .semibold))
                .foregroundStyle(on ? palette.accentInk.color : palette.ink.color)
                .padding(.horizontal, 13)
                .frame(minHeight: 40)
                .background(shape.fill(on ? palette.accent.color : palette.paper.color))
                .overlay(shape.strokeBorder(on ? palette.accent.color : palette.ink.color, lineWidth: 1.4))
                .background { if on { shape.fill(palette.printShadow).offset(x: 2.5, y: 2.5) } }
        }
        .buttonStyle(PressableStyle(pressedOpacity: 0.65, tapSound: false))
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - On / off

/// A label and a two-box OFF / ON pair. The whole row is the button.
struct LibraryToggleRow: View {
    let title: String
    var note: String? = nil
    @Binding var isOn: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        Button {
            UIFeedback.select()
            isOn.toggle()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.skyfold(16, weight: .medium))
                    if let note {
                        Text(note).font(.skyfold(13)).foregroundStyle(palette.inkSoft.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                pair
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(alignment: .bottom) { RuleLine() }
        }
        .buttonStyle(PressableStyle(pressedOpacity: 0.7, tapSound: false))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }

    private var pair: some View {
        HStack(spacing: 0) {
            cell("Off", filled: !isOn, fill: palette.ink.color, text: palette.paper.color)
            cell("On", filled: isOn, fill: palette.accent.color, text: palette.accentInk.color)
        }
        .overlay(Rectangle().strokeBorder(palette.ink.color, lineWidth: 1.4))
        .background(Rectangle().fill(palette.printShadow).offset(x: 2.5, y: 2.5))
    }

    private func cell(_ text: String, filled: Bool, fill: Color, text color: Color) -> some View {
        Text(text)
            .signage(11.5, weight: .bold)
            .foregroundStyle(filled ? color : palette.inkSoft.color)
            .frame(width: 46, height: 34)
            .background(filled ? fill : palette.paper.color)
    }
}

// MARK: - Ruler slider

/// A ruled scale from 0 to 100 with a card tab to slide along it.
struct LibraryRulerRow: View {
    let title: String
    @Binding var value: Double
    @Environment(\.palette) private var palette
    @State private var lastStep = -1

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.skyfold(16, weight: .medium))
                Spacer()
                Text("\(Int((value * 100).rounded()))")
                    .font(.ticket(16, weight: .bold))
                    .foregroundStyle(palette.ink.color)
                    .monospacedDigit()
            }
            ruler
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(alignment: .bottom) { RuleLine() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(1, (value * 10).rounded() / 10 + 0.1)
            case .decrement: value = max(0, (value * 10).rounded() / 10 - 0.1)
            @unknown default: break
            }
        }
    }

    private var ruler: some View {
        GeometryReader { geo in
            let thumbW: CGFloat = 20
            let usable = max(geo.size.width - thumbW, 1)
            let x = thumbW / 2 + usable * value
            ZStack(alignment: .leading) {
                Canvas { ctx, size in
                    for i in 0...20 {
                        let tx = thumbW / 2 + usable * CGFloat(i) / 20
                        let long = i % 5 == 0
                        var p = Path()
                        p.move(to: CGPoint(x: tx, y: size.height / 2 + 4))
                        p.addLine(to: CGPoint(x: tx, y: size.height / 2 + (long ? 14 : 9)))
                        ctx.stroke(p, with: .color(palette.inkSoft.color), lineWidth: long ? 1.5 : 1)
                    }
                }
                Rectangle().fill(palette.ink.color)
                    .frame(height: 2)
                    .offset(y: 0)
                Rectangle().fill(palette.accent.color)
                    .frame(width: max(x - thumbW / 2, 0), height: 6)
                    .offset(x: thumbW / 2)
                Rectangle()
                    .fill(palette.paper.color)
                    .overlay(Rectangle().strokeBorder(palette.ink.color, lineWidth: 1.6))
                    .overlay(Rectangle().fill(palette.ink.color).frame(width: 1.6, height: 12))
                    .frame(width: thumbW, height: 28)
                    .background(Rectangle().fill(palette.printShadow).offset(x: 2.5, y: 2.5))
                    .offset(x: x - thumbW / 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let v = min(max((drag.location.x - thumbW / 2) / usable, 0), 1)
                        let step = Int((v * 10).rounded())
                        if step != lastStep {
                            lastStep = step
                            Services.haptics.play(.selection)
                        }
                        value = v
                    }
                    .onEnded { _ in
                        lastStep = -1
                        UIFeedback.tap()
                    }
            )
        }
        .frame(height: 40)
    }
}
