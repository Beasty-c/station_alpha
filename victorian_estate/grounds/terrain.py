"""
The ground the estate sits on.

The site is a gently rolling park flattened into a level terrace around the
house, because a Victorian mansion was almost always built on a made-up
platform with the ground falling away from it - that is what gives the
approach its sense of arrival.  The height field is analytic and
deterministic, so every other module (drive, paths, walls, tree planting) can
ask :func:`height` where the ground is without needing the mesh.
"""

from __future__ import annotations

import math

import bpy
import numpy as np

from ..core import config, meshkit as mk
from ..core.materials import Library

#: Half-extent of the modelled ground.
SIZE = config.SITE_HALF

#: The level platform: the house plus its immediate gardens.
TERRACE = (-46.0, -38.0, 34.0, 26.0)      # x0, y0, x1, y1
TERRACE_FALLOFF = 22.0


def _smoothstep(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _rect_distance(x, y, rect):
    """Distance outside an axis-aligned rectangle; 0 inside."""
    x0, y0, x1, y1 = rect
    dx = np.maximum(np.maximum(x0 - x, x - x1), 0.0)
    dy = np.maximum(np.maximum(y0 - y, y - y1), 0.0)
    return np.hypot(dx, dy)


def _natural(x, y):
    """Rolling parkland: three octaves of smooth ridges plus a general fall."""
    h = np.zeros_like(x)
    # Broad landform - the ground falls away to the north and east.
    h += -0.020 * y - 0.012 * x
    h += 2.30 * np.sin(x * 0.0180 + 0.9) * np.cos(y * 0.0155 - 0.4)
    h += 1.05 * np.sin(x * 0.0395 - 2.1) * np.cos(y * 0.0342 + 1.7)
    h += 0.42 * np.sin(x * 0.0910 + 0.3) * np.cos(y * 0.0805 + 2.6)
    h += 0.14 * np.sin(x * 0.2100 - 1.2) * np.cos(y * 0.1930 + 0.8)
    # A shallow hollow where the ornamental water sits.
    px, py = config.POND_XY
    d = np.hypot(x - px, y - py)
    h -= 2.6 * np.exp(-(d / 26.0) ** 2)
    return h


def height(x, y):
    """Ground height at a point (accepts scalars or numpy arrays)."""
    scalar = np.isscalar(x)
    xa = np.atleast_1d(np.asarray(x, dtype=float))
    ya = np.atleast_1d(np.asarray(y, dtype=float))
    natural = _natural(xa, ya)
    d = _rect_distance(xa, ya, TERRACE)
    blend = _smoothstep(d / TERRACE_FALLOFF)
    h = natural * blend
    return float(h[0]) if scalar else h


def build(lib: Library, col, size: float = SIZE, step: float = 1.15
          ) -> list[bpy.types.Object]:
    """The ground mesh, as a single grid conforming to :func:`height`."""
    n = int(round(2 * size / step)) + 1
    xs = np.linspace(-size, size, n)
    gx, gy = np.meshgrid(xs, xs, indexing='ij')
    gz = height(gx, gy)

    verts = np.stack([gx.ravel(), gy.ravel(), gz.ravel()], axis=1)
    idx = np.arange(n * n).reshape(n, n)
    quads = np.stack([idx[:-1, :-1], idx[1:, :-1], idx[1:, 1:], idx[:-1, 1:]],
                     axis=-1).reshape(-1, 4)

    me = bpy.data.meshes.new("ground")
    me.vertices.add(len(verts))
    me.vertices.foreach_set("co", verts.ravel())
    me.loops.add(quads.size)
    me.loops.foreach_set("vertex_index", quads.ravel())
    me.polygons.add(len(quads))
    me.polygons.foreach_set("loop_start", np.arange(len(quads)) * 4)
    me.polygons.foreach_set("loop_total", np.full(len(quads), 4))
    me.update()
    me.validate(verbose=False)

    obj = mk.new_object("ground", me, col)
    mk.set_material(obj, lib.lawn)
    mk.shade_smooth(obj, math.radians(50))
    return [obj]


# ---------------------------------------------------------------------------
# Helpers for everything that has to sit on the ground
# ---------------------------------------------------------------------------

#: Vertical separation between surfacing layers.
#:
#: Every surfaced area is laid a little above the ground, so two of them that
#: cross - a walk over a drive, the carriage sweep over a path - end up
#: exactly coplanar and z-fight, which resolves to hard black and white
#: patches at the crossing.  Overlays that can overlap are given different
#: layer numbers; 6 mm apart is invisible and settles the depth test.
LAYER = 0.006


def drape(points, lift: float = 0.0):
    """Lift a list of (x, y) onto the terrain, returning (x, y, z)."""
    return [(x, y, height(x, y) + lift) for x, y in points]


def ribbon(name: str, path, width: float, lib: Library, col,
           material=None, lift: float = 0.035, kerb: float = 0.0,
           layer: int = 0) -> bpy.types.Object:
    """A surfaced strip - drive, path or terrace edge - laid on the ground.

    The strip is re-sampled finely enough to follow the ground rather than
    bridge across it, and each cross-section is squared to the local tangent
    so the edges stay parallel through a curve.
    """
    pts = [np.array(p, dtype=float) for p in path]
    dense: list[np.ndarray] = []
    for a, b in zip(pts, pts[1:]):
        seg = np.linalg.norm(b - a)
        n = max(1, int(math.ceil(seg / 1.5)))
        for i in range(n):
            dense.append(a + (b - a) * (i / n))
    dense.append(pts[-1])

    verts, faces = [], []
    half = width / 2.0
    lift = lift + layer * LAYER
    for i, p in enumerate(dense):
        prev = dense[max(0, i - 1)]
        nxt = dense[min(len(dense) - 1, i + 1)]
        d = nxt - prev
        if np.linalg.norm(d) < 1e-9:
            d = np.array([1.0, 0.0])
        d = d / np.linalg.norm(d)
        nrm = np.array([-d[1], d[0]])
        for s in (-1.0, 1.0):
            q = p + nrm * (half * s)
            verts.append((q[0], q[1], height(q[0], q[1]) + lift))
    for i in range(len(dense) - 1):
        a = i * 2
        faces.append((a, a + 2, a + 3, a + 1))

    obj = mk.obj_from(name, verts, faces, col=col)
    mk.orient_up(obj)
    mk.set_material(obj, material or lib.gravel)
    if kerb:
        mk.solidify(obj, kerb)
    return obj


def disc(name: str, cx: float, cy: float, r: float, lib: Library, col,
         material=None, lift: float = 0.035, segments: int = 72,
         rings: int = 6, layer: int = 0) -> bpy.types.Object:
    """A circular surfaced area (a carriage turn, a garden roundel)."""
    lift = lift + layer * LAYER
    verts = [(cx, cy, height(cx, cy) + lift)]
    for ring in range(1, rings + 1):
        rr = r * ring / rings
        for i in range(segments):
            a = math.tau * i / segments
            x, y = cx + rr * math.cos(a), cy + rr * math.sin(a)
            verts.append((x, y, height(x, y) + lift))
    faces = []
    for i in range(segments):
        j = (i + 1) % segments
        faces.append((0, 1 + i, 1 + j))
    for ring in range(rings - 1):
        base = 1 + ring * segments
        nxt = base + segments
        for i in range(segments):
            j = (i + 1) % segments
            faces.append((base + i, nxt + i, nxt + j, base + j))
    obj = mk.obj_from(name, verts, faces, col=col)
    mk.orient_up(obj)
    mk.set_material(obj, material or lib.gravel)
    return obj


def annulus(name: str, cx: float, cy: float, r_in: float, r_out: float,
            lib: Library, col, material=None, lift: float = 0.035,
            segments: int = 96, layer: int = 0) -> bpy.types.Object:
    """A ring - the carriage sweep around a fountain."""
    lift = lift + layer * LAYER
    verts, faces = [], []
    for i in range(segments):
        a = math.tau * i / segments
        for rr in (r_in, r_out):
            x, y = cx + rr * math.cos(a), cy + rr * math.sin(a)
            verts.append((x, y, height(x, y) + lift))
    for i in range(segments):
        j = (i + 1) % segments
        faces.append((i * 2, j * 2, j * 2 + 1, i * 2 + 1))
    obj = mk.obj_from(name, verts, faces, col=col)
    mk.orient_up(obj)
    mk.set_material(obj, material or lib.gravel)
    return obj
