"""
The front door: a pair of panelled leaves with etched glass, under a transom
light, flanked by sidelights, inside a heavy moulded surround.

The entrance is the one place on a Victorian house where the joinery is worth
modelling at furniture scale, because it is the part a visitor stands two feet
from.
"""

from __future__ import annotations

import math

import bpy
from mathutils import Matrix

from ..core import config, meshkit as mk, ornament as orn
from ..core.materials import Library
from . import windows as W


def door_leaf(name: str, width: float, height: float, thickness: float,
              lib: Library, col, glazed: bool = True) -> bpy.types.Object:
    """One leaf: stiles, rails, a glazed upper light and two sunk panels."""
    parts = []
    stile = width * 0.135
    rail = height * 0.075
    lock_rail_z = height * 0.545

    slab = mk.box(f"{name}.slab", (0.0, thickness / 2, height / 2),
                  (width, thickness, height), col)
    mk.set_material(slab, lib.wood_dark)
    parts.append(slab)

    light_w = width - stile * 2
    if glazed:
        # Cut the upper light straight through, then glaze it.
        top0 = lock_rail_z + rail * 0.6
        top1 = height - rail * 1.4
        cut = mk.box(f"{name}.lightcut", (0.0, thickness / 2,
                                          (top0 + top1) / 2),
                     (light_w, thickness * 2, top1 - top0), col)
        mk.boolean(slab, cut)
        glass = mk.box(f"{name}.glass", (0.0, thickness * 0.62,
                                         (top0 + top1) / 2),
                       (light_w, 0.006, top1 - top0), col)
        mk.set_material(glass, lib.glass_old)
        parts.append(glass)
        bead = mk.sweep_frame(f"{name}.lightbead", orn.ovolo(0.030, 0.026),
                              -light_w / 2, light_w / 2, top0, top1,
                              thickness, col=col)
        mk.set_material(bead, lib.wood_dark)
        parts.append(bead)

    # Two raised panels below the lock rail.
    z0 = rail * 1.6
    z1 = lock_rail_z - rail * 0.6
    split = (z0 + z1) / 2
    for lo, hi in ((z0, split - rail * 0.4), (split + rail * 0.4, z1)):
        p = orn.panel(f"{name}.panel{lo:.2f}", light_w, hi - lo, 0.030,
                      0.042, 0.012, col)
        mk.transform(p, Matrix.Translation((0.0, thickness, (lo + hi) / 2)))
        mk.set_material(p, lib.wood_dark)
        parts.append(p)

    # Hardware: a heavy knob and a letter plate.
    knob = mk.lathe(f"{name}.knob",
                    [(0.014, 0.0), (0.014, 0.045), (0.030, 0.055),
                     (0.036, 0.075), (0.028, 0.092), (0.0, 0.098)], 14,
                    col=col)
    mk.transform(knob, Matrix.Translation(
        (width * 0.34, thickness, lock_rail_z - 0.10))
        @ Matrix.Rotation(-math.pi / 2, 4, 'X'))
    mk.shade_smooth(knob, math.radians(40))
    mk.set_material(knob, lib.gilt)
    parts.append(knob)

    return mk.join(parts, name, col)


def build(name: str, lib: Library, col, width: float = 2.05,
          height: float = 3.05, wall_t: float = 0.40,
          sidelights: bool = True, transom: bool = True,
          hood: bool = True) -> tuple[bpy.types.Object, list]:
    """The whole entrance, in the canonical window frame (sill at z = 0)."""
    parts = []
    side_w = 0.44 if sidelights else 0.0
    total_w = width + side_w * 2
    transom_h = 0.62 if transom else 0.0
    total_h = height + transom_h

    lining = mk.band_solid(
        f"{name}.lining",
        [(-total_w / 2 - 0.01, -0.01), (total_w / 2 + 0.01, -0.01),
         (total_w / 2 + 0.01, total_h + 0.01), (-total_w / 2 - 0.01, total_h + 0.01)],
        [(-total_w / 2 + 0.06, 0.0), (total_w / 2 - 0.06, 0.0),
         (total_w / 2 - 0.06, total_h - 0.06), (-total_w / 2 + 0.06, total_h - 0.06)],
        -wall_t, -0.04, col)
    mk.set_material(lining, lib.trim)
    parts.append(lining)

    for sgn in (-1, 1):
        leaf = door_leaf(f"{name}.leaf{sgn}", width / 2 - 0.012, height,
                         0.062, lib, col)
        mk.transform(leaf, Matrix.Translation(
            (sgn * (width / 4), -0.13, 0.0)))
        parts.append(leaf)

    if sidelights:
        for sgn in (-1, 1):
            x = sgn * (width / 2 + side_w / 2)
            mull = mk.box(f"{name}.mullion{sgn}",
                          (sgn * (width / 2 + 0.045), -0.12, height / 2),
                          (0.09, 0.20, height), col)
            mk.set_material(mull, lib.trim)
            parts.append(mull)
            glass = mk.box(f"{name}.sideglass{sgn}", (x, -0.14, height * 0.52),
                           (side_w - 0.16, 0.008, height * 0.82), col)
            mk.set_material(glass, lib.stained)
            parts.append(glass)
            frame = mk.band_solid(
                f"{name}.sideframe{sgn}",
                [(x - side_w / 2 + 0.02, height * 0.11),
                 (x + side_w / 2 - 0.02, height * 0.11),
                 (x + side_w / 2 - 0.02, height * 0.93),
                 (x - side_w / 2 + 0.02, height * 0.93)],
                [(x - side_w / 2 + 0.09, height * 0.15),
                 (x + side_w / 2 - 0.09, height * 0.15),
                 (x + side_w / 2 - 0.09, height * 0.89),
                 (x - side_w / 2 + 0.09, height * 0.89)],
                -0.17, -0.10, col)
            mk.set_material(frame, lib.trim)
            parts.append(frame)
            apron = orn.panel(f"{name}.sideapron{sgn}", side_w - 0.16,
                              height * 0.09, 0.026, 0.022, 0.008, col)
            mk.transform(apron, Matrix.Translation((x, -0.05, height * 0.055)))
            mk.set_material(apron, lib.wood_dark)
            parts.append(apron)

    if transom:
        rail = mk.box(f"{name}.transomrail", (0.0, -0.11, height + 0.055),
                      (total_w, 0.22, 0.11), col)
        mk.set_material(rail, lib.trim)
        parts.append(rail)
        glass = mk.box(f"{name}.transomglass",
                       (0.0, -0.14, height + 0.11 + (transom_h - 0.11) / 2),
                       (total_w - 0.26, 0.008, transom_h - 0.18), col)
        mk.set_material(glass, lib.stained)
        parts.append(glass)
        # Radiating bars, as a fanlight has.
        for i in range(5):
            t = (i + 0.5) / 5
            bar = mk.box(f"{name}.fanbar{i}", (0, 0, 0),
                         (0.030, 0.05, transom_h - 0.20), col)
            mk.transform(bar, Matrix.Translation(
                (0.0, -0.13, height + 0.11))
                @ Matrix.Rotation(math.radians(52) * (t - 0.5) * 2, 4, 'Y')
                @ Matrix.Translation((0.0, 0.0, (transom_h - 0.20) / 2)))
            mk.set_material(bar, lib.trim)
            parts.append(bar)

    casing = mk.sweep_frame(f"{name}.casing", orn.casing_profile(0.20, 0.055),
                            -total_w / 2, total_w / 2, 0.0, total_h, 0.0,
                            col=col)
    mk.set_material(casing, lib.trim)
    parts.append(casing)

    extra = []
    if hood:
        proj = 1.05
        top = total_h + 0.20
        for sgn in (-1, 1):
            br = orn.bracket(f"{name}.hoodbr{sgn}", proj * 0.80, 1.15, 0.085,
                             "console", pierce=False, col=col)
            mk.transform(br, Matrix.Translation(
                (sgn * (total_w / 2 + 0.02), 0.0, top))
                @ Matrix.Rotation(math.pi / 2, 4, 'Z')
                @ Matrix.Scale(sgn, 4, (0.0, 1.0, 0.0)))
            mk.recalc_normals(br)
            mk.set_material(br, lib.trim)
            parts.append(br)
        soffit = mk.box(f"{name}.hoodsoffit", (0.0, proj / 2, top + 0.09),
                        (total_w + 0.70, proj, 0.18), col)
        mk.set_material(soffit, lib.trim)
        parts.append(soffit)
        cor = mk.sweep_straight(
            f"{name}.hoodcornice", orn.cornice_profile(proj * 0.62, 0.42),
            (-total_w / 2 - 0.40, proj * 0.42, top + 0.18),
            (total_w / 2 + 0.40, proj * 0.42, top + 0.18), (0, 1, 0), col=col)
        mk.set_material(cor, lib.trim)
        parts.append(cor)

    obj = mk.join(parts, name, col)
    return obj, extra


def opening_polygon(width: float = 2.05, height: float = 3.05,
                    sidelights: bool = True, transom: bool = True
                    ) -> list[tuple[float, float]]:
    """The hole this entrance needs cut in the wall."""
    side_w = 0.44 if sidelights else 0.0
    w = width + side_w * 2
    h = height + (0.62 if transom else 0.0)
    return [(-w / 2, -0.05), (w / 2, -0.05), (w / 2, h), (-w / 2, h)]
