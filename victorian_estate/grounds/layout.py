"""
The estate plan: where the trees, hedges and beds actually go.

A park is not scattered at random.  Specimen trees stand alone on the lawn
where they can be seen from the house, an avenue lines the approach, the
service side is screened by a belt of planting, and the ground immediately in
front of the principal rooms is kept deliberately open so the view out is not
blocked.  This module encodes those rules as exclusion zones and placement
sets rather than leaving it to a uniform scatter.
"""

from __future__ import annotations

import math
import random

import bpy

from ..core import config, meshkit as mk
from ..core.materials import Library
from . import planting as P, terrain as T

#: Circles (x, y, radius) that must stay clear of trees.
KEEP_CLEAR = [
    (0.0, 0.0, 26.0),                      # the house and its terrace
    (-2.0, -11.4, 16.0),                   # service wing
    (11.6, 2.6, 14.0),                     # pavilion
    (0.0, config.DRIVE_CIRCLE_CY, 21.0),   # the carriage turn
    (0.0, 52.0, 16.0),                     # the open sweep of the approach
    (0.0, 74.0, 13.0),
    (0.0, 92.0, 12.0),                     # the gateway
    (config.PARTERRE_CX, config.PARTERRE_CY, 20.0),
    (config.CARRIAGE_HOUSE_XY[0], config.CARRIAGE_HOUSE_XY[1], 15.0),
    (config.CONSERVATORY_XY[0], config.CONSERVATORY_XY[1], 11.0),
    (config.GAZEBO_XY[0], config.GAZEBO_XY[1], 9.0),
    (config.POND_XY[0], config.POND_XY[1], 15.0),
    (26.0, -34.0, 22.0),                   # the walled kitchen garden
    (19.0, 2.6, 12.0),                     # the carriage porch and its spur
    (-12.5, config.GATE_Y - 7.0, 13.0),    # the gate lodge
]

#: The orchard: a regular grid, which is how an orchard is actually planted.
ORCHARD = (-56.0, -26.0, 8, 5, 7.5)        # cx, cy, cols, rows, spacing

#: The view corridor south from the front door is kept open.
VISTA = (-13.0, 12.0, 13.0, 100.0)         # x0, y0, x1, y1


def _clear(x: float, y: float, margin: float = 0.0) -> bool:
    for cx, cy, r in KEEP_CLEAR:
        if math.hypot(x - cx, y - cy) < r + margin:
            return False
    x0, y0, x1, y1 = VISTA
    if x0 < x < x1 and y0 < y < y1:
        return False
    return True


def scatter(count: int, seed: int, bounds: float = config.SITE_HALF - 14.0,
            spacing: float = 11.0, margin: float = 0.0
            ) -> list[tuple[float, float]]:
    """Blue-noise-ish placement: rejected if too close to an earlier pick."""
    rng = random.Random(seed)
    picks: list[tuple[float, float]] = []
    attempts = 0
    while len(picks) < count and attempts < count * 260:
        attempts += 1
        x = rng.uniform(-bounds, bounds)
        y = rng.uniform(-bounds, bounds)
        if not _clear(x, y, margin):
            continue
        if any(math.hypot(x - px, y - py) < spacing for px, py in picks):
            continue
        picks.append((x, y))
    return picks


def avenue(spacing: float = 12.5) -> list[tuple[float, float]]:
    """Paired limes flanking the approach, set back from the gravel."""
    pts = []
    offset = config.DRIVE_WIDTH / 2 + 5.2
    y = config.DRIVE_CIRCLE_CY + config.DRIVE_CIRCLE_R + 8.0
    while y < config.GATE_Y - 8.0:
        # Follow the drive's gentle curve so the avenue stays parallel to it.
        t = (y - 45.0) / (config.GATE_Y - 45.0)
        cx = -3.2 * math.sin(math.pi * max(0.0, min(1.0, t)))
        pts.append((cx - offset, y))
        pts.append((cx + offset, y))
        y += spacing
    return pts


def orchard_positions() -> list[tuple[float, float]]:
    """A quincunx of fruit trees - the rows offset so the grid reads as
    planted rather than scattered."""
    cx, cy, cols, rows, pitch = ORCHARD
    pts = []
    for r in range(rows):
        for c in range(cols):
            x = cx + (c - (cols - 1) / 2) * pitch + (pitch / 2 if r % 2 else 0)
            y = cy + (r - (rows - 1) / 2) * pitch
            pts.append((x, y))
    return pts


def parterre(lib: Library, col) -> list[bpy.types.Object]:
    """A formal box parterre: four quarters on gravel walks, urns at the
    crossings, and a sundial at the centre."""
    made = []
    cx, cy = config.PARTERRE_CX, config.PARTERRE_CY
    half = config.PARTERRE_SIZE / 2
    walk = 2.3

    # Layers keep the four crossings of the walks from z-fighting.
    made.append(T.ribbon("parterre.walkNS", [(cx, cy - half), (cx, cy + half)],
                         walk, lib, col, material=lib.gravel, layer=6))
    made.append(T.ribbon("parterre.walkEW", [(cx - half, cy), (cx + half, cy)],
                         walk, lib, col, material=lib.gravel, layer=7))
    for sgn in (-1, 1):
        made.append(T.ribbon(f"parterre.edge{sgn}",
                             [(cx - half, cy + sgn * half),
                              (cx + half, cy + sgn * half)], walk, lib, col,
                             material=lib.gravel, layer=8))
        made.append(T.ribbon(f"parterre.side{sgn}",
                             [(cx + sgn * half, cy - half),
                              (cx + sgn * half, cy + half)], walk, lib, col,
                             material=lib.gravel, layer=9))

    quarter = half - walk
    for qi, (sx, sy) in enumerate([(-1, -1), (1, -1), (1, 1), (-1, 1)]):
        qx = cx + sx * (walk / 2 + quarter / 2)
        qy = cy + sy * (walk / 2 + quarter / 2)
        h = quarter / 2 - 0.5
        box = [(qx - h, qy - h), (qx + h, qy - h), (qx + h, qy + h),
               (qx - h, qy + h), (qx - h, qy - h)]
        made.append(P.hedge(f"parterre.box{qi}", box, lib, col,
                            height=0.55, width=0.52, seed=qi))
        # A smaller hedge ring inside, with the bed between the two.
        g = h * 0.46
        inner = [(qx - g, qy - g), (qx + g, qy - g), (qx + g, qy + g),
                 (qx - g, qy + g), (qx - g, qy - g)]
        made.append(P.hedge(f"parterre.inner{qi}", inner, lib, col,
                            height=0.42, width=0.40, seed=qi + 40))
        made += P.bed(f"parterre.bed{qi}",
                      [(qx - h + 0.5, qy - h + 0.5), (qx + h - 0.5, qy - h + 0.5),
                       (qx + h - 0.5, qy + h - 0.5), (qx - h + 0.5, qy + h - 0.5)],
                      lib, col, seed=qi * 17, density=1.5, height=0.34)
        made.append(P.topiary(f"parterre.top{qi}", qx, qy, lib, col,
                              "cone", 1.9, seed=qi))

    for sx in (-1, 1):
        for sy in (-1, 1):
            made.append(P.topiary(f"parterre.corner{sx}{sy}",
                                  cx + sx * (half - 0.4), cy + sy * (half - 0.4),
                                  lib, col, "tiers", 2.4, seed=int(sx * 3 + sy)))

    # A sundial on a baluster pedestal at the crossing.
    z = T.height(cx, cy)
    ped = mk.lathe("parterre.sundial", [
        (0.0, 0.0), (0.62, 0.0), (0.62, 0.14), (0.46, 0.24), (0.30, 0.34),
        (0.22, 0.62), (0.30, 0.90), (0.24, 1.02), (0.42, 1.12), (0.42, 1.20),
        (0.0, 1.20)], 20, center=(cx, cy, z), col=col)
    mk.shade_smooth(ped, math.radians(36))
    mk.set_material(ped, lib.stone)
    made.append(ped)
    plate = mk.lathe("parterre.dial", [(0.0, 0.0), (0.34, 0.0), (0.34, 0.035),
                                       (0.0, 0.035)], 24,
                     center=(cx, cy, z + 1.20), col=col)
    mk.set_material(plate, lib.copper)
    made.append(plate)
    return made


def foundation_planting(lib: Library, col) -> list[bpy.types.Object]:
    """Shrubs and low hedging tucked against the plinth of the house."""
    made = []
    b = config.MAIN
    runs = [
        [(b.x1 + 0.8, b.y1 - 1.0), (b.x1 + 0.8, b.y0 + 2.0)],
        [(b.x0 - 0.8, b.y1 - 4.0), (b.x0 - 0.8, b.y0 + 2.0)],
        [(b.x0 - 0.8, b.y0 - 0.8), (config.WING.x0 - 0.9, b.y0 - 0.8)],
    ]
    for i, run in enumerate(runs):
        made.append(P.hedge(f"foundation.hedge{i}", run, lib, col,
                            height=0.95, width=0.9, seed=i * 11))
    rng = random.Random(4)
    shrubs = []
    for i in range(46):
        side = rng.choice(runs)
        t = rng.random()
        x = side[0][0] + (side[1][0] - side[0][0]) * t + rng.uniform(-0.6, 0.9)
        y = side[0][1] + (side[1][1] - side[0][1]) * t + rng.uniform(-0.9, 0.6)
        shrubs.append(P.topiary(f"foundation.shrub{i}", x, y, lib, col,
                                rng.choice(("ball", "cone")),
                                rng.uniform(1.0, 1.9), seed=i))
    made.append(mk.join(shrubs, "foundation.shrubs", col))
    return made


def creepers(lib: Library, col) -> list[bpy.types.Object]:
    """Ivy on the service elevations and the garden walls.

    Kept off the show fronts: a house like this was maintained, and the
    climbers were let go only where nobody important was looking.
    """
    made = []
    m, w, p = config.MAIN, config.WING, config.PAVILION
    patches = [
        # (centre of the patch foot, outward normal, width, height, stems, seed)
        ((w.x0 - 0.06, w.cy - 0.8, config.Z_BASE), (-1, 0, 0), 7.4, 8.6, 15, 1),
        ((w.x1 + 0.06, w.cy - 1.4, config.Z_BASE), (1, 0, 0), 6.2, 7.8, 13, 2),
        ((w.cx + 0.4, w.y0 - 0.06, config.Z_BASE), (0, -1, 0), 8.6, 8.0, 16, 3),
        ((m.x0 - 0.06, m.y0 + 3.0, config.Z_BASE), (-1, 0, 0), 5.0, 7.0, 11, 4),
        ((m.cx + 4.5, m.y0 - 0.06, config.Z_BASE), (0, -1, 0), 5.6, 7.2, 12, 5),
        ((p.x1 + 0.06, p.y0 + 2.0, config.Z_BASE), (1, 0, 0), 3.6, 6.4, 9, 6),
    ]
    for i, (centre, normal, wd, ht, stems, seed) in enumerate(patches):
        made.append(ivy_patch(f"ivy.house{i}", centre, normal, wd, ht, lib,
                              col, stems, seed))

    # And along the outer face of the kitchen garden's north wall.
    for i in range(3):
        x = 16.0 + i * 8.6
        made.append(ivy_patch(f"ivy.kitchen{i}",
                              (x, -22.76, T.height(x, -23.0) - 0.3),
                              (0, 1, 0), 7.6, 2.4, lib, col, 9, 20 + i))
    return made


def ivy_patch(name, origin, normal, width, height, lib, col, stems, seed):
    return P.ivy(name, origin, normal, width, height, lib, col, stems=stems,
                 density=22.0, seed=seed,
                 coverage=0.72 + (seed % 5) * 0.05)


def build(lib: Library, col, detail: config.Detail) -> list[bpy.types.Object]:
    """All the planting on the estate."""
    made: list[bpy.types.Object] = []

    made += P.plantation(
        "park.specimen", scatter(int(detail.trees * 0.42), seed=11,
                                 spacing=17.0),
        lib, col, species=("oak", "beech", "cedar", "elm"), variants=3,
        seed=101)
    made += P.plantation(
        "park.belt", scatter(int(detail.trees * 0.58), seed=23, spacing=8.5),
        lib, col, species=("lime", "birch", "elm", "poplar"), variants=3,
        seed=202, scale=0.86)
    made += P.plantation("park.avenue", avenue(), lib, col,
                             species=("lime",), variants=3, seed=303,
                             scale=0.92)
    made += P.plantation(
        "park.willows",
        [(config.POND_XY[0] + math.cos(a) * 13.5,
          config.POND_XY[1] + math.sin(a) * 13.5)
         for a in [0.4, 1.3, 2.2, 3.4, 4.6, 5.5]],
        lib, col, species=("willow",), variants=2, seed=404)

    made += P.plantation("park.orchard", orchard_positions(), lib, col,
                             species=("apple", "pear"), variants=4, seed=505)

    made += parterre(lib, col)
    made += foundation_planting(lib, col)
    made += creepers(lib, col)
    return made
