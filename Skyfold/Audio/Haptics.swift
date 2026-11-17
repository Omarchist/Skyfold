#if os(iOS)
import SwiftUI
import UIKit
#endif

@MainActor
final class Haptics: HapticService {
    static let shared = Haptics()

    var isEnabled = true {
        didSet {
            if isEnabled && !oldValue { prepare() }
        }
    }

    #if os(iOS)
    private weak var window: UIWindow?
    private var feedback: Feedback?

    private struct Feedback {
        let light: UIImpactFeedbackGenerator
        let soft: UIImpactFeedbackGenerator
        let heavy: UIImpactFeedbackGenerator
        let rigid: UIImpactFeedbackGenerator
        let medium: UIImpactFeedbackGenerator
        let notification: UINotificationFeedbackGenerator
        let selection: UISelectionFeedbackGenerator

        init(window: UIWindow) {
            light = UIImpactFeedbackGenerator(style: .light, view: window)
            soft = UIImpactFeedbackGenerator(style: .soft, view: window)
            heavy = UIImpactFeedbackGenerator(style: .heavy, view: window)
            rigid = UIImpactFeedbackGenerator(style: .rigid, view: window)
            medium = UIImpactFeedbackGenerator(style: .medium, view: window)
            notification = UINotificationFeedbackGenerator(view: window)
            selection = UISelectionFeedbackGenerator(view: window)
        }

        var generators: [UIFeedbackGenerator] { [light, soft, heavy, rigid, medium, notification, selection] }
    }

    fileprivate func attach(to window: UIWindow) {
        guard self.window !== window else { return }
        if let previous = self.window, let feedback {
            for generator in feedback.generators { previous.removeInteraction(generator) }
        }
        self.window = window
        feedback = Feedback(window: window)
        prepare()
    }
    #endif

    private init() {}

    func play(_ event: HapticEvent) {
        #if os(iOS)
        guard isEnabled, let feedback else { return }

        func impact(_ generator: UIImpactFeedbackGenerator) {
            generator.impactOccurred()
            generator.prepare()
        }

        func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
            feedback.notification.notificationOccurred(type)
            feedback.notification.prepare()
        }

        switch event {
        case .laneSwitch:
            feedback.light.impactOccurred(intensity: 0.5)
            feedback.light.prepare()
        case .star:
            impact(feedback.soft)
        case .crash:
            impact(feedback.heavy)
            notify(.error)
        case .shield:
            impact(feedback.rigid)
        case .gate:
            impact(feedback.medium)
        case .success:
            notify(.success)
        case .warning:
            notify(.warning)
        case .selection:
            feedback.selection.selectionChanged()
            feedback.selection.prepare()
        }
        #endif
    }

    private func prepare() {
        #if os(iOS)
        guard isEnabled, let feedback else { return }
        for generator in feedback.generators { generator.prepare() }
        #endif
    }
}

#if os(iOS)
/// Binds UIKit feedback to the window so it also works in sheets and full-screen covers.
struct HapticsAnchor: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { WindowObserver(frame: .zero) }

    func updateUIView(_ uiView: UIView, context: Context) {}

    private final class WindowObserver: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { Haptics.shared.attach(to: window) }
        }
    }
}
#endif
