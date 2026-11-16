import SwiftUI

@main
struct SkyfoldApp: App {
    @State private var model = AppModel()

    init() {
        // Real audio/haptics services are installed here once they exist (see Core/Services.swift).
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onAppear { model.settings.applyToServices() }
        }
    }
}
