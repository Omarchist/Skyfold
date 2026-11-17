import SwiftUI

@main
struct SkyfoldApp: App {
    @State private var model: AppModel

    init() {
        let audio = AudioEngine.shared
        Services.sound = audio
        Services.haptics = Haptics.shared

        let model = AppModel()
        _model = State(initialValue: model)
        model.settings.applyToServices()
        audio.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                #if os(iOS)
                .background {
                    HapticsAnchor()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                #endif
        }
    }
}
