"""
The body of the house: plinth, walls, trim courses and the main cornice.

The massing is three rectangular blocks (a main block, a service wing behind
it and a gabled pavilion on the east) plus a round corner tower, all built as
wall slabs rather than solids so that openings can be cut cheaply and an
interior can be dropped in later.

Elevations are described declaratively.  An :class:`Elevation` knows where its
wall face is and which way it looks; a :class:`Bay` says what goes at a given
offset along it and on which floors.  That keeps the composition of the
facades - which is a design decision, not a procedural one - readable and in
one place, while the repetitive work of cutting the opening, building the
joinery and orienting it stays automatic.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

import bpy
from mathutils import Matrix

from ..core import config, meshkit as mk, ornament as orn
from ..core.materials import Library
from . import windows as W

WALL_T = 0.40
CORNER_BOARD = 0.26


# ---------------------------------------------------------------------------
# Elevations
# ---------------------------------------------------------------------------

#: Outward normal and the yaw that rotates a canonical window onto it.
SIDES = {
    "south": ((0.0, 1.0), 0.0),          # faces +Y, toward the carriage drive
    "north": ((0.0, -1.0), math.pi),
    "east":  ((1.0, 0.0), -math.pi / 2),
    "west":  ((-1.0, 0.0), math.pi / 2),
}


@dataclass
class Elevation:
    """One flat face of one block."""

    block: config.Block
    side: str

    @property
    def normal(self) -> tuple[float, float]:
        return SIDES[self.side][0]

    @property
    def yaw(self) -> float:
        return SIDES[self.side][1]

    @property
    def span(self) -> float:
        return self.block.sx if self.side in ("south", "north") else self.block.sy

    def point(self, offset: float, z: float) -> tuple[float, float, float]:
        """A point on the wall face, ``offset`` metres along it from centre.

        Offset runs left-to-right as seen from outside, so a bay schedule
        reads the same way on every elevation.
        """
        b = self.block
        if self.side == "south":
            return (offset, b.y1, z)
        if self.side == "north":
            return (-offset, b.y0, z)
        if self.side == "east":
            return (b.x1, -offset, z)
        return (b.x0, offset, z)


# ---------------------------------------------------------------------------
# Bay schedule
# ---------------------------------------------------------------------------

@dataclass
class Bay:
    """One vertical stack of openings at a given offset along an elevation."""

    offset: float
    kind: str = "window"                  # window|door|bay|blank|oriel
    floors: tuple[int, ...] = (1, 2, 3)
    spec: dict = field(default_factory=dict)


#: Floor deck heights and the window height used on each.
FLOORS = {
    1: (config.Z_F1, config.WIN_H_1),
    2: (config.Z_F2, config.WIN_H_2),
    3: (config.Z_F3, config.WIN_H_3),
}


def window_spec(floor: int, **overrides) -> W.WindowSpec:
    """The house's standard window for a floor, with per-bay overrides."""
    _, height = FLOORS[floor]
    base = dict(width=config.WIN_W, height=height, wall_t=WALL_T)
    if floor == 1:
        base.update(upper_lights=(2, 2), hood="cornice", hood_brackets=True,
                    corner_blocks=True, height=config.WIN_H_1, width=1.24)
    elif floor == 2:
        base.update(hood="cornice", hood_brackets=False, corner_blocks=True)
    else:
        base.update(head="segmental", upper_lights=(1, 1), hood="label",
                    width=1.02)
    base.update(overrides)
    return W.WindowSpec(**base)


# ---------------------------------------------------------------------------
# Wall construction
# ---------------------------------------------------------------------------

def _wall_slab(name: str, elev: Elevation, z0: float, z1: float,
               col) -> bpy.types.Object:
    """One face of a block, as a slab whose outer surface is the wall face."""
    b = elev.block
    nx, ny = elev.normal
    if elev.side in ("south", "north"):
        cy = b.y1 - WALL_T / 2 if ny > 0 else b.y0 + WALL_T / 2
        return mk.box(name, (b.cx, cy, (z0 + z1) / 2), (b.sx, WALL_T, z1 - z0),
                      col)
    cx = b.x1 - WALL_T / 2 if nx > 0 else b.x0 + WALL_T / 2
    return mk.box(name, (cx, b.cy, (z0 + z1) / 2), (WALL_T, b.sy, z1 - z0), col)


def _cut_opening(wall: bpy.types.Object, elev: Elevation, offset: float,
                 spec: W.WindowSpec, z: float, col) -> None:
    """Punch a window-shaped hole through a wall slab."""
    outline = mk.offset_polygon(W.opening_outline(spec), 0.005)
    cutter = mk.prism_y(f"{wall.name}.cut", outline,
                        -WALL_T - 0.25, 0.25, col)
    px, py, _ = elev.point(offset, 0.0)
    mk.transform(cutter, Matrix.Translation((px, py, z))
                 @ Matrix.Rotation(elev.yaw, 4, 'Z'))
    mk.boolean(wall, cutter)


# ---------------------------------------------------------------------------
# Horizontal trim courses
# ---------------------------------------------------------------------------

def _block_outline(b: config.Block, inflate: float = 0.0
                   ) -> list[tuple[float, float]]:
    return [(b.x0 - inflate, b.y0 - inflate), (b.x1 + inflate, b.y0 - inflate),
            (b.x1 + inflate, b.y1 + inflate), (b.x0 - inflate, b.y1 + inflate)]


def _course(name: str, b: config.Block, z: float, profile, inflate: float,
            col) -> bpy.types.Object:
    """A moulded band running right round a block."""
    path = [(x, y, z) for x, y in _block_outline(b, inflate)]
    obj = mk.sweep(name, profile, path, closed_path=True, col=col)
    mk.recalc_normals(obj)
    return obj


def water_table(b: config.Block, lib: Library, col) -> bpy.types.Object:
    o = _course(f"{b.name}.watertable", b, config.Z_F1 - 0.30,
                orn.water_table(0.20, 0.44), 0.06, col)
    mk.set_material(o, lib.stone)
    return o


def belt_course(name: str, b: config.Block, z: float, lib: Library, col
                ) -> bpy.types.Object:
    o = _course(name, b, z, orn.cyma_reversa(0.16, 0.30), 0.02, col)
    mk.set_material(o, lib.trim)
    return o


def main_cornice(b: config.Block, z: float, lib: Library, col,
                 brackets: bool = True, dentils: bool = True,
                 bracket_pitch: float = 1.42) -> list[bpy.types.Object]:
    """Frieze, dentil course, bracketed eaves and the crowning cornice."""
    parts: list[bpy.types.Object] = []
    depth = config.CORNICE_DEPTH
    height = 0.86

    frieze = mk.prism(f"{b.name}.frieze", _block_outline(b, 0.05),
                      z - 0.62, z, col)
    mk.set_material(frieze, lib.trim)
    parts.append(frieze)

    if dentils:
        path = [(x, y, z - 0.10) for x, y in _block_outline(b, 0.11)]
        d = orn.dentil_course(f"{b.name}.dentils", path, 0.105, 0.085,
                              0.16, 0.17, closed=True, col=col)
        mk.set_material(d, lib.trim_crisp)
        parts.append(d)

    if brackets:
        proto = orn.bracket(f"{b.name}.brproto", depth * 0.66, 0.78, 0.075,
                            "scroll", col=col)
        mk.set_material(proto, lib.trim)
        made = []
        for side in ("south", "north", "east", "west"):
            elev = Elevation(b, side)
            nx, ny = elev.normal
            # A bracket is a sawn board standing edge-on to the wall, so its
            # silhouette plane has to be perpendicular to the face.  Its local
            # +X is the projection direction; the extra quarter turn past the
            # window yaw is what points that out of the wall.
            yaw = elev.yaw + math.pi / 2
            count = max(2, int(elev.span / bracket_pitch))
            for i in range(count + 1):
                off = -elev.span / 2 + elev.span * i / count
                px, py, _ = elev.point(off, 0.0)
                made.append(mk.instance(
                    proto, f"{b.name}.br.{side}.{i}",
                    (px + nx * 0.02, py + ny * 0.02, z - 0.02),
                    rotation=(0.0, 0.0, yaw), col=col))
        bpy.data.objects.remove(proto)
        joined = mk.join(made, f"{b.name}.brackets", col)
        mk.set_material(joined, lib.trim)
        parts.append(joined)

    cor = _course(f"{b.name}.cornice", b, z,
                  orn.cornice_profile(depth, height), 0.10, col)
    mk.set_material(cor, lib.trim)
    parts.append(cor)
    return parts


def corner_boards(b: config.Block, z0: float, z1: float, lib: Library, col
                  ) -> bpy.types.Object:
    """The wide flat boards that stop the clapboard at each external angle."""
    parts = []
    w = CORNER_BOARD
    for sx in (-1, 1):
        for sy in (-1, 1):
            x = b.x1 if sx > 0 else b.x0
            y = b.y1 if sy > 0 else b.y0
            parts.append(mk.box(f"{b.name}.cb{sx}{sy}a",
                                (x - sx * w / 2, y + sy * 0.028,
                                 (z0 + z1) / 2), (w, 0.056, z1 - z0), col))
            parts.append(mk.box(f"{b.name}.cb{sx}{sy}b",
                                (x + sx * 0.028, y - sy * (w / 2 + 0.028),
                                 (z0 + z1) / 2), (0.056, w, z1 - z0), col))
    obj = mk.join(parts, f"{b.name}.cornerboards", col)
    mk.set_material(obj, lib.trim)
    return obj


def plinth(b: config.Block, lib: Library, col) -> list[bpy.types.Object]:
    """Rusticated stone basement, stepped out below the water table."""
    parts = []
    base = mk.prism(f"{b.name}.plinth", _block_outline(b, 0.16),
                    config.Z_BASE - 0.9, config.Z_F1 - 0.28, col)
    mk.set_material(base, lib.stone_dark)
    parts.append(base)
    # A projecting course at grade reads as the footing.
    foot = mk.prism(f"{b.name}.footing", _block_outline(b, 0.30),
                    config.Z_BASE - 0.9, config.Z_BASE + 0.22, col)
    mk.set_material(foot, lib.stone_dark)
    parts.append(foot)
    return parts


# ---------------------------------------------------------------------------
# Assembling a block
# ---------------------------------------------------------------------------

def build_block(b: config.Block, schedule: dict[str, list[Bay]],
                lib: Library, col, top_floor: int = 3
                ) -> list[bpy.types.Object]:
    """Walls, openings, joinery and trim for one rectangular mass."""
    made: list[bpy.types.Object] = []
    made += plinth(b, lib, col)

    walls: dict[str, bpy.types.Object] = {}
    for side in SIDES:
        elev = Elevation(b, side)
        wall = _wall_slab(f"{b.name}.wall.{side}", elev,
                          config.Z_F1 - 0.34, b.z1, col)
        mk.set_material(wall, lib.body)
        walls[side] = wall

    joinery: list[bpy.types.Object] = []
    for side, bays in schedule.items():
        elev = Elevation(b, side)
        wall = walls[side]
        for bi, bay in enumerate(bays):
            for floor in bay.floors:
                if floor > top_floor:
                    continue
                deck, _ = FLOORS[floor]
                z = deck + config.WIN_SILL
                if bay.kind == "door":
                    continue                      # the porch code handles it
                if bay.kind == "blank":
                    continue
                spec = window_spec(floor, **bay.spec.get(floor, {}))
                spec.wall_t = WALL_T
                _cut_opening(wall, elev, bay.offset, spec, z, col)
                name = f"{b.name}.{side}.{bi}.f{floor}"
                obj = W.build(name, spec, lib, col)
                px, py, _ = elev.point(bay.offset, 0.0)
                W.place(obj, px, py, z, elev.yaw)
                joinery.append(obj)

    made += list(walls.values())
    made += joinery
    made.append(corner_boards(b, config.Z_F1 - 0.30, b.z1 - 0.60, lib, col))
    made.append(water_table(b, lib, col))
    made.append(belt_course(f"{b.name}.belt1", b, config.Z_F2 - 0.30, lib, col))
    if top_floor >= 3:
        made.append(belt_course(f"{b.name}.belt2", b, config.Z_F3 - 0.28,
                                lib, col))
    return made


# ---------------------------------------------------------------------------
# The house's own schedule
# ---------------------------------------------------------------------------

def main_schedule() -> dict[str, list[Bay]]:
    """Window layout for the principal block.

    The south front is deliberately asymmetric: the tower takes the west end,
    the entrance sits off centre, and a canted bay lights the drawing room.
    """
    return {
        "south": [
            Bay(-2.30, floors=(1, 2, 3)),
            Bay(1.10, "door", floors=(2, 3)),
            Bay(4.40, floors=(1, 2, 3)),
            Bay(7.30, floors=(1, 2, 3)),
        ],
        "east": [
            Bay(-4.30, floors=(2, 3)),
            Bay(-0.20, floors=(2, 3)),
            Bay(4.10, floors=(1, 2, 3)),
        ],
        "west": [
            Bay(-3.90, floors=(1, 2, 3)),
            Bay(0.00, floors=(2, 3)),
            Bay(3.80, floors=(1, 2, 3)),
        ],
        "north": [
            Bay(-6.20, floors=(1, 2, 3)),
            Bay(-2.10, floors=(1, 2, 3)),
            Bay(2.10, floors=(1, 2, 3)),
            Bay(6.20, floors=(1, 2, 3)),
        ],
    }


def wing_schedule() -> dict[str, list[Bay]]:
    small = {1: dict(width=1.00, hood="label", hood_brackets=False,
                     corner_blocks=False),
             2: dict(width=1.00, hood="label", corner_blocks=False)}
    return {
        "west": [Bay(-2.90, floors=(1, 2), spec=small),
                 Bay(0.00, floors=(1, 2), spec=small),
                 Bay(2.90, floors=(1, 2), spec=small)],
        "east": [Bay(-2.90, floors=(1, 2), spec=small),
                 Bay(2.90, floors=(1, 2), spec=small)],
        "north": [Bay(-3.40, floors=(1, 2), spec=small),
                  Bay(0.00, floors=(1, 2), spec=small),
                  Bay(3.40, floors=(1, 2), spec=small)],
    }


def pavilion_schedule() -> dict[str, list[Bay]]:
    return {
        "east": [Bay(-2.10, floors=(1, 2, 3)), Bay(2.10, floors=(1, 2, 3))],
        "south": [Bay(0.00, floors=(1, 2, 3))],
        "north": [Bay(0.00, floors=(1, 2, 3))],
    }


def build(lib: Library, col=None) -> list[bpy.types.Object]:
    """Every wall, opening and trim course of the three blocks."""
    made: list[bpy.types.Object] = []
    made += build_block(config.MAIN, main_schedule(), lib, col, top_floor=3)
    made += build_block(config.WING, wing_schedule(), lib, col, top_floor=2)
    made += build_block(config.PAVILION, pavilion_schedule(), lib, col,
                        top_floor=3)
    made += main_cornice(config.MAIN, config.Z_CORNICE, lib, col)
    made += main_cornice(config.WING, config.WING.z1, lib, col,
                         dentils=False, bracket_pitch=1.55)
    made += main_cornice(config.PAVILION, config.PAVILION.z1, lib, col,
                         bracket_pitch=1.30)
    return made
