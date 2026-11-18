"""Twin-engine fighter jet with F-15 proportions. Nose points +X.

Built from the component modules in `Tools/Blender/jet/` (fuselage, wings, engines), which all
follow `jet/spec.py`. Parts: "Paper" (main skin), "Crease" (panel lines and shaded facets),
"Canopy", "Metal", "Marking". Size about 1.10 (X) x 0.32 (Y, up) x 0.74 (Z, span), origin at the
bounding-box centre. A component that does not exist yet is skipped, so the jet can be previewed
while it is being built.
"""
import importlib
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
import common as C  # noqa: E402
from jet import spec  # noqa: E402

COLORS = {
    "Paper": "#9AA5AF",    # air-superiority grey on card stock
    "Crease": "#6F7C88",   # the darker grey of panel lines and shaded facets
    "Canopy": "#24303A",   # tinted glass
    "Metal": "#3C4046",    # nozzles, intake throats, seeker heads
    "Marking": "#C8382A",  # the few printed details
}

C.reset_scene()
parts = {}
for name in ("fuselage", "wings", "engines"):
    try:
        module = importlib.import_module(f"jet.{name}")
    except ModuleNotFoundError as err:
        if err.name != f"jet.{name}":
            raise
        print(f"jet: component {name} not built yet, skipped")
        continue
    for part, builder in module.build().items():
        assert part in spec.PARTS, f"{name}: unknown part {part}"
        parts.setdefault(part, C.MeshBuilder()).merge(builder)

for part, builder in parts.items():
    print(f"jet: {part} {builder.tri_count()} triangles")
    builder.to_object(part, C.flat_material(f"{part}Mat", COLORS[part]))

C.recenter("center")
C.export_usdz("jet", max_tris=3600)  # the other models stay under 400; the jet has its own budget
