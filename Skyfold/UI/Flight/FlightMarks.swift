import SwiftUI

/// Small paper tags for what is active on this flight: shield and revive charges (blue),
/// then the blessings and curses taken at the gates. Tap a tag to read its name.
///
/// Blessings have a solid outline, curses a dashed one, so the two never depend on color alone.
struct FlightMarks: View {
    let session: RunSession
    @State private var selected: ModifierID?
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        let blessings = UIFormat.tally(session.blessings)
        let curses = UIFormat.tally(session.curses)
        let shields = session.shields
        let revives = session.revives
        VStack(alignment: .leading, spacing: 8) {
            FlightFlowLayout(spacing: 7) {
                if shields > 0 {
                    FlightChargeTag(id: .paperShield, count: shields, isSelected: selected == .paperShield) {
                        toggle(.paperShield)
                    }
                }
                if revives > 0 {
                    FlightChargeTag(id: .secondWind, count: revives, isSelected: selected == .secondWind) {
                        toggle(.secondWind)
                    }
                }
                ForEach(blessings, id: \.id) { entry in
                    FlightMarkTag(id: entry.id, count: entry.count, isSelected: selected == entry.id) {
                        toggle(entry.id)
                    }
                }
                ForEach(curses, id: \.id) { entry in
                    FlightMarkTag(id: entry.id, count: entry.count, isSelected: selected == entry.id) {
                        toggle(entry.id)
                    }
                }
            }
            if let id = selected {
                FlightMarkSlip(id: id, taken: session.modifiers.filter { $0 == id }.count)
                    .transition(.opacity.combined(with: .offset(y: -4)))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.15), value: selected)
        .frame(maxWidth: 420, alignment: .leading)
    }

    private func toggle(_ id: ModifierID) {
        UIFeedback.select()
        hideTask?.cancel()
        if selected == id {
            selected = nil
            return
        }
        selected = id
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            selected = nil
        }
    }
}

// MARK: - Tags

/// A square tag for one blessing or curse.
private struct FlightMarkTag: View {
    let id: ModifierID
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        let info = id.info
        let ink = palette.kindInk(info.kind)
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        let dash: [CGFloat] = info.kind == .curse ? [4, 3] : []
        let tilt = Seeded.tilt("mark." + id.rawValue, min: 0.8, max: 2.2)
        Button(action: action) {
            Glyph(info.symbol, size: 16)
                .foregroundStyle(ink)
                .frame(width: 36, height: 36)
                .background(shape.fill(palette.paper.color))
                .overlay(shape.inset(by: 1).stroke(ink, style: StrokeStyle(lineWidth: 1.5, dash: dash)))
                .overlay(alignment: .bottomTrailing) {
                    if count > 1 {
                        Text("\(count)")
                            .font(.ticket(10, weight: .bold))
                            .foregroundStyle(palette.paper.color)
                            .frame(minWidth: 14, minHeight: 14)
                            .background(ink)
                            .offset(x: 4, y: 4)
                    }
                }
                .printShadow(shape, offset: isSelected ? 1 : 2.5)
                .offset(x: isSelected ? 1.5 : 0, y: isSelected ? 1.5 : 0)
                .rotationEffect(tilt)
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(-4)
        .accessibilityLabel("\(info.name), \(info.kind.rawValue)\(count > 1 ? ", taken \(count) times" : "")")
        .accessibilityHint(info.effect)
    }
}

/// A shield or revive count: an airmail blue tag with the symbol and the number left.
private struct FlightChargeTag: View {
    let id: ModifierID
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        let blue = palette.secondary.color
        let tilt = Seeded.tilt("charge." + id.rawValue, min: 0.6, max: 1.6)
        Button(action: action) {
            HStack(spacing: 5) {
                Glyph(id.info.symbol, size: 15)
                Text("×\(count)")
                    .font(.ticket(15, weight: .bold))
            }
            .foregroundStyle(blue)
            .padding(.horizontal, 9)
            .frame(height: 36)
            .background(shape.fill(palette.paper.color))
            .overlay(shape.inset(by: 1).stroke(blue, lineWidth: 1.5))
            .printShadow(shape, offset: isSelected ? 1 : 2.5)
            .offset(x: isSelected ? 1.5 : 0, y: isSelected ? 1.5 : 0)
            .rotationEffect(tilt)
            .padding(4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(-4)
        .accessibilityLabel(id == .paperShield ? "Paper shields left, \(count)" : "Second winds left, \(count)")
    }
}

/// The note that opens under the tags: kind, name, what it does.
private struct FlightMarkSlip: View {
    let id: ModifierID
    let taken: Int
    @Environment(\.palette) private var palette

    var body: some View {
        let info = id.info
        let ink = palette.kindInk(info.kind)
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(info.kind == .blessing ? "Blessing" : "Curse")
                    .signage(10, weight: .bold)
                    .foregroundStyle(ink)
                if taken > 1 {
                    Text("taken ×\(taken)")
                        .font(.ticket(10, weight: .semibold))
                        .foregroundStyle(palette.inkSoft.color)
                }
            }
            Text(info.name)
                .font(.display(19))
                .foregroundStyle(palette.ink.color)
            Text(info.effect)
                .font(.skyfold(13))
                .foregroundStyle(palette.ink.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: 270, alignment: .leading)
        .background(shape.fill(palette.paper.color))
        .overlay(alignment: .leading) { Rectangle().fill(ink).frame(width: 3).padding(.vertical, 1) }
        .overlay(shape.stroke(palette.flightEdge, lineWidth: 1))
        .printShadow(shape)
        .rotationEffect(Seeded.tilt("slip." + id.rawValue, min: 0.3, max: 0.9))
    }
}
