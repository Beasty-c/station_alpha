"""
Build once, then render the project's views, each in its own light.

    python3 scripts/render_gallery.py [preset] [view ...]

With no views named it renders all of them.  Building the estate takes about
twenty seconds, so sharing one build across the set is far cheaper than
re-running a single-view script per image.
"""
import os, sys, time
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import bpy
from victorian_estate import build as vb
from victorian_estate.core import render as rr

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
preset = sys.argv[1] if len(sys.argv) > 1 else "preview"
wanted = [a.lower() for a in sys.argv[2:]]

t = time.time()
vb.build_all()
print(f"built in {time.time() - t:.1f}s", flush=True)

for view in vb.VIEWS:
    if wanted and view.key not in wanted:
        continue
    for obj in list(bpy.data.objects):
        if obj.type == 'LIGHT':
            bpy.data.objects.remove(obj)
    rr.daylight(elevation=view.elevation, rotation=view.rotation,
                sky_strength=view.sky, sun_energy=view.energy,
                softness=view.softness, warmth=0.35)
    cam = rr.two_point(view.shot)
    rr.configure(preset, exposure=view.exposure)
    path = os.path.join(ROOT, "renders", f"{view.key}.png")
    t0 = time.time()
    rr.render_to(path, cam)
    print(f"  {view.key:<12s} {time.time() - t0:6.1f}s  -> {path}", flush=True)
