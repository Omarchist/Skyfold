import SwiftUI

/// Pause: a printed form on card stock. Resume, three quick settings, End flight.
struct FlightPauseOverlay: View {
    let session: RunSession
    let landscape: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    @State private var confirmingEnd = false
    @State private var confirmTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            palette.scrim
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}
                .accessibilityHidden(true)

            card
                .frame(maxWidth: landscape ? 680 : 390)
                .padding(.horizontal, 16)
                .padding(.vertical, landscape ? 8 : 16)
                .overlay(alignment: .topTrailing) {
                    // Sits on the paper under the airmail stripe, never across it.
                    FlightStamp(text: "Paused", color: palette.accent.color, tilt: .degrees(5))
                        .padding(.trailing, landscape ? 34 : 32)
                        .padding(.top, (landscape ? 8 : 16) + 22)
                        .allowsHitTesting(false)
                }
        }
        .accessibilityAddTraits(.isModal)
        .onDisappear { confirmTask?.cancel() }
    }

    // MARK: Card

    private var card: some View {
        CardStock(padding: 0, cornerRadius: 4) {
            VStack(spacing: 0) {
                AirmailStripe(stripe: 7)
                    .frame(height: 9)
                Group {
                    if landscape {
                        HStack(alignment: .top, spacing: 22) {
                            lead.frame(maxWidth: .infinity, alignment: .topLeading)
                            Perforation(vertical: true).frame(maxHeight: .infinity)
                            settingsForm.frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            lead
                            Perforation()
                            settingsForm
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)
            }
        }
    }

    private var lead: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Flight \(UIFormat.flightNumber(from: session.leg.fromRoute, to: session.leg.toRoute))")
                .font(.display(landscape ? 26 : 30))
                .foregroundStyle(palette.ink.color)
                .accessibilityAddTraits(.isHeader)
            Text("\(session.origin.code) to \(session.destination.code)  \(FlightFormat.toGo(session.metersToGo)) to go")
                .font(.ticket(13))
                .foregroundStyle(palette.inkSoft.color)
            Text("Score \(UIFormat.number(session.score))  Stars \(session.stars)")
                .font(.ticket(13))
                .foregroundStyle(palette.inkSoft.color)
                .padding(.bottom, landscape ? 8 : 12)

            Button {
                UIFeedback.select()
                session.resume()
            } label: {
                Text("Resume")
            }
            .buttonStyle(FlightPrimaryButtonStyle())
            .padding(.trailing, 3)

            endButton
        }
    }

    @ViewBuilder
    private var endButton: some View {
        if confirmingEnd {
            HStack(spacing: 18) {
                Button {
                    UIFeedback.tap()
                    session.quit()
                } label: {
                    Text("End flight now")
                }
                .buttonStyle(FlightTextButtonStyle(tint: palette.accent.color))
                Button {
                    UIFeedback.tap()
                    confirmTask?.cancel()
                    confirmingEnd = false
                } label: {
                    Text("Keep flying")
                }
                .buttonStyle(FlightTextButtonStyle())
            }
        } else {
            Button {
                UIFeedback.tap()
                confirmingEnd = true
                confirmTask?.cancel()
                confirmTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    confirmingEnd = false
                }
            } label: {
                Text("End flight")
            }
            .buttonStyle(FlightTextButtonStyle(tint: palette.accent.color))
        }
    }

    // MARK: Settings

    private var settingsForm: some View {
        @Bindable var settings = model.settings
        return VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .signage(11, weight: .bold)
                .foregroundStyle(palette.inkSoft.color)
                .padding(.bottom, 4)
            FlightFormRule()
            FlightSliderRow(title: "Music", value: $settings.musicVolume)
            FlightFormRule()
            FlightSliderRow(title: "Effects", value: $settings.effectsVolume, sample: true)
            FlightFormRule()
            FlightCheckRow(title: "Haptics", isOn: $settings.hapticsEnabled)
            FlightFormRule()
        }
    }
}

// MARK: - Form pieces

private struct FlightFormRule: View {
    @Environment(\.palette) private var palette
    var body: some View {
        Rectangle().fill(palette.paperEdge.color).frame(height: 1)
    }
}

/// "Music  ruler-slider  60". Dragging anywhere on the ruler sets the value.
private struct FlightSliderRow: View {
    let title: String
    @Binding var value: Double
    var sample = false
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.skyfold(15))
                .foregroundStyle(palette.ink.color)
                .frame(width: 64, alignment: .leading)
            FlightRuleSlider(value: $value, label: title) {
                if sample { Services.sound.play(.uiTap) }
            }
            Text("\(Int((value * 100).rounded()))")
                .font(.ticket(14, weight: .semibold))
                .foregroundStyle(palette.ink.color)
                .frame(width: 30, alignment: .trailing)
        }
        .frame(minHeight: 46)
    }
}

/// A slider drawn like a ruler: a track with ticks, ink up to the value, and a card tab for a handle.
private struct FlightRuleSlider: View {
    @Binding var value: Double
    let label: String
    var onRelease: () -> Void = {}
    @Environment(\.palette) private var palette
    @State private var lastStep = -1

    var body: some View {
        let ink = palette.ink.color
        let soft = palette.paperEdge.color
        let accent = palette.accent.color
        let paper = palette.paper.color
        let shadow = palette.printShadow
        let v = CGFloat(min(max(value, 0), 1))
        GeometryReader { geo in
            Canvas { ctx, size in
                let handleW: CGFloat = 14
                let x0 = handleW / 2, x1 = size.width - handleW / 2
                let y = size.height / 2
                let x = x0 + (x1 - x0) * v
                for i in 0...10 {
                    let tx = x0 + (x1 - x0) * CGFloat(i) / 10
                    let major = i == 0 || i == 5 || i == 10
                    let h: CGFloat = major ? 9 : 5
                    ctx.fill(Path(CGRect(x: tx - 0.5, y: y + 4, width: 1, height: h)), with: .color(soft))
                }
                ctx.fill(Path(CGRect(x: x0, y: y - 1, width: x1 - x0, height: 2)), with: .color(soft))
                ctx.fill(Path(CGRect(x: x0, y: y - 1.5, width: max(0, x - x0), height: 3)), with: .color(accent))
                let tab = CGRect(x: x - handleW / 2, y: y - 12, width: handleW, height: 22)
                ctx.fill(Path(roundedRect: tab.offsetBy(dx: 2, dy: 2), cornerRadius: 2), with: .color(shadow))
                ctx.fill(Path(roundedRect: tab, cornerRadius: 2), with: .color(paper))
                ctx.stroke(Path(roundedRect: tab, cornerRadius: 2), with: .color(ink), lineWidth: 1.5)
                ctx.fill(Path(CGRect(x: x - 0.75, y: y - 6, width: 1.5, height: 10)), with: .color(ink))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let handleW: CGFloat = 14
                        let t = (drag.location.x - handleW / 2) / max(1, geo.size.width - handleW)
                        let next = Double(min(max(t, 0), 1))
                        value = next
                        let step = Int((next * 10).rounded())
                        if step != lastStep {
                            if lastStep != -1 { Services.haptics.play(.selection) }
                            lastStep = step
                        }
                    }
                    .onEnded { _ in
                        lastStep = -1
                        onRelease()
                    }
            )
        }
        .frame(height: 42)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(1, value + 0.1)
            case .decrement: value = max(0, value - 0.1)
            @unknown default: break
            }
        }
    }
}

/// A printed check box: "Haptics   [X]".
private struct FlightCheckRow: View {
    let title: String
    @Binding var isOn: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        Button {
            isOn.toggle()
            Services.sound.play(.uiTap)
            Services.haptics.play(.selection)
        } label: {
            HStack(spacing: 10) {
                Text(title)
                    .font(.skyfold(15))
                    .foregroundStyle(palette.ink.color)
                    .frame(width: 64, alignment: .leading)
                Text(isOn ? "On" : "Off")
                    .font(.ticket(14, weight: .semibold))
                    .foregroundStyle(isOn ? palette.ink.color : palette.inkSoft.color)
                Spacer(minLength: 0)
                ZStack {
                    Rectangle().stroke(palette.ink.color, lineWidth: 1.5)
                    if isOn {
                        FlightCross().stroke(palette.accent.color, style: StrokeStyle(lineWidth: 2.5, lineCap: .square))
                            .padding(5)
                    }
                }
                .frame(width: 22, height: 22)
                .padding(.trailing, 4)
            }
            .frame(minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }
}

private nonisolated struct FlightCross: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.move(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        return p
    }
}
