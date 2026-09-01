"""Audit every moulding profile: closed, CCW in (u, v), no degenerate points.

A profile wound the wrong way sweeps a solid with inverted normals, and a
duplicated point pinches the swept surface, so both are worth catching before
a profile is used a few hundred times across a facade.
"""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from victorian_estate.core import ornament as orn


def shoelace(poly):
    n = len(poly)
    return sum(poly[i][0] * poly[(i + 1) % n][1] - poly[(i + 1) % n][0] * poly[i][1]
               for i in range(n)) / 2.0


def duplicates(poly, eps=1e-9):
    n = len(poly)
    return sum(1 for i in range(n)
               if math.dist(poly[i], poly[(i + 1) % n]) < eps)


def self_intersections(poly):
    def hit(p, q, r, s):
        d1 = (q[0] - p[0], q[1] - p[1])
        d2 = (s[0] - r[0], s[1] - r[1])
        den = d1[0] * d2[1] - d1[1] * d2[0]
        if abs(den) < 1e-12:
            return False
        t = ((r[0] - p[0]) * d2[1] - (r[1] - p[1]) * d2[0]) / den
        u = ((r[0] - p[0]) * d1[1] - (r[1] - p[1]) * d1[0]) / den
        return 1e-7 < t < 1 - 1e-7 and 1e-7 < u < 1 - 1e-7
    n = len(poly)
    return sum(1 for i in range(n) for j in range(i + 2, n)
               if not (i == 0 and j == n - 1)
               and hit(poly[i], poly[(i + 1) % n], poly[j], poly[(j + 1) % n]))


CASES = [
    ("cornice_profile", orn.cornice_profile(0.95, 0.90)),
    ("cyma_recta", orn.cyma_recta(0.30, 0.30)),
    ("cyma_reversa", orn.cyma_reversa(0.22, 0.22)),
    ("ovolo", orn.ovolo(0.10, 0.10)),
    ("cavetto", orn.cavetto(0.10, 0.12)),
    ("torus_bead", orn.torus_bead(0.05)),
    ("fillet", orn.fillet(0.08, 0.05)),
    ("sill_profile", orn.sill_profile(0.115, 0.085)),
    ("water_table", orn.water_table(0.20, 0.30)),
    ("handrail_profile", orn.handrail_profile(0.14, 0.09)),
    ("casing_profile", orn.casing_profile(0.145, 0.042)),
    ("astragal", orn.astragal(0.02)),
]
LATHES = [
    ("post veranda", orn.turned_post_profile(3.0, 0.26, "veranda")),
    ("post newel", orn.turned_post_profile(1.4, 0.22, "newel")),
    ("post colonette", orn.turned_post_profile(1.0, 0.09, "colonette")),
    ("bal vase", orn.baluster_profile(0.72, 0.09, "vase")),
    ("bal bobbin", orn.baluster_profile(0.72, 0.09, "bobbin")),
    ("bal spindle", orn.baluster_profile(0.5, 0.055, "spindle")),
    ("fin spike", orn.finial_profile(1.6, 0.22, "spike")),
    ("fin urn", orn.finial_profile(1.6, 0.22, "urn")),
    ("fin ball", orn.finial_profile(1.0, 0.20, "ball")),
    ("fin acorn", orn.finial_profile(1.0, 0.18, "acorn")),
]

fails = 0
print(f"{'profile':22s} {'area':>10s} {'wind':>5s} {'dup':>4s} {'xint':>5s}")
for name, poly in CASES:
    a = shoelace(poly)
    d = duplicates(poly)
    x = self_intersections(poly)
    ok = a > 0 and d == 0 and x == 0
    fails += not ok
    print(f"{name:22s} {a:+10.5f} {'CCW' if a > 0 else 'CW ':>5s} {d:4d} {x:5d}"
          f"  {'' if ok else '  <-- FAIL'}")

# A lathe profile may legally double back in z - that is what an urn's
# turned-over rim is.  The invariant that actually matters is that the
# profile, closed along the axis, does not cross itself: that is what would
# make the revolved surface pass through itself.
print()
print(f"{'lathe profile':22s} {'pts':>5s} {'rmin':>8s} {'rmax':>8s} {'xint':>5s}")
for name, poly in LATHES:
    closed = list(poly) + [(0.0, poly[-1][1]), (0.0, poly[0][1])]
    seen, dedup = set(), []
    for pt in closed:
        key = (round(pt[0], 9), round(pt[1], 9))
        if key not in seen:
            seen.add(key)
            dedup.append(pt)
    x = self_intersections(dedup)
    rmin, rmax = min(r for r, _ in poly), max(r for r, _ in poly)
    bad = rmin < -1e-9 or x > 0
    fails += bad
    print(f"{name:22s} {len(poly):5d} {rmin:8.4f} {rmax:8.4f} {x:5d}"
          f"  {'' if not bad else '  <-- FAIL'}")

print()
print("FAILURES:", fails)
sys.exit(1 if fails else 0)
