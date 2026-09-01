"""
Check no camera is standing inside something.

Twice now a view has been set up at a plausible-looking coordinate that turned
out to be inside a tree canopy, and the render came back as a wall of leaves.
A camera has no collision, so nothing complains: the only symptom is the
image. This casts a ray forward from each view and reports anything closer
than a sensible near distance, plus how much of the frame it blocks.
"""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import bpy
from mathutils import Vector
from victorian_estate import build as vb

#: A hit closer than this fraction of the distance to the subject counts as
#: foreground, and too much foreground means the view is looking at a thing
#: rather than through it.  An absolute floor stops close-up views (the
#: veranda) from flagging their own subject.
FOREGROUND = 0.20
FLOOR = 2.5
MAX_BLOCKED = 0.35     # fraction of the frame allowed to be foreground
GRID = (9, 7)          # rays across and down the frame

vb.build_all()
deps = bpy.context.evaluated_depsgraph_get()
scene = bpy.context.scene

fails = 0
print(f"{'view':<12s} {'nearest fg':>12s}  {'frame':>7s}  blocked by")
for view in vb.VIEWS:
    eye = Vector(view.shot.location)
    target = Vector(view.shot.target)
    forward = (target - eye).normalized()
    right = forward.cross(Vector((0, 0, 1)))
    if right.length < 1e-6:
        right = Vector((1, 0, 0))
    right.normalize()
    up = right.cross(forward)
    spread = math.atan(view.shot.sensor / (2 * view.shot.lens))

    subject = (target - eye).length
    near = max(FLOOR, FOREGROUND * subject)

    nearest, culprit, blocked, total = 1e9, "", 0, 0
    cols, rows = GRID
    for ix in range(cols):
        for iy in range(rows):
            dx = (ix / (cols - 1)) * 2 - 1
            dy = (iy / (rows - 1)) * 2 - 1
            d = (forward + right * (dx * math.tan(spread))
                 + up * (dy * math.tan(spread) * 0.56)).normalized()
            total += 1
            hit, loc, _, _, obj, _ = scene.ray_cast(deps, eye, d)
            if not hit:
                continue
            dist = (loc - eye).length
            if dist < near:
                blocked += 1
                if dist < nearest:
                    nearest, culprit = dist, obj.name
    frac = blocked / total
    ok = frac <= MAX_BLOCKED
    fails += not ok
    print(f"{view.key:<12s} {nearest if blocked else float('nan'):12.2f}  "
          f"{frac:7.0%}  {culprit if not ok else ''}")

print(f"\nviews with more than {MAX_BLOCKED:.0%} of the frame in foreground: "
      f"{fails}")
sys.exit(1 if fails else 0)
