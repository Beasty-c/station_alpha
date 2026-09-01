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
    "front":  ((1.0, 74.0, 10.0), (1.0, 0.0, 11.0), 55),
    "corner": ((44.0, 52.0, 12.0), (0.0, 0.0, 11.0), 50),
    "swcorner": ((-42.0, 48.0, 12.0), (-3.0, 2.0, 11.0), 50),
    "rear":   ((-34.0, -56.0, 12.0), (-2.0, -6.0, 10.0), 52),
    "west":   ((-58.0, 16.0, 11.0), (-2.0, 2.0, 10.0), 55),
    "high":   ((52.0, 62.0, 40.0), (0.0, 0.0, 11.0), 55),
    "estate": ((96.0, 118.0, 86.0), (-4.0, 6.0, 6.0), 52),
    "approach": ((2.0, 88.0, 6.5), (0.5, 20.0, 12.0), 62),
    "garden": ((-62.0, -18.0, 16.0), (-24.0, 6.0, 10.0), 48),
    "stables": ((-48.0, -54.0, 14.0), (-24.0, -26.0, 6.0), 50),
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
