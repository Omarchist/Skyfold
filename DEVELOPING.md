# Developing Skyfold

Notes for working on the code. For what the game is and how it plays, see [README.md](README.md).

- **iPhone**, portrait and landscape · iOS 18+ · SwiftUI + RealityKit
- **3D world, 2D rules**: gameplay is plain 2D math (forward distance × altitude lane);
  RealityKit just draws that state with low-poly models each frame.
- macOS is planned: Core and Game avoid UIKit except behind `#if os(iOS)`.
- Look and feel: airmail and travel paper, a pop-up-book world. See
  [ART_DIRECTION.md](ART_DIRECTION.md) before adding any screen or model.

## Open & run

1. Open `Skyfold.xcodeproj` in Xcode 27 or later.
2. Pick an iPhone simulator and press Run.
3. To run on your own iPhone, choose your team under *Signing & Capabilities* and change the
   bundle identifier (`com.henry.skyfold`) if needed.

## Develop on Linux

Use Swift 6.2 or later and run the following commands from the repo root.
[Install Swift on Linux](https://www.swift.org/install/linux/)

```bash
swift build
swift test
find Skyfold -name '*.swift' -exec swiftc -frontend -parse -swift-version 5 {} +
```

The Swift package compiles the same core models, flight rules, and audio synthesis that
ship in the app. The test flies a seeded leg with the autopilot. The last command checks
Swift syntax across the app. Xcode is required to typecheck SwiftUI, RealityKit and other
iOS APIs and to produce the iPhone app.

### Build and run on the Mac from Linux

Write code, run tests and export models on Linux. The Mac only runs Xcode and the iOS
Simulator. On the Mac, open Xcode 27 or later once and install its iOS platform support.
Select that Xcode under *Xcode → Settings → Locations → Command Line Tools*. Enable
Remote Login for your macOS user. On Linux, use the address shown in Sharing.
[Set up Remote Login](https://support.apple.com/guide/mac-help/allow-a-remote-computer-to-access-your-mac-mchlp1066/mac)

```bash
ssh-copy-id user@mac-host
git config --local skyfold.mac user@mac-host
```

Run these commands on Linux. Each one does its Xcode and Simulator work on the Mac.

| Command | Effect |
|---|---|
| `Tools/build-ios.sh` | Build the unsigned simulator app and print its path on the Mac |
| `Tools/run-sim.sh [launch args]` | Build, boot an iPhone simulator, open its window and launch Skyfold |
| `Tools/screenshots.sh <name> <orientation> <count> <seconds> [launch args]` | Build, launch and copy timed screenshots to `Screenshots/` |
| `Tools/stop-sim.sh` | Shut down the Mac's simulators to free memory |

The scripts use SSH, rsync and flock. They send your current app sources and Xcode
project, including uncommitted edits and new files. Jobs from this Linux machine to one
Mac run one at a time, so many agents can share it. Each checkout keeps an incremental
build cache of about 150 MB per orientation under `~/.cache/skyfold-builds/` on the Mac.
Delete folders there for checkouts you no longer use. Set `SKYFOLD_MAC` to use a
different address or SSH alias.

The simulator stays booted between runs. A cold boot takes about two minutes on an 8 GB
Mac, and later runs take seconds. Xcode 27 shows the simulator in DeviceHub. The same
commands work in a Mac checkout without SSH. For a physical iPhone, use the signing and
run steps above.

### Debug launch arguments

Add them in *Product › Scheme › Edit Scheme › Run › Arguments*, or pass them to `simctl launch`:

| Argument | Effect |
|---|---|
| `-SkyfoldAutopilot YES` | The plane flies itself (always picks a safe lane) |
| `-SkyfoldShortLegs YES` | Legs are ~15% length, so you reach airports fast |
| `-SkyfoldAutostart YES` | Skip the menu and start a run |
| `-SkyfoldUnlockAll YES` | Unlock every skin, difficulty and airport (Debug builds) |
| `-SkyfoldAutoGates YES` | Airports advance on their own: arrival, open a gate, board |
| `-SkyfoldTimeOfDay day` | Force the time-of-day setting: `cycle`, `clock`, `day` or `night` |
| `-SkyfoldScreen journal` | Open a menu screen on launch: `journal`, `hangar`, `atlas`, `settings` |
| `-SkyfoldMenuPicker skin` | Open a menu picker on launch: `airport`, `difficulty`, `skin` (Debug builds) |
| `-SkyfoldProgress mid` | Replace saved progress on launch: `fresh`, `mid` or `all` (Debug builds) |
| `-SkyfoldStartAirport 5` | Start a run from route city 0, 3, 5 or 8; needs `-SkyfoldUnlockAll YES` (Debug builds) |
| `-SkyfoldFlightScript crash` | About 6 s into the first leg: `pause`, `crash`, `shield`, `gameover` or `newbest`; needs `-SkyfoldAutostart YES -SkyfoldAutopilot YES` (Debug builds) |
| `-SkyfoldExperiments postcards` | Switch experimental features on at launch: a comma list of `postcards`, `nearMissBonus`, `windGusts`, `ghostFlight`, `dailyRoute`, or `all` / `none` |
| `-SkyfoldSkin interceptor` | Select a skin on launch (Debug builds) |
| `-SkyfoldShowFPS YES` | Show the frame-rate readout (Debug builds) |
| `-SkyfoldDayCycleSeconds 20` | Run the day-night cycle this fast, to test the transitions (Debug builds) |
| `-SkyfoldPlaneDemo stunt` | Repeat a scripted `stunt` or `drag` on the menu plane (Debug builds) |

The Interceptor skin (the fighter jet from `Tools/Blender/jet/`) is for developers only: Debug
builds list and unlock it, Release builds (TestFlight and the App Store) leave it out. See
`PlaneSkin.developerOnly` in `Skyfold/Core/Content.swift`.

`Tools/run-sim.sh` and `Tools/screenshots.sh` pass any of these switches to the app. The
screenshot script saves a timed portrait or landscape series to `Screenshots/` and prints
each path.

```bash
Tools/screenshots.sh flight landscape 5 3 -SkyfoldAutostart YES -SkyfoldAutopilot YES
```

## Experimental features

The `experimental` branch adds trial features. Each one has its own switch under
*Settings › Experiments* (see `Skyfold/Core/Experiments.swift`) and is off by default, so the
game can be compared with and without it.

## Project layout

```
Skyfold/
  App/          @main app entry; installs audio/haptics services
  Core/         Shared models and rules data, no rendering
    World.swift        lane metrics + coordinate contract (+X forward, +Y altitude)
    RunSession.swift   the run state machine shared by engine, renderer and UI
    Content.swift      cities/route, difficulties, plane skins, leg planning
    Modifiers.swift    curses & blessings, RunTuning, gate offers
    Theme.swift        day → dusk → night palettes (warm day, eerie night)
    Settings.swift     persisted settings + loadout
    Progress.swift     unlocks, journal, stats (persisted)
    Services.swift     sound/haptics protocols (silent defaults)
  Game/         2D rules (spawner, collisions, autopilot) + RealityKit renderer
  UI/           SwiftUI: menu, HUD, airport gates, journal, settings, hangar, atlas
  Audio/        Procedural synth (no audio files) + haptics
  Resources/Models/  low-poly .usdz generated by Tools/Blender
Tools/
  Blender/      bpy scripts that generate every model (+ previews, app icon)
  lib/          shared helpers for the Xcode and Simulator scripts
  build-ios.sh, run-sim.sh, screenshots.sh, stop-sim.sh
                Xcode and Simulator jobs, run from Linux or the Mac
  typecheck.sh  Mac only: typecheck Core + one module with the target's Swift flags
```

The Xcode project uses folder-synchronized groups, so new files in `Skyfold/` join the
app target automatically.

## Regenerating the 3D models

```bash
Tools/Blender/build_all.sh
```

Requires Blender 5.2 or later as `blender` on `PATH`, or at `/Applications/Blender.app`
on a Mac. Run it on Linux to keep the Mac free. Each model is a script in
`Tools/Blender/models/`; tweak and rerun. See `Tools/Blender/README.md` for the part names
the game recolors at runtime.

## How a run flows

`countdown → flying → landing → airport (arrival card → choose gate → board) → countdown …`
A hit with no shield either offers a revive (Second Wind) or ends the run. Landing in a
city for the first time unlocks things: skins (Marrakesh, Cairo, Mumbai, Kyoto, Honolulu,
New York, full lap), difficulties (Cairo → Gale, Sydney → Tempest, New York → Paper Cut),
and departure airports (Istanbul, Kyoto, Rio).
