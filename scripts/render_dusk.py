"""
Render the house at dusk, with the windows and the gas lamps lit.

    python3 scripts/render_dusk.py [preset] [view ...]

Almost the whole point of a house like this is the skyline, and the skyline
only reads against a low sun. Lighting the ground- and first-floor windows
also gives the facade something the daytime views cannot: a reason to look at
the openings rather than the mouldings around them.
"""
import os, sys, time
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import bpy
from victorian_estate import build as vb
from victorian_estate.core import config, render as rr

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
preset = sys.argv[1] if len(sys.argv) > 1 else "preview"
wanted = [a.lower() for a in sys.argv[2:]] or ["southwest", "approach"]

detail = config.Detail()
detail.lit = True
t = time.time()
vb.build_all(detail)
print(f"built in {time.time() - t:.1f}s", flush=True)

for view in vb.VIEWS:
    if view.key not in wanted:
        continue
    for obj in list(bpy.data.objects):
        if obj.type == 'LIGHT':
            bpy.data.objects.remove(obj)
    # A sun just above the horizon, well round to the west, with the sky
    # dropped far enough that the lit windows carry the picture.
    rr.daylight(elevation=2.6, rotation=view.rotation, sky_strength=0.11,
                sun_energy=3.1, softness=1.4, warmth=1.0)
    cam = rr.two_point(view.shot)
    rr.configure(preset, exposure=0.55)
    path = os.path.join(ROOT, "renders", f"dusk_{view.key}.png")
    t0 = time.time()
    rr.render_to(path, cam)
    print(f"  dusk {view.key:<12s} {time.time() - t0:6.1f}s -> {path}",
          flush=True)
