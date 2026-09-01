"""
Just enough interior to give the windows depth.

Nothing here is meant to be walked through.  The point is that a window on an
empty shell reads as a hole: you want a floor a little way in so the eye stops,
something warm behind the glass at dusk, and the vertical break of a drape at
the reveal.  Three planes and a pair of curtains per opening do all of that
for a fraction of the cost of a modelled room.
"""

from __future__ import annotations

import math
import random

import bpy
from mathutils import Matrix

from ..core import config, meshkit as mk
from ..core.materials import Library
from .shell import FLOORS, WALL_T, Elevation, Bay


def floors(b: config.Block, lib: Library, col, top_floor: int = 3
           ) -> list[bpy.types.Object]:
    """Floor decks and ceilings inside a block, inset from the walls."""
    made = []
    inset = WALL_T + 0.02
    poly = [(b.x0 + inset, b.y0 + inset), (b.x1 - inset, b.y0 + inset),
            (b.x1 - inset, b.y1 - inset), (b.x0 + inset, b.y1 - inset)]
    for floor in range(1, top_floor + 1):
        deck, _ = FLOORS[floor]
        slab = mk.prism(f"{b.name}.floor{floor}", poly, deck - 0.30, deck, col)
        mk.set_material(slab, lib.wood_dark)
        made.append(slab)
        # A pale ceiling above, so an upward view through a window is not void.
        ceil_z = deck + (config.FLOOR_1 if floor == 1 else config.FLOOR_2) - 0.42
        ceil = mk.prism(f"{b.name}.ceiling{floor}", poly, ceil_z, ceil_z + 0.16,
                        col)
        mk.set_material(ceil, lib.trim)
        made.append(ceil)
    return made


def drapes(name: str, width: float, height: float, lib: Library, col,
           folds: int = 7, gather: float = 0.34, setback: float = 0.46
           ) -> bpy.types.Object:
    """A pair of gathered curtains, drawn back to either side of a reveal.

    ``setback`` puts them behind the wall rather than inside its thickness -
    curtains hang on the room side of the reveal, and seeing them through the
    glass at a slight distance is what gives the opening depth.
    """
    parts = []
    for sgn in (-1, 1):
        panel_w = width * gather
        verts, faces = [], []
        rings = 9
        for r in range(rings + 1):
            t = r / rings
            z = height * (1.0 - t)
            # Curtains hang wider at the hem and swing back toward the wall.
            spread = panel_w * (0.72 + 0.42 * t)
            depth = 0.10 + 0.11 * t
            for f in range(folds + 1):
                u = f / folds
                wobble = math.sin(u * math.pi * folds) * 0.5 + 0.5
                x = sgn * (width / 2 - spread * (1.0 - u))
                y = -depth * (0.35 + 0.65 * wobble)
                verts.append((x, y, z))
        for r in range(rings):
            a = r * (folds + 1)
            b = a + folds + 1
            for f in range(folds):
                faces.append((a + f, b + f, b + f + 1, a + f + 1))
        panel = mk.obj_from(f"{name}.panel{sgn}", verts, faces, col=col)
        mk.solidify(panel, 0.02)
        mk.shade_smooth(panel, math.radians(60))
        mk.set_material(panel, lib.drape)
        parts.append(panel)

    pole = mk.lathe(f"{name}.pole", [(0.022, 0.0), (0.022, width + 0.16)],
                    8, col=col)
    mk.transform(pole, Matrix.Translation((-(width + 0.16) / 2, -0.10, height))
                 @ Matrix.Rotation(math.pi / 2, 4, 'Y'))
    mk.set_material(pole, lib.gilt)
    parts.append(pole)
    obj = mk.join(parts, name, col)
    mk.transform(obj, Matrix.Translation((0.0, -setback, 0.0)))
    return obj


def dress_windows(schedule: dict[str, list[Bay]], b: config.Block,
                  lib: Library, col, fraction: float = 0.55, seed: int = 5,
                  lit_floors: tuple[int, ...] = (1, 2)
                  ) -> list[bpy.types.Object]:
    """Hang drapes behind a share of a block's openings."""
    from . import windows as W
    rng = random.Random(seed)
    made = []
    for side, bays in schedule.items():
        elev = Elevation(b, side)
        for bi, bay in enumerate(bays):
            if bay.kind not in ("window",):
                continue
            for floor in bay.floors:
                if floor not in lit_floors or rng.random() > fraction:
                    continue
                deck, _ = FLOORS[floor]
                spec_h = config.WIN_H_1 if floor == 1 else config.WIN_H_2
                d = drapes(f"{b.name}.drape.{side}.{bi}.{floor}",
                           config.WIN_W + 0.34, spec_h + 0.22, lib, col)
                px, py, _ = elev.point(bay.offset, 0.0)
                W.place(d, px, py, deck + config.WIN_SILL - 0.12, elev.yaw)
                made.append(d)
    return made


def build(lib: Library, col) -> list[bpy.types.Object]:
    from .shell import main_schedule, pavilion_schedule, wing_schedule
    made: list[bpy.types.Object] = []
    made += floors(config.MAIN, lib, col, 3)
    made += floors(config.WING, lib, col, 2)
    made += floors(config.PAVILION, lib, col, 3)
    made += dress_windows(main_schedule(), config.MAIN, lib, col)
    made += dress_windows(pavilion_schedule(), config.PAVILION, lib, col,
                          fraction=0.4, seed=9)
    return made
