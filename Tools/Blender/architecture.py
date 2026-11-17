"""Punched card walls shared by the tower and the city models."""
import common as C


def windowed_block(wall, window, width, depth, height, openings, name,
                   *, taper=0.035, peak=0.0, bottom=0.0):
    rnd = C.rng(name)
    sides = ("front", "right", "back", "left")
    faces = wall.block(-width / 2, width / 2, -depth / 2, depth / 2,
                       bottom, height, inset=taper, rnd=rnd, wobble=0.018,
                       floor=True, skip=sides)
    for side in sides:
        cols, rows = openings[side]
        face = faces[side]
        holes = C.window_grid(face, cols, rows, t0=0.16, t1=0.89,
                              gap_t=0.80, rnd=rnd, wobble=0.015, peak=peak)
        wall.punched(face, holes)
        window.backing(face, inset=0.045, margin=0.04)


def folded_roof(width, depth, bottom, top, ridge_y=0.0):
    """A hipped roof made from four card planes meeting at a ridge."""
    x, y = width / 2, depth / 2
    verts = [(-x, -y, bottom), (x, -y, bottom), (x, y, bottom), (-x, y, bottom),
             (-x * 0.64, ridge_y, top), (x * 0.56, ridge_y, top)]
    return C.solid(lambda roof: roof.poly(verts, [
        (0, 3, 2, 1), (0, 1, 5, 4), (1, 2, 5), (2, 3, 4, 5), (3, 0, 4),
    ]))


def export_building(name, wall, window, roof):
    wall.to_object("Wall", C.flat_material("WallMat", C.INK["wall"]), recalc=False)
    window.to_object("Window", C.flat_material("WindowMat", C.INK["ink"]), recalc=False)
    roof.to_object("Roof", C.flat_material("RoofMat", C.INK["roof"]))
    C.recenter("bottom")
    C.export_usdz(name, max_tris=C.BUILDING_TRI_BUDGET)
