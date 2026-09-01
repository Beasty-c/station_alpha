"""
The wrap-around veranda.

A veranda is defined by a matched pair of plan polylines: ``outer``, the free
edge that carries the posts, and ``wall``, where the roof meets the house.
Everything else - deck, skirt, lattice, posts, balustrade, spindle frieze,
spandrels, beam, cornice and the shed roof over it - is generated between
them.  Keeping the two paths as data means a straight front run, an L return
and a curved sweep round the foot of the tower are all the same code.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

import bpy
from mathutils import Matrix, Vector

from ..core import config, meshkit as mk, ornament as orn
from ..core.materials import Library
from .roof import Face, slate_field

Vec2 = tuple[float, float]


@dataclass
class Plan:
    """Matched outer and wall polylines, plus where the flights of steps go."""

    outer: list[Vec2]
    wall: list[Vec2]
    deck_z: float = config.VERANDA_DECK_Z
    ceil_z: float = config.VERANDA_CEIL_Z
    #: Index of the outer-path bay each flight of steps descends from.
    step_bays: tuple[int, ...] = ()
    bay: float = config.VERANDA_POST_BAY

    def __post_init__(self) -> None:
        if len(self.outer) != len(self.wall):
            raise ValueError("outer and wall paths must be matched")


def _resample(path: list[Vec2], nominal: float) -> list[Vec2]:
    """Subdivide each leg of a polyline into whole bays of about ``nominal``."""
    out: list[Vec2] = [path[0]]
    for a, b in zip(path, path[1:]):
        length = math.dist(a, b)
        n = max(1, int(round(length / nominal)))
        for i in range(1, n + 1):
            t = i / n
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out


def _pair(plan: Plan) -> tuple[list[Vec2], list[Vec2]]:
    """Resample both paths to the same bay structure."""
    outer = _resample(plan.outer, plan.bay)
    # Carry the same parameterisation onto the wall path so the roof rafters
    # stay square: walk both by matching fraction along each leg.
    wall: list[Vec2] = [plan.wall[0]]
    for (a, b), (wa, wb) in zip(zip(plan.outer, plan.outer[1:]),
                                zip(plan.wall, plan.wall[1:])):
        n = max(1, int(round(math.dist(a, b) / plan.bay)))
        for i in range(1, n + 1):
            t = i / n
            wall.append((wa[0] + (wb[0] - wa[0]) * t,
                         wa[1] + (wb[1] - wa[1]) * t))
    return outer, wall


# ---------------------------------------------------------------------------
# Parts
# ---------------------------------------------------------------------------

def _deck(name: str, outer: list[Vec2], wall: list[Vec2], z: float,
          lib: Library, col) -> list[bpy.types.Object]:
    """Deck boards on a skirt, with a lattice panel beneath."""
    made = []
    poly = list(wall) + list(reversed(outer))
    slab = mk.prism(f"{name}.deck", poly, z - 0.30, z, col)
    mk.set_material(slab, lib.wood_oak)
    made.append(slab)

    # Individual boards, laid parallel to the house wall.
    board_w = 0.135
    for i, (a, b) in enumerate(zip(outer, outer[1:])):
        wa, wb = wall[i], wall[i + 1]
        span = math.dist(a, wa)
        n = max(1, int(span / board_w))
        for k in range(n):
            t0, t1 = k / n, (k + 1) / n - 0.06 / n
            p0 = Vector((a[0] + (wa[0] - a[0]) * t0,
                         a[1] + (wa[1] - a[1]) * t0, z))
            p1 = Vector((b[0] + (wb[0] - b[0]) * t0,
                         b[1] + (wb[1] - b[1]) * t0, z))
            p2 = Vector((b[0] + (wb[0] - b[0]) * t1,
                         b[1] + (wb[1] - b[1]) * t1, z))
            p3 = Vector((a[0] + (wa[0] - a[0]) * t1,
                         a[1] + (wa[1] - a[1]) * t1, z))
            board = mk.obj_from(f"{name}.board.{i}.{k}",
                                [tuple(p0), tuple(p1), tuple(p2), tuple(p3)],
                                [(0, 1, 2, 3)], col=col)
            mk.solidify(board, 0.028)
            mk.set_material(board, lib.wood_oak)
            made.append(board)
    return made


def _lattice(name: str, outer: list[Vec2], z_top: float, z_bot: float,
             lib: Library, col, pitch: float = 0.20) -> bpy.types.Object:
    """Diagonal lattice closing the space under the deck."""
    parts = []
    for i, (a, b) in enumerate(zip(outer, outer[1:])):
        d = Vector((b[0] - a[0], b[1] - a[1], 0.0))
        length = d.length
        if length < 1e-6:
            continue
        d.normalize()
        nrm = Vector((d.y, -d.x, 0.0))
        height = z_top - z_bot
        # Two opposed sets of slats, as a real lattice is made.
        for sign in (1, -1):
            steps = int((length + height) / pitch)
            for k in range(steps):
                s = k * pitch - (height if sign > 0 else 0.0)
                p = Vector((a[0], a[1], z_bot)) + d * s
                slat = mk.box(f"{name}.lat{i}{sign}{k}", (0, 0, 0),
                              (0.030, 0.016, math.hypot(height, height) * 1.02),
                              col)
                yaw = math.atan2(d.y, d.x)
                mk.transform(
                    slat,
                    Matrix.Translation(p + Vector((0, 0, height / 2))
                                       + nrm * 0.02)
                    @ Matrix.Rotation(yaw, 4, 'Z')
                    @ Matrix.Rotation(math.radians(45) * sign, 4, 'Y'))
                parts.append(slat)
        frame = mk.box(f"{name}.latframe{i}", (0, 0, 0),
                       (length, 0.075, 0.14), col)
        mid = Vector(((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, z_top - 0.07))
        mk.transform(frame, Matrix.Translation(mid + nrm * 0.02)
                     @ Matrix.Rotation(math.atan2(d.y, d.x), 4, 'Z'))
        parts.append(frame)
    obj = mk.join(parts, name, col)
    mk.set_material(obj, lib.accent_dark)
    return obj


def _posts(name: str, outer: list[Vec2], deck_z: float, ceil_z: float,
           lib: Library, col, segments: int) -> list[bpy.types.Object]:
    """Turned posts on plinth blocks, with a moulded cap under the beam."""
    made = []
    plinth_h = 0.26
    shaft = ceil_z - deck_z - plinth_h - 0.14
    proto = orn.turned_post(f"{name}.postproto", shaft, 0.235, segments,
                            "veranda", col)
    mk.set_material(proto, lib.trim)
    posts = []
    for i, (x, y) in enumerate(outer):
        block = mk.box(f"{name}.plinth{i}", (x, y, deck_z + plinth_h / 2),
                       (0.34, 0.34, plinth_h), col)
        mk.set_material(block, lib.trim)
        posts.append(block)
        posts.append(mk.instance(proto, f"{name}.post{i}",
                                 (x, y, deck_z + plinth_h), col=col))
        cap = mk.box(f"{name}.postcap{i}",
                     (x, y, deck_z + plinth_h + shaft + 0.07),
                     (0.32, 0.32, 0.14), col)
        mk.set_material(cap, lib.trim)
        posts.append(cap)
    bpy.data.objects.remove(proto)
    joined = mk.join(posts, f"{name}.posts", col)
    mk.set_material(joined, lib.trim)
    made.append(joined)
    return made


def _balustrade(name: str, outer: list[Vec2], deck_z: float, lib: Library,
                col, skip: tuple[int, ...], segments: int
                ) -> bpy.types.Object:
    """Turned balusters between top and bottom rails, bay by bay."""
    parts = []
    rail_h = config.VERANDA_RAIL_H
    bal_h = rail_h - 0.20
    proto = orn.baluster(f"{name}.balproto", bal_h, 0.078, segments, "vase",
                         col)
    for i, (a, b) in enumerate(zip(outer, outer[1:])):
        if i in skip:
            continue
        d = Vector((b[0] - a[0], b[1] - a[1], 0.0))
        length = d.length - 0.34
        if length <= 0.2:
            continue
        d.normalize()
        yaw = math.atan2(d.y, d.x)
        mid = Vector(((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, 0.0))

        bottom = mk.box(f"{name}.brail{i}", (0, 0, 0), (length, 0.11, 0.075), col)
        mk.transform(bottom, Matrix.Translation(
            mid + Vector((0, 0, deck_z + 0.10))) @ Matrix.Rotation(yaw, 4, 'Z'))
        parts.append(bottom)

        top = mk.sweep_straight(
            f"{name}.trail{i}", orn.handrail_profile(0.135, 0.085),
            (-length / 2, 0.0, 0.0), (length / 2, 0.0, 0.0), (0, 1, 0),
            col=col)
        mk.transform(top, Matrix.Translation(
            mid + Vector((0, 0, deck_z + rail_h - 0.085)))
            @ Matrix.Rotation(yaw, 4, 'Z'))
        parts.append(top)

        n = max(2, int(length / config.BALUSTER_SPACING))
        for k in range(n):
            t = (k + 0.5) / n
            p = Vector((a[0], a[1], 0.0)).lerp(Vector((b[0], b[1], 0.0)), t)
            parts.append(mk.instance(proto, f"{name}.bal{i}.{k}",
                                     (p.x, p.y, deck_z + 0.14), col=col))
    bpy.data.objects.remove(proto)
    obj = mk.join(parts, name, col)
    mk.set_material(obj, lib.trim)
    return obj


def _frieze(name: str, outer: list[Vec2], ceil_z: float, lib: Library, col,
            segments: int) -> bpy.types.Object:
    """Spindle frieze and sawn spandrels filling the head of each bay."""
    parts = []
    height = 0.52
    for i, (a, b) in enumerate(zip(outer, outer[1:])):
        d = Vector((b[0] - a[0], b[1] - a[1], 0.0))
        length = d.length - 0.36
        if length <= 0.3:
            continue
        d.normalize()
        yaw = math.atan2(d.y, d.x)
        f = orn.spindle_frieze(f"{name}.sf{i}", length, height, 0.052, 0.135,
                               segments, col)
        mk.transform(f, Matrix.Translation(
            Vector((a[0], a[1], ceil_z - height - 0.22)) + d * 0.18)
            @ Matrix.Rotation(yaw, 4, 'Z'))
        parts.append(f)

        # A spandrel bracket springing from each post head into the bay.
        for end, sgn in ((a, 1), (b, -1)):
            sp = orn.bracket(f"{name}.sp{i}{sgn}", 0.62, 0.60, 0.05,
                             "spandrel", pierce=False, col=col)
            mk.transform(sp, Matrix.Translation(
                Vector((end[0], end[1], ceil_z - 0.22)) + d * (0.17 * sgn))
                @ Matrix.Rotation(yaw, 4, 'Z')
                @ Matrix.Scale(sgn, 4, (1.0, 0.0, 0.0)))
            mk.recalc_normals(sp)
            parts.append(sp)
    obj = mk.join(parts, name, col)
    mk.set_material(obj, lib.trim)
    return obj


def _entablature(name: str, outer: list[Vec2], ceil_z: float, lib: Library,
                 col) -> list[bpy.types.Object]:
    """The beam over the posts and the little cornice that crowns it."""
    made = []
    for i, (a, b) in enumerate(zip(outer, outer[1:])):
        d = Vector((b[0] - a[0], b[1] - a[1], 0.0))
        length = d.length
        d.normalize()
        yaw = math.atan2(d.y, d.x)
        mid = Vector(((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, 0.0))

        beam = mk.box(f"{name}.beam{i}", (0, 0, 0),
                      (length + 0.02, 0.26, 0.34), col)
        mk.transform(beam, Matrix.Translation(
            mid + Vector((0, 0, ceil_z - 0.17))) @ Matrix.Rotation(yaw, 4, 'Z'))
        mk.set_material(beam, lib.trim)
        made.append(beam)

        cor = mk.sweep_straight(
            f"{name}.cornice{i}", orn.cornice_profile(0.42, 0.38),
            (-length / 2 - 0.01, 0.0, 0.0), (length / 2 + 0.01, 0.0, 0.0),
            (0, 1, 0), col=col)
        mk.transform(cor, Matrix.Translation(mid + Vector((0, 0, ceil_z)))
                     @ Matrix.Rotation(yaw, 4, 'Z'))
        mk.set_material(cor, lib.trim)
        made.append(cor)
    return made


def _roof(name: str, outer: list[Vec2], wall: list[Vec2], ceil_z: float,
          lib: Library, col, rise: float = 1.15, slate: bool = True
          ) -> list[bpy.types.Object]:
    """A shallow shed roof from the wall down over the veranda."""
    made = []
    lo = [Vector((x, y, ceil_z + 0.38)) for x, y in outer]
    hi = [Vector((x, y, ceil_z + 0.38 + rise)) for x, y in wall]
    verts, faces = [], []
    for i in range(len(lo) - 1):
        base = len(verts)
        verts += [tuple(lo[i]), tuple(lo[i + 1]), tuple(hi[i + 1]), tuple(hi[i])]
        faces.append((base, base + 1, base + 2, base + 3))
    deck = mk.obj_from(f"{name}.roofdeck", verts, faces, col=col)
    mk.solidify(deck, 0.14)
    mk.set_material(deck, lib.slate)
    made.append(deck)
    if slate:
        for i in range(len(lo) - 1):
            f = Face(lo[i], lo[i + 1], hi[i + 1], hi[i])
            made.append(slate_field(f"{name}.slate{i}", f, lib, col,
                                    exposure=config.SLATE_EXPOSURE * 1.1,
                                    jitter=0.7, seed=311 + i * 13))
    return made


def steps(name: str, at: Vec2, direction: Vec2, width: float, deck_z: float,
          lib: Library, col, grade: float = 0.0, segments: int = 16
          ) -> bpy.types.Object:
    """A flight down from the deck, with closed cheeks and newel posts."""
    parts = []
    d = Vector((direction[0], direction[1], 0.0)).normalized()
    side = Vector((-d.y, d.x, 0.0))
    rise = 0.185
    tread = 0.31
    n = max(1, int(round((deck_z - grade) / rise)))
    rise = (deck_z - grade) / n

    for i in range(n):
        z = deck_z - rise * (i + 0.5)
        centre = Vector((at[0], at[1], 0.0)) + d * (tread * (i + 0.5))
        step = mk.box(f"{name}.tread{i}", (0, 0, 0),
                      (width, tread * 1.06, rise), col)
        mk.transform(step, Matrix.Translation(centre + Vector((0, 0, z)))
                     @ Matrix.Rotation(math.atan2(d.y, d.x), 4, 'Z')
                     @ Matrix.Rotation(math.pi / 2, 4, 'Z'))
        mk.set_material(step, lib.stone)
        parts.append(step)

    run = tread * n
    for sgn in (-1, 1):
        cheek_pts = [(0.0, deck_z), (run, deck_z - rise * n),
                     (run, deck_z - rise * n - 0.30), (0.0, deck_z - 0.30)]
        cheek = mk.prism_y(f"{name}.cheek{sgn}", cheek_pts, -0.08, 0.08, col)
        mk.transform(cheek, Matrix.Translation(
            Vector((at[0], at[1], 0.0)) + side * (sgn * width / 2))
            @ Matrix.Rotation(math.atan2(d.y, d.x), 4, 'Z'))
        mk.set_material(cheek, lib.stone)
        parts.append(cheek)

        newel = orn.turned_post(f"{name}.newel{sgn}", 1.32, 0.30, segments,
                                "newel", col)
        mk.transform(newel, Matrix.Translation(
            Vector((at[0], at[1], deck_z - 0.30))
            + side * (sgn * (width / 2 + 0.02)) + d * 0.16))
        mk.set_material(newel, lib.trim)
        parts.append(newel)

    return mk.join(parts, name, col)


# ---------------------------------------------------------------------------
# Assembly
# ---------------------------------------------------------------------------

def build(plan: Plan, lib: Library, col, name: str = "veranda",
          segments: int = 18, slate: bool = True) -> list[bpy.types.Object]:
    outer, wall = _pair(plan)
    made: list[bpy.types.Object] = []
    made += _deck(f"{name}.deck", outer, wall, plan.deck_z, lib, col)
    made.append(_lattice(f"{name}.lattice", outer, plan.deck_z - 0.30,
                         config.Z_BASE + 0.10, lib, col))
    made += _posts(name, outer, plan.deck_z, plan.ceil_z, lib, col, segments)
    made.append(_balustrade(f"{name}.balustrade", outer, plan.deck_z, lib, col,
                            plan.step_bays, max(10, segments - 6)))
    made.append(_frieze(f"{name}.frieze", outer, plan.ceil_z, lib, col,
                        max(8, segments - 8)))
    made += _entablature(f"{name}.entab", outer, plan.ceil_z, lib, col)
    made += _roof(f"{name}.roof", outer, wall, plan.ceil_z, lib, col,
                  slate=slate)
    return made


def front_plan() -> Plan:
    """The veranda across the south front, returning west toward the tower."""
    y_wall = config.MAIN.y1
    y_out = y_wall + config.VERANDA_DEPTH
    x_east = config.MAIN.x1 + 0.20
    x_west = -6.30
    return Plan(
        outer=[(x_east, y_out), (x_west, y_out)],
        wall=[(x_east, y_wall), (x_west, y_wall)],
        step_bays=(2,),
    )
