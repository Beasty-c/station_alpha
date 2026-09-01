"""
Everything paved, walled or plumbed: the carriage drive and forecourt, the
fountain, the terrace and its balustrade, the perimeter wall, and the gates.

All of it is laid on the terrain height field rather than on a flat plane, so
the drive rises and falls on the approach the way a real one does.
"""

from __future__ import annotations

import math

import bpy
from mathutils import Matrix, Vector

from ..core import config, meshkit as mk, ornament as orn
from ..core.materials import Library
from . import terrain as T


# ---------------------------------------------------------------------------
# Drive and paths
# ---------------------------------------------------------------------------

def _bezier_path(p0, c0, c1, p1, n=24):
    return orn.bezier(p0, c0, c1, p1, n)


def drive(lib: Library, col) -> list[bpy.types.Object]:
    """The approach from the gate, the sweep round the fountain, and the
    service branch to the carriage house."""
    made = []
    cy = config.DRIVE_CIRCLE_CY
    r = config.DRIVE_CIRCLE_R
    w = config.DRIVE_WIDTH

    # The approach curves gently rather than running dead straight, so the
    # house comes into view obliquely.
    approach = _bezier_path((0.0, config.GATE_Y), (5.0, 78.0),
                            (-7.0, 62.0), (0.0, cy + r), 30)
    made.append(T.ribbon("drive.approach", approach, w, lib, col, layer=0))

    made.append(T.annulus("drive.turn", 0.0, cy, r - w / 2, r + w / 2,
                          lib, col, layer=1))

    # A spur from the turn to the front steps, and one to the porte-cochere
    # side of the house.
    front = _bezier_path((0.0, cy - r), (0.0, cy - r - 4.0),
                         (1.1, 16.0), (1.1, 11.6), 14)
    made.append(T.ribbon("drive.front", front, 4.4, lib, col, layer=2))

    service = _bezier_path((-r * 0.86, cy - r * 0.5), (-24.0, 22.0),
                           (-30.0, -8.0), config.CARRIAGE_HOUSE_XY, 28)
    made.append(T.ribbon("drive.service", service, 4.2, lib, col, layer=2))

    # A spur east to the carriage porch, and on round to the kitchen yard.
    carriage = _bezier_path((r * 0.80, cy - r * 0.58), (20.0, 22.0),
                            (24.0, 12.0), (18.6, 2.6), 22)
    made.append(T.ribbon("drive.portecochere", carriage, 4.4, lib, col,
                         layer=4))
    yard = _bezier_path((18.6, 2.6), (23.0, -6.0), (26.0, -14.0),
                        (26.0, -22.0), 18)
    made.append(T.ribbon("drive.yard", yard, 3.6, lib, col, layer=4))

    # A gravel forecourt in front of the veranda steps.
    made.append(T.ribbon("drive.forecourt",
                         [(-8.0, 13.4), (11.6, 13.4)], 4.6, lib, col, layer=3))

    # Flagged garden walks.
    walks = [
        [(-8.0, 13.0), (-20.0, 10.0), (-30.0, 6.0), (config.PARTERRE_CX + 12,
                                                     config.PARTERRE_CY)],
        [(11.6, 13.0), (20.0, 8.0), (24.0, -2.0)],
        [(0.0, cy + r), (18.0, 40.0), (config.GAZEBO_XY[0],
                                       config.GAZEBO_XY[1])],
    ]
    for i, pts in enumerate(walks):
        made.append(T.ribbon(f"walk{i}", pts, 2.1, lib, col,
                             material=lib.stone, lift=0.03, layer=5))
    return made


# ---------------------------------------------------------------------------
# Terrace
# ---------------------------------------------------------------------------

def balustrade(name: str, path, z: float, lib: Library, col,
               height: float = 1.02, segments: int = 12,
               pier_every: int = 6) -> bpy.types.Object:
    """A stone balustrade: plinth, turned balusters, moulded coping, piers."""
    parts = []
    bal_h = height - 0.30
    proto = orn.baluster(f"{name}.proto", bal_h, 0.155, segments, "vase", col)

    total = 0.0
    for a, b in zip(path, path[1:]):
        d = Vector((b[0] - a[0], b[1] - a[1], 0.0))
        length = d.length
        if length < 1e-6:
            continue
        d.normalize()
        yaw = math.atan2(d.y, d.x)
        mid = Vector(((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, 0.0))

        plinth = mk.box(f"{name}.plinth{total:.1f}", (0, 0, 0),
                        (length, 0.40, 0.22), col)
        mk.transform(plinth, Matrix.Translation(mid + Vector((0, 0, z + 0.11)))
                     @ Matrix.Rotation(yaw, 4, 'Z'))
        parts.append(plinth)

        coping = mk.sweep_straight(
            f"{name}.coping{total:.1f}", orn.cyma_reversa(0.26, 0.20),
            (-length / 2, -0.13, 0.0), (length / 2, -0.13, 0.0), (0, 1, 0),
            col=col)
        mk.transform(coping, Matrix.Translation(
            mid + Vector((0, 0, z + height - 0.20)))
            @ Matrix.Rotation(yaw, 4, 'Z'))
        parts.append(coping)

        n = max(2, int(length / 0.34))
        for k in range(n):
            t = (k + 0.5) / n
            p = Vector((a[0], a[1], 0.0)).lerp(Vector((b[0], b[1], 0.0)), t)
            parts.append(mk.instance(proto, f"{name}.b{total:.1f}.{k}",
                                     (p.x, p.y, z + 0.22), col=col))
        total += length

    for i, (x, y) in enumerate(path):
        if i % pier_every and i not in (0, len(path) - 1):
            continue
        pier = mk.box(f"{name}.pier{i}", (x, y, z + height / 2 + 0.06),
                      (0.62, 0.62, height + 0.12), col)
        parts.append(pier)
        cap = mk.sweep(f"{name}.piercap{i}", orn.cyma_reversa(0.11, 0.13),
                       mk.rect_path(x - 0.31, y - 0.31, x + 0.31, y + 0.31,
                                    z + height + 0.12), closed_path=True,
                       col=col)
        mk.recalc_normals(cap)
        parts.append(cap)
        urn = orn.finial(f"{name}.urn{i}", 0.70, 0.165, 16, "urn", col)
        mk.transform(urn, Matrix.Translation((x, y, z + height + 0.25)))
        parts.append(urn)

    bpy.data.objects.remove(proto)
    obj = mk.join(parts, name, col)
    mk.set_material(obj, lib.stone)
    return obj


def terrace(lib: Library, col) -> list[bpy.types.Object]:
    """A raised stone terrace wrapping the south and west fronts."""
    made = []
    y0, y1 = config.MAIN.y1 + config.VERANDA_DEPTH, config.MAIN.y1 + config.VERANDA_DEPTH + 1.9
    slab = mk.prism("terrace.slab",
                    [(-13.5, y0 - 0.2), (12.4, y0 - 0.2),
                     (12.4, y1), (-13.5, y1)],
                    config.VERANDA_DECK_Z - 1.10, config.VERANDA_DECK_Z - 0.34,
                    col)
    mk.set_material(slab, lib.stone)
    made.append(slab)

    # The balustrade runs along the terrace edge, broken for the steps.
    left = [(x, y1 - 0.30) for x in (-13.2, -9.6, -6.0, -2.4)]
    right = [(x, y1 - 0.30) for x in (4.6, 8.0, 12.1)]
    made.append(balustrade("terrace.balL", left,
                           config.VERANDA_DECK_Z - 0.34, lib, col,
                           pier_every=3))
    made.append(balustrade("terrace.balR", right,
                           config.VERANDA_DECK_Z - 0.34, lib, col,
                           pier_every=2))
    return made


# ---------------------------------------------------------------------------
# Fountain
# ---------------------------------------------------------------------------

def fountain(lib: Library, col, segments: int = 48) -> list[bpy.types.Object]:
    """A tiered fountain in the middle of the carriage turn."""
    made = []
    cx, cy = config.FOUNTAIN_XY
    z = T.height(cx, cy)
    r = config.FOUNTAIN_R

    basin = mk.lathe("fountain.basin", [
        (0.0, 0.0), (r + 0.55, 0.0), (r + 0.55, 0.42), (r + 0.40, 0.60),
        (r + 0.10, 0.68), (r, 0.62), (r, 0.16), (r - 0.22, 0.10),
        (0.0, 0.10),
    ], segments, center=(cx, cy, z), col=col)
    mk.shade_smooth(basin, math.radians(34))
    mk.set_material(basin, lib.stone)
    made.append(basin)

    water = mk.disc("fountain.water", (cx, cy, z + 0.44), r - 0.06,
                    segments, col=col)
    mk.set_material(water, lib.water)
    made.append(water)

    pedestal = mk.lathe("fountain.pedestal", [
        (0.0, 0.0), (1.05, 0.0), (1.05, 0.22), (0.86, 0.34), (0.72, 0.42),
        (0.72, 1.20), (0.90, 1.34), (1.02, 1.46), (0.86, 1.56), (0.52, 1.62),
        (0.44, 1.74), (0.52, 1.86), (0.0, 1.92),
    ], segments, center=(cx, cy, z + 0.10), col=col)
    mk.shade_smooth(pedestal, math.radians(36))
    mk.set_material(pedestal, lib.stone)
    made.append(pedestal)

    upper = mk.lathe("fountain.upperbowl", [
        (0.0, 0.0), (0.30, 0.0), (0.62, 0.10), (1.34, 0.42), (1.52, 0.62),
        (1.44, 0.70), (1.30, 0.52), (0.66, 0.26), (0.30, 0.20), (0.0, 0.18),
    ], segments, center=(cx, cy, z + 2.02), col=col)
    mk.shade_smooth(upper, math.radians(36))
    mk.set_material(upper, lib.stone)
    made.append(upper)

    jet = mk.lathe("fountain.jet", [
        (0.0, 0.0), (0.20, 0.0), (0.18, 0.36), (0.11, 0.72), (0.05, 1.00),
        (0.0, 1.15),
    ], 20, center=(cx, cy, z + 2.28), col=col)
    mk.shade_smooth(jet, math.radians(40))
    mk.set_material(jet, lib.water)
    made.append(jet)
    return made


# ---------------------------------------------------------------------------
# Perimeter wall and gates
# ---------------------------------------------------------------------------

def _wall_run(name: str, a, b, lib: Library, col, height: float,
              thickness: float, pier_pitch: float = 9.0
              ) -> list[bpy.types.Object]:
    """A length of estate wall with piers and a moulded coping, on the ground."""
    made = []
    d = Vector((b[0] - a[0], b[1] - a[1], 0.0))
    length = d.length
    d.normalize()
    steps = max(2, int(length / 3.0))
    verts, faces = [], []
    half = thickness / 2.0
    nrm = Vector((-d.y, d.x, 0.0))
    for i in range(steps + 1):
        p = Vector((a[0], a[1], 0.0)) + d * (length * i / steps)
        z0 = T.height(p.x, p.y) - 0.35
        for s in (-1, 1):
            q = p + nrm * (half * s)
            verts.append((q.x, q.y, z0))
            verts.append((q.x, q.y, z0 + height + 0.35))
    for i in range(steps):
        a0 = i * 4
        b0 = a0 + 4
        faces += [(a0, b0, b0 + 1, a0 + 1),              # left face
                  (a0 + 2, a0 + 3, b0 + 3, b0 + 2),      # right face
                  (a0 + 1, b0 + 1, b0 + 3, a0 + 3),      # top
                  (a0, a0 + 2, b0 + 2, b0)]              # bottom
    core = mk.obj_from(f"{name}.core", verts, faces, col=col)
    mk.recalc_normals(core)
    mk.set_material(core, lib.brick)
    made.append(core)

    # Coping and piers.
    cop_path = [(a[0] + d.x * (length * i / steps),
                 a[1] + d.y * (length * i / steps),
                 T.height(a[0] + d.x * (length * i / steps),
                          a[1] + d.y * (length * i / steps)) + height)
                for i in range(steps + 1)]
    cop = mk.sweep(f"{name}.coping", orn.cyma_reversa(thickness * 0.72, 0.16),
                   [(x - nrm.x * thickness * 0.36, y - nrm.y * thickness * 0.36, z)
                    for x, y, z in cop_path], closed_path=False,
                   up=(0, 0, 1), col=col)
    mk.recalc_normals(cop)
    mk.set_material(cop, lib.stone)
    made.append(cop)

    n_piers = max(2, int(round(length / pier_pitch)))
    piers = []
    for i in range(n_piers + 1):
        p = Vector((a[0], a[1], 0.0)) + d * (length * i / n_piers)
        z0 = T.height(p.x, p.y)
        pw = thickness + 0.34
        piers.append(mk.box(f"{name}.pier{i}", (p.x, p.y, z0 + height / 2 + 0.1),
                            (pw, pw, height + 0.5), col))
        cap = mk.lathe(f"{name}.piercap{i}", [
            (pw * 0.80, 0.0), (pw * 0.80, 0.10), (pw * 0.62, 0.22),
            (pw * 0.40, 0.34), (0.0, 0.42)], 4, arc=math.tau,
            start=math.pi / 4, center=(p.x, p.y, z0 + height + 0.36), col=col)
        piers.append(cap)
    pier_obj = mk.join(piers, f"{name}.piers", col)
    mk.set_material(pier_obj, lib.brick)
    made.append(pier_obj)
    return made


def iron_gate(name: str, cx: float, cy: float, width: float, height: float,
              lib: Library, col, yaw: float = 0.0, leaves: int = 2
              ) -> bpy.types.Object:
    """A pair of wrought-iron carriage gates with dog bars and finials."""
    parts = []
    z = T.height(cx, cy)
    leaf_w = width / leaves
    for L in range(leaves):
        x0 = -width / 2 + leaf_w * L
        # Frame.
        for (px, pw) in ((x0 + 0.03, 0.06), (x0 + leaf_w - 0.03, 0.06)):
            parts.append(mk.box(f"{name}.stile{L}{px:.2f}",
                                (px, 0.0, height / 2), (pw, 0.06, height), col))
        parts.append(mk.box(f"{name}.rail{L}b", (x0 + leaf_w / 2, 0.0, 0.14),
                            (leaf_w, 0.055, 0.09), col))
        parts.append(mk.box(f"{name}.rail{L}m",
                            (x0 + leaf_w / 2, 0.0, height * 0.46),
                            (leaf_w, 0.055, 0.075), col))
        parts.append(mk.box(f"{name}.rail{L}t",
                            (x0 + leaf_w / 2, 0.0, height * 0.84),
                            (leaf_w, 0.055, 0.075), col))
        n = max(4, int(leaf_w / 0.155))
        for k in range(n):
            px = x0 + leaf_w * (k + 0.5) / n
            parts.append(mk.box(f"{name}.bar{L}{k}", (px, 0.0, height * 0.50),
                                (0.026, 0.026, height * 0.92), col))
            spear = mk.lathe(f"{name}.spear{L}{k}", [
                (0.030, 0.0), (0.052, 0.06), (0.044, 0.10), (0.030, 0.13),
                (0.030, 0.18), (0.0, 0.30)], 8, col=col)
            mk.transform(spear, Matrix.Translation(
                (px, 0.0, height * 0.96)))
            parts.append(spear)
    obj = mk.join(parts, f"{name}.leaves", col)
    mk.transform(obj, Matrix.Translation((cx, cy, z))
                 @ Matrix.Rotation(yaw, 4, 'Z'))
    mk.set_material(obj, lib.iron)
    return obj


def perimeter(lib: Library, col) -> list[bpy.types.Object]:
    """Estate wall along the south boundary, with the gateway at its centre."""
    made = []
    y = config.GATE_Y
    h, t = config.WALL_H, config.WALL_T
    gate_half = 3.4
    pier_half = 1.0
    made += _wall_run("wall.se", (gate_half + pier_half, y),
                      (config.SITE_HALF - 8.0, y), lib, col, h, t)
    made += _wall_run("wall.sw", (-config.SITE_HALF + 8.0, y),
                      (-gate_half - pier_half, y), lib, col, h, t)
    made += _wall_run("wall.east", (config.SITE_HALF - 8.0, y),
                      (config.SITE_HALF - 8.0, y - 62.0), lib, col, h, t)
    made += _wall_run("wall.west", (-config.SITE_HALF + 8.0, y),
                      (-config.SITE_HALF + 8.0, y - 62.0), lib, col, h, t)

    # Gate piers: taller, with moulded caps and urns.
    for sgn in (-1, 1):
        px = sgn * (gate_half + pier_half * 0.5)
        z = T.height(px, y)
        pier = mk.box(f"gate.pier{sgn}", (px, y, z + 1.90), (1.5, 1.5, 3.8),
                      col)
        mk.set_material(pier, lib.stone)
        made.append(pier)
        band = mk.sweep("gate.piercap%d" % sgn, orn.cornice_profile(0.34, 0.34),
                        mk.rect_path(px - 0.75, y - 0.75, px + 0.75, y + 0.75,
                                     z + 3.80), closed_path=True, col=col)
        mk.recalc_normals(band)
        mk.set_material(band, lib.stone)
        made.append(band)
        urn = orn.finial(f"gate.urn{sgn}", 1.65, 0.44, 20, "urn", col)
        mk.transform(urn, Matrix.Translation((px, y, z + 4.16)))
        mk.set_material(urn, lib.stone)
        made.append(urn)

    made.append(iron_gate("gate", 0.0, y, gate_half * 2, 3.1, lib, col))
    return made
