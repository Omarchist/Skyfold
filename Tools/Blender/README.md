# Skyfold model assets

Run the asset build with Blender 5.2. A `blender` executable on `PATH` works on Linux, and the script also checks for Blender.app on macOS. Set `BLENDER` to use a specific executable.

```bash
Tools/Blender/build_all.sh
```

The script exports and verifies all 16 USDZ files, renders 512 × 512 previews and a contact sheet, then updates the bundled models and icon. The 1024 × 1024 RGB day icon ships in the app. The night study is in `previews/icon_night.png`.

To iterate on a single asset, put the executable on `PATH` and run its model script. You can render extra views into a temporary directory.

```bash
blender --background --factory-startup --python-exit-code 1 \
    --python Tools/Blender/models/gate.py
blender --background --factory-startup --python-exit-code 1 \
    --python Tools/Blender/render_previews.py -- gate --extra-views /tmp/skyfold-gate
blender --background --factory-startup --python-exit-code 1 \
    --python Tools/Blender/verify_usdz.py
```

## RealityKit contract

Blender authors in Z-up. The exporter converts the mesh data to game coordinates with +X forward, +Y up, and +Z toward the side camera. The stage uses meters and has one flat material per mesh. Its parts use identity rotation and scale. Dimensions below are approximate in X × Y × Z order. Grounded models sit at bottom center and flying models use their bounding-box center.

| Asset | Size (m) | Required mesh names |
| --- | --- | --- |
| `plane` | 0.90 × 0.22 × 0.75 | `Paper`, `Crease` |
| `jet` | 1.13 × 0.26 × 0.74 | `Paper`, `Crease`, `Canopy`, `Metal`, `Marking` |
| `bird` | 0.45 long, 0.70 wingspan | `Body`, `WingL`, `WingR`, `Beak` |
| `balloons` | 0.90 × 1.20 × 0.54 | `BalloonA`, `BalloonB`, `BalloonC`, `String` |
| `kite` | 0.80 × 1.00 sail | `Sail`, `Spar`, `Tail` |
| `storm_cloud` | 1.40 × 1.00 × 1.00 | `Cloud`, `Bolt` |
| `thunderhead` | 1.80 × 3.10 × 1.60 | `Cloud`, `Bolt` |
| `tower` | 1.20 × 4.10 × 1.20 | `Wall`, `Window`, `Beacon` |
| `star` | 0.45 × 0.45 × 0.18 | `Star` |
| `cloud_puff` | 2.40 × 1.20 × 1.20 | `Cloud` |
| `building_a` | 2.50 × 8.00 × 2.50 | `Wall`, `Window`, `Roof` |
| `building_b` | 3.50 × 4.50 × 3.00 | `Wall`, `Window`, `Roof` |
| `building_c` | 1.60 × 9.00 × 1.60 | `Wall`, `Window`, `Roof` |
| `building_d` | 5.00 × 2.50 × 3.00 | `Wall`, `Window`, `Roof` |
| `landmark_dome` | 4.00 × 6.00 × 4.00 | `Wall`, `Dome`, `Window` |
| `gate` | 1.80 × 2.60 × 0.30 | `Frame`, `DoorL`, `DoorR`, `Sign`, `Glow` |

The plane points along +X and the bird faces −X. The bird wing origins sit at the shoulders. The gate faces +Z and each door keeps its pivot at the outer hinge. The triangle cap is 400 per asset and 360 per building variant, except the jet, which has its own 3600 cap (it is 2438 now).

The jet is the Interceptor skin's aircraft: a twin-engine fighter with F-15 proportions, nose along +X, 1.13 m long (the game scales it to the paper plane's footprint). `models/jet.py` builds it by importing the components in `jet/` in order: `fuselage.py`, `wings.py` and `engines.py`. Each one builds to the shared numbers in `jet/spec.py` so the pieces meet without gaps, and `jet.py` merges them into five meshes and recentres the result on its bounding box. The game colors `Paper` and `Crease` from the skin and gives `Canopy`, `Metal` and `Marking` fixed colors. A component that is missing is skipped, so the jet can be previewed while one is unfinished.

## Look and icon

Everything is folded or cut paper: balloons are four-sided origami water-bombs, the star is a lucky star, clouds are three cut-card layers with scalloped edges, and buildings are card boxes with punched windows. Default part colors come from the print palette in `common.py` (`INK`); the game recolors parts by name at runtime. `verify_usdz.py` also checks matte materials (roughness 0.9, metallic 0).

`render_icon.py` draws the app icon flat with numpy (no 3D render): cream card, diagonal airmail stripes, one folded dart made of flat facets, and a hard offset shadow with no blur or gradient.
