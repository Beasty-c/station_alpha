"""Close-up of a single window, for checking the joinery reads correctly."""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
from mathutils import Matrix
from victorian_estate.core import meshkit as mk, materials as mat, render as rr, config
from victorian_estate.mansion import windows as W

mat.reset(); lib = mat.library(); col = mk.collection("Closeup")
WALL_T = 0.42
spec = W.WindowSpec(height=config.WIN_H_1, width=1.28, wall_t=WALL_T,
                    upper_lights=(2, 2), lower_lights=(2, 1),
                    hood="cornice", hood_brackets=True, corner_blocks=True,
                    open_frac=0.18, head="segmental")

wall = mk.box("wall", (0.0, -WALL_T / 2, 3.0), (6.0, WALL_T, 8.0), col)
mk.set_material(wall, lib.body)
cutter = mk.prism_y("cut", mk.offset_polygon(W.opening_outline(spec), 0.004),
                    -WALL_T - 0.1, 0.1, col)
mk.transform(cutter, Matrix.Translation((0.0, 0.0, 1.0)))
mk.boolean(wall, cutter)
# A dark room behind, so the glass has something to reflect and hide.
room = mk.box("room", (0.0, -WALL_T - 1.6, 3.0), (5.0, 3.2, 8.0), col)
mk.set_material(room, mat.painted("Room", (0.035, 0.030, 0.028), 0.8, 0.1))
W.place(W.build("win", spec, lib, col), 0.0, 0.0, 1.0)

rr.daylight(elevation=30, rotation=68, sky_strength=0.9, sun_energy=2.4,
            softness=1.2)
cam = rr.two_point(rr.Shot("C", (2.6, 9.2, 2.3), (0.0, 0.0, 2.3), lens=62))
rr.configure("preview", exposure=-0.4)
p = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                 "renders", "window_closeup.png")
rr.render_to(p, cam)
print("wrote", p)
