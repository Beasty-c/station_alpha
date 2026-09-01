"""Render a catalogue sheet of every ornament primitive, for eyeballing."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
from victorian_estate.core import meshkit as mk, ornament as orn, materials as mat, render as rr
mat.reset()
col = mk.collection("Catalogue")
lib = mat.library()

items = []
def add(obj, label, mtl=None):
    mk.set_material(obj, mtl or lib.trim)
    items.append((obj, label))

add(orn.turned_post("post.veranda", 2.4, 0.24, 24, "veranda", col), "post")
add(orn.turned_post("post.newel", 2.4, 0.26, 24, "newel", col), "newel")
add(orn.turned_post("post.colonette", 2.4, 0.16, 20, "colonette", col), "colonette")
for s in ("vase", "bobbin", "spindle"):
    add(orn.baluster(f"bal.{s}", 2.0, 0.30, 20, s, col), s)
for s in ("spike", "urn", "ball", "acorn"):
    add(orn.finial(f"fin.{s}", 2.0, 0.34, 22, s, col), s, lib.copper)
for s in ("scroll", "console", "spandrel", "plain"):
    b = orn.bracket(f"br.{s}", 1.1, 1.9, 0.14, s, col=col)
    add(b, s)
add(orn.cresting("crest", 2.2, 1.0, 0.42, 0.05, col), "cresting", lib.iron)
add(orn.spindle_frieze("frieze", 2.0, 1.4, 0.13, 0.30, 14, col), "frieze")
add(orn.panel("panel", 1.3, 1.9, 0.16, 0.13, 0.05, col), "panel")
add(orn.rosette("rosette", 0.8, 0.42, 10, col), "rosette")

# Moulding runs, swept along a short L so the mitre shows.
path = [(-0.9, 0.5, 0), (0.6, 0.5, 0), (0.6, -0.7, 0)]
for label, prof in [
    ("cornice", orn.cornice_profile(0.9, 1.5)),
    ("cyma recta", orn.cyma_recta(0.7, 1.2)),
    ("cyma reversa", orn.cyma_reversa(0.7, 1.2)),
    ("sill", orn.sill_profile(0.8, 0.9)),
    ("water table", orn.water_table(0.7, 1.2)),
    ("casing", orn.casing_profile(1.0, 0.5)),
]:
    o = mk.sweep(f"mld.{label}", prof, path, closed_path=False, col=col)
    add(o, label)
add(orn.dentil_course("dentils", [(-0.9, 0.5, 0.4), (0.6, 0.5, 0.4), (0.6, -0.7, 0.4)],
                      0.16, 0.13, 0.28, 0.30, closed=False, col=col), "dentils")
for label, sty in [("trefoil", "trefoil"), ("sawtooth", "sawtooth"),
                   ("drop", "drop"), ("pendant", "pendant")]:
    o = mk.prism_y(f"barge.{label}",
                   orn.bargeboard_outline(2.2, 0.5, 5, 0.55, sty), -0.06, 0.06, col)
    mk.translate(o, (-1.1, 0, 1.5))
    add(o, label)
for label, poly in [("quatrefoil", orn.quatrefoil(0.85)), ("trefoil.f", orn.trefoil(0.85)),
                    ("cinquefoil", orn.cinquefoil(0.85))]:
    o = mk.prism_y(f"foil.{label}", poly, -0.07, 0.07, col)
    mk.translate(o, (0, 0, 1.0))
    add(o, label)

# Lay out on a grid, each in its own 3.2 m cell.
COLS = 7
PITCH = 3.2
for i, (obj, label) in enumerate(items):
    r, c = divmod(i, COLS)
    mk.translate(obj, (c * PITCH - (COLS - 1) * PITCH / 2, -r * PITCH, 0))
rows = (len(items) + COLS - 1) // COLS
print(f"{len(items)} items in {rows} rows")

ground = mk.box("ground", (0, -(rows - 1) * PITCH / 2, -0.06),
                (COLS * PITCH + 4, rows * PITCH + 4, 0.1), col)
mk.set_material(ground, mat.painted("Sheet.BG", (0.30, 0.29, 0.27), 0.6, 0.1))

rr.studio_world(strength=1.1)
key = rr.sun_lamp(elevation=38, rotation=232, energy=3.0, angle=2.5)
cy = -(rows - 1) * PITCH / 2
cam = rr.make_camera(rr.Shot("Sheet", (0.0, cy - 34.0, 11.5), (0.0, cy + 0.5, 1.15), lens=62))
rr.configure("sheet")
out = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "renders", "ornament_sheet.png")
rr.render_to(out, cam)
print("wrote", out)
