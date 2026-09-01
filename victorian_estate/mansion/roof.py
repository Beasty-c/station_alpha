"""
Roofs: the mansard over the main block, gables over the wing and pavilion,
dormers, ridge cresting, finials and chimney stacks.

The slating is modelled slate by slate rather than textured.  A mansard's
lower slope is nearly vertical and reads at eye level, so the thing that
actually sells it is the shadow under each butt edge and the slight
irregularity of a hand-laid course - neither of which a bump map gives you at
a raking sun angle.  :func:`slate_field` therefore emits the vertices and
faces for a whole face in one pass (a few thousand slates), which is far
cheaper than building and joining that many objects.
"""

from __future__ import annotations

import math
import random
from dataclasses import dataclass

import bpy
from mathutils import Matrix, Vector

from ..core import config, meshkit as mk, ornament as orn
from ..core.materials import Library
from . import windows as W


# ---------------------------------------------------------------------------
# Slating
# ---------------------------------------------------------------------------

@dataclass
class Face:
    """A planar quadrilateral roof face, corners given as seen from outside."""

    bl: Vector
    br: Vector
    tr: Vector
    tl: Vector

    @property
    def normal(self) -> Vector:
        n = (self.br - self.bl).cross(self.tl - self.bl)
        return n.normalized()

    def point(self, u: float, v: float) -> Vector:
        """Bilinear point; u across the face, v up the slope, both 0..1."""
        bottom = self.bl.lerp(self.br, u)
        top = self.tl.lerp(self.tr, u)
        return bottom.lerp(top, v)

    @property
    def slope_length(self) -> float:
        return ((self.tl - self.bl).length + (self.tr - self.br).length) / 2.0


def slate_field(name: str, face: Face, lib: Library, col,
                exposure: float = config.SLATE_EXPOSURE,
                width: float = config.SLATE_W,
                thickness: float = 0.014,
                bands: tuple[int, ...] = (),
                jitter: float = 1.0,
                seed: int = 0) -> bpy.types.Object:
    """Tile a roof face with individually modelled slates.

    Courses run bottom to top with a half-slate stagger.  ``bands`` names
    course indices to be laid in the accent colour, which is how the
    patterned bands on a Second Empire mansard are made.
    """
    rng = random.Random(seed)
    # Every roof slope in the model faces upward, so a face whose normal
    # points down was wound the wrong way round.  Mirroring it horizontally
    # reverses the normal while leaving the courses running horizontally,
    # which swapping a diagonal pair would not.
    if face.normal.z < 0.0:
        face = Face(face.br, face.bl, face.tl, face.tr)
    normal = face.normal
    slope = face.slope_length
    courses = max(1, int(math.ceil(slope / exposure)))

    verts: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    mat_index: list[int] = []

    for c in range(courses):
        v0 = c * exposure / slope
        v1 = min(1.0, (c * exposure + width * 1.35) / slope)
        if v0 >= 1.0:
            break
        # Physical width of the face at this course sets how many slates fit.
        left = face.bl.lerp(face.tl, v0)
        right = face.br.lerp(face.tr, v0)
        run = (right - left).length
        if run < width * 0.5:
            continue
        n_slates = max(1, int(round(run / width)))
        stagger = 0.5 if c % 2 else 0.0
        band = 1 if c in bands else 0

        for s in range(-1, n_slates + 1):
            u0 = (s + stagger) / n_slates
            u1 = (s + stagger + 1.0) / n_slates
            if u1 <= 0.0 or u0 >= 1.0:
                continue
            u0, u1 = max(0.0, u0), min(1.0, u1)
            gap = (u1 - u0) * 0.045
            u0 += gap
            u1 -= gap
            if u1 <= u0:
                continue

            lift = thickness * (1.0 + rng.uniform(-0.25, 0.55) * jitter)
            tilt = rng.uniform(-0.0035, 0.0035) * jitter
            base = len(verts)
            for (uu, vv, extra) in ((u0, v0, tilt), (u1, v0, -tilt),
                                    (u1, v1, 0.0), (u0, v1, 0.0)):
                p = face.point(uu, vv) + normal * (lift + extra)
                verts.append((p.x, p.y, p.z))
            for (uu, vv) in ((u0, v0), (u1, v0), (u1, v1), (u0, v1)):
                p = face.point(uu, vv) + normal * (lift * 0.06)
                verts.append((p.x, p.y, p.z))
            f, b = base, base + 4
            faces += [(f, f + 1, f + 2, f + 3),          # exposed face
                      (b + 3, b + 2, b + 1, b),          # underside
                      (b, b + 1, f + 1, f),              # the butt edge
                      (b + 1, b + 2, f + 2, f + 1),
                      (b + 2, b + 3, f + 3, f + 2),
                      (b + 3, b, f, f + 3)]
            mat_index += [band] * 6

    obj = mk.obj_from(name, verts, faces, col=col)
    obj.data.materials.append(lib.slate)
    obj.data.materials.append(lib.slate_band)
    for poly, idx in zip(obj.data.polygons, mat_index):
        poly.material_index = idx
    return obj


# ---------------------------------------------------------------------------
# Mansard
# ---------------------------------------------------------------------------

def _rect(cx: float, cy: float, hx: float, hy: float, z: float
          ) -> list[Vector]:
    """Corner ring in plan order SW, SE, NE, NW at height z."""
    return [Vector((cx - hx, cy - hy, z)), Vector((cx + hx, cy - hy, z)),
            Vector((cx + hx, cy + hy, z)), Vector((cx - hx, cy + hy, z))]


def _loft(name: str, lower: list[Vector], upper: list[Vector], col,
          cap_top: bool = False) -> bpy.types.Object:
    """The solid band between two matched rings - one storey of a roof."""
    n = len(lower)
    verts = [tuple(p) for p in lower] + [tuple(p) for p in upper]
    faces = [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    if cap_top:
        faces.append(tuple(range(n, 2 * n)))
    obj = mk.obj_from(name, verts, faces, col=col)
    # An open band has no volume to orient from, so point the faces away from
    # the roof's own vertical axis explicitly.
    axis = sum((p for p in lower + upper), Vector()) / (2 * n)
    mk.orient_outward(obj, (axis.x, axis.y, axis.z))
    return obj


def mansard(b: config.Block, lib: Library, col, eave_z: float,
            lower_run: float = config.MANSARD_LOWER_RUN,
            lower_rise: float = config.MANSARD_LOWER_RISE,
            upper_run: float = 3.6,
            upper_rise: float = config.MANSARD_UPPER_RISE,
            overhang: float = 0.42, slate: bool = True,
            band_courses: tuple[int, ...] = (7, 8, 16, 17, 18)
            ) -> list[bpy.types.Object]:
    """A Second Empire mansard: steep slated lower slope, shallow upper slope,
    flat deck.  Returns the structure plus the slating."""
    made: list[bpy.types.Object] = []
    hx, hy = b.sx / 2 + overhang, b.sy / 2 + overhang

    eave = _rect(b.cx, b.cy, hx, hy, eave_z)
    knuckle = _rect(b.cx, b.cy, hx - lower_run, hy - lower_run,
                    eave_z + lower_rise)
    deck_hx = max(1.6, hx - lower_run - upper_run)
    deck_hy = max(1.6, hy - lower_run - upper_run)
    deck = _rect(b.cx, b.cy, deck_hx, deck_hy,
                 eave_z + lower_rise + upper_rise)

    steep = _loft(f"{b.name}.mansard.lower", eave, knuckle, col)
    mk.set_material(steep, lib.slate)
    made.append(steep)
    shallow = _loft(f"{b.name}.mansard.upper", knuckle, deck, col,
                    cap_top=True)
    mk.set_material(shallow, lib.slate)
    made.append(shallow)

    # A soffit closing the eave overhang back to the wall.
    soffit = _loft(f"{b.name}.mansard.soffit",
                   _rect(b.cx, b.cy, b.sx / 2, b.sy / 2, eave_z), eave, col)
    mk.set_material(soffit, lib.trim)
    made.append(soffit)

    if slate:
        for i in range(4):
            j = (i + 1) % 4
            f = Face(eave[i], eave[j], knuckle[j], knuckle[i])
            made.append(slate_field(f"{b.name}.slate.lo{i}", f, lib, col,
                                    bands=band_courses, seed=i * 71))
            f2 = Face(knuckle[i], knuckle[j], deck[j], deck[i])
            made.append(slate_field(f"{b.name}.slate.up{i}", f2, lib, col,
                                    exposure=config.SLATE_EXPOSURE * 1.15,
                                    jitter=0.6, seed=100 + i * 31))

    # Cast-iron cresting round the deck, with corner standards.
    for i in range(4):
        j = (i + 1) % 4
        a, bb = deck[i], deck[j]
        run = (bb - a).length
        crest = orn.cresting(f"{b.name}.crest{i}", run, config.CRESTING_H,
                             0.32, 0.020, col)
        yaw = math.atan2(bb.y - a.y, bb.x - a.x)
        mk.transform(crest, Matrix.Translation(a)
                     @ Matrix.Rotation(yaw, 4, 'Z'))
        mk.set_material(crest, lib.iron)
        made.append(crest)
    for corner in deck:
        f = orn.finial(f"{b.name}.deckfin", config.CRESTING_H * 2.4, 0.10,
                       12, "spike", col)
        mk.transform(f, Matrix.Translation(corner))
        mk.set_material(f, lib.iron)
        made.append(f)

    return made


# ---------------------------------------------------------------------------
# Dormers
# ---------------------------------------------------------------------------

def dormer(name: str, lib: Library, col, width: float = 1.34,
           height: float = 2.05, projection: float = 0.95,
           style: str = "segmental") -> bpy.types.Object:
    """A mansard dormer: cheeks, a window, a hood and its own little roof."""
    parts = []
    spec = W.WindowSpec(width=width - 0.42, height=height - 0.30,
                        head="segmental" if style != "gable" else "flat",
                        upper_lights=(1, 1), lower_lights=(1, 1),
                        wall_t=0.22, reveal=0.07, casing_w=0.10,
                        casing_d=0.032, sill_proj=0.09, sill_h=0.07,
                        apron=False, hood="none")
    head_z = spec.head_z

    # Box body: two cheeks, a head and a sill board.
    body_h = head_z + 0.30
    for sgn in (-1, 1):
        cheek = mk.box(f"{name}.cheek{sgn}",
                       (sgn * (width / 2 - 0.10), -projection / 2, body_h / 2),
                       (0.20, projection, body_h), col)
        mk.set_material(cheek, lib.trim)
        parts.append(cheek)
    head = mk.box(f"{name}.head", (0.0, -projection / 2, body_h - 0.11),
                  (width, projection, 0.22), col)
    mk.set_material(head, lib.trim)
    parts.append(head)

    win = W.build(f"{name}.win", spec, lib, col)
    parts.append(win)

    # Roof over the dormer.
    if style == "gable":
        rise = width * 0.42
        for sgn in (-1, 1):
            a = (sgn * (width / 2 + 0.20), 0.10, body_h)
            bp = (0.0, 0.10, body_h + rise)
            run, climb = bp[0] - a[0], bp[2] - a[2]
            L = math.hypot(run, climb)
            up = (-climb / L, 0.0, run / L)
            if up[2] < 0:
                up = (-up[0], 0.0, -up[2])
            rake = mk.sweep_straight(f"{name}.rake{sgn}",
                                     orn.cyma_recta(0.14, 0.17), a, bp,
                                     (0, 1, 0), up=up, col=col)
            mk.set_material(rake, lib.trim)
            parts.append(rake)
        tym = mk.prism_y(f"{name}.tympanum",
                         [(-width / 2 - 0.2, body_h), (width / 2 + 0.2, body_h),
                          (0.0, body_h + rise)], -projection, 0.10, col)
        mk.set_material(tym, lib.body_upper)
        parts.append(tym)
    else:
        # A flat-capped hood on a pair of little consoles.
        cap = mk.box(f"{name}.cap", (0.0, -projection / 2 + 0.06,
                                     body_h + 0.10),
                     (width + 0.44, projection + 0.24, 0.20), col)
        mk.set_material(cap, lib.trim)
        parts.append(cap)
        cor = mk.sweep_straight(f"{name}.cornice",
                                orn.cornice_profile(0.30, 0.26),
                                (-width / 2 - 0.26, 0.06, body_h + 0.20),
                                (width / 2 + 0.26, 0.06, body_h + 0.20),
                                (0, 1, 0), col=col)
        mk.set_material(cor, lib.trim)
        parts.append(cor)
        crown = mk.box(f"{name}.crown", (0.0, -projection / 2 + 0.06,
                                         body_h + 0.50),
                       (width + 0.30, projection + 0.16, 0.40), col)
        mk.set_material(crown, lib.slate)
        parts.append(crown)

    for sgn in (-1, 1):
        br = orn.bracket(f"{name}.br{sgn}", 0.26, 0.56, 0.05, "console",
                         pierce=False, col=col)
        mk.transform(br, Matrix.Translation(
            (sgn * (width / 2 + 0.16), 0.05, body_h))
            @ Matrix.Rotation(math.pi / 2, 4, 'Z')
            @ Matrix.Scale(sgn, 4, (0.0, 1.0, 0.0)))
        mk.recalc_normals(br)
        mk.set_material(br, lib.trim)
        parts.append(br)

    return mk.join(parts, name, col)


def place_dormers(b: config.Block, lib: Library, col, eave_z: float,
                  counts: dict[str, int], inset: float = 0.55,
                  overhang: float = 0.42, style: str = "segmental"
                  ) -> list[bpy.types.Object]:
    """Space dormers evenly along each side of a mansard's lower slope."""
    from .shell import Elevation, SIDES
    made = []
    proto = dormer(f"{b.name}.dormer.proto", lib, col, style=style)
    for side, count in counts.items():
        if count <= 0:
            continue
        normal, yaw = SIDES[side]
        nx, ny = normal
        span = b.sx if side in ("south", "north") else b.sy
        for i in range(count):
            off = -span / 2 + span * (i + 0.5) / count
            if side == "south":
                px, py = off, b.y1 + overhang - inset
            elif side == "north":
                px, py = -off, b.y0 - overhang + inset
            elif side == "east":
                px, py = b.x1 + overhang - inset, -off
            else:
                px, py = b.x0 - overhang + inset, off
            made.append(mk.instance(proto, f"{b.name}.dormer.{side}.{i}",
                                    (px, py, eave_z + 0.30),
                                    rotation=(0.0, 0.0, yaw), col=col))
    data = proto.data
    bpy.data.objects.remove(proto)
    joined = mk.join(made, f"{b.name}.dormers", col)
    return [joined]


# ---------------------------------------------------------------------------
# Gable roofs, for the wing and the pavilion
# ---------------------------------------------------------------------------

def gable_roof(b: config.Block, lib: Library, col, eave_z: float,
               pitch: float = 52.0, along_x: bool = True,
               overhang: float = 0.55, bargeboard: bool = True,
               slate: bool = True) -> list[bpy.types.Object]:
    """A pitched roof with sawn bargeboards and a finial at each gable apex."""
    made: list[bpy.types.Object] = []
    hx, hy = b.sx / 2 + overhang, b.sy / 2 + overhang
    half_span = hy if along_x else hx
    rise = half_span * math.tan(math.radians(pitch))
    ridge_z = eave_z + rise

    if along_x:
        eave_l = [Vector((b.cx - hx, b.cy - hy, eave_z)),
                  Vector((b.cx + hx, b.cy - hy, eave_z))]
        eave_r = [Vector((b.cx - hx, b.cy + hy, eave_z)),
                  Vector((b.cx + hx, b.cy + hy, eave_z))]
        ridge = [Vector((b.cx - hx, b.cy, ridge_z)),
                 Vector((b.cx + hx, b.cy, ridge_z))]
    else:
        eave_l = [Vector((b.cx - hx, b.cy - hy, eave_z)),
                  Vector((b.cx - hx, b.cy + hy, eave_z))]
        eave_r = [Vector((b.cx + hx, b.cy - hy, eave_z)),
                  Vector((b.cx + hx, b.cy + hy, eave_z))]
        ridge = [Vector((b.cx, b.cy - hy, ridge_z)),
                 Vector((b.cx, b.cy + hy, ridge_z))]

    faces = [Face(eave_l[0], eave_l[1], ridge[1], ridge[0]),
             Face(eave_r[1], eave_r[0], ridge[0], ridge[1])]
    for i, f in enumerate(faces):
        deck = mk.obj_from(f"{b.name}.roofdeck{i}",
                           [tuple(f.bl), tuple(f.br), tuple(f.tr), tuple(f.tl)],
                           [(0, 1, 2, 3)], col=col)
        mk.solidify(deck, 0.12)
        mk.set_material(deck, lib.slate)
        made.append(deck)
        if slate:
            made.append(slate_field(f"{b.name}.gslate{i}", f, lib, col,
                                    seed=17 + i * 53))

    # Gable end walls, bargeboards and apex finials.
    for end, sign in ((0, -1), (1, 1)):
        if along_x:
            x = b.x0 - overhang if end == 0 else b.x1 + overhang
            tri = [(b.cy - hy, eave_z), (b.cy + hy, eave_z), (b.cy, ridge_z)]
            wall = mk.prism_x(f"{b.name}.gable{end}", tri,
                              x - sign * 0.16, x, col)
            apex = Vector((x, b.cy, ridge_z))
        else:
            y = b.y0 - overhang if end == 0 else b.y1 + overhang
            tri = [(b.cx - hx, eave_z), (b.cx + hx, eave_z), (b.cx, ridge_z)]
            wall = mk.prism_y(f"{b.name}.gable{end}", tri,
                              y - sign * 0.16, y, col)
            apex = Vector((b.cx, y, ridge_z))
        mk.set_material(wall, lib.body_upper)
        made.append(wall)

        if bargeboard:
            for s in (-1, 1):
                run = math.hypot(half_span, rise)
                board = mk.prism_y(
                    f"{b.name}.barge{end}{s}",
                    orn.bargeboard_outline(run, 0.34, max(4, int(run / 0.62)),
                                           0.22, "drop"),
                    -0.055, 0.055, col)
                # The board runs from the ridge DOWN the rake.  A rotation of
                # +ang about Y sends local +X to (cos, 0, -sin); the mirrored
                # board runs along -X and so needs the opposite sign.
                ang = math.atan2(rise, half_span)
                if along_x:
                    m = (Matrix.Translation((x + sign * 0.09, b.cy, ridge_z))
                         @ Matrix.Rotation(math.pi / 2, 4, 'Z')
                         @ Matrix.Rotation(s * ang, 4, 'Y')
                         @ Matrix.Scale(s, 4, (1.0, 0.0, 0.0)))
                else:
                    m = (Matrix.Translation((b.cx, y + sign * 0.09, ridge_z))
                         @ Matrix.Rotation(s * ang, 4, 'Y')
                         @ Matrix.Scale(s, 4, (1.0, 0.0, 0.0)))
                mk.transform(board, m)
                mk.recalc_normals(board)
                mk.set_material(board, lib.trim)
                made.append(board)

        fin = orn.finial(f"{b.name}.gfin{end}", 1.35, 0.16, 14, "spike", col)
        mk.transform(fin, Matrix.Translation(apex + Vector((0, 0, -0.15))))
        mk.set_material(fin, lib.iron)
        made.append(fin)

    # Ridge cresting.
    a, bb = ridge[0], ridge[1]
    run = (bb - a).length
    crest = orn.cresting(f"{b.name}.ridgecrest", run, 0.42, 0.28, 0.018, col)
    yaw = math.atan2(bb.y - a.y, bb.x - a.x)
    mk.transform(crest, Matrix.Translation(a + Vector((0, 0, 0.10)))
                 @ Matrix.Rotation(yaw, 4, 'Z'))
    mk.set_material(crest, lib.iron)
    made.append(crest)
    return made


# ---------------------------------------------------------------------------
# Chimneys
# ---------------------------------------------------------------------------

def chimney(name: str, lib: Library, col, x: float, y: float,
            base_z: float, top_z: float, width: float = 1.30,
            depth: float = 0.95, pots: int = 3) -> bpy.types.Object:
    """A corbelled brick stack with a moulded cap and terracotta pots."""
    parts = []
    shaft = mk.box(f"{name}.shaft", (x, y, (base_z + top_z) / 2),
                   (width, depth, top_z - base_z), col)
    mk.set_material(shaft, lib.brick_chimney)
    parts.append(shaft)

    # Two corbelled bands: each course steps out a little further.
    for k, (zz, grow) in enumerate([(top_z - 1.55, 0.06), (top_z - 1.40, 0.13),
                                    (top_z - 1.25, 0.20)]):
        band = mk.box(f"{name}.corbel{k}", (x, y, zz + 0.075),
                      (width + grow * 2, depth + grow * 2, 0.15), col)
        mk.set_material(band, lib.brick_chimney)
        parts.append(band)

    cap = mk.box(f"{name}.cap", (x, y, top_z + 0.09),
                 (width + 0.44, depth + 0.44, 0.18), col)
    mk.set_material(cap, lib.stone)
    parts.append(cap)
    cor = mk.sweep(f"{name}.capmould",
                   orn.cyma_reversa(0.13, 0.16),
                   mk.rect_path(x - width / 2 - 0.10, y - depth / 2 - 0.10,
                                x + width / 2 + 0.10, y + depth / 2 + 0.10,
                                top_z - 0.02), closed_path=True, col=col)
    mk.recalc_normals(cor)
    mk.set_material(cor, lib.stone)
    parts.append(cor)

    for i in range(pots):
        px = x + (i - (pots - 1) / 2) * (width / max(1, pots)) * 0.92
        pot = mk.lathe(f"{name}.pot{i}", [
            (0.19, 0.0), (0.19, 0.10), (0.16, 0.14), (0.16, 0.62),
            (0.185, 0.70), (0.20, 0.78), (0.185, 0.84), (0.15, 0.86),
            (0.15, 0.16), (0.0, 0.16), (0.0, 0.0),
        ][:8], 14, col=col)
        mk.transform(pot, Matrix.Translation((px, y, top_z + 0.18)))
        mk.shade_smooth(pot, math.radians(40))
        mk.set_material(pot, lib.brick)
        parts.append(pot)

    return mk.join(parts, name, col)
