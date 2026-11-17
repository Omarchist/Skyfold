// swift-tools-version: 6.2
import PackageDescription

// Build the same sources used by the app, with the app's Swift language settings.
let package = Package(
    name: "Skyfold",
    platforms: [.iOS(.v18), .macOS(.v15)],
    targets: [
        .target(
            name: "SkyfoldCore",
            path: "Skyfold",
            exclude: [
                "App",
                "Assets.xcassets",
                "Audio/AudioEngine.swift",
                "Audio/Haptics.swift",
                "Game/Backdrop",
                "Game/Engine",
                "Game/FlightView.swift",
                "Game/PlanePreviewView.swift",
                "Game/Render",
                "Resources",
                "UI",
            ],
            sources: ["Core", "Game/Rules", "Audio/Synth.swift"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("DisableOutwardActorInference"),
                .enableUpcomingFeature("InferSendableFromCaptures"),
                .enableUpcomingFeature("GlobalActorIsolatedTypesUsability"),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
        .testTarget(name: "SkyfoldCoreTests", dependencies: ["SkyfoldCore"]),
    ],
    swiftLanguageModes: [.v5]
)
