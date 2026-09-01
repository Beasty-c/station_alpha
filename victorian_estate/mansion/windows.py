"""
Double-hung sash windows and their surrounds.

A Victorian window is a surprising amount of joinery: an outer casing with a
backband, a projecting weathered sill over a moulded apron, a boxed frame,
two sashes each with its own stiles, rails and muntins, and often a hood
mould on brackets over the top.  All of it is modelled here, because the
shadow lines those parts throw are what stop a facade reading as a flat card
with rectangles painted on it.

Everything is built in a canonical local frame and moved into place by the
facade code:

    * the opening is centred on x = 0
    * the sill line sits at z = 0
    * the exterior wall face is the plane y = 0, and the wall runs to -y
    * outward is +y
"""

from __future__ import annotations

import math
from dataclasses import dataclass

import bpy
from mathutils import Matrix

from ..core import config, meshkit as mk, ornament as orn
from ..core.materials import Library

Vec2 = tuple[float, float]


# ---------------------------------------------------------------------------
# Specification
# ---------------------------------------------------------------------------

@dataclass
class WindowSpec:
    """Everything that varies between one opening and the next."""

    width: float = config.WIN_W
    height: float = config.WIN_H_2          # sill to head (or to springing)
    head: str = "flat"                      # flat|segmental|round|gothic
    rise: float = 0.0                       # 0 => a sensible default per head

    upper_lights: tuple[int, int] = (2, 1)  # (columns, rows) of glass
    lower_lights: tuple[int, int] = (2, 1)

    wall_t: float = 0.42
    reveal: float = 0.10                    # sash setback from the wall face
    sash_t: float = 0.048
    stile: float = 0.058                    # sash stile / rail width
    meeting_rail: float = 0.072
    muntin: float = config.MUNTIN

    casing_w: float = 0.145
    casing_d: float = 0.042
    corner_blocks: bool = False             # rosette blocks at the casing head

    sill_proj: float = 0.115
    sill_h: float = 0.085
    apron: bool = True

    hood: str = "none"                      # none|label|cornice|pediment
    hood_brackets: bool = False

    shutters: bool = False
    shutter_slats: int = 14

    stained: bool = False
    lit: bool = False                       # a warm pane behind the glass
    open_frac: float = 0.0                  # lower sash raised, 0..0.45
    blind: float = 0.0                      # roller blind drawn down, 0..0.9

    def default_rise(self) -> float:
        if self.rise:
            return self.rise
        return {"flat": 0.0,
                "segmental": self.width * 0.17,
                "round": self.width / 2.0,
                "gothic": self.width * 0.62}[self.head]

    @property
    def head_z(self) -> float:
        """Top of the opening, arch included."""
        return self.height + self.default_rise()


# ---------------------------------------------------------------------------
# Opening outlines
# ---------------------------------------------------------------------------

def segmental_arc(half: float, spring_z: float, rise: float, steps: int = 14
                  ) -> list[Vec2]:
    """Arc points left to right over a segmental head.

    For a chord of 2*half and a rise r, the radius is (half^2 + r^2) / 2r and
    the centre sits (half^2 - r^2) / 2r below the springing line.
    """
    if rise <= 1e-6:
        return [(-half, spring_z), (half, spring_z)]
    if abs(rise - half) < 1e-6:                    # exact semicircle
        cz, radius = spring_z, half
    else:
        drop = (half * half - rise * rise) / (2.0 * rise)
        cz, radius = spring_z - drop, (half * half + rise * rise) / (2.0 * rise)
    a_l = math.atan2(spring_z - cz, -half)
    a_r = math.atan2(spring_z - cz, half)
    return [(radius * math.cos(a_l + (a_r - a_l) * i / steps),
             cz + radius * math.sin(a_l + (a_r - a_l) * i / steps))
            for i in range(steps + 1)]


def gothic_arc(half: float, spring_z: float, rise: float, steps: int = 10
               ) -> list[Vec2]:
    """A two-centred pointed arch, drawn left half then right half."""
    apex = spring_z + rise
    # Centres on the springing line, chosen so both arcs pass through the apex.
    radius = (half * half + rise * rise) / (2.0 * half)
    cx = radius - half
    pts: list[Vec2] = []
    # left arc: centre at (+cx, spring_z), from the left springing to the apex
    a0 = math.atan2(0.0, -half - cx)
    a1 = math.atan2(rise, -cx)
    for i in range(steps + 1):
        a = a0 + (a1 - a0) * i / steps
        pts.append((cx + radius * math.cos(a), spring_z + radius * math.sin(a)))
    # right arc: mirror, from the apex back down to the right springing
    for i in range(1, steps + 1):
        a = a1 + (a0 - a1) * i / steps
        pts.append((-cx - radius * math.cos(a),
                    spring_z + radius * math.sin(a)))
    pts[len(pts) // 2] = (0.0, apex)
    return pts


def opening_outline(spec: WindowSpec, steps: int = 14) -> list[Vec2]:
    """The opening perimeter, wound clockwise in XZ for the casing sweep."""
    half = spec.width / 2.0
    rise = spec.default_rise()
    if spec.head == "flat" or rise <= 1e-6:
        head = [(-half, spec.height), (half, spec.height)]
    elif spec.head == "gothic":
        head = gothic_arc(half, spec.height, rise, max(6, steps // 2))
    else:
        head = segmental_arc(half, spec.height, rise, steps)
    return [(-half, 0.0)] + head + [(half, 0.0)]


# ---------------------------------------------------------------------------
# Sashes
# ---------------------------------------------------------------------------

def _glass_material(spec: WindowSpec, lib: Library) -> bpy.types.Material:
    return lib.stained if spec.stained else lib.glass_old


def _sash(name: str, outline: list[Vec2], spec: WindowSpec, lights: tuple[int, int],
          y_front: float, lib: bpy.types.Material, col) -> list[bpy.types.Object]:
    """One sash: a frame band around ``outline`` plus muntins and glazing."""
    parts: list[bpy.types.Object] = []
    y_back = y_front - spec.sash_t
    inner = mk.offset_polygon(outline, -spec.stile)

    frame = mk.band_solid(f"{name}.frame", outline, inner, y_back, y_front, col)
    mk.set_material(frame, lib.accent)
    parts.append(frame)

    xs = [p[0] for p in inner]
    zs = [p[1] for p in inner]
    x0, x1, z0, z1 = min(xs), max(xs), min(zs), max(zs)
    cols, rows = lights

    # Vertical muntins run the full light height; horizontals span the light
    # width.  Both sit slightly proud of the glass on the outside face.
    m = spec.muntin
    my0, my1 = y_back + spec.sash_t * 0.18, y_front - spec.sash_t * 0.12
    for c in range(1, cols):
        x = x0 + (x1 - x0) * c / cols
        # An arched head shortens the outer muntins; clip each to the outline.
        top = _outline_top_at(outline, x) - spec.stile
        bar = mk.box(f"{name}.mv{c}", (x, (my0 + my1) / 2, (z0 + top) / 2),
                     (m, my1 - my0, max(0.02, top - z0)), col)
        mk.set_material(bar, lib.accent)
        parts.append(bar)
    for r in range(1, rows):
        z = z0 + (z1 - z0) * r / rows
        # Set the horizontals fractionally shallower than the verticals: real
        # muntins are halved together, and coincident faces would z-fight.
        bar = mk.box(f"{name}.mh{r}",
                     ((x0 + x1) / 2, (my0 + my1) / 2 - 0.0018, z),
                     (x1 - x0, (my1 - my0) * 0.86, m), col)
        mk.set_material(bar, lib.accent)
        parts.append(bar)

    glass = mk.prism_y(f"{name}.glass", inner,
                       y_back + spec.sash_t * 0.30,
                       y_back + spec.sash_t * 0.30 + 0.004, col)
    mk.set_material(glass, _glass_material(spec, lib))
    parts.append(glass)
    return parts


def _outline_top_at(outline: list[Vec2], x: float) -> float:
    """Height of the outline's upper edge at a given x."""
    best = None
    for i in range(len(outline)):
        a, b = outline[i], outline[(i + 1) % len(outline)]
        if a[1] <= 1e-6 and b[1] <= 1e-6:
            continue                                # the cill edge
        lo, hi = min(a[0], b[0]), max(a[0], b[0])
        if lo - 1e-9 <= x <= hi + 1e-9:
            t = 0.0 if abs(b[0] - a[0]) < 1e-9 else (x - a[0]) / (b[0] - a[0])
            z = a[1] + (b[1] - a[1]) * t
            best = z if best is None else max(best, z)
    return best if best is not None else 0.0


def _split_outline(outline: list[Vec2], z_split: float
                   ) -> tuple[list[Vec2], list[Vec2]]:
    """Cut an opening outline into a lower rectangle and an upper part."""
    half = max(p[0] for p in outline)
    lower = [(-half, 0.0), (half, 0.0), (half, z_split), (-half, z_split)]
    upper = [(-half, z_split), (half, z_split)]
    top = [p for p in outline if p[1] > z_split + 1e-6]
    # keep the head points in left-to-right order, then close back
    top.sort(key=lambda p: p[0])
    upper = [(-half, z_split)] + top + [(half, z_split)]
    # wind counter-clockwise for band_solid consistency
    return lower, list(reversed(upper))


# ---------------------------------------------------------------------------
# Shutters
# ---------------------------------------------------------------------------

def louvered_shutter(name: str, width: float, height: float, slats: int,
                     thickness: float, lib: Library, col
                     ) -> bpy.types.Object:
    """A louvered blind: stiles, rails and raked slats."""
    parts = []
    stile = width * 0.13
    rail = height * 0.055
    frame_outer = [(-width / 2, 0.0), (width / 2, 0.0),
                   (width / 2, height), (-width / 2, height)]
    inner = [(-width / 2 + stile, rail), (width / 2 - stile, rail),
             (width / 2 - stile, height - rail), (-width / 2 + stile, height - rail)]
    parts.append(mk.band_solid(f"{name}.frame", frame_outer, inner,
                               -thickness / 2, thickness / 2, col))
    # A centre rail, as almost every real shutter has.
    parts.append(mk.box(f"{name}.mid", (0.0, 0.0, height * 0.52),
                        (width - stile * 2, thickness, rail * 1.2), col))

    light_w = width - stile * 2
    for band, (za, zb) in enumerate([(rail, height * 0.52 - rail * 0.6),
                                     (height * 0.52 + rail * 0.6, height - rail)]):
        n = max(2, int(slats * (zb - za) / (height - 2 * rail)))
        pitch = (zb - za) / n
        for i in range(n):
            z = za + pitch * (i + 0.5)
            slat = mk.box(f"{name}.s{band}{i}", (0.0, 0.0, 0.0),
                          (light_w, thickness * 0.95, pitch * 0.94), col)
            mk.transform(slat, Matrix.Translation((0.0, 0.0, z))
                         @ Matrix.Rotation(math.radians(28), 4, 'X'))
            parts.append(slat)
    obj = mk.join(parts, name, col)
    mk.set_material(obj, lib.accent_dark)
    return obj


# ---------------------------------------------------------------------------
# The whole window
# ---------------------------------------------------------------------------

def build(name: str, spec: WindowSpec, lib: Library, col=None
          ) -> bpy.types.Object:
    """Build one complete window in the canonical local frame."""
    parts: list[bpy.types.Object] = []
    half = spec.width / 2.0
    outline = opening_outline(spec)
    head_z = spec.head_z

    # -- frame box lining the reveal ---------------------------------------
    lining_outer = mk.offset_polygon(outline, 0.012)
    lining_inner = mk.offset_polygon(outline, -0.055)
    lining = mk.band_solid(f"{name}.lining", lining_outer, lining_inner,
                           -spec.wall_t, -spec.reveal * 0.35, col)
    mk.set_material(lining, lib.trim)
    parts.append(lining)

    # -- sashes ------------------------------------------------------------
    # The meeting rail sits a little above centre, as it does in life.
    split = spec.height * 0.50
    lower_out, upper_out = _split_outline(outline, split)
    lift = spec.open_frac * (split * 0.85)

    y_low = -spec.reveal
    y_up = -spec.reveal - spec.sash_t - 0.014         # upper sash runs behind

    lower = [(x, z + lift) for x, z in lower_out]
    parts += _sash(f"{name}.lower", lower, spec, spec.lower_lights,
                   y_low, lib, col)
    parts += _sash(f"{name}.upper", upper_out, spec, spec.upper_lights,
                   y_up, lib, col)

    # A parting bead between the two sash runs.
    for side in (-1, 1):
        bead = mk.box(f"{name}.pbead{side}",
                      (side * (half - 0.012), y_up + spec.sash_t / 2,
                       head_z / 2), (0.022, 0.030, head_z), col)
        mk.set_material(bead, lib.trim)
        parts.append(bead)

    # -- roller blind ------------------------------------------------------
    if spec.blind > 0.01:
        drop = spec.blind * head_z
        cloth = mk.box(f"{name}.blind",
                       (0.0, -spec.reveal - spec.sash_t - 0.055,
                        head_z - drop / 2),
                       (spec.width - 0.10, 0.006, drop), col)
        mk.set_material(cloth, lib.drape)
        parts.append(cloth)
        # The batten at the hem, which is what makes a blind read as a blind.
        batten = mk.box(f"{name}.blindbatten",
                        (0.0, -spec.reveal - spec.sash_t - 0.055,
                         head_z - drop),
                        (spec.width - 0.08, 0.022, 0.038), col)
        mk.set_material(batten, lib.wood_oak)
        parts.append(batten)

    # -- an interior glow pane, for the dusk renders -----------------------
    if spec.lit:
        glow = mk.prism_y(f"{name}.glow", mk.offset_polygon(outline, -0.02),
                          -spec.reveal - 0.32, -spec.reveal - 0.31, col)
        mk.set_material(glow, lib.window_glow)
        parts.append(glow)

    # -- casing ------------------------------------------------------------
    casing = mk.sweep_wall_path(
        f"{name}.casing", orn.casing_profile(spec.casing_w, spec.casing_d),
        outline, 0.0, col=col)
    mk.set_material(casing, lib.trim)
    parts.append(casing)

    if spec.corner_blocks:
        for side in (-1, 1):
            r = orn.rosette(f"{name}.block{side}", spec.casing_w * 0.46,
                            spec.casing_d * 1.5, 10, col)
            blk = mk.box(f"{name}.blockbase{side}",
                         (side * (half + spec.casing_w / 2),
                          spec.casing_d / 2, head_z + spec.casing_w / 2),
                         (spec.casing_w * 1.16, spec.casing_d,
                          spec.casing_w * 1.16), col)
            mk.transform(r, Matrix.Translation(
                (side * (half + spec.casing_w / 2), spec.casing_d,
                 head_z + spec.casing_w / 2))
                @ Matrix.Rotation(-math.pi / 2, 4, 'X'))
            mk.set_material(blk, lib.trim)
            mk.set_material(r, lib.trim_crisp)
            parts += [blk, r]

    # -- sill and apron ----------------------------------------------------
    sill_w = spec.width + spec.casing_w * 2 + 0.10
    # Dropped so the sill's top surface at the wall meets the sill datum.
    sill = mk.sweep_straight(
        f"{name}.sill", orn.sill_profile(spec.sill_proj, spec.sill_h),
        (-sill_w / 2, 0.0, 0.0), (sill_w / 2, 0.0, 0.0), (0, 1, 0), col=col)
    mk.transform(sill, Matrix.Translation((0.0, 0.0, -spec.sill_h * 0.86)))
    mk.set_material(sill, lib.trim)
    parts.append(sill)

    if spec.apron:
        ap_h = spec.sill_h * 2.6
        ap = orn.panel(f"{name}.apron", spec.width * 0.86, ap_h, 0.038,
                       0.032, 0.010, col)
        mk.transform(ap, Matrix.Translation(
            (0.0, 0.0, -spec.sill_h - ap_h / 2 - 0.06)))
        mk.set_material(ap, lib.trim)
        parts.append(ap)

    # -- hood --------------------------------------------------------------
    if spec.hood != "none":
        parts += _hood(name, spec, lib, col)

    # -- shutters ----------------------------------------------------------
    if spec.shutters:
        sh_w = spec.width * 0.52
        sh_h = spec.height * 0.98
        for side in (-1, 1):
            s = louvered_shutter(f"{name}.shutter{side}", sh_w, sh_h,
                                 spec.shutter_slats, 0.036, lib, col)
            mk.transform(s, Matrix.Translation(
                (side * (half + spec.casing_w + sh_w / 2 - 0.02),
                 spec.casing_d + 0.03, 0.02)))
            parts.append(s)

    obj = mk.join(parts, name, col)
    return obj


def _hood(name: str, spec: WindowSpec, lib: Library, col
          ) -> list[bpy.types.Object]:
    """Label mould, bracketed cornice or pediment over the opening."""
    parts = []
    half = spec.width / 2.0
    top = spec.head_z + spec.casing_w
    reach = half + spec.casing_w + 0.14

    if spec.hood == "label":
        # A drip mould returning down the sides a short way.
        path = [(-reach, top - 0.34), (-reach, top), (reach, top),
                (reach, top - 0.34)]
        m = mk.sweep_wall_path(f"{name}.label", orn.cyma_reversa(0.075, 0.10),
                               path, 0.0, closed=False, col=col)
        mk.recalc_normals(m)
        mk.set_material(m, lib.trim)
        parts.append(m)
        return parts

    proj = 0.30
    cor_h = 0.22
    band = mk.box(f"{name}.hoodband", (0.0, proj * 0.32, top + cor_h * 0.35),
                  (reach * 2, proj * 0.64, cor_h * 0.7), col)
    mk.set_material(band, lib.trim)
    parts.append(band)

    cor = mk.sweep_straight(f"{name}.hoodcornice",
                            orn.cornice_profile(proj, cor_h),
                            (-reach - 0.06, 0.0, top + cor_h * 0.7),
                            (reach + 0.06, 0.0, top + cor_h * 0.7),
                            (0, 1, 0), col=col)
    mk.set_material(cor, lib.trim)
    parts.append(cor)

    if spec.hood == "pediment":
        rise = reach * 0.42
        tym = mk.prism_y(f"{name}.tympanum",
                         [(-reach, top + cor_h * 0.7),
                          (reach, top + cor_h * 0.7), (0.0, top + cor_h * 0.7 + rise)],
                         0.0, proj * 0.42, col)
        mk.set_material(tym, lib.accent_dark)
        parts.append(tym)
        # A raking cornice carries its section square to the slope, so "up"
        # for the sweep is the rake normal in the wall plane, not world Z.
        for sgn in (-1, 1):
            a = (sgn * (reach + 0.05), proj * 0.42, top + cor_h * 0.7)
            b = (0.0, proj * 0.42, top + cor_h * 0.7 + rise)
            run, climb = b[0] - a[0], b[2] - a[2]
            length = math.hypot(run, climb)
            rake_up = (-climb / length, 0.0, run / length)
            if rake_up[2] < 0:
                rake_up = (-rake_up[0], 0.0, -rake_up[2])
            rake = mk.sweep_straight(f"{name}.rake{sgn}",
                                     orn.cyma_recta(0.13, 0.16), a, b,
                                     (0, 1, 0), up=rake_up, col=col)
            mk.set_material(rake, lib.trim)
            parts.append(rake)

    if spec.hood_brackets:
        # As on the eaves, a console stands edge-on to the wall: rotate its
        # silhouette a quarter turn so its projection runs out along +Y.
        for sgn in (-1, 1):
            b = orn.bracket(f"{name}.hb{sgn}", proj * 0.74, cor_h * 3.0,
                            0.055, "console", pierce=False, col=col)
            m = (Matrix.Translation((sgn * (half + spec.casing_w * 0.55), 0.0,
                                     top + cor_h * 0.7))
                 @ Matrix.Rotation(math.pi / 2, 4, 'Z')
                 @ Matrix.Scale(sgn, 4, (0.0, 1.0, 0.0)))
            mk.transform(b, m)
            mk.recalc_normals(b)
            mk.set_material(b, lib.trim)
            parts.append(b)
    return parts


# ---------------------------------------------------------------------------
# Placement
# ---------------------------------------------------------------------------

def place(obj: bpy.types.Object, x: float, y: float, z: float,
          yaw: float = 0.0) -> bpy.types.Object:
    """Move a canonical window onto a wall.

    ``yaw`` is the rotation about Z that takes the window's outward +Y to the
    wall's outward normal: 0 for a wall facing +Y (north), pi for -Y, +pi/2
    for -X and -pi/2 for +X.
    """
    mk.transform(obj, Matrix.Translation((x, y, z)) @ Matrix.Rotation(yaw, 4, 'Z'))
    return obj
