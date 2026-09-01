"""
Check the model builds identically twice.

The README promises the estate is reproducible from one command, and the
planting is the part most easily made non-deterministic: seeding a tree from
hash(species) looks harmless but Python randomises string hashing per process,
so the park would grow differently on every run.  This builds the estate
twice in one process and compares object names and vertex counts.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from victorian_estate import build as vb


def fingerprint() -> dict[str, tuple[int, int]]:
    out = vb.build_all()
    return {o.name: (len(o.data.vertices), len(o.data.polygons))
            for group in out.values() for o in group if o.type == 'MESH'}


a = fingerprint()
b = fingerprint()

only_a = sorted(set(a) - set(b))
only_b = sorted(set(b) - set(a))
differing = sorted(k for k in set(a) & set(b) if a[k] != b[k])

total_a = sum(v[0] for v in a.values())
total_b = sum(v[0] for v in b.values())
print(f"build 1: {len(a):5d} meshes, {total_a} verts")
print(f"build 2: {len(b):5d} meshes, {total_b} verts")

for label, rows in (("only in build 1", only_a), ("only in build 2", only_b),
                    ("differing counts", differing)):
    print(f"\n{label}: {len(rows)}")
    for name in rows[:10]:
        print(f"    {name:<48s} {a.get(name)} vs {b.get(name)}")
    if len(rows) > 10:
        print(f"    ... and {len(rows) - 10} more")

bad = len(only_a) + len(only_b) + len(differing)
print(f"\n{'REPRODUCIBLE' if not bad else f'NOT REPRODUCIBLE ({bad} differences)'}")
sys.exit(1 if bad else 0)
