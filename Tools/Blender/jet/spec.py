"""Shared blueprint for the twin-engine fighter jet (F-15 proportions), built by several scripts.

Every component script builds to these numbers so the parts meet without gaps. Authoring axes are
the same as every other model here (see common.py): Blender Z-up, +X is the nose, +Z is up, Y is
the span (+Y is the jet's left side). Units are metres at game scale: the real aircraft's
19.43 m length maps to 1.10 m, so SCALE = 1.10 / 19.43 (wingspan about 0.74 m, height about 0.32 m),
close to the 0.90 m paper plane the game already flies.

`x(d)` turns a distance from the nose tip (in model metres) into Blender X. The fuselage
centreline is at Y = 0, Z = 0; the assembler recentres the finished model on its bounding box.
"""

SCALE = 1.10 / 19.43          # real metres -> model metres
LENGTH = 1.10                 # nose tip to nozzle exit
NOSE_X = LENGTH / 2           # Blender X of the nose tip


def x(d):
    """Blender X of a station `d` metres behind the nose tip."""
    return NOSE_X - d


def real(m):
    """Real F-15 metres to model metres."""
    return m * SCALE


# --- Fuselage (component: fuselage.py) ------------------------------------------------------
RADOME_END = 0.20             # d where the radome meets the forward fuselage
CANOPY = dict(start=0.17, end=0.40, height=0.045, width=0.062)  # bubble above the fuselage top
FORWARD_SECTION = dict(width=0.080, top=0.040, bottom=-0.036)    # half-width etc. at d = 0.30
SPINE_END = 0.62              # d where the spine behind the canopy flattens into the engine deck
FUSELAGE_END = 1.05           # d where the nacelles end and the nozzles begin

# --- Intakes (component: engines.py) --------------------------------------------------------
INTAKE = dict(
    start=0.33,               # d of the intake lip (top edge leans forward, the F-15 ramp)
    inner_y=0.045,            # |Y| of the intake's inner wall (touches the fuselage side)
    outer_y=0.115,            # |Y| of the outer wall
    top=0.035, bottom=-0.058, # Z of the box
    ramp_rake=0.035,          # how much further forward the top lip sits than the bottom lip
)

# --- Engines and nozzles (component: engines.py) --------------------------------------------
ENGINES = dict(
    y=0.040,                  # |Y| of each engine centreline
    radius=0.034,             # nacelle radius at the rear
    start=0.55,               # d where the round nacelles emerge from the intake trunks
    nozzle_start=FUSELAGE_END,
    nozzle_end=LENGTH,
    nozzle_radius=0.030,
)

# --- Wing (component: wings.py) ----------------------------------------------------------------
WING = dict(
    root_y=0.100,             # |Y| of the wing root (meets the intake trunk side)
    root_le=0.48, root_te=0.86,   # d of the root leading and trailing edges
    tip_y=0.369,              # half span
    le_sweep_deg=45.0,        # leading-edge sweep
    tip_chord=0.110,          # the raked, cropped tip
    z=0.000, anhedral_deg=-1.0,
    root_thickness=0.014, tip_thickness=0.006,
)

# --- Horizontal stabilators (component: wings.py) ---------------------------------------------
STABILATOR = dict(
    root_y=0.080, root_le=0.93, root_te=1.075,
    tip_y=0.243, le_sweep_deg=50.0, tip_chord=0.055,
    z=-0.004, thickness=0.006,
    dogtooth=0.015,           # notch in the leading edge near the root
)

# --- Twin vertical tails (component: wings.py) ------------------------------------------------
FIN = dict(
    y=0.070,                  # |Y| (on top of each engine nacelle), vertical, not canted
    root_le=0.82, root_te=1.02,
    base_z=0.030,             # Z of the fin root on the nacelle
    height=0.170, le_sweep_deg=36.0, tip_chord=0.052, thickness=0.006,
)

# --- Stores (component: engines.py, optional detail) ------------------------------------------
STORES = dict(
    fuselage_missiles=4,      # semi-recessed along the lower intake corners
    wing_pylons=1,            # per side, with one slim missile each
)

# --- Part names: the game recolours these by name ---------------------------------------------
# "Paper"  - the main airframe skin (follows the selected skin's main colour)
# "Crease" - panel lines, undersides and shaded facets (follows the skin's second colour)
# "Canopy" - the glass, a dark tinted flat colour
# "Metal"  - nozzles, intake throats, missile seeker heads
# "Marking"- roundels, stripes, the few printed details
PARTS = ["Paper", "Crease", "Canopy", "Metal", "Marking"]

# Triangle budgets (the whole jet must stay under 3600)
BUDGET = dict(fuselage=1200, wings=900, engines=1300)
