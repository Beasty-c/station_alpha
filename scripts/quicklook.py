"""Fast diagnostic render of whatever the build currently produces.

Usage:  python3 scripts/quicklook.py [preset] [view]
        view = front | corner | rear | west | top
"""
import math, os, sys, time
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
from victorian_estate.core import config, meshkit as mk, materials as mat, render as rr
from victorian_estate import build as vb

preset = sys.argv[1] if len(sys.argv) > 1 else "draft"
view = sys.argv[2] if len(sys.argv) > 2 else "corner"

t = time.time()
scene = vb.build_all()
print(f"built in {time.time() - t:.1f}s")

VIEWS = {
    "front":  ((0.0, 52.0, 9.0), (0.0, 0.0, 8.0), 55),
    "corner": ((34.0, 40.0, 11.0), (0.0, 0.0, 8.5), 50),
    "rear":   ((-26.0, -46.0, 11.0), (-2.0, -6.0, 8.0), 52),
    "west":   ((-46.0, 14.0, 10.0), (0.0, 2.0, 8.0), 55),
    "high":   ((44.0, 54.0, 34.0), (0.0, 0.0, 9.0), 55),
}
loc, tgt, lens = VIEWS[view]
rr.daylight(elevation=27, rotation=118, sky_strength=1.0, sun_energy=2.6,
            softness=1.1, warmth=0.35)
cam = rr.two_point(rr.Shot(view, loc, tgt, lens=lens))
rr.configure(preset, exposure=-0.35)
out = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "renders", f"quicklook_{view}.png")
rr.render_to(out, cam)
print("wrote", out)
