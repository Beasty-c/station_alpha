"""
The Victorian ornament vocabulary.

A house of this period is assembled from a small catalogue of parts repeated
at every scale - a turned post is a baluster is a colonette is a finial, only
the height changes; a cyma recta is a crown mould is a sill is a plinth cap.
This module holds that catalogue: 2D moulding profiles fed to
:func:`meshkit.sweep`, revolution profiles fed to :func:`meshkit.lathe`, and
sawn silhouettes for brackets, bargeboards and spandrels.

Profiles are written normalised where it makes sense, then scaled by the
caller, so one definition serves the 3 m veranda posts and the 0.7 m
balusters both.
"""

from __future__ import annotations

import math
from typing import Sequence

import bpy

from . import meshkit as mk

Vec2 = tuple[float, float]

TAU = math.tau


# ---------------------------------------------------------------------------
# Curve primitives used by the profiles
# ---------------------------------------------------------------------------

def bezier(p0: Vec2, c0: Vec2, c1: Vec2, p1: Vec2, n: int = 8,
           include_first: bool = True) -> list[Vec2]:
    """Sampled cubic Bezier - the building block for every ogee and scroll."""
    pts = []
    start = 0 if include_first else 1
    for i in range(start, n + 1):
        t = i / n
        u = 1.0 - t
        x = (u ** 3 * p0[0] + 3 * u * u * t * c0[0]
             + 3 * u * t * t * c1[0] + t ** 3 * p1[0])
        y = (u ** 3 * p0[1] + 3 * u * u * t * c0[1]
             + 3 * u * t * t * c1[1] + t ** 3 * p1[1])
        pts.append((x, y))
    return pts


def arc(cx: float, cy: float, r: float, a0: float, a1: float, n: int = 8,
        include_first: bool = True) -> list[Vec2]:
    start = 0 if include_first else 1
    return [(cx + r * math.cos(a0 + (a1 - a0) * i / n),
             cy + r * math.sin(a0 + (a1 - a0) * i / n))
            for i in range(start, n + 1)]


def spiral(cx: float, cy: float, r0: float, r1: float, a0: float, a1: float,
           n: int = 16, include_first: bool = True) -> list[Vec2]:
    """A logarithmic-ish volute for bracket scrolls and console ends."""
    start = 0 if include_first else 1
    out = []
    for i in range(start, n + 1):
        t = i / n
        a = a0 + (a1 - a0) * t
        r = r0 * (r1 / r0) ** t
        out.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return out


# ---------------------------------------------------------------------------
# Moulding profiles - (u, v) sections for meshkit.sweep
#
# u projects out from the wall, v runs vertically.  Every profile is closed
# and returns to the wall plane at u = 0 so the swept solid is watertight.
# ---------------------------------------------------------------------------

def cyma_recta(depth: float, height: float, n: int = 7) -> list[Vec2]:
    """The classic crown mould: concave above, convex below."""
    pts = [(0.0, 0.0), (depth * 0.12, 0.0)]
    pts += bezier((depth * 0.12, 0.0), (depth * 0.62, height * 0.06),
                  (depth * 0.72, height * 0.42), (depth, height * 0.62),
                  n, include_first=False)
    pts += [(depth, height * 0.78), (depth * 0.86, height * 0.86)]
    pts += bezier((depth * 0.86, height * 0.86), (depth * 0.5, height * 0.95),
                  (depth * 0.30, height * 0.97), (0.0, height),
                  n, include_first=False)
    return pts


def cyma_reversa(depth: float, height: float, n: int = 7) -> list[Vec2]:
    """Convex above, concave below - the bed mould under a cornice."""
    pts = [(0.0, 0.0), (depth * 0.10, 0.0)]
    pts += bezier((depth * 0.10, 0.0), (depth * 0.55, height * 0.05),
                  (depth * 0.98, height * 0.30), (depth, height * 0.55),
                  n, include_first=False)
    pts += bezier((depth, height * 0.55), (depth * 0.98, height * 0.80),
                  (depth * 0.45, height * 0.82), (0.0, height),
                  n, include_first=False)
    return pts


def ovolo(depth: float, height: float, n: int = 8) -> list[Vec2]:
    """A convex quarter-round - the workhorse bead under sills and panels."""
    return [(0.0, 0.0), (depth, 0.0)] + [
        (depth * math.cos(math.pi / 2 * i / n),
         height * math.sin(math.pi / 2 * i / n)) for i in range(1, n + 1)]


def cavetto(depth: float, height: float, n: int = 8) -> list[Vec2]:
    """A concave quarter-hollow, running from (depth, 0) up to (0, height)."""
    return [(0.0, 0.0)] + [
        (depth * (1.0 - math.sin(math.pi / 2 * i / n)),
         height * (1.0 - math.cos(math.pi / 2 * i / n)))
        for i in range(n + 1)]


def torus_bead(radius: float, n: int = 10) -> list[Vec2]:
    """A half-round bead standing proud of the ground plane."""
    return [(0.0, -radius)] + [
        (radius * math.sin(math.pi * i / n),
         -radius * math.cos(math.pi * i / n)) for i in range(1, n + 1)]


def fillet(depth: float, height: float) -> list[Vec2]:
    return [(0.0, 0.0), (depth, 0.0), (depth, height), (0.0, height)]


def cornice_profile(depth: float, height: float, detail: int = 7
                    ) -> list[Vec2]:
    """A full classical cornice: bed mould, dentil bed, corona, cyma, fillet.

    Built bottom-up as a single closed section - one sweep gives the whole
    entablature run rather than five stacked sweeps that never quite align.
    """
    d, h = depth, height
    p: list[Vec2] = [(0.0, 0.0)]
    # bed mould
    p.append((d * 0.16, 0.0))
    p += bezier((d * 0.16, 0.0), (d * 0.34, h * 0.02), (d * 0.36, h * 0.10),
                (d * 0.30, h * 0.16), detail, include_first=False)
    # dentil bed / frieze fillet
    p += [(d * 0.42, h * 0.17), (d * 0.42, h * 0.30), (d * 0.34, h * 0.31)]
    # corona - the deep flat shadow-casting projection
    p += [(d * 0.98, h * 0.40), (d * 1.00, h * 0.44), (d * 1.00, h * 0.60)]
    # crown cyma
    p += bezier((d * 1.00, h * 0.60), (d * 0.92, h * 0.74),
                (d * 0.66, h * 0.72), (d * 0.58, h * 0.86),
                detail, include_first=False)
    p += bezier((d * 0.58, h * 0.86), (d * 0.52, h * 0.96),
                (d * 0.40, h * 0.94), (d * 0.34, h * 1.00),
                detail, include_first=False)
    p += [(0.0, h)]
    return p


def sill_profile(depth: float, height: float) -> list[Vec2]:
    """A weathered sill with a drip groove cut in the soffit."""
    d, h = depth, height
    return [
        (0.0, 0.0), (d * 0.72, 0.0), (d * 0.72, -h * 0.16),
        (d * 0.58, -h * 0.16), (d * 0.58, 0.0),      # drip groove
        (d, 0.0), (d, h * 0.30), (d * 0.94, h * 0.42),
        (d * 0.10, h * 0.86), (0.0, h * 0.86),
    ]


def water_table(depth: float, height: float, n: int = 7) -> list[Vec2]:
    """The sloped cap where the basement stonework meets the siding."""
    d, h = depth, height
    p = [(0.0, 0.0), (d, 0.0), (d, h * 0.22)]
    p += bezier((d, h * 0.22), (d * 0.86, h * 0.46), (d * 0.52, h * 0.52),
                (d * 0.30, h * 0.78), n, include_first=False)
    p += [(d * 0.22, h), (0.0, h)]
    return p


def handrail_profile(width: float, height: float, n: int = 6) -> list[Vec2]:
    """A mopstick handrail, symmetric about u = 0 so it centres on its path."""
    w, h = width / 2.0, height
    p = [(-w, 0.0), (w, 0.0), (w, h * 0.30)]
    p += bezier((w, h * 0.30), (w, h * 0.72), (w * 0.42, h), (0.0, h),
                n, include_first=False)
    p += bezier((0.0, h), (-w * 0.42, h), (-w, h * 0.72), (-w, h * 0.30),
                n, include_first=False)
    return p


def casing_profile(width: float, depth: float) -> list[Vec2]:
    """Window / door architrave: a flat face with a bead and a backband.

    u runs outward from the opening and v projects out of the wall, so the
    profile leaves the wall at u = 0, steps out to the face, and returns to
    the wall at u = width where the backband dies into the siding.
    """
    w, d = width, depth
    return [
        (0.0, 0.0), (w, 0.0),
        (w, d * 0.30), (w * 0.90, d * 0.55), (w * 0.78, d * 0.55),
        (w * 0.78, d), (w * 0.10, d),
        (w * 0.10, d * 0.35), (0.0, d * 0.35),
    ]


def astragal(radius: float, n: int = 8) -> list[Vec2]:
    """A bead with a fillet either side - the universal joint cover."""
    r = radius
    return ([(0.0, -r * 1.7), (r * 0.35, -r * 1.7), (r * 0.35, -r)]
            + [(r * math.cos(-math.pi / 2 + math.pi * i / n),
                r * math.sin(-math.pi / 2 + math.pi * i / n))
               for i in range(1, n)]
            + [(r * 0.35, r), (r * 0.35, r * 1.7), (0.0, r * 1.7)])


# ---------------------------------------------------------------------------
# Lathe profiles - (radius, z), normalised to a unit height
# ---------------------------------------------------------------------------

def turned_post_profile(height: float, diameter: float,
                        style: str = "veranda", n: int = 6) -> list[Vec2]:
    """A Victorian turned porch column: square plinth, vase, shaft, capital."""
    r = diameter / 2.0
    h = height
    if style == "veranda":
        p: list[Vec2] = [
            (0.0, 0.0), (r * 1.15, 0.0), (r * 1.15, h * 0.055),
            (r * 1.05, h * 0.062), (r * 1.05, h * 0.085),
        ]
        # lower vase / bulb
        p += bezier((r * 1.05, h * 0.085), (r * 1.18, h * 0.10),
                    (r * 1.22, h * 0.13), (r * 0.98, h * 0.165),
                    n, include_first=False)
        p += [(r * 0.78, h * 0.185), (r * 0.86, h * 0.20),
              (r * 0.86, h * 0.215), (r * 0.72, h * 0.235)]
        # the long tapering shaft with an entasis
        p += bezier((r * 0.72, h * 0.235), (r * 0.80, h * 0.40),
                    (r * 0.74, h * 0.60), (r * 0.62, h * 0.755),
                    n + 2, include_first=False)
        # necking rings
        p += [(r * 0.72, h * 0.775), (r * 0.72, h * 0.795),
              (r * 0.60, h * 0.805), (r * 0.60, h * 0.825)]
        # capital
        p += bezier((r * 0.60, h * 0.825), (r * 0.92, h * 0.85),
                    (r * 0.98, h * 0.885), (r * 1.02, h * 0.915),
                    n, include_first=False)
        p += [(r * 0.90, h * 0.930), (r * 1.16, h * 0.950),
              (r * 1.16, h * 0.985), (r * 1.05, h * 1.0), (0.0, h * 1.0)]
        return p

    if style == "colonette":                    # slim, for window mullions
        p = [(0.0, 0.0), (r * 1.25, 0.0), (r * 1.25, h * 0.04),
             (r * 0.95, h * 0.06), (r * 0.80, h * 0.10)]
        p += bezier((r * 0.80, h * 0.10), (r * 0.90, h * 0.35),
                    (r * 0.84, h * 0.62), (r * 0.68, h * 0.86),
                    n + 1, include_first=False)
        p += [(r * 0.86, h * 0.90), (r * 1.20, h * 0.955),
              (r * 1.20, h * 1.0), (0.0, h * 1.0)]
        return p

    if style == "newel":                        # heavy, for stair and steps
        p = [(0.0, 0.0), (r * 1.3, 0.0), (r * 1.3, h * 0.10),
             (r * 1.12, h * 0.115), (r * 1.12, h * 0.20)]
        p += bezier((r * 1.12, h * 0.20), (r * 1.34, h * 0.24),
                    (r * 1.30, h * 0.32), (r * 1.02, h * 0.38),
                    n, include_first=False)
        p += [(r * 0.86, h * 0.42), (r * 0.98, h * 0.45),
              (r * 0.98, h * 0.47), (r * 0.84, h * 0.50)]
        p += bezier((r * 0.84, h * 0.50), (r * 0.94, h * 0.62),
                    (r * 0.90, h * 0.70), (r * 0.80, h * 0.76),
                    n, include_first=False)
        p += [(r * 1.05, h * 0.80), (r * 1.28, h * 0.84),
              (r * 1.28, h * 0.875), (r * 1.10, h * 0.885)]
        # ball terminal
        p += [(r * 0.55, h * 0.90)]
        p += [(r * 1.0 * math.sin(math.pi * i / (n + 4)) * 0.92,
               h * (0.90 + 0.10 * (1 - math.cos(math.pi * i / (n + 4))) / 2))
              for i in range(1, n + 5)]
        return p

    raise ValueError(f"unknown post style {style!r}")


def baluster_profile(height: float, diameter: float,
                     style: str = "vase", n: int = 6) -> list[Vec2]:
    """Turned baluster.  ``vase`` for the veranda, ``bobbin`` for the stair."""
    r = diameter / 2.0
    h = height
    if style == "vase":
        p = [(0.0, 0.0), (r * 1.18, 0.0), (r * 1.18, h * 0.075),
             (r * 0.90, h * 0.095)]
        p += bezier((r * 0.90, h * 0.095), (r * 1.30, h * 0.14),
                    (r * 1.34, h * 0.26), (r * 0.86, h * 0.36),
                    n + 2, include_first=False)
        p += [(r * 0.52, h * 0.44), (r * 0.48, h * 0.52)]
        p += bezier((r * 0.48, h * 0.52), (r * 0.66, h * 0.60),
                    (r * 0.74, h * 0.66), (r * 0.62, h * 0.72),
                    n, include_first=False)
        p += [(r * 0.44, h * 0.78), (r * 0.62, h * 0.82),
              (r * 0.62, h * 0.855), (r * 0.46, h * 0.875),
              (r * 1.10, h * 0.94), (r * 1.10, h * 1.0), (0.0, h * 1.0)]
        return p

    if style == "bobbin":
        p = [(0.0, 0.0), (r * 1.1, 0.0), (r * 1.1, h * 0.06)]
        beads = 4
        for i in range(beads):
            z0 = h * (0.08 + 0.78 * i / beads)
            z1 = h * (0.08 + 0.78 * (i + 1) / beads)
            mid = (z0 + z1) / 2
            p += [(r * 0.45, z0 + (z1 - z0) * 0.06),
                  (r * 1.0, mid), (r * 0.45, z1 - (z1 - z0) * 0.06)]
        p += [(r * 0.5, h * 0.90), (r * 1.05, h * 0.95),
              (r * 1.05, h * 1.0), (0.0, h * 1.0)]
        return p

    if style == "spindle":                      # the tiny frieze spindles
        p = [(0.0, 0.0), (r * 0.9, 0.0), (r * 0.9, h * 0.09),
             (r * 0.5, h * 0.13), (r * 1.15, h * 0.22), (r * 0.42, h * 0.31),
             (r * 0.42, h * 0.40), (r * 0.95, h * 0.50), (r * 0.42, h * 0.60),
             (r * 0.42, h * 0.69), (r * 1.15, h * 0.78), (r * 0.5, h * 0.87),
             (r * 0.9, h * 0.91), (r * 0.9, h * 1.0), (0.0, h * 1.0)]
        return p

    raise ValueError(f"unknown baluster style {style!r}")


def finial_profile(height: float, radius: float, style: str = "spike",
                   n: int = 8) -> list[Vec2]:
    """Roof and gable finials - the punctuation of a Victorian skyline."""
    r, h = radius, height
    if style == "spike":
        p = [(0.0, 0.0), (r * 1.35, 0.0), (r * 1.35, h * 0.045),
             (r * 0.85, h * 0.07)]
        p += bezier((r * 0.85, h * 0.07), (r * 1.45, h * 0.11),
                    (r * 1.45, h * 0.22), (r * 0.72, h * 0.29),
                    n, include_first=False)
        p += [(r * 0.42, h * 0.34), (r * 0.85, h * 0.40), (r * 0.36, h * 0.46)]
        p += bezier((r * 0.36, h * 0.46), (r * 0.95, h * 0.52),
                    (r * 0.80, h * 0.62), (r * 0.34, h * 0.68),
                    n, include_first=False)
        p += [(r * 0.30, h * 0.74), (r * 0.20, h * 0.80), (0.0, h)]
        return p

    if style == "urn":
        p = [(0.0, 0.0), (r * 1.5, 0.0), (r * 1.5, h * 0.06),
             (r * 1.30, h * 0.075), (r * 0.60, h * 0.13)]
        p += bezier((r * 0.60, h * 0.13), (r * 1.30, h * 0.22),
                    (r * 1.42, h * 0.44), (r * 1.00, h * 0.60),
                    n + 2, include_first=False)
        p += bezier((r * 1.00, h * 0.60), (r * 0.74, h * 0.70),
                    (r * 0.66, h * 0.74), (r * 0.70, h * 0.80),
                    n, include_first=False)
        p += [(r * 1.05, h * 0.88), (r * 1.12, h * 0.94),
              (r * 0.94, h * 0.96), (r * 0.80, h * 0.94), (0.0, h * 0.90)]
        return p

    if style == "ball":
        p = [(0.0, 0.0), (r * 1.2, 0.0), (r * 1.2, h * 0.10),
             (r * 0.55, h * 0.18)]
        p += [(r * math.sin(math.pi * i / (n * 2)) * 1.0,
               h * (0.18 + 0.72 * (1 - math.cos(math.pi * i / (n * 2))) / 2))
              for i in range(1, n * 2 + 1)]
        p += [(0.0, h)]
        return p

    if style == "acorn":
        p = [(0.0, 0.0), (r * 1.1, 0.0), (r * 1.1, h * 0.08),
             (r * 0.5, h * 0.14)]
        p += bezier((r * 0.5, h * 0.14), (r * 1.15, h * 0.20),
                    (r * 1.15, h * 0.42), (r * 0.92, h * 0.52),
                    n, include_first=False)
        p += bezier((r * 0.92, h * 0.52), (r * 0.80, h * 0.78),
                    (r * 0.40, h * 0.86), (0.0, h),
                    n, include_first=False)
        return p

    raise ValueError(f"unknown finial style {style!r}")


# ---------------------------------------------------------------------------
# Sawn silhouettes - (x, z) outlines extruded in Y to make flat cut work
# ---------------------------------------------------------------------------

def bracket_outline(width: float, height: float, style: str = "scroll",
                    n: int = 9) -> list[Vec2]:
    """A jig-sawn eaves bracket, seen in elevation.

    Origin is the inner top corner; the bracket hangs down (-z) and projects
    out (+x) from the wall.
    """
    w, h = width, height
    if style == "scroll":
        p: list[Vec2] = [(0.0, 0.0), (w, 0.0), (w, -h * 0.14)]
        # the long ogee sweep from the outer top down to the scroll
        p += bezier((w, -h * 0.14), (w * 0.94, -h * 0.46),
                    (w * 0.52, -h * 0.50), (w * 0.44, -h * 0.72),
                    n, include_first=False)
        # volute at the toe; the sweep is held to 320 degrees so the tail
        # curls inside the ogee instead of crossing it
        p += spiral(w * 0.26, -h * 0.80, h * 0.14, h * 0.042,
                    math.radians(-8), math.radians(320), n + 6,
                    include_first=False)
        p += [(w * 0.20, -h * 0.92), (w * 0.16, -h)]
        p += [(0.0, -h)]
        return p

    if style == "spandrel":                     # a shallow arched corner brace
        p = [(0.0, 0.0), (w, 0.0)]
        p += bezier((w, 0.0), (w * 0.55, -h * 0.10),
                    (w * 0.18, -h * 0.42), (0.0, -h), n + 4,
                    include_first=False)
        return p

    if style == "console":
        # A chunkier door-hood console.  Both volutes are convex arcs of a
        # little under 250 degrees rather than true inward spirals: a spiral
        # ends at its own centre with nowhere to rejoin the outline, which is
        # what tears the silhouette open.
        eye_a = (w * 0.78, -h * 0.22, h * 0.22)     # upper volute cx, cy, r
        eye_b = (w * 0.28, -h * 0.84, h * 0.110)    # lower volute
        a0, a1 = math.radians(70), math.radians(-175)
        b0, b1 = math.radians(55), math.radians(-175)
        p = [(0.0, 0.0), (w, 0.0)]
        p += arc(eye_a[0], eye_a[1], eye_a[2], a0, a1, n + 5,
                 include_first=False)
        toe = (eye_b[0] + eye_b[2] * math.cos(b0),
               eye_b[1] + eye_b[2] * math.sin(b0))
        p += bezier(p[-1], (w * 0.52, -h * 0.52), (w * 0.44, -h * 0.62),
                    toe, n, include_first=False)
        p += arc(eye_b[0], eye_b[1], eye_b[2], b0, b1, n + 3,
                 include_first=False)
        p += [(0.0, -h)]
        return p

    if style == "plain":
        return [(0.0, 0.0), (w, 0.0), (w * 0.30, -h * 0.70), (0.0, -h)]

    raise ValueError(f"unknown bracket style {style!r}")


def bargeboard_outline(run: float, drop: float, teeth: int,
                       tooth_depth: float, style: str = "trefoil",
                       n: int = 6) -> list[Vec2]:
    """The sawn edge of a gable board, given as a horizontal strip outline.

    Returned in (x, z) with the straight top edge on z = 0 and the decorated
    edge cut into the strip below it.  The caller rotates it up to the rake.
    """
    top = [(0.0, 0.0), (run, 0.0)]
    bottom: list[Vec2] = []
    step = run / teeth
    for i in range(teeth, 0, -1):
        x0 = (i - 1) * step
        x1 = i * step
        mid = (x0 + x1) / 2.0
        if style == "trefoil":
            bottom.append((x1, -drop + tooth_depth * 0.25))
            bottom += arc(mid, -drop + tooth_depth * 0.25,
                          step * 0.34, math.radians(20), math.radians(160),
                          n, include_first=False)
            bottom.append((x0, -drop + tooth_depth * 0.25))
        elif style == "sawtooth":
            bottom += [(x1, -drop), (mid, -drop - tooth_depth), (x0, -drop)]
        elif style == "drop":
            bottom += [(x1, -drop)]
            bottom += bezier((x1, -drop), (mid + step * 0.18, -drop - tooth_depth),
                             (mid - step * 0.18, -drop - tooth_depth),
                             (x0, -drop), n, include_first=False)
        elif style == "pendant":
            bottom += [(x1, -drop), (x1 - step * 0.30, -drop),
                       (x1 - step * 0.30, -drop - tooth_depth),
                       (x1 - step * 0.42, -drop - tooth_depth * 1.15),
                       (x1 - step * 0.58, -drop - tooth_depth * 1.15),
                       (x1 - step * 0.70, -drop - tooth_depth),
                       (x1 - step * 0.70, -drop), (x0, -drop)]
        else:
            raise ValueError(f"unknown bargeboard style {style!r}")
    return top + bottom


def foil(radius: float, lobes: int, n: int = 10, lobe_ratio: float = 0.52,
         phase: float | None = None) -> list[Vec2]:
    """A cusped foil - the trefoil / quatrefoil / cinquefoil piercing.

    Each lobe arc is trimmed to end exactly where it crosses its neighbour,
    which is what puts a sharp cusp at the join.  Guessing a fixed sweep angle
    instead leaves the arcs overlapping, and the resulting self-intersecting
    outline tears a hole in the face when it is triangulated.
    """
    if lobes < 3:
        raise ValueError("a foil needs at least 3 lobes")
    if phase is None:
        phase = math.pi / 2
    step = TAU / lobes
    # Place the lobe centres so the outermost point of each sits on ``radius``.
    lobe_r = radius * lobe_ratio
    off = radius - lobe_r
    d = 2.0 * off * math.sin(step / 2.0)          # centre-to-centre spacing
    # Neighbouring lobe centres sit d apart; two circles of radius lobe_r meet
    # at +/- acos(d / 2r) off the line joining them, and that line lies at
    # step/2 + 90 degrees from the lobe's own outward direction.
    phi = 0.0 if d >= 2.0 * lobe_r else math.acos(d / (2.0 * lobe_r))
    half = step / 2.0 + math.pi / 2.0 - phi

    pts: list[Vec2] = []
    for k in range(lobes):
        a = phase + step * k
        cx, cy = off * math.cos(a), off * math.sin(a)
        pts += arc(cx, cy, lobe_r, a - half, a + half, n,
                   include_first=(k == 0))
    return pts


def quatrefoil(radius: float, n: int = 10) -> list[Vec2]:
    """The pierced quatrefoil that fills gable panels and stair spandrels."""
    return foil(radius, 4, n, lobe_ratio=0.46, phase=math.pi / 4)


def trefoil(radius: float, n: int = 10) -> list[Vec2]:
    return foil(radius, 3, n, lobe_ratio=0.50)


def cinquefoil(radius: float, n: int = 10) -> list[Vec2]:
    return foil(radius, 5, n, lobe_ratio=0.44)


# ---------------------------------------------------------------------------
# Ready-made objects
# ---------------------------------------------------------------------------

def turned_post(name: str, height: float, diameter: float, segments: int = 20,
                style: str = "veranda", col=None) -> bpy.types.Object:
    obj = mk.lathe(name, turned_post_profile(height, diameter, style),
                   segments, col=col)
    mk.shade_smooth(obj, math.radians(38))
    return obj


def baluster(name: str, height: float, diameter: float, segments: int = 14,
             style: str = "vase", col=None) -> bpy.types.Object:
    obj = mk.lathe(name, baluster_profile(height, diameter, style),
                   segments, col=col)
    mk.shade_smooth(obj, math.radians(38))
    return obj


def finial(name: str, height: float, radius: float, segments: int = 18,
           style: str = "spike", col=None) -> bpy.types.Object:
    obj = mk.lathe(name, finial_profile(height, radius, style),
                   segments, col=col)
    mk.shade_smooth(obj, math.radians(40))
    return obj


def bracket(name: str, width: float, height: float, thickness: float,
            style: str = "scroll", pierce: bool = True, col=None
            ) -> bpy.types.Object:
    """A flat sawn bracket lying in the XZ plane, thickness in Y."""
    outline = bracket_outline(width, height, style)
    obj = mk.prism_y(name, outline, -thickness / 2.0, thickness / 2.0, col)
    if pierce and style in ("scroll", "console"):
        hole = mk.lathe(f"{name}.hole",
                        [(height * 0.075, -thickness), (height * 0.075, thickness)],
                        12, col=col)
        mk.transform(hole, __import__("mathutils").Matrix.Translation(
            (width * 0.52, 0.0, -height * 0.30)) @
            __import__("mathutils").Matrix.Rotation(math.pi / 2, 4, 'X'))
        mk.boolean(obj, hole)
    mk.bevel(obj, min(thickness * 0.22, 0.012), 2)
    return obj


def dentil_course(name: str, path: Sequence[Sequence[float]], block: float,
                  gap: float, depth: float, height: float,
                  closed: bool = True, col=None) -> bpy.types.Object:
    """Little blocks marching along a cornice - cheap, and reads instantly.

    Blocks are laid along each straight run of ``path`` independently so
    corners always land on a whole block.
    """
    from mathutils import Vector
    parts = []
    n = len(path)
    spans = n if closed else n - 1
    pitch = block + gap
    for i in range(spans):
        a = Vector(path[i])
        b = Vector(path[(i + 1) % n])
        d = b - a
        length = d.length
        if length < pitch:
            continue
        d = d / length
        normal = Vector((d.y, -d.x, 0.0))       # outward for a CCW path
        count = max(1, int(length / pitch))
        used = count * pitch - gap
        start = (length - used) / 2.0
        for k in range(count):
            centre = a + d * (start + k * pitch + block / 2.0)
            verts = []
            for sx in (-block / 2, block / 2):
                for sy in (0.0, depth):
                    for sz in (0.0, height):
                        p = centre + d * sx - normal * sy + Vector((0, 0, sz))
                        verts.append((p.x, p.y, p.z))
            # index order: (sx, sy, sz) -> 4*i + 2*j + k
            f = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 2, 6, 4),
                 (1, 5, 7, 3), (2, 3, 7, 6), (0, 4, 5, 1)]
            parts.append(mk.obj_from(f"{name}.{i}.{k}", verts, f, col=col))
    if not parts:
        return mk.obj_from(name, [], [], col=col)
    out = mk.join(parts, name, col)
    mk.recalc_normals(out)
    return out


def cresting(name: str, length: float, height: float, pitch: float = 0.30,
             thickness: float = 0.022, col=None) -> bpy.types.Object:
    """Cast-iron ridge cresting: a repeating fleur-de-lis picket on a rail.

    Modelled as flat cut-out in the XZ plane running along +X.
    """
    parts = []
    rail_h = height * 0.10
    rail = mk.prism_y(f"{name}.rail",
                      [(0, 0), (length, 0), (length, rail_h), (0, rail_h)],
                      -thickness / 2, thickness / 2, col)
    parts.append(rail)
    count = max(1, int(length / pitch))
    real_pitch = length / count
    for i in range(count):
        x = (i + 0.5) * real_pitch
        w = real_pitch * 0.40
        h = height - rail_h
        # a fleur-de-lis silhouette
        o = [(-w * 0.22, 0), (w * 0.22, 0), (w * 0.22, h * 0.16),
             (w * 0.50, h * 0.20), (w * 0.46, h * 0.34), (w * 0.18, h * 0.34),
             (w * 0.16, h * 0.52), (w * 0.38, h * 0.62), (w * 0.30, h * 0.74),
             (w * 0.10, h * 0.70), (w * 0.07, h * 1.0),
             (-w * 0.07, h * 1.0), (-w * 0.10, h * 0.70),
             (-w * 0.30, h * 0.74), (-w * 0.38, h * 0.62),
             (-w * 0.16, h * 0.52), (-w * 0.18, h * 0.34),
             (-w * 0.46, h * 0.34), (-w * 0.50, h * 0.20),
             (-w * 0.22, h * 0.16)]
        o = [(px + x, pz + rail_h) for px, pz in o]
        parts.append(mk.prism_y(f"{name}.p{i}", o, -thickness / 2,
                                thickness / 2, col))
    out = mk.join(parts, name, col)
    mk.recalc_normals(out)
    return out


def spindle_frieze(name: str, length: float, height: float, spindle_d: float,
                   spacing: float, segments: int = 10, col=None
                   ) -> bpy.types.Object:
    """A run of little turned spindles between top and bottom rails - the
    'gingerbread' that fills the head of every veranda bay."""
    rail = height * 0.09
    parts = [
        mk.box(f"{name}.top", (length / 2, 0, height - rail / 2),
               (length, spindle_d * 1.8, rail), col),
        mk.box(f"{name}.bot", (length / 2, 0, rail / 2),
               (length, spindle_d * 1.8, rail), col),
    ]
    body = height - rail * 2
    count = max(1, int(length / spacing))
    pitch = length / count
    proto = mk.lathe(f"{name}.proto",
                     baluster_profile(body, spindle_d, "spindle"),
                     segments, col=col)
    mk.shade_smooth(proto, math.radians(40))
    for i in range(count):
        parts.append(mk.instance(proto, f"{name}.s{i}",
                                 ((i + 0.5) * pitch, 0.0, rail), col=col))
    bpy.data.objects.remove(proto)
    out = mk.join(parts, name, col)
    return out


def panel(name: str, width: float, height: float, depth: float,
          bevel_in: float = 0.055, raise_h: float = 0.018, col=None
          ) -> bpy.types.Object:
    """A raised-and-fielded panel: sunk border, chamfer, flat field."""
    w, h, b = width / 2, height / 2, bevel_in
    # depth is the full projection of the field above the surrounding stile,
    # so the chamfer starts far enough back for the raised part to land on it.
    z0, z1 = 0.0, max(0.0, depth - raise_h)
    outer = [(-w, -h), (w, -h), (w, h), (-w, h)]
    mid = [(-w + b, -h + b), (w - b, -h + b), (w - b, h - b), (-w + b, h - b)]
    inner = [(-w + b * 1.35, -h + b * 1.35), (w - b * 1.35, -h + b * 1.35),
             (w - b * 1.35, h - b * 1.35), (-w + b * 1.35, h - b * 1.35)]
    verts = [(x, z0, y) for x, y in outer] + \
            [(x, z1, y) for x, y in mid] + \
            [(x, z1 + raise_h, y) for x, y in inner]
    faces = []
    for i in range(4):
        j = (i + 1) % 4
        faces.append((i, j, j + 4, i + 4))          # sunk border
        faces.append((i + 4, j + 4, j + 8, i + 8))  # chamfer
    faces.append((8, 9, 10, 11))                    # field
    faces.append((3, 2, 1, 0))                      # back, so it stays solid
    obj = mk.obj_from(name, verts, faces, col=col)
    mk.recalc_normals(obj)
    return obj


def rosette(name: str, radius: float, depth: float, petals: int = 8,
            col=None) -> bpy.types.Object:
    """A carved corner block rosette for door and window casings."""
    prof = [(radius, 0.0), (radius * 0.98, depth * 0.30),
            (radius * 0.72, depth * 0.55), (radius * 0.34, depth * 0.80),
            (radius * 0.16, depth * 0.92), (0.0, depth)]
    obj = mk.lathe(name, [(0.0, 0.0), (radius, 0.0)] + prof[1:],
                   max(petals * 2, 12), col=col)
    mk.shade_smooth(obj, math.radians(45))
    return obj
