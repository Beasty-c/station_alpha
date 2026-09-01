"""Render a row of window variants set into a length of wall, for review."""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
from mathutils import Matrix
from victorian_estate.core import meshkit as mk, materials as mat, render as rr, config
from victorian_estate.mansion import windows as W

mat.reset()
lib = mat.library()
col = mk.collection("Windows")

VARIANTS = [
    ("plain 2/2", W.WindowSpec()),
    ("hood + brackets", W.WindowSpec(hood="cornice", hood_brackets=True)),
    ("pediment", W.WindowSpec(hood="pediment", hood_brackets=True)),
    ("segmental", W.WindowSpec(head="segmental", hood="label",
                               upper_lights=(1, 1))),
    ("round head", W.WindowSpec(head="round", upper_lights=(1, 1),
                                stained=True, hood="label")),
    ("gothic", W.WindowSpec(head="gothic", upper_lights=(1, 1), stained=True)),
    ("shutters", W.WindowSpec(shutters=True, hood="label")),
    ("4/4 + blocks", W.WindowSpec(upper_lights=(2, 2), lower_lights=(2, 2),
                                  corner_blocks=True, hood="cornice")),
    ("sash raised", W.WindowSpec(open_frac=0.32, hood="cornice",
                                 hood_brackets=True)),
    ("tall ground", W.WindowSpec(height=config.WIN_H_1, width=1.28,
                                 upper_lights=(2, 2), hood="cornice",
                                 hood_brackets=True, corner_blocks=True)),
]

PITCH = 3.0
WALL_T = 0.42
xs = [(i - (len(VARIANTS) - 1) / 2) * PITCH for i in range(len(VARIANTS))]

wall_span = len(VARIANTS) * PITCH + 1.0
wall = mk.box("wall", (0.0, -WALL_T / 2, 2.6), (wall_span, WALL_T, 7.0), col)
mk.set_material(wall, lib.body)

for x, (label, spec) in zip(xs, VARIANTS):
    spec.wall_t = WALL_T
    # Punch the opening, then set the joinery into it.
    out = W.opening_outline(spec)
    cut_poly = mk.offset_polygon(out, 0.004)
    cutter = mk.prism_y(f"cut.{label}", cut_poly, -WALL_T - 0.1, 0.1, col)
    mk.transform(cutter, Matrix.Translation((x, 0.0, 1.0)))
    mk.boolean(wall, cutter)
    obj = W.build(f"win.{label}", spec, lib, col)
    W.place(obj, x, 0.0, 1.0)

ground = mk.box("ground", (0, 14, -0.05), (wall_span + 20, 44, 0.1), col)
mk.set_material(ground, lib.lawn)

rr.sky_world(sun_elevation=26, sun_rotation=88, strength=1.0)
rr.sun_lamp(elevation=26, rotation=88, energy=3.2, angle=1.6)
cam = rr.two_point(rr.Shot("Sheet", (0.0, 26.0, 3.4), (0.0, 0.0, 3.0), lens=48))
rr.configure("preview")
out = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "renders", "window_sheet.png")
rr.render_to(out, cam)
print("wrote", out)
