"""The fighter jet, built from component modules that share `spec.py`.

Each component module (`fuselage`, `wings`, `engines`) exposes `build() -> dict[str, MeshBuilder]`
keyed by the part names in `spec.PARTS`. `models/jet.py` merges the parts and exports `jet.usdz`.
"""
