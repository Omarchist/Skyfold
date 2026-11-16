import SwiftUI

// Buttons for the airmail UI.
//
// The styles play the tap sound on touch-down, so a screen only needs
//   Button { ... } label: { Text("Fly") }.buttonStyle(PrimaryButtonStyle())
// and does not call UIFeedback.tap() itself.

enum PaperButtonSize: Sendable {
    case compact, regular, large
}

/// A solid block in the accent ink (airmail red by day, sodium amber by night) with a hard
/// print shadow. When pressed it slides down onto its shadow, like a stamp.
struct PrimaryButtonStyle: ButtonStyle {
    var size: PaperButtonSize = .regular
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        PaperButtonFace(configuration: configuration, role: .primary, size: size, fullWidth: fullWidth)
    }
}

/// Paper with an ink outline and the same hard shadow.
struct SecondaryButtonStyle: ButtonStyle {
    var size: PaperButtonSize = .regular
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        PaperButtonFace(configuration: configuration, role: .secondary, size: size, fullWidth: fullWidth)
    }
}

/// Underlined text in airmail blue, for quiet actions ("Done", "Not now").
struct LinkButtonStyle: ButtonStyle {
    var size: CGFloat = 15

    func makeBody(configuration: Configuration) -> some View {
        PaperLinkFace(configuration: configuration, size: size)
    }
}

/// For tappable regions that bring their own look: dims while pressed and plays the tap sound.
struct PressableStyle: ButtonStyle {
    var pressedOpacity: Double = 0.55
    var tapSound = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed && tapSound { UIFeedback.tap() }
            }
    }
}

/// A text button in one line: `PaperButton("Fly", size: .large, fullWidth: true) { ... }`.
struct PaperButton: View {
    enum Kind: Sendable { case primary, secondary, link }

    let title: String
    var kind: Kind = .primary
    var size: PaperButtonSize = .regular
    var fullWidth = false
    let action: () -> Void

    init(_ title: String, kind: Kind = .primary, size: PaperButtonSize = .regular,
         fullWidth: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.kind = kind
        self.size = size
        self.fullWidth = fullWidth
        self.action = action
    }

    var body: some View {
        switch kind {
        case .primary:
            Button(action: action) { Text(title) }
                .buttonStyle(PrimaryButtonStyle(size: size, fullWidth: fullWidth))
        case .secondary:
            Button(action: action) { Text(title) }
                .buttonStyle(SecondaryButtonStyle(size: size, fullWidth: fullWidth))
        case .link:
            Button(action: action) { Text(title) }
                .buttonStyle(LinkButtonStyle())
        }
    }
}

// MARK: - Faces

private struct PaperButtonFace: View {
    enum Role { case primary, secondary }

    let configuration: ButtonStyleConfiguration
    let role: Role
    let size: PaperButtonSize
    let fullWidth: Bool
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    private var font: Font {
        switch size {
        case .compact: .skyfold(13, weight: .semibold)
        case .regular: .skyfold(16, weight: .semibold)
        case .large: .display(26, weight: .bold)
        }
    }

    private var padding: EdgeInsets {
        switch size {
        case .compact: EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        case .regular: EdgeInsets(top: 12, leading: 18, bottom: 12, trailing: 18)
        case .large: EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20)
        }
    }

    private var minHeight: CGFloat {
        switch size {
        case .compact: 36
        case .regular: 46
        case .large: 58
        }
    }

    var body: some View {
        let pressed = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        let fill = role == .primary ? palette.accent.color : palette.paper.color
        let text = role == .primary ? palette.accentInk.color : palette.ink.color
        configuration.label
            .font(font)
            .foregroundStyle(text)
            .padding(padding)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: minHeight, alignment: .leading)
            .background(shape.fill(fill))
            .overlay {
                if role == .secondary { shape.strokeBorder(palette.ink.color, lineWidth: 1.5) }
            }
            // The face slides onto the shadow below; the shadow itself stays put.
            .offset(x: pressed ? 3 : 0, y: pressed ? 3 : 0)
            .background { shape.fill(palette.printShadow).offset(x: 3, y: 3) }
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.easeOut(duration: 0.07), value: pressed)
            .onChange(of: pressed) { _, now in
                if now { UIFeedback.tap() }
            }
    }
}

private struct PaperLinkFace: View {
    let configuration: ButtonStyleConfiguration
    let size: CGFloat
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.skyfold(size, weight: .semibold))
            .underline(true, color: palette.secondary.withAlpha(0.6).color)
            .foregroundStyle(palette.secondary.color)
            .opacity(configuration.isPressed ? 0.55 : (isEnabled ? 1 : 0.4))
            .contentShape(Rectangle())
            .onChange(of: configuration.isPressed) { _, now in
                if now { UIFeedback.tap() }
            }
    }
}
