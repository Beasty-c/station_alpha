"""
Canted bay windows.

A bay does three things a flat window cannot: it breaks the plane of the
facade, it catches light on two extra faces, and it throws a shadow down the
wall.  It is built here as a generic prism of ``n`` canted faces so the same
code serves a three-sided ground-floor bay, a two-storey bay carrying a
balcony, and a small oriel corbelled out of an upper wall.
"""

from __future__ import annotations

import math

import bpy
from mathutils import Matrix, Vector

from ..core import config, meshkit as mk, ornament as orn
from ..core.materials import Library
from . import windows as W


def canted_plan(width: float, projection: float, splay: float = 0.62
                ) -> list[tuple[float, float]]:
    """Plan of a three-sided canted bay, local to the wall face.

    x runs along the wall, y projects outward, and the wall face is y = 0.
    ``splay`` is the fraction of the half-width taken by the angled returns.
    """
    half = width / 2.0
    front = half * (1.0 - splay)
    return [(-half, 0.0), (-front, projection), (front, projection),
            (half, 0.0)]


def build(name: str, lib: Library, col, width: float = 4.2,
          projection: float = 1.55, z0: float = config.Z_F1,
          storeys: int = 1, wall_t: float = 0.40,
          roof: str = "balcony", segments: int = 14) -> bpy.types.Object:
    """A bay in the canonical wall frame: face at y = 0, outward +Y.

    ``z0`` is the floor deck it stands on; ``roof`` is ``balcony`` (a leaded
    flat with a balustrade), ``hip`` (a small slated hip) or ``none``.
    """
    parts: list[bpy.types.Object] = []
    plan = canted_plan(width, projection)
    heights = []
    z = z0
    for s in range(storeys):
        floor = config.FLOOR_1 if s == 0 else config.FLOOR_2
        heights.append((z, z + floor - 0.55))
        z += floor
    top = heights[-1][1]

    # Plinth, walls and a cornice at each storey.
    base = mk.prism(f"{name}.plinth",
                    [(x * 1.03, y * 1.03 if y > 0 else -0.30) for x, y in plan],
                    z0 - config.BASEMENT_SHOW - 0.9, z0 - 0.28, col)
    mk.set_material(base, lib.stone_dark)
    parts.append(base)

    body = mk.prism(f"{name}.body",
                    [(x, y if y > 0 else -0.30) for x, y in plan],
                    z0 - 0.34, top, col)
    mk.set_material(body, lib.body)

    # Windows: one in the front face, one in each canted return.
    faces = list(zip(plan, plan[1:]))
    for s, (za, zb) in enumerate(heights):
        h = (config.WIN_H_1 if s == 0 else config.WIN_H_2) - 0.15
        for fi, (a, b) in enumerate(faces):
            d = Vector((b[0] - a[0], b[1] - a[1], 0.0))
            run = d.length
            if run < 0.5:
                continue
            d.normalize()
            yaw = math.atan2(d.y, d.x) - math.pi / 2
            mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
            spec = W.WindowSpec(
                width=min(1.30, run - 0.55), height=h, wall_t=wall_t,
                upper_lights=(2, 2) if s == 0 else (2, 1),
                head="segmental" if fi == 1 else "flat",
                hood="none", corner_blocks=False, casing_w=0.115,
                sill_proj=0.10, apron=False)
            cut = mk.prism_y(f"{name}.cut{s}{fi}",
                             mk.offset_polygon(W.opening_outline(spec), 0.005),
                             -1.2, 0.5, col)
            mk.transform(cut, Matrix.Translation((mid[0], mid[1],
                                                  za + config.WIN_SILL))
                         @ Matrix.Rotation(yaw, 4, 'Z'))
            mk.boolean(body, cut)
            wnd = W.build(f"{name}.win{s}{fi}", spec, lib, col)
            W.place(wnd, mid[0], mid[1], za + config.WIN_SILL, yaw)
            parts.append(wnd)

        # A moulded band at each floor line.
        if s:
            band = mk.sweep(f"{name}.band{s}", orn.cyma_reversa(0.14, 0.24),
                            [(x, y, za - 0.40) for x, y in plan],
                            closed_path=False, col=col)
            mk.recalc_normals(band)
            mk.set_material(band, lib.trim)
            parts.append(band)
    parts.append(body)

    # Corner colonettes at the cants, which is what dresses a bay.
    for (px, py) in plan[1:3]:
        for s, (za, zb) in enumerate(heights):
            col_h = zb - za
            cl = orn.turned_post(f"{name}.colonette{px:.1f}{s}", col_h, 0.16,
                                 segments, "colonette", col)
            mk.transform(cl, Matrix.Translation((px, py + 0.02, za - 0.20)))
            mk.set_material(cl, lib.trim)
            parts.append(cl)

    # Entablature.
    frieze = mk.prism(f"{name}.frieze", [(x * 1.01, y * 1.01) for x, y in plan],
                      top - 0.42, top, col)
    mk.set_material(frieze, lib.trim)
    parts.append(frieze)
    cor = mk.sweep(f"{name}.cornice", orn.cornice_profile(0.46, 0.40),
                   [(x, y, top) for x, y in plan], closed_path=False, col=col)
    mk.recalc_normals(cor)
    mk.set_material(cor, lib.trim)
    parts.append(cor)

    brs = []
    for fi, (a, b) in enumerate(faces):
        d = Vector((b[0] - a[0], b[1] - a[1], 0.0))
        if d.length < 0.5:
            continue
        n = max(1, int(d.length / 0.95))
        yaw = math.atan2(d.y, d.x) - math.pi / 2
        for k in range(n + 1):
            t = k / n
            px = a[0] + d.x * t
            py = a[1] + d.y * t
            br = orn.bracket(f"{name}.br{fi}{k}", 0.36, 0.50, 0.055, "scroll",
                             pierce=False, col=col)
            mk.transform(br, Matrix.Translation((px, py, top - 0.02))
                         @ Matrix.Rotation(yaw + math.pi / 2, 4, 'Z'))
            brs.append(br)
    if brs:
        b = mk.join(brs, f"{name}.brackets", col)
        mk.set_material(b, lib.trim)
        parts.append(b)

    if roof == "balcony":
        deck = mk.prism(f"{name}.deck", [(x * 1.02, y * 1.02) for x, y in plan],
                        top + 0.40, top + 0.52, col)
        mk.set_material(deck, lib.lead)
        parts.append(deck)
        rail_h = 0.92
        proto = orn.baluster(f"{name}.balproto", rail_h - 0.22, 0.085,
                             max(10, segments - 4), "vase", col)
        rails = []
        for a, b in faces:
            d = Vector((b[0] - a[0], b[1] - a[1], 0.0))
            run = d.length
            if run < 0.4:
                continue
            d.normalize()
            yaw = math.atan2(d.y, d.x)
            mid = Vector(((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, 0.0))
            rail = mk.sweep_straight(
                f"{name}.rail{run:.2f}", orn.handrail_profile(0.13, 0.08),
                (-run / 2, 0, 0), (run / 2, 0, 0), (0, 1, 0), col=col)
            mk.transform(rail, Matrix.Translation(
                mid + Vector((0, 0, top + 0.52 + rail_h - 0.08)))
                @ Matrix.Rotation(yaw, 4, 'Z'))
            rails.append(rail)
            n = max(2, int(run / 0.20))
            for k in range(n):
                t = (k + 0.5) / n
                p = Vector((a[0], a[1], 0)).lerp(Vector((b[0], b[1], 0)), t)
                rails.append(mk.instance(proto, f"{name}.bal{run:.2f}.{k}",
                                         (p.x, p.y, top + 0.52 + 0.10),
                                         col=col))
        bpy.data.objects.remove(proto)
        r = mk.join(rails, f"{name}.balustrade", col)
        mk.set_material(r, lib.trim)
        parts.append(r)
    elif roof == "hip":
        apex = Vector((0.0, projection * 0.35, top + 1.35))
        verts = [(x, y, top + 0.40) for x, y in plan] + [tuple(apex)]
        n = len(plan)
        hip_faces = [(i, i + 1, n) for i in range(n - 1)]
        hip = mk.obj_from(f"{name}.hip", verts, hip_faces, col=col)
        mk.recalc_normals(hip)
        mk.solidify(hip, 0.12)
        mk.set_material(hip, lib.slate)
        parts.append(hip)

    return mk.join(parts, name, col)


def opening_polygon(width: float = 4.2, z_span: float = 4.0
                    ) -> list[tuple[float, float]]:
    """The hole a bay needs in the wall it opens off."""
    half = width / 2.0 - 0.30
    return [(-half, 0.10), (half, 0.10), (half, z_span), (-half, z_span)]
