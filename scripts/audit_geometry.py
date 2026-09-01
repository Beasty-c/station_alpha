"""
Audit the built model for the geometry faults that show up as render errors.

Checks each mesh for:
  * inverted normals - a closed manifold mesh with negative signed volume
    renders black or inside-out under Cycles
  * non-manifold edges, which make booleans and shadow terminators unreliable
  * degenerate faces (zero area), which produce NaN normals and fireflies
  * loose geometry, i.e. vertices belonging to no face

Prints one line per offending object and a summary; exits non-zero on any
inverted or degenerate geometry.  Non-manifold and loose counts are reported
but tolerated, since applique parts (panels, slating) are legitimately open.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import bpy          # noqa: E402  - bpy must load before bmesh
import bmesh        # noqa: E402
from victorian_estate import build as vb

vb.build_all()

inverted, degenerate, nonmanifold, loose = [], [], [], []
total_v = total_f = 0

for obj in bpy.data.objects:
    if obj.type != 'MESH' or not obj.data.polygons:
        continue
    total_v += len(obj.data.vertices)
    total_f += len(obj.data.polygons)
    bm = bmesh.new()
    bm.from_mesh(obj.data)

    open_edges = sum(1 for e in bm.edges if len(e.link_faces) != 2)
    if open_edges:
        nonmanifold.append((obj.name, open_edges))
    else:
        vol = bm.calc_volume(signed=True)
        if vol < -1e-9:
            inverted.append((obj.name, vol))

    bad = sum(1 for f in bm.faces if f.calc_area() < 1e-12)
    if bad:
        degenerate.append((obj.name, bad))
    stray = sum(1 for v in bm.verts if not v.link_faces)
    if stray:
        loose.append((obj.name, stray))
    bm.free()


def report(label, rows, limit=12):
    print(f"\n{label}: {len(rows)}")
    for name, n in rows[:limit]:
        print(f"    {name:<44s} {n}")
    if len(rows) > limit:
        print(f"    ... and {len(rows) - limit} more")


print(f"\nscene: {total_v} verts, {total_f} faces, "
      f"{sum(1 for o in bpy.data.objects if o.type == 'MESH')} meshes")
report("INVERTED NORMALS (closed mesh, negative volume)", inverted)
report("DEGENERATE FACES (zero area)", degenerate)
report("non-manifold (tolerated for open applique)", nonmanifold)
report("loose vertices", loose)

fatal = len(inverted) + len(degenerate)
print(f"\nfatal issues: {fatal}")
sys.exit(1 if fatal else 0)
