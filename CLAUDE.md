# Working on Skyfold

Skyfold ships for iPhone and uses SwiftUI and RealityKit. On Linux, run `swift test`
to compile the game rules, core models, and audio synthesis and run the headless
flight test. Use the following command for app-wide syntax checks.

```bash
find Skyfold -name '*.swift' -exec swiftc -frontend -parse -swift-version 5 {} +
```

Run `Tools/build-ios.sh` for a full simulator build when the Mac is
configured. Reserve Xcode builds for Apple SDK checks and integrated verification.
See [Develop on Linux](README.md#develop-on-linux) for SSH setup.

Read [ART_DIRECTION.md](ART_DIRECTION.md) before changing a screen or model.
