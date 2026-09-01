"""
The corner tower.

The shaft is a single revolve whose profile carries the plinth, the string
courses at each floor and the corbelled cornice, so those mouldings wrap the
curve exactly instead of being separate rings that have to be kept in
register.  Windows are cut into the curve and their flat joinery set into the
resulting reveal - at this radius the sagitta across a window is about 55 mm,
which is less than the reveal depth, so a flat sash sits in a curved wall
without any visible discrepancy.
"""

from __future__ import annotations

import math

import bpy
from mathutils import Matrix, Vector

from ..core import config, meshkit as mk, ornament as orn
from ..core.materials import Library
from .roof import Face, slate_field
from . import windows as W

CX, CY = config.TOWER_CX, config.TOWER_CY
R = config.TOWER_R


def shaft_profile(r: float = R) -> list[tuple[float, float]]:
    """Radius/height profile from the footing to the top of the cornice."""
    z_f1, z_f2, z_f3 = config.Z_F1, config.Z_F2, config.Z_F3
    top = config.TOWER_TOP
    p = [
        (0.0, config.Z_BASE - 0.9),
        (r + 0.42, config.Z_BASE - 0.9),          # footing
        (r + 0.42, config.Z_BASE + 0.24),
        (r + 0.30, config.Z_BASE + 0.32),         # rusticated plinth
        (r + 0.30, z_f1 - 0.42),
        (r + 0.34, z_f1 - 0.34),                  # water table
        (r + 0.06, z_f1 - 0.06),
        (r, z_f1 + 0.02),
        (r, z_f2 - 0.44),                         # first string course
        (r + 0.16, z_f2 - 0.34),
        (r + 0.16, z_f2 - 0.20),
        (r, z_f2 - 0.10),
        (r, z_f3 - 0.42),                         # second string course
        (r + 0.16, z_f3 - 0.32),
        (r + 0.16, z_f3 - 0.18),
        (r, z_f3 - 0.08),
        (r, top - 1.30),
    ]
    # Corbelled cornice: three courses stepping out, then a cyma and a fillet.
    for k, (dz, dr) in enumerate([(0.18, 0.14), (0.34, 0.28), (0.50, 0.42)]):
        p += [(r + dr, top - 1.30 + dz), (r + dr, top - 1.30 + dz + 0.14)]
    p += [(r + 0.62, top - 0.52), (r + 0.72, top - 0.32),
          (r + 0.70, top - 0.10), (r + 0.52, top),
          (0.0, top)]
    return p


def build(lib: Library, col, segments: int = config.TOWER_SIDES,
          slate: bool = True) -> list[bpy.types.Object]:
    made: list[bpy.types.Object] = []

    body = mk.lathe("tower.shaft", shaft_profile(), segments,
                    center=(CX, CY, 0.0), col=col)
    mk.shade_smooth(body, math.radians(24))
    mk.set_material(body, lib.body)
    # The plinth and cornice belong to the stone and trim palettes; split them
    # off by height rather than modelling them as separate rings.
    stone_slot = mk.add_material(body, lib.stone_dark)
    trim_slot = mk.add_material(body, lib.trim)
    mk.assign_faces(body, stone_slot,
                    lambda c, n: c.z < config.Z_F1 - 0.10)
    mk.assign_faces(body, trim_slot,
                    lambda c, n: c.z > config.TOWER_TOP - 1.35)
    made.append(body)

    # -- windows --------------------------------------------------------
    azimuths = (math.radians(96), math.radians(138), math.radians(180))
    floors = {1: (config.Z_F1, config.WIN_H_1, dict(
                    width=1.10, head="segmental", upper_lights=(1, 1),
                    hood="label", corner_blocks=False)),
              2: (config.Z_F2, config.WIN_H_2, dict(
                    width=1.06, head="segmental", upper_lights=(1, 1),
                    hood="label", corner_blocks=False)),
              3: (config.Z_F3, config.WIN_H_3 + 0.25, dict(
                    width=1.00, head="round", upper_lights=(1, 1),
                    hood="none", stained=True))}

    for floor, (deck, height, extra) in floors.items():
        z = deck + config.WIN_SILL
        for k, az in enumerate(azimuths):
            spec = W.WindowSpec(height=height, wall_t=0.46, reveal=0.13,
                                casing_w=0.115, apron=(floor != 3), **extra)
            # Cut a flat-faced notch through the curved wall.
            cut = mk.prism_y(f"tower.cut{floor}{k}",
                             mk.offset_polygon(W.opening_outline(spec), 0.005),
                             -1.4, 0.6, col)
            px, py = CX + math.cos(az) * R, CY + math.sin(az) * R
            yaw = az - math.pi / 2
            mk.transform(cut, Matrix.Translation((px, py, z))
                         @ Matrix.Rotation(yaw, 4, 'Z'))
            mk.boolean(body, cut)

            win = W.build(f"tower.win{floor}{k}", spec, lib, col)
            W.place(win, px, py, z, yaw)
            made.append(win)

    # -- corbel brackets under the cornice --------------------------------
    proto = orn.bracket("tower.brproto", 0.46, 0.62, 0.07, "scroll", col=col)
    mk.set_material(proto, lib.trim)
    brs = []
    n_br = segments
    for i in range(n_br):
        a = math.tau * i / n_br
        brs.append(mk.instance(
            proto, f"tower.br{i}",
            (CX + math.cos(a) * (R + 0.02), CY + math.sin(a) * (R + 0.02),
             config.TOWER_TOP - 1.34),
            rotation=(0.0, 0.0, a), col=col))
    bpy.data.objects.remove(proto)
    joined = mk.join(brs, "tower.brackets", col)
    mk.set_material(joined, lib.trim)
    made.append(joined)

    # -- spire -------------------------------------------------------------
    made += spire(lib, col, segments, slate)
    return made


def spire_profile(base_r: float, height: float, n: int = 12
                  ) -> list[tuple[float, float]]:
    """A candle-snuffer: concave near the eaves, straightening as it rises."""
    pts = [(base_r, 0.0)]
    for i in range(1, n + 1):
        t = i / n
        # A slight ogee: the radius falls faster than linearly at first.
        r = base_r * (1.0 - t) ** 1.22
        pts.append((r, height * t))
    pts[-1] = (0.0, height)
    return pts


def spire(lib: Library, col, segments: int = config.TOWER_SIDES,
          slate: bool = True) -> list[bpy.types.Object]:
    made = []
    base_z = config.TOWER_TOP
    base_r = R + 0.52
    prof = spire_profile(base_r, config.TOWER_SPIRE_H)

    cone = mk.lathe("tower.spire", prof, segments, center=(CX, CY, base_z),
                    col=col)
    mk.shade_smooth(cone, math.radians(26))
    mk.set_material(cone, lib.slate)
    made.append(cone)

    if slate:
        # Slate each sector as its own quad strip, tapering to the apex.
        for i in range(segments):
            a0 = math.tau * i / segments
            a1 = math.tau * (i + 1) / segments
            for j in range(len(prof) - 1):
                (r0, z0), (r1, z1) = prof[j], prof[j + 1]
                if r0 < 0.05:
                    continue
                bl = Vector((CX + r0 * math.cos(a0), CY + r0 * math.sin(a0),
                             base_z + z0))
                br = Vector((CX + r0 * math.cos(a1), CY + r0 * math.sin(a1),
                             base_z + z0))
                tr = Vector((CX + r1 * math.cos(a1), CY + r1 * math.sin(a1),
                             base_z + z1))
                tl = Vector((CX + r1 * math.cos(a0), CY + r1 * math.sin(a0),
                             base_z + z1))
                f = Face(bl, br, tr, tl)
                made.append(slate_field(
                    f"tower.spslate{i}.{j}", f, lib, col,
                    exposure=config.SLATE_EXPOSURE * 0.92,
                    width=config.SLATE_W * 0.78, thickness=0.011,
                    jitter=0.8, seed=i * 977 + j))

    # A copper collar where the spire meets the cornice, and a finial above.
    collar = mk.lathe("tower.collar",
                      [(base_r + 0.10, -0.20), (base_r + 0.18, -0.10),
                       (base_r + 0.18, 0.06), (base_r + 0.02, 0.16)],
                      segments, center=(CX, CY, base_z), cap=False, col=col)
    mk.shade_smooth(collar, math.radians(30))
    mk.set_material(collar, lib.copper)
    made.append(collar)

    fin = orn.finial("tower.finial", config.TOWER_FINIAL_H, 0.26, 18, "spike",
                     col)
    mk.transform(fin, Matrix.Translation(
        (CX, CY, base_z + config.TOWER_SPIRE_H - 0.25)))
    mk.set_material(fin, lib.copper)
    made.append(fin)

    # A weather vane on top of the finial.
    rod = mk.box("tower.vanerod", (CX, CY, base_z + config.TOWER_SPIRE_H
                                   + config.TOWER_FINIAL_H * 0.72),
                 (0.035, 0.035, config.TOWER_FINIAL_H * 0.5), col)
    mk.set_material(rod, lib.iron)
    made.append(rod)
    arrow = mk.prism_y(
        "tower.vane",
        [(-0.62, 0.0), (-0.30, 0.16), (-0.30, 0.05), (0.42, 0.05),
         (0.42, 0.26), (0.78, 0.0), (0.42, -0.26), (0.42, -0.05),
         (-0.30, -0.05), (-0.30, -0.16)], -0.012, 0.012, col)
    mk.transform(arrow, Matrix.Translation(
        (CX, CY, base_z + config.TOWER_SPIRE_H + config.TOWER_FINIAL_H * 0.95))
        @ Matrix.Rotation(math.radians(-34), 4, 'Z'))
    mk.set_material(arrow, lib.iron)
    made.append(arrow)
    return made
