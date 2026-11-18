# Skyfold model assets

Run the asset build with Blender 5.2. A `blender` executable on `PATH` works on Linux, and the script also checks for Blender.app on macOS. Set `BLENDER` to use a specific executable.

```bash
Tools/Blender/build_all.sh
```

The script exports and verifies all 15 USDZ files, renders 512 × 512 previews and a contact sheet, then updates the bundled models and icon. The 1024 × 1024 RGB day icon ships in the app. The night study is in `previews/icon_night.png`.

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

The plane points along +X and the bird faces −X. The bird wing origins sit at the shoulders. The gate faces +Z and each door keeps its pivot at the outer hinge. The triangle cap is 400 per asset and 360 per building variant.
