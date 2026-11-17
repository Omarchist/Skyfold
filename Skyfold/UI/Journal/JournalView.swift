import SwiftUI

/// "Flight log": a pilot's logbook. A summary on the left (or on top), then ruled entries for
/// every blessing and curse, with the traveler's note under each name once it has been logged.
struct JournalView: View {
    let onClose: () -> Void
    @Environment(AppModel.self) private var model
    private let postcardsOn = ExperimentStore.shared.isOn(.postcards)

    var body: some View {
        LibraryPage(kicker: "Pilot's logbook", title: "Flight log", onClose: onClose) {
            LibraryJournalSummary(progress: model.progress)
        } content: {
            VStack(alignment: .leading, spacing: 28) {
                if postcardsOn { PostcardsSection(progress: model.progress) }
                LibraryJournalSection(title: "Blessings", kind: .blessing, progress: model.progress)
                LibraryJournalSection(title: "Curses", kind: .curse, progress: model.progress)
            }
        }
    }
}

// MARK: - Summary

private struct LibraryJournalSummary: View {
    let progress: ProgressStore
    @Environment(\.palette) private var palette

    var body: some View {
        let data = progress.data
        let total = ModifierID.allCases.count
        let logged = progress.discoveredModifierCount
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Logged").signage(11, weight: .bold).foregroundStyle(palette.inkSoft.color)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(logged)")
                        .font(.display(60, weight: .bold))
                        .foregroundStyle(palette.accent.color)
                    Text("of \(total)")
                        .font(.ticket(18, weight: .semibold))
                        .foregroundStyle(palette.ink.color)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Logged \(logged) of \(total)")
            }

            tally

            VStack(spacing: 0) {
                RuleLine(color: palette.ink.color, weight: 2)
                stat("Flights", UIFormat.number(data.runsPlayed))
                stat("Best score", UIFormat.number(data.bestScore))
                stat("Best distance", UIFormat.distance(data.bestDistance))
                stat("Stars", UIFormat.number(data.totalStars))
                stat("Cities visited", "\(data.visitedCities.count) of \(Route.count)")
            }
        }
    }

    /// One printed square per entry: blessings first, then curses. Filled once logged.
    private var tally: some View {
        let columns = [GridItem(.adaptive(minimum: 15, maximum: 15), spacing: 5, alignment: .leading)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 5) {
            ForEach(ModifierID.allCases) { id in
                let done = progress.timesCollected(id) > 0
                let ink = palette.kindInk(id.kind)
                Rectangle()
                    .fill(done ? ink : Color.clear)
                    .overlay(Rectangle().strokeBorder(done ? ink : palette.inkSoft.withAlpha(0.7).color, lineWidth: 1.3))
                    .frame(width: 15, height: 15)
            }
        }
        .accessibilityHidden(true)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label).font(.skyfold(15))
            DottedLeader()
            Text(value).font(.ticket(15, weight: .semibold))
        }
        .padding(.vertical, 9)
        .background(alignment: .bottom) { RuleLine() }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Entries

private struct LibraryJournalSection: View {
    let title: String
    let kind: ModifierKind
    let progress: ProgressStore
    @Environment(\.palette) private var palette

    var body: some View {
        let ids = kind == .blessing ? ModifierID.blessings : ModifierID.curses
        let logged = ids.filter { progress.timesCollected($0) > 0 }.count
        VStack(alignment: .leading, spacing: 0) {
            LibrarySectionHead(title: title, note: "\(logged) of \(ids.count) logged", tint: palette.kindInk(kind))
            ForEach(Array(ids.enumerated()), id: \.element) { offset, id in
                LibraryJournalEntry(id: id, number: offset + 1, count: progress.timesCollected(id))
            }
        }
    }
}

private struct LibraryJournalEntry: View {
    let id: ModifierID
    let number: Int
    let count: Int
    @Environment(\.palette) private var palette

    var body: some View {
        let info = id.info
        let ink = palette.kindInk(info.kind)
        let code = (info.kind == .blessing ? "B-" : "C-") + String(format: "%02d", number)
        HStack(alignment: .top, spacing: 12) {
            Text(code)
                .font(.ticket(11.5, weight: .semibold))
                .foregroundStyle(count > 0 ? ink : palette.inkSoft.color)
                .frame(width: 34, alignment: .leading)
                .padding(.top, 7)
            if count > 0 {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(info.name).font(.display(21)).layoutPriority(1)
                        Spacer(minLength: 4)
                        Text("Logged x\(count)")
                            .font(.ticket(11.5, weight: .semibold))
                            .foregroundStyle(ink)
                            .fixedSize()
                    }
                    Text(info.lore)
                        .font(.display(15, weight: .regular).italic())
                        .foregroundStyle(palette.ink.color.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(info.effect)
                        .font(.skyfold(13.5))
                        .foregroundStyle(palette.inkSoft.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Not logged yet")
                    .font(.display(17, weight: .regular).italic())
                    .foregroundStyle(palette.inkSoft.color)
                    .padding(.top, 3)
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 10)
        .frame(minHeight: 48, alignment: .top)
        .background(alignment: .bottom) { RuleLine() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(count > 0
            ? "\(info.name). \(info.lore) \(info.effect) Logged \(count) times."
            : "Entry \(code). Not logged yet.")
    }
}
