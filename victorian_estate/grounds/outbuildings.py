"""
The estate's lesser buildings: carriage house and stables, the conservatory,
a gazebo, the lodge at the gates, and the ornamental water.

These reuse the mansion's own vocabulary at a smaller scale - the same
brackets, bargeboards, cresting and slating - which is what makes an estate
read as one composition rather than a collection of unrelated objects.
"""

from __future__ import annotations

import math
import random
import zlib

import bpy
from mathutils import Matrix, Vector

from ..core import config, meshkit as mk, ornament as orn
from ..core.materials import Library
from ..mansion import windows as W
from ..mansion.roof import Face, chimney, slate_field
from . import terrain as T


def _pad(name: str, cx: float, cy: float, sx: float, sy: float,
         lib: Library, col, lift: float = 0.12) -> tuple[bpy.types.Object, float]:
    """A level plinth for a building on sloping ground; returns its top Z."""
    corners = [(cx - sx / 2, cy - sy / 2), (cx + sx / 2, cy - sy / 2),
               (cx + sx / 2, cy + sy / 2), (cx - sx / 2, cy + sy / 2)]
    z = max(T.height(x, y) for x, y in corners) + lift
    pad = mk.prism(f"{name}.pad",
                   [(x + (0.5 if x > cx else -0.5), y + (0.5 if y > cy else -0.5))
                    for x, y in corners], z - 2.2, z, col)
    mk.set_material(pad, lib.stone_dark)
    return pad, z


def _slated_gable(name: str, cx: float, cy: float, sx: float, sy: float,
                  eave_z: float, pitch: float, lib: Library, col,
                  along_x: bool = True, overhang: float = 0.5,
                  slate: bool = True) -> list[bpy.types.Object]:
    """A simple pitched roof for an outbuilding."""
    made = []
    hx, hy = sx / 2 + overhang, sy / 2 + overhang
    half = hy if along_x else hx
    rise = half * math.tan(math.radians(pitch))
    rz = eave_z + rise
    # Each slope is given as (eave start, eave end, ridge start, ridge end)
    # with the ridge points listed in the same order as the eave points, so
    # the quad is never twisted.
    if along_x:
        slopes = [((cx - hx, cy - hy), (cx + hx, cy - hy),
                   (cx - hx, cy), (cx + hx, cy)),
                  ((cx + hx, cy + hy), (cx - hx, cy + hy),
                   (cx + hx, cy), (cx - hx, cy))]
    else:
        slopes = [((cx - hx, cy + hy), (cx - hx, cy - hy),
                   (cx, cy + hy), (cx, cy - hy)),
                  ((cx + hx, cy - hy), (cx + hx, cy + hy),
                   (cx, cy - hy), (cx, cy + hy))]
    for i, (a, b, ra, rb) in enumerate(slopes):
        f = Face(Vector((a[0], a[1], eave_z)), Vector((b[0], b[1], eave_z)),
                 Vector((rb[0], rb[1], rz)), Vector((ra[0], ra[1], rz)))
        deck = mk.obj_from(f"{name}.deck{i}",
                           [tuple(f.bl), tuple(f.br), tuple(f.tr), tuple(f.tl)],
                           [(0, 1, 2, 3)], col=col)
        mk.solidify(deck, 0.12)
        mk.set_material(deck, lib.slate)
        made.append(deck)
        if slate:
            made.append(slate_field(f"{name}.slate{i}", f, lib, col,
                                    seed=zlib.crc32(name.encode()) % 900 + i * 7))
    # Gable ends.
    for end in (0, 1):
        if along_x:
            x = cx - hx if end == 0 else cx + hx
            tri = [(cy - hy, eave_z), (cy + hy, eave_z), (cy, rz)]
            g = mk.prism_x(f"{name}.gable{end}", tri, x, x - (0.2 if end else -0.2), col)
        else:
            y = cy - hy if end == 0 else cy + hy
            tri = [(cx - hx, eave_z), (cx + hx, eave_z), (cx, rz)]
            g = mk.prism_y(f"{name}.gable{end}", tri, y, y - (0.2 if end else -0.2), col)
        mk.set_material(g, lib.body_upper)
        made.append(g)
    return made


# ---------------------------------------------------------------------------
# Carriage house and stables
# ---------------------------------------------------------------------------

def carriage_house(lib: Library, col) -> list[bpy.types.Object]:
    """Brick coach house with arched carriage doors, a hay loft and a cupola."""
    made = []
    cx, cy = config.CARRIAGE_HOUSE_XY
    sx, sy = 19.0, 10.5
    pad, z0 = _pad("carriage", cx, cy, sx, sy, lib, col)
    made.append(pad)

    eave = z0 + 6.4
    body = mk.prism("carriage.body",
                    [(cx - sx / 2, cy - sy / 2), (cx + sx / 2, cy - sy / 2),
                     (cx + sx / 2, cy + sy / 2), (cx - sx / 2, cy + sy / 2)],
                    z0, eave, col)
    mk.set_material(body, lib.brick)
    made.append(body)

    # Three arched carriage openings on the south face.
    for i in range(3):
        ox = cx + (i - 1) * 5.6
        spec = W.WindowSpec(width=3.2, height=3.0, head="round",
                            upper_lights=(3, 1), lower_lights=(3, 2),
                            wall_t=0.5, casing_w=0.22, casing_d=0.06,
                            sill_proj=0.05, sill_h=0.04, apron=False,
                            hood="none", corner_blocks=False)
        cut = mk.prism_y(f"carriage.cut{i}",
                         mk.offset_polygon(W.opening_outline(spec), 0.006),
                         -0.6, 0.6, col)
        mk.transform(cut, Matrix.Translation((ox, cy + sy / 2, z0 + 0.10)))
        mk.boolean(body, cut)
        door = W.build(f"carriage.door{i}", spec, lib, col)
        W.place(door, ox, cy + sy / 2, z0 + 0.10)
        made.append(door)
        # Voussoirs picked out in stone over each arch.
        vou = mk.sweep_wall_path(
            f"carriage.arch{i}", orn.fillet(0.30, 0.10),
            W.opening_outline(spec), 0.02, col=col)
        mk.transform(vou, Matrix.Translation((ox, cy + sy / 2, z0 + 0.10)))
        mk.set_material(vou, lib.stone)
        made.append(vou)

    # Loft windows above.
    for i in range(3):
        ox = cx + (i - 1) * 5.6
        spec = W.WindowSpec(width=0.95, height=1.30, head="segmental",
                            upper_lights=(1, 1), lower_lights=(1, 1),
                            wall_t=0.5, hood="label", corner_blocks=False)
        cut = mk.prism_y(f"carriage.loftcut{i}",
                         mk.offset_polygon(W.opening_outline(spec), 0.006),
                         -0.6, 0.6, col)
        mk.transform(cut, Matrix.Translation((ox, cy + sy / 2, z0 + 4.35)))
        mk.boolean(body, cut)
        wnd = W.build(f"carriage.loft{i}", spec, lib, col)
        W.place(wnd, ox, cy + sy / 2, z0 + 4.35)
        made.append(wnd)

    band = mk.sweep("carriage.band", orn.cyma_reversa(0.16, 0.24),
                    mk.rect_path(cx - sx / 2 - 0.04, cy - sy / 2 - 0.04,
                                 cx + sx / 2 + 0.04, cy + sy / 2 + 0.04,
                                 z0 + 3.95), closed_path=True, col=col)
    mk.recalc_normals(band)
    mk.set_material(band, lib.stone)
    made.append(band)

    cor = mk.sweep("carriage.cornice", orn.cornice_profile(0.55, 0.46),
                   mk.rect_path(cx - sx / 2 - 0.06, cy - sy / 2 - 0.06,
                                cx + sx / 2 + 0.06, cy + sy / 2 + 0.06, eave),
                   closed_path=True, col=col)
    mk.recalc_normals(cor)
    mk.set_material(cor, lib.trim)
    made.append(cor)

    made += _slated_gable("carriage.roof", cx, cy, sx, sy, eave + 0.46, 44.0,
                          lib, col, along_x=True)

    # A louvred cupola with a weather vane, as every coach house has.
    top = eave + 0.46 + (sy / 2 + 0.5) * math.tan(math.radians(44))
    made += cupola("carriage.cupola", cx, cy, top - 0.2, lib, col)

    # A mounting block and a water trough by the doors.
    block = mk.box("carriage.mountingblock",
                   (cx + sx / 2 + 1.6, cy + sy / 2 + 2.0, z0 + 0.34),
                   (1.0, 0.7, 0.68), col)
    mk.set_material(block, lib.stone)
    made.append(block)
    trough = mk.box("carriage.trough",
                    (cx - sx / 2 - 1.4, cy + sy / 2 + 1.4, z0 + 0.40),
                    (0.8, 2.4, 0.8), col)
    mk.set_material(trough, lib.stone)
    made.append(trough)
    return made


def dovecote(name: str, x: float, y: float, lib: Library, col,
             height: float = 4.2, sides: int = 8, seed: int = 0
             ) -> bpy.types.Object:
    """A dovecote on a post: a louvred octagon with landing ledges and a cap."""
    parts = []
    z = T.height(x, y)
    post_h = height * 0.56
    post = mk.box(f"{name}.post", (x, y, z + post_h / 2),
                  (0.26, 0.26, post_h), col)
    mk.set_material(post, lib.trim)
    parts.append(post)
    for sgn in (-1, 1):
        for axis in (0, 1):
            brace = mk.box(f"{name}.brace{sgn}{axis}", (0, 0, 0),
                           (0.09, 0.09, 1.05), col)
            off = (sgn * 0.38, 0.0) if axis == 0 else (0.0, sgn * 0.38)
            mk.transform(brace, Matrix.Translation(
                (x + off[0] * 0.5, y + off[1] * 0.5, z + post_h - 0.42))
                @ Matrix.Rotation(math.radians(34) * sgn,
                                  4, 'Y' if axis == 0 else 'X'))
            mk.set_material(brace, lib.trim)
            parts.append(brace)

    r = 0.78
    body_h = height * 0.30
    body = mk.lathe(f"{name}.body",
                    [(0.0, 0.0), (r, 0.0), (r, body_h), (0.0, body_h)],
                    sides, start=math.pi / sides,
                    center=(x, y, z + post_h), col=col)
    mk.set_material(body, lib.body)
    parts.append(body)

    # Entrance holes and their landing ledges, two tiers.
    holes = []
    for tier, zz in enumerate((post_h + body_h * 0.32, post_h + body_h * 0.68)):
        for i in range(sides):
            a = math.tau * (i + 0.5) / sides + math.pi / sides
            hx, hy = x + math.cos(a) * r, y + math.sin(a) * r
            cut = mk.box(f"{name}.hole{tier}{i}", (0, 0, 0),
                         (0.13, 0.5, 0.17), col)
            mk.transform(cut, Matrix.Translation((hx, hy, z + zz))
                         @ Matrix.Rotation(a, 4, 'Z'))
            holes.append(cut)
            ledge = mk.box(f"{name}.ledge{tier}{i}", (0, 0, 0),
                           (0.34, 0.18, 0.035), col)
            mk.transform(ledge, Matrix.Translation(
                (hx + math.cos(a) * 0.07, hy + math.sin(a) * 0.07,
                 z + zz - 0.10))
                @ Matrix.Rotation(a, 4, 'Z'))
            mk.set_material(ledge, lib.trim)
            parts.append(ledge)
    for cut in holes:
        mk.boolean(body, cut)

    band = mk.lathe(f"{name}.band",
                    [(r + 0.10, 0.0), (r + 0.16, 0.06), (r + 0.10, 0.12)],
                    sides, start=math.pi / sides, cap=False,
                    center=(x, y, z + post_h + body_h - 0.06), col=col)
    mk.set_material(band, lib.trim)
    parts.append(band)

    cap_h = height * 0.16
    cap = mk.lathe(f"{name}.cap",
                   [(r + 0.24, 0.0), (r * 0.62, cap_h * 0.55),
                    (r * 0.26, cap_h * 0.85), (0.0, cap_h)],
                   sides, start=math.pi / sides,
                   center=(x, y, z + post_h + body_h), col=col)
    mk.set_material(cap, lib.slate)
    parts.append(cap)
    fin = orn.finial(f"{name}.finial", 0.55, 0.09, 12, "ball", col)
    mk.transform(fin, Matrix.Translation((x, y, z + post_h + body_h + cap_h)))
    mk.set_material(fin, lib.copper)
    parts.append(fin)
    return mk.join(parts, name, col)


def pump(name: str, x: float, y: float, lib: Library, col, yaw: float = 0.0
         ) -> bpy.types.Object:
    """A cast-iron yard pump over a stone trough."""
    parts = []
    z = T.height(x, y)
    body = mk.lathe(f"{name}.body", [
        (0.0, 0.0), (0.30, 0.0), (0.30, 0.09), (0.20, 0.14), (0.155, 0.24),
        (0.135, 0.90), (0.155, 0.98), (0.145, 1.12), (0.175, 1.20),
        (0.155, 1.28), (0.11, 1.34), (0.0, 1.38)], 14,
        center=(x, y, z), col=col)
    mk.shade_smooth(body, math.radians(36))
    parts.append(body)
    spout = mk.lathe(f"{name}.spout",
                     [(0.075, 0.0), (0.070, 0.30), (0.085, 0.34)], 10, col=col)
    mk.transform(spout, Matrix.Translation((x, y, z + 0.98))
                 @ Matrix.Rotation(yaw, 4, 'Z')
                 @ Matrix.Rotation(math.radians(104), 4, 'X'))
    parts.append(spout)
    handle = mk.box(f"{name}.handle", (0, 0, 0), (0.05, 0.62, 0.05), col)
    mk.transform(handle, Matrix.Translation((x, y, z + 1.24))
                 @ Matrix.Rotation(yaw, 4, 'Z')
                 @ Matrix.Translation((0.0, -0.24, 0.0))
                 @ Matrix.Rotation(math.radians(22), 4, 'X'))
    parts.append(handle)
    obj = mk.join(parts, name, col)
    mk.set_material(obj, lib.iron)
    return obj


def stable_yard(lib: Library, col) -> list[bpy.types.Object]:
    """A cobbled yard in front of the coach house, with a dovecote and pump."""
    made = []
    cx, cy = config.CARRIAGE_HOUSE_XY
    yard_y = cy + 11.5
    made.append(T.ribbon("yard.cobbles",
                         [(cx - 11.0, yard_y), (cx + 11.0, yard_y)],
                         13.0, lib, col, material=lib.cobbles, lift=0.03,
                         layer=12))
    made.append(dovecote("yard.dovecote", cx + 8.4, yard_y + 4.2, lib, col))
    made.append(pump("yard.pump", cx - 8.6, yard_y + 3.4, lib, col,
                     yaw=math.radians(200)))
    trough = mk.box("yard.trough", (cx - 8.6, yard_y + 2.4,
                                    T.height(cx - 8.6, yard_y + 2.4) + 0.28),
                    (0.85, 2.0, 0.56), col)
    mk.set_material(trough, lib.stone)
    made.append(trough)
    return made


def cupola(name: str, cx: float, cy: float, base_z: float, lib: Library, col,
           width: float = 2.1, height: float = 2.4) -> list[bpy.types.Object]:
    """A louvred belvedere with an ogee cap and a vane."""
    made = []
    body = mk.box(f"{name}.body", (cx, cy, base_z + height / 2),
                  (width, width, height), col)
    mk.set_material(body, lib.trim)
    made.append(body)
    louvres = []
    for face in range(4):
        yaw = math.pi / 2 * face
        for i in range(6):
            z = base_z + height * (0.12 + 0.72 * i / 6)
            sl = mk.box(f"{name}.lv{face}{i}", (0, 0, 0),
                        (width * 0.78, 0.05, height * 0.10), col)
            mk.transform(sl, Matrix.Translation((cx, cy, z))
                         @ Matrix.Rotation(yaw, 4, 'Z')
                         @ Matrix.Translation((0.0, width / 2 + 0.02, 0.0))
                         @ Matrix.Rotation(math.radians(30), 4, 'X'))
            louvres.append(sl)
    lv = mk.join(louvres, f"{name}.louvres", col)
    mk.set_material(lv, lib.accent_dark)
    made.append(lv)

    cor = mk.sweep(f"{name}.cornice", orn.cornice_profile(0.26, 0.24),
                   mk.rect_path(cx - width / 2 - 0.04, cy - width / 2 - 0.04,
                                cx + width / 2 + 0.04, cy + width / 2 + 0.04,
                                base_z + height), closed_path=True, col=col)
    mk.recalc_normals(cor)
    mk.set_material(cor, lib.trim)
    made.append(cor)

    # An ogee (bell) cap.
    prof = [(width * 0.80, 0.0)]
    n = 10
    for i in range(1, n + 1):
        t = i / n
        r = width * 0.80 * (1 - t) ** 0.62 * (1.0 - 0.35 * math.sin(math.pi * t))
        prof.append((max(0.0, r), height * 0.85 * t))
    prof[-1] = (0.0, height * 0.85)
    cap = mk.lathe(f"{name}.cap", prof, 16,
                   center=(cx, cy, base_z + height + 0.24), col=col)
    mk.shade_smooth(cap, math.radians(34))
    mk.set_material(cap, lib.copper)
    made.append(cap)

    fin = orn.finial(f"{name}.finial", 1.1, 0.16, 14, "ball", col)
    mk.transform(fin, Matrix.Translation(
        (cx, cy, base_z + height + 0.24 + height * 0.85 - 0.1)))
    mk.set_material(fin, lib.copper)
    made.append(fin)
    return made


# ---------------------------------------------------------------------------
# Conservatory
# ---------------------------------------------------------------------------

def conservatory(lib: Library, col) -> list[bpy.types.Object]:
    """A curvilinear iron-and-glass house on a low brick dwarf wall."""
    made = []
    cx, cy = config.CONSERVATORY_XY
    sx, sy = 9.0, 13.0
    pad, z0 = _pad("conservatory", cx, cy, sx, sy, lib, col, lift=0.10)
    made.append(pad)

    wall_h = 0.95
    dwarf = mk.prism("conservatory.dwarf",
                     [(cx - sx / 2, cy - sy / 2), (cx + sx / 2, cy - sy / 2),
                      (cx + sx / 2, cy + sy / 2), (cx - sx / 2, cy + sy / 2)],
                     z0, z0 + wall_h, col)
    mk.set_material(dwarf, lib.brick)
    made.append(dwarf)
    cop = mk.sweep("conservatory.coping", orn.cyma_reversa(0.16, 0.12),
                   mk.rect_path(cx - sx / 2 - 0.06, cy - sy / 2 - 0.06,
                                cx + sx / 2 + 0.06, cy + sy / 2 + 0.06,
                                z0 + wall_h), closed_path=True, col=col)
    mk.recalc_normals(cop)
    mk.set_material(cop, lib.stone)
    made.append(cop)

    # A barrel vault of glass on iron ribs.
    eave = z0 + wall_h + 2.5
    radius = sx / 2
    ribs = []
    glass_faces = []
    n_arc = 14
    n_bays = 11
    for b in range(n_bays + 1):
        y = cy - sy / 2 + sy * b / n_bays
        pts = [(cx + radius * math.cos(math.pi * i / n_arc),
                eave + radius * math.sin(math.pi * i / n_arc))
               for i in range(n_arc + 1)]
        for i in range(n_arc):
            a = Vector((pts[i][0], y, pts[i][1]))
            bb = Vector((pts[i + 1][0], y, pts[i + 1][1]))
            rib = mk.box(f"conservatory.rib{b}.{i}", (0, 0, 0),
                         (0.055, 0.055, (bb - a).length), col)
            mid = (a + bb) / 2
            d = (bb - a).normalized()
            rot = d.to_track_quat('Z', 'Y').to_euler()
            mk.transform(rib, Matrix.Translation(mid)
                         @ rot.to_matrix().to_4x4())
            ribs.append(rib)
        if b < n_bays:
            y2 = cy - sy / 2 + sy * (b + 1) / n_bays
            for i in range(n_arc):
                glass_faces.append((
                    (pts[i][0], y, pts[i][1]), (pts[i][0], y2, pts[i][1]),
                    (pts[i + 1][0], y2, pts[i + 1][1]),
                    (pts[i + 1][0], y, pts[i + 1][1])))
    # Longitudinal purlins.
    for i in range(0, n_arc + 1, 2):
        a = Vector((cx + radius * math.cos(math.pi * i / n_arc),
                    cy - sy / 2, eave + radius * math.sin(math.pi * i / n_arc)))
        bb = Vector((a.x, cy + sy / 2, a.z))
        purlin = mk.box(f"conservatory.purlin{i}", (0, 0, 0),
                        (0.045, (bb - a).length, 0.045), col)
        mk.transform(purlin, Matrix.Translation((a + bb) / 2))
        ribs.append(purlin)
    frame = mk.join(ribs, "conservatory.frame", col)
    mk.set_material(frame, lib.iron)
    made.append(frame)

    verts, faces = [], []
    for quad in glass_faces:
        base = len(verts)
        verts += [tuple(p) for p in quad]
        faces.append((base, base + 1, base + 2, base + 3))
    glazing = mk.obj_from("conservatory.glazing", verts, faces, col=col)
    mk.solidify(glazing, 0.006)
    mk.set_material(glazing, lib.glass)
    made.append(glazing)

    # Gable-end glazing and a door.
    for sgn in (-1, 1):
        y = cy + sgn * sy / 2
        arc_pts = [(cx + radius * math.cos(math.pi * i / n_arc),
                    eave + radius * math.sin(math.pi * i / n_arc))
                   for i in range(n_arc + 1)]
        poly = [(cx - radius, eave)] + arc_pts + [(cx + radius, eave)]
        end = mk.prism_y(f"conservatory.end{sgn}", poly, y, y + sgn * 0.05, col)
        mk.set_material(end, lib.glass)
        made.append(end)

    made += conservatory_interior(cx, cy, sx, sy, z0 + wall_h, lib, col)

    ridge = orn.cresting("conservatory.cresting", sy, 0.34, 0.016 * 20, 0.016,
                         col)
    mk.transform(ridge, Matrix.Translation((cx, cy - sy / 2, eave + radius))
                 @ Matrix.Rotation(math.pi / 2, 4, 'Z'))
    mk.set_material(ridge, lib.iron)
    made.append(ridge)
    return made


def palm(name: str, x: float, y: float, z: float, lib: Library, col,
         height: float = 3.2, fronds: int = 11, seed: int = 0
         ) -> bpy.types.Object:
    """A tub palm - the thing every Victorian conservatory was full of."""
    rng = random.Random(seed)
    parts = []
    tub = mk.lathe(f"{name}.tub", [
        (0.0, 0.0), (0.30, 0.0), (0.32, 0.04), (0.34, 0.44), (0.38, 0.50),
        (0.38, 0.56), (0.34, 0.58), (0.32, 0.54), (0.30, 0.10), (0.0, 0.10),
    ], 14, center=(x, y, z), col=col)
    mk.set_material(tub, lib.brick)
    parts.append(tub)

    trunk_h = height * 0.42
    trunk = mk.lathe(f"{name}.trunk", [
        (0.11, 0.0), (0.095, trunk_h * 0.4), (0.082, trunk_h * 0.75),
        (0.075, trunk_h)], 9, center=(x, y, z + 0.5), col=col)
    mk.set_material(trunk, lib.bark)
    parts.append(trunk)

    crown = z + 0.5 + trunk_h
    blades = []
    for i in range(fronds):
        az = math.tau * i / fronds + rng.uniform(-0.2, 0.2)
        droop = rng.uniform(0.35, 0.85)
        length = (height - trunk_h - 0.5) * rng.uniform(0.85, 1.25)
        # A frond as a tapering strip that bends over under its own weight.
        verts, faces = [], []
        segs = 6
        for k in range(segs + 1):
            t = k / segs
            r = length * t
            zz = crown + length * (0.42 * t - droop * t * t)
            w = 0.16 * (1.0 - 0.75 * t) * (0.4 + 0.6 * math.sin(math.pi * t))
            for side in (-1, 1):
                verts.append((x + r * math.cos(az) - side * w * math.sin(az),
                              y + r * math.sin(az) + side * w * math.cos(az),
                              zz))
        for k in range(segs):
            a = k * 2
            faces.append((a, a + 2, a + 3, a + 1))
        blades.append(mk.obj_from(f"{name}.frond{i}", verts, faces, col=col))
    fr = mk.join(blades, f"{name}.fronds", col)
    mk.set_material(fr, lib.leaf)
    parts.append(fr)
    return mk.join(parts, name, col)


def conservatory_interior(cx: float, cy: float, sx: float, sy: float,
                          z: float, lib: Library, col
                          ) -> list[bpy.types.Object]:
    """Staging down both sides, a tiled walk, and a collection of palms.

    Worth the geometry: the whole point of a glasshouse is that you see into
    it, and an empty one reads as an oddly shaped shed.
    """
    made = []
    rng = random.Random(31)
    walk = mk.prism("conservatory.walk",
                    [(cx - 1.3, cy - sy / 2 + 0.4), (cx + 1.3, cy - sy / 2 + 0.4),
                     (cx + 1.3, cy + sy / 2 - 0.4), (cx - 1.3, cy + sy / 2 - 0.4)],
                    z - 0.94, z - 0.90, col)
    mk.set_material(walk, lib.stone)
    made.append(walk)

    staging = []
    for sgn in (-1, 1):
        bx = cx + sgn * (sx / 2 - 1.05)
        top = mk.box(f"conservatory.bench{sgn}", (bx, cy, z - 0.10),
                     (1.7, sy - 1.4, 0.07), col)
        staging.append(top)
        for i in range(6):
            ly = cy - sy / 2 + 0.9 + i * (sy - 1.8) / 5
            staging.append(mk.box(f"conservatory.leg{sgn}{i}", (bx, ly, z - 0.52),
                                  (1.5, 0.06, 0.84), col))
    st = mk.join(staging, "conservatory.staging", col)
    mk.set_material(st, lib.iron)
    made.append(st)

    # Pots on the staging.  Positions are settled once and reused for the
    # foliage, so each plant sits in a pot rather than beside one.
    spots = []
    for i in range(46):
        sgn = 1 if i % 2 else -1
        spots.append((cx + sgn * (sx / 2 - 1.05) + rng.uniform(-0.55, 0.55),
                      cy + rng.uniform(-sy / 2 + 1.0, sy / 2 - 1.0),
                      rng.uniform(0.7, 1.3)))

    proto = mk.lathe("conservatory.potproto",
                     [(0.0, 0.0), (0.11, 0.0), (0.13, 0.15), (0.145, 0.19),
                      (0.125, 0.20), (0.105, 0.16), (0.0, 0.16)], 10, col=col)
    pots = [mk.instance(proto, f"conservatory.pot{i}", (px, py, z - 0.06),
                        scale=(ps, ps, ps), col=col)
            for i, (px, py, ps) in enumerate(spots)]
    bpy.data.objects.remove(proto)
    po = mk.join(pots, "conservatory.pots", col)
    mk.set_material(po, lib.brick)
    made.append(po)

    # Foliage in those pots, and palms in tubs down the walk.
    from .planting import _blob
    leaf_v, leaf_f = [], []
    for px, py, ps in spots:
        vs, fs = _blob(rng, 0.20 * ps, 0.45)
        base = len(leaf_v)
        for vx, vy, vz in vs:
            leaf_v.append((px + vx, py + vy, z + 0.10 + 0.16 * ps + vz))
        for f in fs:
            leaf_f.append(tuple(base + k for k in f))
    greens = mk.obj_from("conservatory.potplants", leaf_v, leaf_f, col=col)
    mk.set_material(greens, lib.leaf)
    mk.shade_smooth(greens, math.radians(60))
    made.append(greens)

    for i, ty in enumerate((-3.6, -0.6, 2.6, 5.0)):
        made.append(palm(f"conservatory.palm{i}", cx + (0.6 if i % 2 else -0.6),
                         cy + ty, z - 0.90, lib, col,
                         height=rng.uniform(2.6, 3.9), seed=i))
    return made


# ---------------------------------------------------------------------------
# Gazebo, lodge and water
# ---------------------------------------------------------------------------

def gazebo(lib: Library, col, sides: int = 8) -> list[bpy.types.Object]:
    """An octagonal summer house with turned posts and a spindle frieze."""
    made = []
    cx, cy = config.GAZEBO_XY
    r = 3.0
    z0 = max(T.height(cx + r * math.cos(math.tau * i / sides),
                      cy + r * math.sin(math.tau * i / sides))
             for i in range(sides)) + 0.55

    base = mk.lathe("gazebo.base", [(0.0, -1.6), (r + 0.55, -1.6),
                                    (r + 0.55, -0.12), (r + 0.40, 0.0),
                                    (0.0, 0.0)], sides,
                    start=math.pi / sides, center=(cx, cy, z0), col=col)
    mk.set_material(base, lib.stone)
    made.append(base)

    deck_z = z0
    ceil_z = z0 + 2.85
    posts, rails = [], []
    proto = orn.turned_post("gazebo.postproto", ceil_z - deck_z - 0.20, 0.20,
                            16, "veranda", col)
    pts = [(cx + r * math.cos(math.tau * i / sides + math.pi / sides),
            cy + r * math.sin(math.tau * i / sides + math.pi / sides))
           for i in range(sides)]
    for i, (px, py) in enumerate(pts):
        posts.append(mk.instance(proto, f"gazebo.post{i}",
                                 (px, py, deck_z + 0.10), col=col))
    bpy.data.objects.remove(proto)
    made.append(mk.set_material(mk.join(posts, "gazebo.posts", col), lib.trim))

    bal_proto = orn.baluster("gazebo.balproto", 0.66, 0.075, 12, "vase", col)
    for i in range(sides):
        a = pts[i]
        b = pts[(i + 1) % sides]
        if i == 0:
            continue                       # the entrance bay
        d = Vector((b[0] - a[0], b[1] - a[1], 0.0))
        length = d.length - 0.30
        yaw = math.atan2(d.y, d.x)
        mid = Vector(((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, 0.0))
        rail = mk.sweep_straight(f"gazebo.rail{i}",
                                 orn.handrail_profile(0.12, 0.075),
                                 (-length / 2, 0, 0), (length / 2, 0, 0),
                                 (0, 1, 0), col=col)
        mk.transform(rail, Matrix.Translation(mid + Vector((0, 0, deck_z + 0.92)))
                     @ Matrix.Rotation(yaw, 4, 'Z'))
        rails.append(rail)
        n = max(3, int(length / 0.17))
        for k in range(n):
            t = (k + 0.5) / n
            p = Vector((a[0], a[1], 0)).lerp(Vector((b[0], b[1], 0)), t)
            rails.append(mk.instance(bal_proto, f"gazebo.bal{i}.{k}",
                                     (p.x, p.y, deck_z + 0.20), col=col))
        fz = orn.spindle_frieze(f"gazebo.frieze{i}", length, 0.42, 0.045,
                                0.12, 10, col)
        mk.transform(fz, Matrix.Translation(
            Vector((a[0], a[1], ceil_z - 0.62)) + d.normalized() * 0.15)
            @ Matrix.Rotation(yaw, 4, 'Z'))
        rails.append(fz)
    bpy.data.objects.remove(bal_proto)
    made.append(mk.set_material(mk.join(rails, "gazebo.rails", col), lib.trim))

    plate = mk.lathe("gazebo.plate", [(r - 0.16, 0.0), (r + 0.30, 0.0),
                                      (r + 0.30, 0.26), (r - 0.16, 0.26)],
                     sides, start=math.pi / sides,
                     center=(cx, cy, ceil_z - 0.26), col=col)
    mk.set_material(plate, lib.trim)
    made.append(plate)

    spire_h = 3.4
    roof = mk.lathe("gazebo.roof", [(r + 0.62, 0.0), (r * 0.62, spire_h * 0.42),
                                    (r * 0.28, spire_h * 0.76), (0.0, spire_h)],
                    sides, start=math.pi / sides,
                    center=(cx, cy, ceil_z), col=col)
    mk.set_material(roof, lib.slate)
    made.append(roof)
    fin = orn.finial("gazebo.finial", 1.5, 0.18, 14, "spike", col)
    mk.transform(fin, Matrix.Translation((cx, cy, ceil_z + spire_h - 0.2)))
    mk.set_material(fin, lib.copper)
    made.append(fin)
    return made


def lodge(lib: Library, col) -> list[bpy.types.Object]:
    """A gate lodge beside the entrance, in the same idiom as the house."""
    made = []
    cx, cy = -12.5, config.GATE_Y - 7.0
    sx, sy = 9.0, 8.0
    pad, z0 = _pad("lodge", cx, cy, sx, sy, lib, col)
    made.append(pad)
    eave = z0 + 4.6
    body = mk.prism("lodge.body",
                    [(cx - sx / 2, cy - sy / 2), (cx + sx / 2, cy - sy / 2),
                     (cx + sx / 2, cy + sy / 2), (cx - sx / 2, cy + sy / 2)],
                    z0, eave, col)
    mk.set_material(body, lib.body)
    made.append(body)

    for i, (ox, oy, yaw) in enumerate([(cx - 2.4, cy + sy / 2, 0.0),
                                       (cx + 2.4, cy + sy / 2, 0.0),
                                       (cx + sx / 2, cy, -math.pi / 2)]):
        spec = W.WindowSpec(width=1.05, height=1.95, wall_t=0.4,
                            hood="label", corner_blocks=False)
        cut = mk.prism_y(f"lodge.cut{i}",
                         mk.offset_polygon(W.opening_outline(spec), 0.006),
                         -0.6, 0.6, col)
        mk.transform(cut, Matrix.Translation((ox, oy, z0 + 0.95))
                     @ Matrix.Rotation(yaw, 4, 'Z'))
        mk.boolean(body, cut)
        wnd = W.build(f"lodge.win{i}", spec, lib, col)
        W.place(wnd, ox, oy, z0 + 0.95, yaw)
        made.append(wnd)

    cor = mk.sweep("lodge.cornice", orn.cornice_profile(0.42, 0.34),
                   mk.rect_path(cx - sx / 2 - 0.05, cy - sy / 2 - 0.05,
                                cx + sx / 2 + 0.05, cy + sy / 2 + 0.05, eave),
                   closed_path=True, col=col)
    mk.recalc_normals(cor)
    mk.set_material(cor, lib.trim)
    made.append(cor)
    made += _slated_gable("lodge.roof", cx, cy, sx, sy, eave + 0.34, 48.0,
                          lib, col, along_x=False)
    made.append(chimney("lodge.chimney", lib, col, cx - 2.0, cy, z0 + 3.0,
                        eave + 4.6, 0.9, 0.7, 2))
    return made


def pond(lib: Library, col) -> list[bpy.types.Object]:
    """An ornamental lake in the hollow, with a reedy margin."""
    made = []
    cx, cy = config.POND_XY
    level = T.height(cx, cy) + 1.35
    rng = random.Random(9)
    pts = []
    n = 40
    for i in range(n):
        a = math.tau * i / n
        r = 15.0 * (1.0 + 0.24 * math.sin(a * 3 + 0.6)
                    + 0.12 * math.sin(a * 5 - 1.2))
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    surface = mk.prism("pond.water", pts, level - 0.4, level, col)
    mk.set_material(surface, lib.water)
    made.append(surface)

    # A shallow shelf of mud and reeds round the edge.
    reeds = []
    for i in range(150):
        a = rng.uniform(0, math.tau)
        r = 15.0 * (1.0 + 0.24 * math.sin(a * 3 + 0.6)
                    + 0.12 * math.sin(a * 5 - 1.2)) * rng.uniform(0.96, 1.06)
        x, y = cx + r * math.cos(a), cy + r * math.sin(a)
        h = rng.uniform(0.7, 1.5)
        blade = mk.box(f"pond.reed{i}", (0, 0, 0), (0.05, 0.05, h), col)
        mk.transform(blade, Matrix.Translation((x, y, level + h / 2 - 0.2))
                     @ Matrix.Rotation(rng.uniform(0, math.tau), 4, 'Z')
                     @ Matrix.Rotation(rng.uniform(-0.2, 0.2), 4, 'X'))
        reeds.append(blade)
    obj = mk.join(reeds, "pond.reeds", col)
    mk.set_material(obj, lib.hedge)
    made.append(obj)
    return made
