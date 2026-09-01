"""
Trees, hedges, topiary and beds.

Trees are grown from a small recursive skeleton: tapered segments for the
woody structure, and a deformed blob of foliage at every twig tip.  A canopy
made of sixty small blobs reads far better at estate distance than one large
one, because its silhouette breaks up and it self-shadows.

Each species is built a handful of times as a prototype and then instanced
across the park, so a hundred and forty trees cost about eight trees' worth
of memory.
"""

from __future__ import annotations

import math
import random
import zlib

import bpy
from mathutils import Matrix, Vector

from ..core import meshkit as mk
from ..core.materials import Library
from . import terrain as T


# ---------------------------------------------------------------------------
# Species
# ---------------------------------------------------------------------------

SPECIES = {
    #                 height   trunk  splits  spread  droop  levels  blob
    "oak":          dict(h=17.0, r=0.52, splits=3, spread=0.62, droop=-0.06,
                         levels=5, blob=1.42, tips=1.00, taper=0.68),
    "elm":          dict(h=20.0, r=0.44, splits=2, spread=0.40, droop=-0.16,
                         levels=6, blob=1.16, tips=0.95, taper=0.72),
    "beech":        dict(h=18.0, r=0.60, splits=3, spread=0.52, droop=-0.02,
                         levels=5, blob=1.06, tips=1.05, taper=0.66),
    "lime":         dict(h=15.0, r=0.38, splits=3, spread=0.46, droop=0.02,
                         levels=5, blob=1.20, tips=0.95, taper=0.70),
    "poplar":       dict(h=21.0, r=0.34, splits=2, spread=0.085, droop=-0.62,
                         levels=6, blob=0.74, tips=0.62, taper=0.80),
    "willow":       dict(h=13.0, r=0.55, splits=3, spread=0.72, droop=0.34,
                         levels=5, blob=1.06, tips=0.85, taper=0.64),
    "cedar":        dict(h=19.0, r=0.66, splits=4, spread=0.92, droop=0.26,
                         levels=4, blob=1.72, tips=1.30, taper=0.60),
    "birch":        dict(h=12.0, r=0.22, splits=2, spread=0.34, droop=-0.10,
                         levels=5, blob=0.80, tips=0.70, taper=0.74),
    # An orchard tree is pruned to an open goblet on a short leg, so it wants
    # a much shorter trunk and a wider, lower head than a park tree.
    "apple":        dict(h=4.6, r=0.16, splits=3, spread=0.80, droop=0.08,
                         levels=4, blob=0.46, tips=1.00, taper=0.66),
    "pear":         dict(h=5.4, r=0.15, splits=3, spread=0.58, droop=-0.06,
                         levels=4, blob=0.42, tips=0.95, taper=0.70),
}

#: Species whose canopy starts low on a short leg.
SHORT_LEG = {"apple", "pear"}

FOLIAGE_MATERIAL = {
    "beech": "leaf_copper",
    "cedar": "hedge",
}


def _blob(rng: random.Random, radius: float, rough: float = 0.34,
          rings: int = 5, seg: int = 9) -> tuple[list, list]:
    """A low-poly deformed sphere - one puff of foliage."""
    verts, faces = [], []
    top = (0.0, 0.0, radius * rng.uniform(0.9, 1.15))
    bottom = (0.0, 0.0, -radius * rng.uniform(0.75, 1.0))
    verts.append(top)
    for r in range(1, rings):
        phi = math.pi * r / rings
        for s in range(seg):
            th = math.tau * s / seg + rng.uniform(-0.15, 0.15)
            jitter = 1.0 + rng.uniform(-rough, rough)
            rr = radius * math.sin(phi) * jitter
            z = radius * math.cos(phi) * jitter
            verts.append((rr * math.cos(th), rr * math.sin(th), z))
    verts.append(bottom)
    last = len(verts) - 1
    for s in range(seg):
        faces.append((0, 1 + s, 1 + (s + 1) % seg))
    for r in range(rings - 2):
        a = 1 + r * seg
        b = a + seg
        for s in range(seg):
            t = (s + 1) % seg
            faces.append((a + s, b + s, b + t, a + t))
    a = 1 + (rings - 2) * seg
    for s in range(seg):
        faces.append((last, a + (s + 1) % seg, a + s))
    return verts, faces


def tree(name: str, species: str, lib: Library, col, seed: int = 0,
         scale: float = 1.0) -> bpy.types.Object:
    """Grow one tree prototype."""
    spec = SPECIES[species]
    # zlib.crc32, not hash(): Python randomises string hashing per process,
    # so hash() here would grow a different tree on every run and the model
    # would not be reproducible.
    rng = random.Random(seed * 7919 + zlib.crc32(species.encode()) % 100003)
    height = spec["h"] * scale * rng.uniform(0.85, 1.15)

    wood_v: list[tuple] = []
    wood_f: list[tuple] = []
    leaf_v: list[tuple] = []
    leaf_f: list[tuple] = []

    def segment(base: Vector, direction: Vector, length: float, r0: float,
                r1: float, sides: int = 6) -> Vector:
        """Emit a tapered tube and return its tip."""
        d = direction.normalized()
        up = Vector((0, 0, 1))
        ref = up if abs(d.dot(up)) < 0.95 else Vector((1, 0, 0))
        u = d.cross(ref).normalized()
        v = d.cross(u)
        tip = base + d * length
        start = len(wood_v)
        for i in range(sides):
            a = math.tau * i / sides
            off = u * math.cos(a) + v * math.sin(a)
            wood_v.append(tuple(base + off * r0))
        for i in range(sides):
            a = math.tau * i / sides
            off = u * math.cos(a) + v * math.sin(a)
            wood_v.append(tuple(tip + off * r1))
        for i in range(sides):
            j = (i + 1) % sides
            wood_f.append((start + i, start + sides + i,
                           start + sides + j, start + j))
        return tip

    def foliage(at: Vector, radius: float) -> None:
        vs, fs = _blob(rng, radius)
        base = len(leaf_v)
        for x, y, z in vs:
            leaf_v.append((at.x + x, at.y + y, at.z + z))
        for f in fs:
            leaf_f.append(tuple(base + i for i in f))

    def grow(base: Vector, direction: Vector, length: float, radius: float,
             level: int) -> None:
        tip = segment(base, direction, length,
                      radius, radius * spec["taper"])
        if level >= spec["levels"] or radius < 0.03:
            # Two or three smaller puffs along the last twig read better than
            # one large one: the silhouette breaks up at leaf-clump scale
            # instead of showing a single faceted ball.
            for t in (0.35, 0.72, 1.0):
                foliage(base.lerp(tip, t) if t < 1.0 else tip,
                        spec["blob"] * spec["tips"] * scale
                        * rng.uniform(0.46, 0.78))
            return
        # Foliage on the penultimate level too, so the canopy has depth
        # rather than being a shell of blobs on the outermost twigs.
        if level == spec["levels"] - 1:
            foliage(tip, spec["blob"] * 0.72 * scale * rng.uniform(0.6, 1.0))
        n = spec["splits"] + rng.randint(-1, 1)
        n = max(2, n)
        for k in range(n):
            az = math.tau * (k + rng.uniform(-0.22, 0.22)) / n
            lean = spec["spread"] * rng.uniform(0.65, 1.35)
            child = direction.normalized()
            side = Vector((math.cos(az), math.sin(az), spec["droop"]))
            side = (side - child * side.dot(child))
            if side.length < 1e-6:
                side = Vector((1, 0, 0))
            child = (child + side.normalized() * lean).normalized()
            grow(tip, child, length * rng.uniform(0.62, 0.80),
                 radius * spec["taper"] * rng.uniform(0.82, 0.98), level + 1)
            # A few side branches carry extra foliage low down, which is what
            # stops a park tree reading as a lollipop.
            if level <= 2 and rng.random() < 0.55:
                foliage(tip + child * length * rng.uniform(0.3, 0.7),
                        spec["blob"] * 0.66 * scale)

    trunk_len = height * (0.26 if species == "cedar"
                          else 0.17 if species in SHORT_LEG else 0.34)
    grow(Vector((0, 0, 0)), Vector((rng.uniform(-0.05, 0.05),
                                    rng.uniform(-0.05, 0.05), 1.0)),
         trunk_len, spec["r"] * scale, 1)

    trunk = mk.obj_from(f"{name}.wood", wood_v, wood_f, col=col)
    mk.set_material(trunk, lib.bark)
    mk.shade_smooth(trunk, math.radians(50))
    leaves = mk.obj_from(f"{name}.leaves", leaf_v, leaf_f, col=col)
    leaf_mat = getattr(lib, FOLIAGE_MATERIAL.get(species, "leaf"))
    mk.set_material(leaves, leaf_mat)
    mk.shade_smooth(leaves, math.radians(60))
    obj = mk.join([trunk, leaves], name, col)

    # The recursion compounds segment lengths, so the grown height depends on
    # the branching ratios rather than on the species' stated height.  Measure
    # what actually grew and scale it to the intended size - which also keeps
    # trunk girth and canopy spread in proportion.
    grown = max(v.co.z for v in obj.data.vertices)
    if grown > 1e-6:
        obj.data.transform(Matrix.Scale(height / grown, 4))
        obj.data.update()
    return obj


def plantation(name: str, positions, lib: Library, col,
               species: tuple[str, ...] = ("oak", "elm", "beech", "lime"),
               variants: int = 3, seed: int = 0, scale: float = 1.0
               ) -> bpy.types.Object:
    """Instance a handful of prototypes across many positions."""
    rng = random.Random(seed)
    protos = []
    for si, sp in enumerate(species):
        for v in range(variants):
            protos.append(tree(f"{name}.proto.{sp}.{v}", sp, lib, col,
                               seed=seed + si * 31 + v, scale=scale))
    made = []
    for i, (x, y) in enumerate(positions):
        p = rng.choice(protos)
        s = rng.uniform(0.78, 1.22)
        made.append(mk.instance(p, f"{name}.{i}",
                                (x, y, T.height(x, y) - 0.15),
                                rotation=(0.0, 0.0, rng.uniform(0, math.tau)),
                                scale=(s, s, s * rng.uniform(0.92, 1.10)),
                                col=col))
    for p in protos:
        bpy.data.objects.remove(p)
    return mk.join(made, name, col)


# ---------------------------------------------------------------------------
# Clipped work
# ---------------------------------------------------------------------------

def hedge(name: str, path, lib: Library, col, height: float = 1.15,
          width: float = 0.85, wobble: float = 0.055, seed: int = 0,
          material=None) -> bpy.types.Object:
    """A clipped hedge following a plan polyline, sitting on the ground."""
    rng = random.Random(seed)
    dense: list[tuple[float, float]] = []
    for a, b in zip(path, path[1:]):
        length = math.dist(a, b)
        n = max(1, int(length / 0.45))
        for i in range(n):
            t = i / n
            dense.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    dense.append(path[-1])

    verts, faces = [], []
    for i, (x, y) in enumerate(dense):
        prev = dense[max(0, i - 1)]
        nxt = dense[min(len(dense) - 1, i + 1)]
        d = Vector((nxt[0] - prev[0], nxt[1] - prev[1], 0.0))
        if d.length < 1e-9:
            d = Vector((1, 0, 0))
        d.normalize()
        nrm = Vector((-d.y, d.x, 0.0))
        z0 = T.height(x, y) - 0.10
        h = height * (1.0 + rng.uniform(-wobble, wobble))
        w = width * (1.0 + rng.uniform(-wobble, wobble)) / 2.0
        base = Vector((x, y, z0))
        # Section: a slightly domed top so it reads as clipped, not extruded.
        for off, dz in ((-w, 0.0), (-w * 0.94, h * 0.86), (0.0, h),
                        (w * 0.94, h * 0.86), (w, 0.0)):
            p = base + nrm * off + Vector((0, 0, dz))
            verts.append((p.x, p.y, p.z))
    m = 5
    for i in range(len(dense) - 1):
        a = i * m
        b = a + m
        for j in range(m - 1):
            faces.append((a + j, b + j, b + j + 1, a + j + 1))
    # Close the ends.
    faces.append(tuple(range(m - 1, -1, -1)))
    last = (len(dense) - 1) * m
    faces.append(tuple(range(last, last + m)))

    obj = mk.obj_from(name, verts, faces, col=col)
    mk.recalc_normals(obj)
    mk.set_material(obj, material or lib.hedge)
    mk.shade_smooth(obj, math.radians(48))
    return obj


def topiary(name: str, x: float, y: float, lib: Library, col,
            shape: str = "cone", height: float = 2.2, seed: int = 0
            ) -> bpy.types.Object:
    """A clipped yew: cone, ball on a stem, or a tiered wedding cake."""
    rng = random.Random(seed)
    z = T.height(x, y)
    if shape == "cone":
        prof = [(0.0, 0.0), (height * 0.30, 0.0)]
        n = 10
        for i in range(1, n + 1):
            t = i / n
            prof.append((height * 0.30 * (1 - t) ** 0.86, height * t))
    elif shape == "ball":
        stem = height * 0.34
        r = height * 0.30
        prof = [(0.0, 0.0), (0.08, 0.0), (0.08, stem)]
        n = 12
        for i in range(n + 1):
            a = math.pi * i / n
            prof.append((r * math.sin(a), stem + r * (1 - math.cos(a))))
    elif shape == "tiers":
        prof = [(0.0, 0.0), (0.09, 0.0), (0.09, height * 0.14)]
        for k, (rr, z0, z1) in enumerate([(0.42, 0.14, 0.42),
                                          (0.30, 0.46, 0.68),
                                          (0.19, 0.72, 0.92)]):
            prof += [(0.07, height * z0), (height * rr, height * (z0 + 0.04)),
                     (height * rr * 0.86, height * (z1 - 0.03)),
                     (0.07, height * z1)]
        prof.append((0.0, height))
    else:
        raise ValueError(f"unknown topiary shape {shape!r}")

    obj = mk.lathe(name, prof, 14, center=(x, y, z), col=col)
    # Break the silhouette so it does not read as a lathe.
    for v in obj.data.vertices:
        v.co.x += rng.uniform(-0.035, 0.035)
        v.co.y += rng.uniform(-0.035, 0.035)
        v.co.z += rng.uniform(-0.025, 0.025)
    mk.set_material(obj, lib.hedge)
    mk.shade_smooth(obj, math.radians(52))
    return obj


def bed(name: str, polygon, lib: Library, col, seed: int = 0,
        density: float = 2.4, height: float = 0.42,
        colours=((0.42, 0.06, 0.10), (0.55, 0.42, 0.10),
                 (0.28, 0.10, 0.34), (0.62, 0.58, 0.52))
        ) -> list[bpy.types.Object]:
    """A planted bed: bare earth with clumps of flowering stock on it."""
    from ..core import materials as mats
    made = []
    soil = mk.prism(f"{name}.soil", polygon, -0.6, 0.0, col)
    for v in soil.data.vertices:
        v.co.z += T.height(v.co.x, v.co.y) + (0.10 if v.co.z > -0.3 else 0.0)
    mk.set_material(soil, mats.stone("Soil", (0.075, 0.052, 0.038), 0.95, 0.7))
    made.append(soil)

    rng = random.Random(seed)
    xs = [p[0] for p in polygon]
    ys = [p[1] for p in polygon]

    def inside(px, py):
        hit = False
        n = len(polygon)
        for i in range(n):
            a, b = polygon[i], polygon[(i + 1) % n]
            if (a[1] > py) != (b[1] > py):
                t = (py - a[1]) / (b[1] - a[1])
                if px < a[0] + t * (b[0] - a[0]):
                    hit = not hit
        return hit

    clumps = []
    protos = []
    for ci, c in enumerate(colours):
        vs, fs = _blob(rng, height * 0.5, 0.42)
        o = mk.obj_from(f"{name}.proto{ci}", vs, fs, col=col)
        mk.set_material(o, mats.foliage(f"Bloom.{name}.{ci}", c, 0.5, 60.0))
        mk.shade_smooth(o, math.radians(60))
        protos.append(o)

    area = (max(xs) - min(xs)) * (max(ys) - min(ys))
    for i in range(int(area * density)):
        px = rng.uniform(min(xs), max(xs))
        py = rng.uniform(min(ys), max(ys))
        if not inside(px, py):
            continue
        s = rng.uniform(0.7, 1.4)
        clumps.append(mk.instance(
            rng.choice(protos), f"{name}.c{i}",
            (px, py, T.height(px, py) + height * 0.34),
            rotation=(0.0, 0.0, rng.uniform(0, math.tau)),
            scale=(s, s, s * 0.8), col=col))
    for p in protos:
        bpy.data.objects.remove(p)
    if clumps:
        made.append(mk.join(clumps, f"{name}.planting", col))
    return made


# ---------------------------------------------------------------------------
# Climbers
# ---------------------------------------------------------------------------

def _leaf_shape(size: float, lobes: int = 5) -> tuple[list, list]:
    """A single ivy leaf: a lobed outline in the XY plane, tip at +Y."""
    pts = [(0.0, -size * 0.28)]
    for i in range(lobes):
        a = math.pi * (i + 0.5) / lobes
        r = size * (0.62 + 0.38 * math.sin(a) ** 0.6)
        pts.append((-r * math.cos(a) * 0.86, size * 0.72 - r * math.cos(a) * 0.0
                    + r * math.sin(a) * 0.0))
    # Simpler and more reliable: a five-point star-ish silhouette.
    pts = [(0.0, size), (size * 0.38, size * 0.42), (size * 0.62, size * 0.52),
           (size * 0.44, size * 0.02), (size * 0.26, -size * 0.30),
           (0.0, -size * 0.22), (-size * 0.26, -size * 0.30),
           (-size * 0.44, size * 0.02), (-size * 0.62, size * 0.52),
           (-size * 0.38, size * 0.42)]
    faces = [(0, i, i + 1) for i in range(1, len(pts) - 1)]
    return [(x, 0.0, y) for x, y in pts], faces


def ivy(name: str, centre, normal, width: float, height: float,
        lib: Library, col, up=(0.0, 0.0, 1.0), stems: int = 14,
        density: float = 26.0, leaf: float = 0.085, seed: int = 0,
        coverage: float = 0.75, material=None) -> bpy.types.Object:
    """A patch of climbing ivy on a wall plane.

    ``centre`` is the midpoint of the patch's foot and ``normal`` is the
    wall's outward direction; the patch spreads ``width`` along the wall,
    half either side, and climbs ``height``.  Taking a centre rather than a
    corner is deliberate: which way "along the wall" runs depends on the
    normal, and a patch anchored at a corner runs off the end of its own wall
    on half the elevations.

    Stems random-walk upward with a bias to stay on the wall, and leaves are
    single lobed quads scattered along them, tilted out of the plane so the
    mass catches light instead of reading as a flat decal.
    """
    rng = random.Random(seed * 131 + 7)
    u = Vector(up).normalized()
    n = Vector(normal).normalized()
    r = u.cross(n).normalized()
    o = Vector(centre) - r * (width / 2.0)

    stem_v: list[tuple] = []
    stem_f: list[tuple] = []
    leaf_v: list[tuple] = []
    leaf_f: list[tuple] = []
    lv, lf = _leaf_shape(leaf)

    def place_leaf(at: Vector, tilt: float, spin: float, scale: float) -> None:
        base = len(leaf_v)
        m = (Matrix.Translation(at)
             @ Matrix.Rotation(spin, 4, n)
             @ Matrix.Rotation(tilt, 4, r)
             @ Matrix.Scale(scale, 4))
        # Map the leaf's local XZ onto the wall plane.
        basis = Matrix((r, n, u)).transposed().to_4x4()
        for vx, vy, vz in lv:
            p = m @ (basis @ Vector((vx, vy, vz)))
            leaf_v.append((p.x, p.y, p.z))
        for f in lf:
            leaf_f.append(tuple(base + i for i in f))

    for s in range(stems):
        x = width * (s + rng.uniform(0.1, 0.9)) / stems
        z = 0.0
        drift = rng.uniform(-0.25, 0.25)
        top = height * rng.uniform(0.55, 1.0) * coverage + height * 0.1
        thick = rng.uniform(0.016, 0.030)
        prev = o + r * x + u * z + n * 0.02
        while z < top:
            step = rng.uniform(0.18, 0.34)
            z += step
            drift += rng.uniform(-0.16, 0.16)
            drift = max(-0.7, min(0.7, drift))
            x = max(0.0, min(width, x + drift * step))
            cur = o + r * x + u * z + n * rng.uniform(0.015, 0.05)
            # Stem segment as a flat ribbon; it is never seen edge on.
            side = r * (thick * 0.5)
            base = len(stem_v)
            for p in (prev - side, prev + side, cur + side, cur - side):
                stem_v.append((p.x, p.y, p.z))
            stem_f.append((base, base + 1, base + 2, base + 3))
            # Leaves along the segment.
            for _ in range(int(density * step)):
                t = rng.random()
                at = prev.lerp(cur, t) + n * rng.uniform(0.02, 0.09) \
                    + r * rng.uniform(-0.16, 0.16) + u * rng.uniform(-0.06, 0.06)
                place_leaf(at, rng.uniform(-0.9, 0.9), rng.uniform(0, math.tau),
                           rng.uniform(0.65, 1.35))
            prev = cur

    stem = mk.obj_from(f"{name}.stems", stem_v, stem_f, col=col)
    mk.set_material(stem, lib.bark)
    leaves = mk.obj_from(f"{name}.leaves", leaf_v, leaf_f, col=col)
    mk.set_material(leaves, material or lib.leaf)
    obj = mk.join([stem, leaves], name, col)
    obj.data.materials  # keep both slots
    return obj
