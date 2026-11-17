# Working on Skyfold

Skyfold ships for iPhone and uses SwiftUI and RealityKit. Write code, run tests and
export models on Linux. The Mac only runs Xcode and the iOS Simulator. On Linux, run
`swift test` to compile the game rules, core models, and audio synthesis and run the
headless flight test. Use the following command for app-wide syntax checks.

```bash
find Skyfold -name '*.swift' -exec swiftc -frontend -parse -swift-version 5 {} +
```

Run `Tools/build-ios.sh` for a full simulator build on the Mac. To see the app, run
`Tools/screenshots.sh` and read the PNG files it prints. Mac jobs run one at a time,
so reserve them for Apple SDK checks and visual verification. Run
`Tools/Blender/build_all.sh` on Linux. See
[Build and run on the Mac from Linux](README.md#build-and-run-on-the-mac-from-linux)
for setup and the other commands.

Read [ART_DIRECTION.md](ART_DIRECTION.md) before changing a screen or model.
