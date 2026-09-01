"""
Render the four elevations of the house in parallel projection.

    python3 scripts/elevations.py [preset] [side ...]

Perspective hides exactly the faults that matter on a facade: whether the
string courses line through, whether openings sit centred on their bays, and
whether anything is floating clear of the wall. An elevation shows all three
at a glance, which is why architects draw them.
"""
import os, sys, time
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import bpy
from victorian_estate import build as vb
from victorian_estate.core import render as rr

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
preset = sys.argv[1] if len(sys.argv) > 1 else "draft"
wanted = [a.lower() for a in sys.argv[2:]]

SIDES = {
    #        look direction     frame centre        width  near clip plane
    "south": ((0.0, -1.0, 0.0), (2.0, 0.0, 10.5), 38.0, (0.0, 15.5, 0.0)),
    "north": ((0.0, 1.0, 0.0), (-2.0, -8.0, 10.5), 38.0, (0.0, -25.0, 0.0)),
    "east":  ((-1.0, 0.0, 0.0), (0.0, 0.0, 10.5), 38.0, (23.5, 0.0, 0.0)),
    "west":  ((1.0, 0.0, 0.0), (0.0, 0.0, 10.5), 38.0, (-16.0, 0.0, 0.0)),
}

t = time.time()
vb.build_all()
print(f"built in {time.time() - t:.1f}s", flush=True)

# An elevation is a drawing of the house, so the detached buildings come out.
# They also cross the near clip plane on some sides - the conservatory sits
# right in front of the east front - and a solid sliced open by a clip plane
# shows its backfaces, which render as a black slab across the drawing.
for name in ("Outbuildings",):
    hidden = bpy.data.collections.get(name)
    if hidden:
        for obj in hidden.all_objects:
            obj.hide_render = True
        print(f"hidden for elevations: {name} "
              f"({len(hidden.all_objects)} objects)", flush=True)

# Flat, near-frontal light: an elevation is for reading geometry, not mood,
# but a little rake keeps the mouldings from disappearing altogether.
rr.daylight(elevation=42, rotation=150, sky_strength=0.85, sun_energy=3.0,
            softness=2.5, warmth=0.0)
rr.configure(preset, exposure=-0.25)
bpy.context.scene.render.resolution_x = 1500
bpy.context.scene.render.resolution_y = 1100

for side, (direction, centre, scale, near) in SIDES.items():
    if wanted and side not in wanted:
        continue
    cam = rr.orthographic(f"Elev.{side}", centre, direction, scale, near=near)
    path = os.path.join(ROOT, "renders", f"elevation_{side}.png")
    t0 = time.time()
    rr.render_to(path, cam)
    print(f"  {side:<6s} {time.time() - t0:6.1f}s -> {path}", flush=True)
