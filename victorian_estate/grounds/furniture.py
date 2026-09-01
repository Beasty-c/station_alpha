"""
The small things that make grounds look inhabited: gas lamp standards along
the drive, park benches, urns on plinths, statuary, and the kitchen garden.

Nothing here is architecturally important, but a park with no lamps, seats or
ornament reads as a landscape rather than as somebody's garden.
"""

from __future__ import annotations

import math
import random

import bpy
from mathutils import Matrix

from ..core import config, meshkit as mk, ornament as orn
from ..core.materials import Library
from . import planting as P, terrain as T


# ---------------------------------------------------------------------------
# Gas lamp standard
# ---------------------------------------------------------------------------

def lamp_standard(name: str, x: float, y: float, lib: Library, col,
                  height: float = 3.2, lit: bool = False, segments: int = 14
                  ) -> bpy.types.Object:
    """A cast-iron lamp column with a fluted shaft and a glazed lantern."""
    parts = []
    z = T.height(x, y)
    h = height
    column = mk.lathe(f"{name}.column", [
        (0.0, 0.0), (0.205, 0.0), (0.205, 0.07), (0.155, 0.13), (0.140, 0.22),
        (0.104, 0.30), (0.082, 0.42), (0.072, h * 0.30), (0.058, h * 0.62),
        (0.052, h * 0.80), (0.072, h * 0.83), (0.086, h * 0.855),
        (0.060, h * 0.875), (0.060, h * 0.90), (0.098, h * 0.925),
        (0.098, h * 0.95), (0.0, h * 0.95),
    ], segments, center=(x, y, z), col=col)
    mk.shade_smooth(column, math.radians(34))
    mk.set_material(column, lib.iron)
    parts.append(column)

    # The lantern: a tapered glazed box with a vented cap.
    base_z = z + h * 0.95
    lw = 0.21
    frame = []
    for k in range(4):
        a = math.pi / 2 * k + math.pi / 4
        post = mk.box(f"{name}.lp{k}", (0, 0, 0), (0.022, 0.022, 0.46), col)
        mk.transform(post, Matrix.Translation(
            (x + lw * 0.72 * math.cos(a), y + lw * 0.72 * math.sin(a),
             base_z + 0.23)))
        frame.append(post)
    for zz in (base_z + 0.02, base_z + 0.44):
        ring = mk.lathe(f"{name}.ring{zz:.2f}",
                        [(lw * 0.62, 0.0), (lw * 0.78, 0.0),
                         (lw * 0.78, 0.06), (lw * 0.62, 0.06)], 4,
                        start=math.pi / 4, center=(x, y, zz), col=col)
        frame.append(ring)
    f = mk.join(frame, f"{name}.lantern", col)
    mk.set_material(f, lib.iron)
    parts.append(f)

    glass = mk.lathe(f"{name}.glass",
                     [(0.0, 0.0), (lw * 0.66, 0.0), (lw * 0.66, 0.42),
                      (0.0, 0.42)], 4, start=math.pi / 4,
                     center=(x, y, base_z + 0.02), col=col)
    mk.set_material(glass, lib.lamp if lit else lib.glass)
    parts.append(glass)

    cap = mk.lathe(f"{name}.cap", [
        (lw * 0.96, 0.0), (lw * 0.80, 0.11), (lw * 0.44, 0.21),
        (lw * 0.30, 0.26), (lw * 0.30, 0.32), (0.0, 0.38)], 8,
        center=(x, y, base_z + 0.44), col=col)
    mk.set_material(cap, lib.iron)
    parts.append(cap)
    fin = orn.finial(f"{name}.finial", 0.24, 0.040, 10, "acorn", col)
    mk.transform(fin, Matrix.Translation((x, y, base_z + 0.80)))
    mk.set_material(fin, lib.iron)
    parts.append(fin)
    return mk.join(parts, name, col)


# ---------------------------------------------------------------------------
# Seats and ornament
# ---------------------------------------------------------------------------

def bench(name: str, x: float, y: float, yaw: float, lib: Library, col,
          length: float = 1.85) -> bpy.types.Object:
    """A park seat: cast-iron ends, slatted seat and back."""
    parts = []
    z = T.height(x, y)
    seat_z = 0.44
    slats = []
    for i in range(5):
        s = mk.box(f"{name}.seat{i}", (0.0, -0.10 + i * 0.085, seat_z),
                   (length, 0.070, 0.028), col)
        slats.append(s)
    for i in range(4):
        b = mk.box(f"{name}.back{i}", (0, 0, 0), (length, 0.060, 0.026), col)
        mk.transform(b, Matrix.Translation(
            (0.0, -0.16, seat_z + 0.16 + i * 0.135))
            @ Matrix.Rotation(math.radians(16), 4, 'X'))
        slats.append(b)
    wood = mk.join(slats, f"{name}.slats", col)
    mk.set_material(wood, lib.wood_oak)
    parts.append(wood)

    for sgn in (-1, 1):
        # A scrolled iron end, drawn as a flat silhouette.
        outline = [(-0.03, 0.0), (0.30, 0.0), (0.30, 0.06), (0.05, 0.10),
                   (0.05, seat_z - 0.03), (0.34, seat_z - 0.03),
                   (0.34, seat_z + 0.02), (0.02, seat_z + 0.02),
                   (-0.14, seat_z + 0.30), (-0.20, seat_z + 0.58),
                   (-0.27, seat_z + 0.60), (-0.21, seat_z + 0.28),
                   (-0.06, seat_z + 0.02), (-0.30, seat_z + 0.02),
                   (-0.30, seat_z - 0.03), (-0.05, seat_z - 0.03),
                   (-0.05, 0.10), (-0.30, 0.06), (-0.30, 0.0)]
        end = mk.prism_x(f"{name}.end{sgn}",
                         [(oy, oz) for oy, oz in outline],
                         sgn * (length / 2 - 0.02),
                         sgn * (length / 2 + 0.03), col)
        mk.set_material(end, lib.iron)
        parts.append(end)

    obj = mk.join(parts, name, col)
    mk.transform(obj, Matrix.Translation((x, y, z)) @ Matrix.Rotation(yaw, 4, 'Z'))
    return obj


def urn_on_plinth(name: str, x: float, y: float, lib: Library, col,
                  height: float = 1.42, segments: int = 18
                  ) -> bpy.types.Object:
    """A stone urn on a moulded pedestal, for terminating a walk."""
    parts = []
    z = T.height(x, y)
    ph = height * 0.55
    plinth = mk.box(f"{name}.plinth", (x, y, z + ph / 2), (0.62, 0.62, ph), col)
    parts.append(plinth)
    for zz, w in ((z + 0.06, 0.80), (z + ph - 0.06, 0.76)):
        band = mk.box(f"{name}.band{zz:.2f}", (x, y, zz), (w, w, 0.12), col)
        parts.append(band)
    u = orn.finial(f"{name}.urn", height * 0.62, height * 0.20, segments,
                   "urn", col)
    mk.transform(u, Matrix.Translation((x, y, z + ph)))
    parts.append(u)
    obj = mk.join(parts, name, col)
    mk.set_material(obj, lib.stone)
    return obj


def statue(name: str, x: float, y: float, yaw: float, lib: Library, col,
           height: float = 2.9, seed: int = 0) -> bpy.types.Object:
    """A classical figure on a pedestal.

    Deliberately impressionistic - a weathered marble silhouette at twenty
    metres, which is the only distance it is ever seen from.
    """
    rng = random.Random(seed)
    parts = []
    z = T.height(x, y)
    ph = height * 0.42
    ped = mk.box(f"{name}.ped", (x, y, z + ph / 2), (0.78, 0.78, ph), col)
    parts.append(ped)
    for zz, w in ((z + 0.08, 0.98), (z + ph - 0.08, 0.92)):
        parts.append(mk.box(f"{name}.cap{zz:.2f}", (x, y, zz), (w, w, 0.16),
                            col))

    fh = height - ph
    # Body: a tapering lathe, leaning slightly, with a draped mass at the base.
    # Vary the figure with the seed - a pair of identical statues at opposite
    # ends of a walk reads as a copy-paste, which is exactly what it was.
    def w(base):
        return base * rng.uniform(0.88, 1.14)

    body = mk.lathe(f"{name}.body", [
        (w(0.34), 0.0), (w(0.30), fh * 0.10), (w(0.26), fh * 0.30),
        (w(0.20), fh * 0.46), (w(0.16), fh * 0.56), (w(0.19), fh * 0.62),
        (w(0.21), fh * 0.72), (w(0.17), fh * 0.80), (w(0.10), fh * 0.84),
        (w(0.13), fh * 0.90), (w(0.11), fh * 0.96), (0.0, fh),
    ], 14, center=(x, y, z + ph), col=col)
    mk.shade_smooth(body, math.radians(46))
    parts.append(body)
    # An arm, and a fold of drapery.
    arm = mk.lathe(f"{name}.arm", [(0.075, 0.0), (0.065, 0.34), (0.05, 0.62),
                                   (0.0, 0.70)], 8, col=col)
    mk.transform(arm, Matrix.Translation(
        (x, y, z + ph + fh * rng.uniform(0.58, 0.74)))
        @ Matrix.Rotation(yaw + rng.uniform(-0.5, 0.5), 4, 'Z')
        @ Matrix.Rotation(math.radians(rng.uniform(40, 74)), 4, 'Y'))
    mk.shade_smooth(arm, math.radians(46))
    parts.append(arm)
    obj = mk.join(parts, name, col)
    mk.set_material(obj, lib.marble)
    return obj


# ---------------------------------------------------------------------------
# Kitchen garden
# ---------------------------------------------------------------------------

def kitchen_garden(lib: Library, col) -> list[bpy.types.Object]:
    """A walled kitchen garden on the service side: cross paths, vegetable
    beds in rotation, cold frames and espaliered fruit against the wall."""
    from . import hardscape
    made = []
    cx, cy = 26.0, -34.0
    sx, sy = 30.0, 22.0
    h, t = 2.6, 0.45

    corners = [(cx - sx / 2, cy - sy / 2), (cx + sx / 2, cy - sy / 2),
               (cx + sx / 2, cy + sy / 2), (cx - sx / 2, cy + sy / 2)]
    for i in range(4):
        a, b = corners[i], corners[(i + 1) % 4]
        made += hardscape._wall_run(f"kitchen.wall{i}", a, b, lib, col, h, t,
                                    pier_pitch=11.0)

    made.append(T.ribbon("kitchen.walkEW",
                         [(cx - sx / 2 + 1, cy), (cx + sx / 2 - 1, cy)],
                         1.8, lib, col, material=lib.gravel, layer=10))
    made.append(T.ribbon("kitchen.walkNS",
                         [(cx, cy - sy / 2 + 1), (cx, cy + sy / 2 - 1)],
                         1.8, lib, col, material=lib.gravel, layer=11))

    # Four quarters in rotation, each row a different crop and each bed a
    # slightly different width - a kitchen garden is worked, not set out once.
    rng = random.Random(77)
    crops = [(0.16, 0.30, 0.10), (0.22, 0.36, 0.14), (0.14, 0.26, 0.09),
             (0.30, 0.34, 0.16)]
    for qi, (sxx, syy) in enumerate([(-1, -1), (1, -1), (1, 1), (-1, 1)]):
        qx = cx + sxx * (sx / 4 + 0.5)
        qy = cy + syy * (sy / 4 + 0.5)
        for row in range(4):
            ry = qy - 2.6 + row * 1.75
            half = rng.uniform(4.4, 5.3)
            depth = rng.uniform(0.5, 0.7)
            made += P.bed(f"kitchen.bed{qi}{row}",
                          [(qx - half, ry - depth), (qx + half, ry - depth),
                           (qx + half, ry + depth), (qx - half, ry + depth)],
                          lib, col, seed=qi * 40 + row,
                          density=rng.uniform(2.8, 4.2), height=0.36,
                          colours=(crops[(qi + row) % 4],))

    # Cold frames along the south wall.
    frames = []
    for i in range(5):
        fx = cx - 9.0 + i * 4.4
        fy = cy - sy / 2 + 2.0
        z = T.height(fx, fy)
        box = mk.box(f"kitchen.frame{i}", (fx, fy, z + 0.28),
                     (3.2, 1.5, 0.56), col)
        mk.set_material(box, lib.brick)
        frames.append(box)
        lid = mk.box(f"kitchen.lid{i}", (0, 0, 0), (3.1, 1.6, 0.05), col)
        mk.transform(lid, Matrix.Translation((fx, fy, z + 0.62))
                     @ Matrix.Rotation(math.radians(-12), 4, 'X'))
        mk.set_material(lid, lib.glass)
        frames.append(lid)
    made += frames

    # A potting shed in the corner.
    shed_x, shed_y = cx + sx / 2 - 4.0, cy + sy / 2 - 3.0
    z = T.height(shed_x, shed_y)
    shed = mk.prism("kitchen.shed",
                    [(shed_x - 3.0, shed_y - 2.2), (shed_x + 3.0, shed_y - 2.2),
                     (shed_x + 3.0, shed_y + 2.2), (shed_x - 3.0, shed_y + 2.2)],
                    z, z + 2.6, col)
    mk.set_material(shed, lib.brick)
    made.append(shed)
    from .outbuildings import _slated_gable
    made += _slated_gable("kitchen.shedroof", shed_x, shed_y, 6.0, 4.4,
                          z + 2.6, 40.0, lib, col, along_x=True, overhang=0.35)
    return made


# ---------------------------------------------------------------------------
# Placement
# ---------------------------------------------------------------------------

def build(lib: Library, col, lit: bool = False) -> list[bpy.types.Object]:
    made: list[bpy.types.Object] = []
    cy, r = config.DRIVE_CIRCLE_CY, config.DRIVE_CIRCLE_R

    # Lamps: paired at the gates, round the carriage sweep, and at the steps.
    lamp_spots = [(-4.8, config.GATE_Y - 2.5), (4.8, config.GATE_Y - 2.5)]
    for i in range(6):
        a = math.tau * i / 6 + 0.35
        lamp_spots.append((math.cos(a) * (r + 4.2),
                           cy + math.sin(a) * (r + 4.2)))
    lamp_spots += [(-4.4, 14.9), (6.6, 14.9)]
    lamps = [lamp_standard(f"lamp{i}", x, y, lib, col, lit=lit)
             for i, (x, y) in enumerate(lamp_spots)]
    made.append(mk.join(lamps, "lamps", col))

    seats = [
        bench("bench.terrace1", -11.0, 12.2, math.pi, lib, col),
        bench("bench.terrace2", 9.6, 12.2, math.pi, lib, col),
        bench("bench.parterre", config.PARTERRE_CX + 12.6,
              config.PARTERRE_CY, -math.pi / 2, lib, col),
        bench("bench.parterre2", config.PARTERRE_CX - 12.6,
              config.PARTERRE_CY, math.pi / 2, lib, col),
        bench("bench.pond", config.POND_XY[0] - 17.0, config.POND_XY[1],
              math.pi / 2, lib, col),
        bench("bench.gazebo", config.GAZEBO_XY[0] - 5.0,
              config.GAZEBO_XY[1] - 1.0, math.pi / 2, lib, col),
    ]
    made.append(mk.join(seats, "benches", col))

    urns = [urn_on_plinth(f"urn.walk{i}", x, y, lib, col)
            for i, (x, y) in enumerate([
                (-16.4, 12.6), (14.6, 12.6),
                (config.PARTERRE_CX, config.PARTERRE_CY + 17.5),
                (config.PARTERRE_CX, config.PARTERRE_CY - 17.5)])]
    made.append(mk.join(urns, "urns", col))

    made.append(statue("statue.lawn", 30.0, 26.0, math.radians(210), lib, col,
                       seed=1))
    made.append(statue("statue.vista", config.PARTERRE_CX - 21.0,
                       config.PARTERRE_CY, math.radians(90), lib, col, seed=2))

    made += kitchen_garden(lib, col)
    return made
