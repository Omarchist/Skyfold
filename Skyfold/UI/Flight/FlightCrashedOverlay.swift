import SwiftUI

/// "Second Wind": the plane is down but a revive is in hand. A paper telegram with the airmail
/// stripe along its top, Revive as the one big key and Give up as plain text. It waits a beat
/// so the crash reads first.
struct FlightCrashedOverlay: View {
    let session: RunSession
    let landscape: Bool
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private var left: String {
        switch session.revives {
        case 0: "No second winds left."
        case 1: "This uses your last second wind."
        default: "You have \(session.revives) second winds. This uses one."
        }
    }

    var body: some View {
        ZStack {
            if shown {
                palette.scrim
                    .opacity(0.8)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    .transition(.opacity)
                    .accessibilityHidden(true)
                // The plane went down in the middle of the picture (portrait) or on the left
                // (landscape), so the slip sits low in portrait, in reach of a thumb, and on the
                // right in landscape. The crash stays in view above or beside it.
                slip
                    .frame(maxWidth: landscape ? 470 : 380)
                    .rotationEffect(.degrees(-1))
                    .padding(.horizontal, 18)
                    .padding(.bottom, landscape ? 0 : 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: landscape ? .trailing : .bottom)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 14)))
                    .accessibilityAddTraits(.isModal)
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) { shown = true }
        }
    }

    private var slip: some View {
        CardStock(padding: 0, cornerRadius: 3) {
            VStack(alignment: .leading, spacing: 0) {
                AirmailStripe(stripe: 8)
                    .frame(height: 11)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        Text("Final call")
                            .signage(11, weight: .bold)
                            .foregroundStyle(palette.accent.color)
                        Spacer()
                        Text(UIFormat.number(session.score))
                            .font(.ticket(13, weight: .semibold))
                            .foregroundStyle(palette.inkSoft.color)
                    }
                    Text("Second Wind")
                        .font(.display(landscape ? 32 : 38))
                        .foregroundStyle(palette.ink.color)
                        .accessibilityAddTraits(.isHeader)
                    Text("Went down hard. Smooth the creases out and keep flying?")
                        .font(.display(16, weight: .regular).italic())
                        .foregroundStyle(palette.ink.color)
                        .fixedSize(horizontal: false, vertical: true)
                    Perforation().padding(.vertical, 4)
                    Button {
                        UIFeedback.select()
                        session.revive()
                    } label: {
                        Text("Revive")
                    }
                    .buttonStyle(FlightPrimaryButtonStyle())
                    .padding(.trailing, 3)
                    Text(left)
                        .font(.ticket(12))
                        .foregroundStyle(palette.inkSoft.color)
                    Button {
                        UIFeedback.tap()
                        session.declineRevive()
                    } label: {
                        Text("Give up")
                    }
                    .buttonStyle(FlightTextButtonStyle())
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 8)
            }
        }
    }
}
