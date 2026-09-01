"""
Low level mesh construction helpers.

Victorian architecture is almost entirely made of two operations repeated at
every scale: a profile revolved about an axis (turned posts, balusters, urns,
finials, colonettes) and a profile swept along a path (cornices, string
courses, handrails, architraves, bargeboards).  Everything in this project is
built from :func:`lathe` and :func:`sweep` plus a handful of prism helpers, so
those two functions are worth doing properly - in particular ``sweep`` mitres
its corners, which is what stops cornices from tearing open where they turn.
"""

from __future__ import annotations

import math
from typing import Sequence

import bmesh
import bpy
from mathutils import Matrix, Vector

Vec2 = Sequence[float]
Vec3 = Sequence[float]

TAU = math.tau


# ---------------------------------------------------------------------------
# Object / collection plumbing
# ---------------------------------------------------------------------------

def collection(name: str, parent: bpy.types.Collection | None = None
               ) -> bpy.types.Collection:
    """Fetch or create a collection, linked under ``parent`` (scene root)."""
    col = bpy.data.collections.get(name)
    if col is None:
        col = bpy.data.collections.new(name)
    target = parent or bpy.context.scene.collection
    if col.name not in target.children:
        target.children.link(col)
    return col


def link(obj: bpy.types.Object, col: bpy.types.Collection | None) -> bpy.types.Object:
    """Link ``obj`` into exactly one collection."""
    for existing in list(obj.users_collection):
        existing.objects.unlink(obj)
    (col or bpy.context.scene.collection).objects.link(obj)
    return obj


def new_object(name: str, mesh: bpy.types.Mesh,
               col: bpy.types.Collection | None = None) -> bpy.types.Object:
    obj = bpy.data.objects.new(name, mesh)
    return link(obj, col)


def mesh_from(name: str, verts: Sequence[Vec3], faces: Sequence[Sequence[int]],
              edges: Sequence[Sequence[int]] = ()) -> bpy.types.Mesh:
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [tuple(e) for e in edges],
                   [tuple(f) for f in faces])
    me.validate(verbose=False)
    me.update()
    return me


def obj_from(name: str, verts, faces, edges=(), col=None) -> bpy.types.Object:
    return new_object(name, mesh_from(name, verts, faces, edges), col)


def instance(source: bpy.types.Object, name: str,
             location: Vec3 = (0, 0, 0),
             rotation: Vec3 = (0, 0, 0),
             scale: Vec3 = (1, 1, 1),
             col: bpy.types.Collection | None = None) -> bpy.types.Object:
    """A linked duplicate: new object, *shared* mesh data.

    Cycles turns these into real instances, so a thousand balusters cost one
    baluster's worth of memory.
    """
    obj = bpy.data.objects.new(name, source.data)
    obj.location = location
    obj.rotation_euler = rotation
    obj.scale = scale
    return link(obj, col)


def join(objects: Sequence[bpy.types.Object], name: str,
         col: bpy.types.Collection | None = None) -> bpy.types.Object:
    """Merge meshes into a single object (materials are remapped)."""
    objects = [o for o in objects if o and o.type == 'MESH']
    if not objects:
        return obj_from(name, [], [], col=col)
    if len(objects) == 1:
        objects[0].name = name
        return objects[0]

    # matrix_world is only recomputed when the depsgraph evaluates, so an
    # object placed a moment ago still reports the identity.  matrix_basis is
    # composed from loc/rot/scale on read and is always current; fall back to
    # a real update only if something is parented.
    if any(o.parent is not None for o in objects):
        bpy.context.view_layer.update()

    bm = bmesh.new()
    out_mats: list[bpy.types.Material] = []
    index = {}
    for obj in objects:
        tmp = bmesh.new()
        tmp.from_mesh(obj.data)
        tmp.transform(obj.matrix_world if obj.parent else obj.matrix_basis)
        remap = {}
        for i, mat in enumerate(obj.data.materials):
            if mat not in index:
                index[mat] = len(out_mats)
                out_mats.append(mat)
            remap[i] = index[mat]
        for f in tmp.faces:
            f.material_index = remap.get(f.material_index, 0)
        me = bpy.data.meshes.new("_tmp_join")
        tmp.to_mesh(me)
        tmp.free()
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)

    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for mat in out_mats:
        me.materials.append(mat)
    result = new_object(name, me, col)
    for obj in objects:
        data = obj.data
        bpy.data.objects.remove(obj)
        if data.users == 0:
            bpy.data.meshes.remove(data)
    return result


# ---------------------------------------------------------------------------
# Prisms and boxes
# ---------------------------------------------------------------------------

def box(name: str, center: Vec3, size: Vec3,
        col: bpy.types.Collection | None = None) -> bpy.types.Object:
    """An axis-aligned box given by centre and full size."""
    cx, cy, cz = center
    hx, hy, hz = size[0] / 2.0, size[1] / 2.0, size[2] / 2.0
    v = [(cx - hx, cy - hy, cz - hz), (cx + hx, cy - hy, cz - hz),
         (cx + hx, cy + hy, cz - hz), (cx - hx, cy + hy, cz - hz),
         (cx - hx, cy - hy, cz + hz), (cx + hx, cy - hy, cz + hz),
         (cx + hx, cy + hy, cz + hz), (cx - hx, cy + hy, cz + hz)]
    f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4),
         (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return obj_from(name, v, f, col=col)


def box_between(name: str, p0: Vec3, p1: Vec3,
                col: bpy.types.Collection | None = None) -> bpy.types.Object:
    """A box spanning two opposite corners."""
    c = [(a + b) / 2.0 for a, b in zip(p0, p1)]
    s = [abs(b - a) for a, b in zip(p0, p1)]
    return box(name, c, s, col)


def polygon_area(poly: Sequence[Vec2]) -> float:
    """Signed area; positive for a counter-clockwise winding."""
    n = len(poly)
    return sum(poly[i][0] * poly[(i + 1) % n][1]
               - poly[(i + 1) % n][0] * poly[i][1] for i in range(n)) / 2.0


def clean_polygon(poly: Sequence[Vec2], eps: float = 1e-7
                  ) -> list[tuple[float, float]]:
    """Drop consecutive duplicate and exactly collinear vertices.

    Repeating outlines - bargeboard teeth, cresting pickets, bracket scrolls -
    naturally end one motif where the next begins, and the doubled vertex
    extrudes to a zero-area side face.  Those faces have no valid normal, so
    they show up as black slivers and shading artefacts.
    """
    pts = [(float(x), float(y)) for x, y in poly]
    out: list[tuple[float, float]] = []
    for p in pts:
        if not out or math.dist(p, out[-1]) > eps:
            out.append(p)
    while len(out) > 1 and math.dist(out[0], out[-1]) <= eps:
        out.pop()
    if len(out) < 3:
        return out

    keep: list[tuple[float, float]] = []
    n = len(out)
    for i in range(n):
        a, b, c = out[(i - 1) % n], out[i], out[(i + 1) % n]
        cross = ((b[0] - a[0]) * (c[1] - a[1])
                 - (b[1] - a[1]) * (c[0] - a[0]))
        scale = max(math.dist(a, b) * math.dist(b, c), eps)
        if abs(cross) > eps * scale:
            keep.append(b)
    return keep if len(keep) >= 3 else out


def as_ccw(poly: Sequence[Vec2]) -> list[tuple[float, float]]:
    """Return the polygon cleaned and wound counter-clockwise.

    The extrusion helpers below wind their side faces on that assumption, and
    a clockwise outline - which is exactly what the window and door code hands
    round, since a casing sweep needs the opposite winding - would otherwise
    extrude to a solid with every normal inverted.  An inside-out cutter makes
    a boolean silently do nothing, so it is worth normalising here rather than
    at each call site.
    """
    pts = clean_polygon(poly)
    return pts if polygon_area(pts) >= 0.0 else pts[::-1]


def prism(name: str, poly: Sequence[Vec2], z0: float, z1: float,
          col: bpy.types.Collection | None = None) -> bpy.types.Object:
    """Extrude a closed 2D polygon between two Z heights."""
    poly = as_ccw(poly)
    z0, z1 = min(z0, z1), max(z0, z1)
    n = len(poly)
    verts = [(x, y, z0) for x, y in poly] + [(x, y, z1) for x, y in poly]
    faces = [tuple(range(n - 1, -1, -1)), tuple(range(n, 2 * n))]
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, j + n, i + n))
    return obj_from(name, verts, faces, col=col)


def prism_x(name: str, poly: Sequence[Vec2], x0: float, x1: float,
            col: bpy.types.Collection | None = None) -> bpy.types.Object:
    """Extrude a (y, z) polygon along X - useful for gables and mouldings."""
    poly = as_ccw(poly)
    x0, x1 = min(x0, x1), max(x0, x1)
    n = len(poly)
    verts = [(x0, y, z) for y, z in poly] + [(x1, y, z) for y, z in poly]
    faces = [tuple(range(n - 1, -1, -1)), tuple(range(n, 2 * n))]
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, j + n, i + n))
    return obj_from(name, verts, faces, col=col)


def prism_y(name: str, poly: Sequence[Vec2], y0: float, y1: float,
            col: bpy.types.Collection | None = None) -> bpy.types.Object:
    """Extrude an (x, z) polygon along Y."""
    poly = as_ccw(poly)
    y0, y1 = min(y0, y1), max(y0, y1)
    n = len(poly)
    verts = [(x, y0, z) for x, z in poly] + [(x, y1, z) for x, z in poly]
    faces = [tuple(range(n)), tuple(range(2 * n - 1, n - 1, -1))]
    for i in range(n):
        j = (i + 1) % n
        faces.append((j, i, i + n, j + n))
    return obj_from(name, verts, faces, col=col)


# ---------------------------------------------------------------------------
# Lathe - revolve a (radius, height) profile about the Z axis
# ---------------------------------------------------------------------------

def lathe(name: str, profile: Sequence[Vec2], segments: int = 20,
          arc: float = TAU, start: float = 0.0, cap: bool = True,
          center: Vec3 = (0, 0, 0),
          col: bpy.types.Collection | None = None) -> bpy.types.Object:
    """Revolve ``profile`` - a list of ``(radius, z)`` pairs - about +Z.

    The profile runs bottom to top.  Radii of exactly zero are collapsed to a
    single pole vertex so that finials and spire tips close cleanly instead of
    leaving a ring of coincident points.
    """
    prof = [(max(0.0, float(r)), float(z)) for r, z in profile]
    # Two consecutive points on the axis describe nothing: the quad between
    # them collapses to an edge, so no face references the second one and it
    # is left as a loose vertex.  Keep only the last of each such run.
    collapsed: list[tuple[float, float]] = []
    for point in prof:
        if collapsed and point[0] < 1e-9 and collapsed[-1][0] < 1e-9:
            collapsed[-1] = point
        else:
            collapsed.append(point)
    prof = collapsed
    if len(prof) < 2:
        raise ValueError(f"lathe({name}): profile needs >= 2 points")

    closed = abs(arc - TAU) < 1e-6
    rings = segments if closed else segments + 1
    cx, cy, cz = center

    verts: list[tuple[float, float, float]] = []
    ring_idx: list[list[int]] = []          # index per profile point per ring
    pole: dict[int, int] = {}               # profile point -> single vertex

    for pi, (r, z) in enumerate(prof):
        if r < 1e-9:
            pole[pi] = len(verts)
            verts.append((cx, cy, cz + z))

    for s in range(rings):
        a = start + arc * (s / segments)
        ca, sa = math.cos(a), math.sin(a)
        row = []
        for pi, (r, z) in enumerate(prof):
            if pi in pole:
                row.append(pole[pi])
            else:
                row.append(len(verts))
                verts.append((cx + r * ca, cy + r * sa, cz + z))
        ring_idx.append(row)

    faces: list[tuple[int, ...]] = []
    for s in range(rings if closed else rings - 1):
        a_row = ring_idx[s]
        b_row = ring_idx[(s + 1) % rings]
        for pi in range(len(prof) - 1):
            # wound so the normal points away from the axis
            quad = [a_row[pi], b_row[pi], b_row[pi + 1], a_row[pi + 1]]
            uniq = []
            for v in quad:
                if v not in uniq:
                    uniq.append(v)
            if len(uniq) >= 3:
                faces.append(tuple(uniq))

    if cap and closed:
        if prof[0][0] > 1e-9:
            faces.append(tuple(ring_idx[s][0] for s in range(rings - 1, -1, -1)))
        if prof[-1][0] > 1e-9:
            last = len(prof) - 1
            faces.append(tuple(ring_idx[s][last] for s in range(rings)))

    return obj_from(name, verts, faces, col=col)


def disc(name: str, center: Vec3, radius: float, segments: int = 32,
         up: bool = True, col: bpy.types.Collection | None = None
         ) -> bpy.types.Object:
    """A flat circular face.

    Worth having as its own primitive: revolving a horizontal profile such as
    [(0, 0), (r, 0)] describes a disc with no thickness, and the revolve's own
    fan plus the end cap then land on each other and z-fight to black.
    """
    cx, cy, cz = center
    verts = [(cx, cy, cz)]
    for i in range(segments):
        a = TAU * i / segments
        verts.append((cx + radius * math.cos(a), cy + radius * math.sin(a), cz))
    faces = []
    for i in range(segments):
        j = (i + 1) % segments
        faces.append((0, 1 + i, 1 + j) if up else (0, 1 + j, 1 + i))
    return obj_from(name, verts, faces, col=col)


# ---------------------------------------------------------------------------
# Sweep - carry a cross-section along a path, mitring the corners
# ---------------------------------------------------------------------------

def _mitre_frames(path: Sequence[Vector], closed: bool, up: Vector):
    """Per-point (right, up, mitre-scale) frames for a sweep.

    ``right`` at a corner is the bisector of the two adjacent edge normals and
    ``scale`` stretches the section across that bisector, which is exactly what
    a mitre joint does: the profile widens through the turn so both runs meet
    edge to edge.
    """
    n = len(path)
    frames = []
    for i in range(n):
        if closed:
            prev_p, next_p = path[(i - 1) % n], path[(i + 1) % n]
        else:
            prev_p = path[i - 1] if i > 0 else path[i]
            next_p = path[i + 1] if i < n - 1 else path[i]

        d_in = (path[i] - prev_p)
        d_out = (next_p - path[i])
        if d_in.length < 1e-9:
            d_in = d_out.copy()
        if d_out.length < 1e-9:
            d_out = d_in.copy()
        d_in.normalize()
        d_out.normalize()

        n_in = d_in.cross(up)
        n_out = d_out.cross(up)
        if n_in.length < 1e-9:
            n_in = Vector((1, 0, 0))
        if n_out.length < 1e-9:
            n_out = n_in.copy()
        n_in.normalize()
        n_out.normalize()

        bis = (n_in + n_out)
        if bis.length < 1e-9:              # a 180 degree reversal; give up
            bis = n_out.copy()
        bis.normalize()
        denom = bis.dot(n_out)
        scale = 1.0 / denom if abs(denom) > 0.2 else 1.0   # clamp sharp spikes
        frames.append((bis, up, scale))
    return frames


def sweep(name: str, profile: Sequence[Vec2], path: Sequence[Vec3],
          closed_path: bool = False, up: Vec3 = (0, 0, 1),
          closed_profile: bool = True, cap: bool = True,
          flip: bool = False,
          col: bpy.types.Collection | None = None) -> bpy.types.Object:
    """Sweep a cross-section along a polyline.

    ``profile`` is a list of ``(u, v)`` where *u* runs along the path's outward
    horizontal normal and *v* along ``up``.  A positive *u* therefore projects
    the moulding away from the wall it runs along.
    """
    pts = [Vector(p) for p in path]
    if len(pts) < 2:
        raise ValueError(f"sweep({name}): path needs >= 2 points")
    upv = Vector(up).normalized()
    sign = -1.0 if flip else 1.0
    frames = _mitre_frames(pts, closed_path, upv)

    m = len(profile)
    verts: list[tuple[float, float, float]] = []
    for p, (right, u_ax, sc) in zip(pts, frames):
        for (pu, pv) in profile:
            q = p + right * (sign * pu * sc) + u_ax * pv
            verts.append((q.x, q.y, q.z))

    faces = []
    n = len(pts)
    spans = n if closed_path else n - 1
    seg_count = m if closed_profile else m - 1
    for i in range(spans):
        a = i * m
        b = ((i + 1) % n) * m
        for j in range(seg_count):
            k = (j + 1) % m
            # wound so the normal faces out of the swept solid for a CCW
            # path with a CCW profile
            faces.append((a + j, b + j, b + k, a + k))

    if cap and not closed_path and closed_profile:
        faces.append(tuple(range(m)))
        faces.append(tuple(range(n * m - 1, (n - 1) * m - 1, -1)))

    return obj_from(name, verts, faces, col=col)


# ---------------------------------------------------------------------------
# Path helpers
# ---------------------------------------------------------------------------

def rect_path(x0: float, y0: float, x1: float, y1: float, z: float
              ) -> list[tuple[float, float, float]]:
    """A closed CCW rectangle at height ``z`` - the usual cornice path."""
    return [(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)]


def frame_path(x0: float, x1: float, z0: float, z1: float, y: float
               ) -> list[tuple[float, float, float]]:
    """A closed rectangle standing in a wall plane (constant Y).

    Wound top-left, top-right, bottom-right, bottom-left so that a sweep with
    ``up=(0, 1, 0)`` sends the profile's +u away from the opening - i.e. a
    casing grows outward around a window rather than closing over the glass.
    """
    return [(x0, y, z1), (x1, y, z1), (x1, y, z0), (x0, y, z0)]


def sweep_straight(name: str, profile: Sequence[Vec2], p0: Vec3, p1: Vec3,
                   out: Vec3, up: Vec3 = (0.0, 0.0, 1.0), cap: bool = True,
                   col: bpy.types.Collection | None = None) -> bpy.types.Object:
    """Sweep a section along a straight run with an explicit outward direction.

    :func:`sweep` derives its own frame from the path tangent, which for a run
    along +X with up=+Z points the profile's +u at -Y - backwards into the
    wall.  Rather than remember which runs need flipping, straight mouldings
    say where "out" is and get it built that way.
    """
    o = Vector(out)
    u = Vector(up)
    o = (o - u * o.dot(u))          # keep the frame orthogonal
    if o.length < 1e-9:
        raise ValueError(f"sweep_straight({name}): out is parallel to up")
    o.normalize()
    u = u.normalized()
    a, b = Vector(p0), Vector(p1)
    m = len(profile)
    verts = []
    for p in (a, b):
        for (pu, pv) in profile:
            q = p + o * pu + u * pv
            verts.append((q.x, q.y, q.z))
    faces = []
    for j in range(m):
        k = (j + 1) % m
        faces.append((j, m + j, m + k, k))
    if cap:
        faces.append(tuple(range(m)))
        faces.append(tuple(range(2 * m - 1, m - 1, -1)))
    obj = obj_from(name, verts, faces, col=col)
    recalc_normals(obj)
    return obj


def sweep_wall_path(name: str, profile: Sequence[Vec2],
                    path2d: Sequence[Vec2], y: float, outward: float = 1.0,
                    closed: bool = True,
                    col: bpy.types.Collection | None = None
                    ) -> bpy.types.Object:
    """Sweep a moulding around an arbitrary outline standing in a wall plane.

    ``path2d`` is a list of ``(x, z)`` wound **clockwise** in the XZ plane;
    that is the direction that makes the profile's +u point away from the
    enclosed opening, so an arched window head carries its casing outward the
    same way a square one does.  ``profile`` is ``(u, v)`` with *v* projecting
    out of the wall along +Y (pass ``outward=-1`` for a wall facing -Y).
    """
    prof = [(u, v * outward) for u, v in profile]
    path = [(x, y, z) for x, z in path2d]
    return sweep(name, prof, path, closed_path=closed, up=(0.0, 1.0, 0.0),
                 col=col)


def sweep_frame(name: str, profile: Sequence[Vec2], x0: float, x1: float,
                z0: float, z1: float, y: float, outward: float = 1.0,
                col: bpy.types.Collection | None = None) -> bpy.types.Object:
    """Mitred rectangular frame in a vertical wall plane.

    ``profile`` is ``(u, v)`` with *u* running outward from the opening within
    the wall plane and *v* projecting out of the wall along +Y (scale
    ``outward`` by -1 for a wall that faces -Y).
    """
    prof = [(u, v * outward) for u, v in profile]
    return sweep(name, prof, frame_path(x0, x1, z0, z1, y), closed_path=True,
                 up=(0.0, 1.0, 0.0), col=col)


def arc_path(cx: float, cy: float, r: float, a0: float, a1: float,
             steps: int, z: float = 0.0) -> list[tuple[float, float, float]]:
    return [(cx + r * math.cos(a0 + (a1 - a0) * i / steps),
             cy + r * math.sin(a0 + (a1 - a0) * i / steps), z)
            for i in range(steps + 1)]


def circle_path(cx: float, cy: float, r: float, steps: int, z: float = 0.0):
    return [(cx + r * math.cos(TAU * i / steps),
             cy + r * math.sin(TAU * i / steps), z) for i in range(steps)]


def poly_circle(cx: float, cy: float, r: float, n: int, phase: float = 0.0
                ) -> list[tuple[float, float]]:
    return [(cx + r * math.cos(phase + TAU * i / n),
             cy + r * math.sin(phase + TAU * i / n)) for i in range(n)]


def offset_polygon(poly: Sequence[Vec2], dist: float,
                   clockwise: bool | None = None) -> list[tuple[float, float]]:
    """Offset a closed polygon by ``dist``, positive being outward.

    Each vertex moves along the bisector of its two edge normals, scaled by
    1 / cos(half-angle) so the offset edges stay parallel to the originals -
    the same mitre correction the sweep uses, in 2D.
    """
    n = len(poly)
    if n < 3:
        raise ValueError("offset_polygon needs a closed polygon")
    if clockwise is None:
        area = sum(poly[i][0] * poly[(i + 1) % n][1]
                   - poly[(i + 1) % n][0] * poly[i][1] for i in range(n)) / 2.0
        clockwise = area < 0.0
    sign = -1.0 if clockwise else 1.0

    def normal(a, b):
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dy)
        if length < 1e-12:
            return (0.0, 0.0)
        # outward normal for a CCW polygon
        return (dy / length * sign, -dx / length * sign)

    out = []
    for i in range(n):
        n_in = normal(poly[(i - 1) % n], poly[i])
        n_out = normal(poly[i], poly[(i + 1) % n])
        bx, by = n_in[0] + n_out[0], n_in[1] + n_out[1]
        blen = math.hypot(bx, by)
        if blen < 1e-9:
            bx, by, blen = n_out[0], n_out[1], 1.0
        bx, by = bx / blen, by / blen
        cos_half = bx * n_out[0] + by * n_out[1]
        scale = 1.0 / cos_half if abs(cos_half) > 0.25 else 1.0
        out.append((poly[i][0] + bx * dist * scale,
                    poly[i][1] + by * dist * scale))
    return out


def band_solid(name: str, outer: Sequence[Vec2], inner: Sequence[Vec2],
               y0: float, y1: float,
               col: bpy.types.Collection | None = None) -> bpy.types.Object:
    """A closed solid filling the gap between two matched closed outlines.

    Both outlines live in the XZ plane and must have the same vertex count and
    winding; the solid is extruded between ``y0`` and ``y1``.  This is how
    every sash frame, shutter frame and arched head lining is made: offset the
    opening inward for the light, then fill the ring left over.
    """
    n = len(outer)
    if len(inner) != n:
        raise ValueError("band_solid needs matched outlines")
    verts = ([(x, y0, z) for x, z in outer] + [(x, y0, z) for x, z in inner]
             + [(x, y1, z) for x, z in outer] + [(x, y1, z) for x, z in inner])
    O0, I0, O1, I1 = 0, n, 2 * n, 3 * n
    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces.append((O0 + i, O0 + j, I0 + j, I0 + i))      # back ring
        faces.append((O1 + j, O1 + i, I1 + i, I1 + j))      # front ring
        faces.append((O0 + j, O0 + i, O1 + i, O1 + j))      # outer wall
        faces.append((I0 + i, I0 + j, I1 + j, I1 + i))      # inner wall
    obj = obj_from(name, verts, faces, col=col)
    recalc_normals(obj)
    return obj


# ---------------------------------------------------------------------------
# bmesh conveniences
# ---------------------------------------------------------------------------

def bevel(obj: bpy.types.Object, width: float = 0.01, segments: int = 2,
          angle: float = math.radians(35)) -> bpy.types.Object:
    """Bake a small bevel in - catching a highlight on every arris is most of
    what makes a render read as built rather than modelled."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    edges = [e for e in bm.edges
             if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > angle]
    if edges:
        bmesh.ops.bevel(bm, geom=edges, offset=width, segments=segments,
                        profile=0.5, affect='EDGES', clamp_overlap=True)
        # Overlap clamping collapses the bevel to nothing where two arrises
        # meet at a tight angle - a scroll's inner curl, say - leaving
        # zero-area faces with no usable normal.  Dissolve them out.
        bmesh.ops.dissolve_degenerate(bm, dist=width * 1e-3,
                                      edges=list(bm.edges))
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return obj


def solidify(obj: bpy.types.Object, thickness: float, offset: float = -1.0
             ) -> bpy.types.Object:
    mod = obj.modifiers.new("Solidify", 'SOLIDIFY')
    mod.thickness = thickness
    mod.offset = offset
    return obj


def shade_smooth(obj: bpy.types.Object, angle: float = math.radians(31)
                 ) -> bpy.types.Object:
    """Auto-smooth without relying on the 4.1+ operator/modifier split."""
    me = obj.data
    for poly in me.polygons:
        poly.use_smooth = True
    mod = obj.modifiers.new("Sharpen", 'EDGE_SPLIT')
    mod.split_angle = angle
    mod.use_edge_angle = True
    return obj


def shade_flat(obj: bpy.types.Object) -> bpy.types.Object:
    for poly in obj.data.polygons:
        poly.use_smooth = False
    return obj


def orient_outward(obj: bpy.types.Object, center: Vec3,
                   axis_only: bool = True) -> bpy.types.Object:
    """Flip any face whose normal points back toward ``center``.

    recalc_face_normals resolves orientation from enclosed volume, which an
    open shell - a roof loft, a soffit band - does not have, so it can settle
    on inward-facing normals.  For a shell wrapped around a known axis the
    outward direction is unambiguous, so state it instead of inferring it.
    """
    me = obj.data
    cx, cy, cz = center
    flipped = []
    for poly in me.polygons:
        c = poly.center
        radial = Vector((c.x - cx, c.y - cy, 0.0 if axis_only else c.z - cz))
        if radial.length < 1e-9:
            continue
        if poly.normal.dot(radial.normalized()) < 0.0:
            flipped.append(poly.index)
    if flipped:
        bm = bmesh.new()
        bm.from_mesh(me)
        bm.faces.ensure_lookup_table()
        bmesh.ops.reverse_faces(bm, faces=[bm.faces[i] for i in flipped])
        bm.to_mesh(me)
        bm.free()
        me.update()
    return obj


def orient_up(obj: bpy.types.Object) -> bpy.types.Object:
    """Flip any face that points downward.

    Flat open surfaces - a gravel walk, a pond, a paved terrace - have no
    volume for recalc_face_normals to orient from, so which way they end up
    facing depends on the order the outline happened to be given in.  A ground
    overlay that ends up face-down shades almost black once a bump node
    tilts its already-inverted normal below the horizon, so state the
    direction rather than letting the winding decide it.
    """
    flipped = [p.index for p in obj.data.polygons if p.normal.z < 0.0]
    if flipped:
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bm.faces.ensure_lookup_table()
        bmesh.ops.reverse_faces(bm, faces=[bm.faces[i] for i in flipped])
        bm.to_mesh(obj.data)
        bm.free()
        obj.data.update()
    return obj


def recalc_normals(obj: bpy.types.Object) -> bpy.types.Object:
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    return obj


def transform(obj: bpy.types.Object, matrix: Matrix) -> bpy.types.Object:
    """Apply a matrix to the mesh data in place (keeps the object at origin)."""
    obj.data.transform(matrix)
    obj.data.update()
    return obj


def rotate_z(obj: bpy.types.Object, angle: float,
             pivot: Vec3 = (0, 0, 0)) -> bpy.types.Object:
    p = Vector(pivot)
    m = Matrix.Translation(p) @ Matrix.Rotation(angle, 4, 'Z') @ \
        Matrix.Translation(-p)
    return transform(obj, m)


def translate(obj: bpy.types.Object, delta: Vec3) -> bpy.types.Object:
    return transform(obj, Matrix.Translation(Vector(delta)))


def boolean(target: bpy.types.Object, cutter: bpy.types.Object,
            op: str = 'DIFFERENCE', remove_cutter: bool = True
            ) -> bpy.types.Object:
    """Apply a boolean immediately via bmesh evaluation of the modifier."""
    mod = target.modifiers.new("Bool", 'BOOLEAN')
    mod.operation = op
    mod.object = cutter
    mod.solver = 'EXACT'
    dg = bpy.context.evaluated_depsgraph_get()
    evaluated = target.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(evaluated)
    old = target.data
    target.data = me
    target.modifiers.remove(mod)
    if old.users == 0:
        bpy.data.meshes.remove(old)
    if remove_cutter:
        data = cutter.data
        bpy.data.objects.remove(cutter)
        if data.users == 0:
            bpy.data.meshes.remove(data)
    return target


def set_material(obj: bpy.types.Object, mat: bpy.types.Material,
                 slot: int | None = None) -> bpy.types.Object:
    """Assign ``mat`` to the whole object, or to one existing slot."""
    me = obj.data
    if slot is None:
        me.materials.clear()
        me.materials.append(mat)
        for poly in me.polygons:
            poly.material_index = 0
    else:
        while len(me.materials) <= slot:
            me.materials.append(mat)
        me.materials[slot] = mat
    return obj


def add_material(obj: bpy.types.Object, mat: bpy.types.Material) -> int:
    """Append a material and return its slot index."""
    me = obj.data
    for i, existing in enumerate(me.materials):
        if existing == mat:
            return i
    me.materials.append(mat)
    return len(me.materials) - 1


def assign_faces(obj: bpy.types.Object, slot: int, predicate) -> None:
    """Set the material slot of every face whose centre satisfies ``predicate``."""
    for poly in obj.data.polygons:
        if predicate(poly.center, poly.normal):
            poly.material_index = slot


# ---------------------------------------------------------------------------
# Small numeric helpers
# ---------------------------------------------------------------------------

def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def spread(start: float, end: float, count: int) -> list[float]:
    """``count`` evenly spaced positions strictly inside [start, end]."""
    if count < 1:
        return []
    step = (end - start) / (count + 1)
    return [start + step * (i + 1) for i in range(count)]


def fit_count(span: float, nominal: float, minimum: int = 1) -> int:
    """How many bays of roughly ``nominal`` width fit into ``span``."""
    return max(minimum, int(round(span / nominal)))
