"""
Build the whole estate and save it as a .blend, with cameras and lighting
already set up.

    python3 scripts/build_blend.py [output.blend] [detail]

``detail`` is draft | default | full.
"""
import os, sys, time
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import bpy
from victorian_estate import build as vb
from victorian_estate.core import config, render as rr

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "victorian_estate.blend")
level = sys.argv[2] if len(sys.argv) > 2 else "default"
detail = {"draft": config.Detail.draft(), "full": config.Detail.full(),
          "default": config.DETAIL}[level]

t = time.time()
vb.build_all(detail)
print(f"model built in {time.time() - t:.1f}s")

# Save every camera, lit for the three-quarter view; render_gallery.py
# re-lights per shot, but a .blend needs one sun to open with.
hero = vb.VIEWS[1]
rr.daylight(elevation=hero.elevation, rotation=hero.rotation,
            sky_strength=hero.sky, sun_energy=hero.energy,
            softness=hero.softness, warmth=0.35)
for shot in vb.SHOTS:
    rr.two_point(shot)
rr.configure("final", exposure=hero.exposure)
bpy.context.scene.camera = bpy.data.objects[hero.shot.name]

os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(out), compress=True)
size = os.path.getsize(out) / 1e6
print(f"saved {out} ({size:.1f} MB)")
