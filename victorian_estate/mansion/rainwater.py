"""
Rainwater goods: hopper heads, downpipes and shoes.

A Victorian elevation is never without them, and they do something useful in a
render that is otherwise all horizontals: a downpipe draws a hard vertical
line down the wall, and the hopper head at the top of it is one of the few
places on the house where cast metal catches a highlight against paint.
"""

from __future__ import annotations

import math

import bpy
from mathutils import Matrix

from ..core import config, meshkit as mk, ornament as orn
from ..core.materials import Library


def hopper(name: str, lib: Library, col, width: float = 0.42,
           height: float = 0.46, depth: float = 0.26) -> bpy.types.Object:
    """A cast hopper head: a flared box with a moulded rim and a date panel."""
    parts = []
    w, h, d = width / 2.0, height, depth
    # Flared body, wider at the top.
    top = [(-w, 0.0), (w, 0.0), (w * 0.86, d), (-w * 0.86, d)]
    bot = [(-w * 0.42, 0.0), (w * 0.42, 0.0), (w * 0.36, d * 0.52),
           (-w * 0.36, d * 0.52)]
    verts = [(x, y, h) for x, y in top] + [(x, y, 0.0) for x, y in bot]
    faces = [(0, 1, 2, 3)]
    for i in range(4):
        j = (i + 1) % 4
        faces.append((4 + j, 4 + i, i, j))
    faces.append((4, 5, 6, 7))
    body = mk.obj_from(f"{name}.body", verts, faces, col=col)
    mk.recalc_normals(body)
    parts.append(body)

    rim = mk.sweep(f"{name}.rim", orn.cyma_reversa(0.055, 0.075),
                   mk.rect_path(-w - 0.02, -0.02, w + 0.02, d + 0.02, h - 0.075),
                   closed_path=True, col=col)
    mk.recalc_normals(rim)
    parts.append(rim)

    # A moulded boss on the face, where a real one carried the date.
    boss = orn.rosette(f"{name}.boss", w * 0.34, 0.045, 10, col)
    mk.transform(boss, Matrix.Translation((0.0, d + 0.02, h * 0.52))
                 @ Matrix.Rotation(-math.pi / 2, 4, 'X'))
    parts.append(boss)

    obj = mk.join(parts, name, col)
    mk.set_material(obj, lib.lead)
    return obj


def downpipe(name: str, lib: Library, col, x: float, y: float,
             z_top: float, z_bottom: float, radius: float = 0.055,
             facing: float = 0.0, segments: int = 10, collars: bool = True
             ) -> bpy.types.Object:
    """A round downpipe with collars, ears and a shoe turning out at the foot."""
    parts = []
    run = z_top - z_bottom
    pipe = mk.lathe(f"{name}.pipe", [(radius, 0.0), (radius, run)], segments,
                    center=(x, y, z_bottom), col=col)
    mk.shade_smooth(pipe, math.radians(40))
    parts.append(pipe)

    if collars:
        n = max(2, int(run / 1.9))
        for i in range(n):
            z = z_bottom + run * (i + 0.5) / n
            collar = mk.lathe(f"{name}.collar{i}", [
                (radius * 1.28, 0.0), (radius * 1.28, 0.075),
                (radius * 1.04, 0.10)], segments, center=(x, y, z), col=col)
            parts.append(collar)
            # The ear that pins it to the wall.
            ear = mk.box(f"{name}.ear{i}", (0, 0, 0),
                         (radius * 0.9, radius * 2.2, 0.05), col)
            mk.transform(ear, Matrix.Translation((x, y, z + 0.04))
                         @ Matrix.Rotation(facing, 4, 'Z')
                         @ Matrix.Translation((0.0, -radius * 1.5, 0.0)))
            parts.append(ear)

    # A swan-neck shoe throwing the water clear of the plinth.
    shoe = mk.lathe(f"{name}.shoe", [
        (radius, 0.0), (radius, 0.22), (radius * 1.15, 0.30),
        (radius * 1.25, 0.36)], segments, cap=False, col=col)
    mk.transform(shoe, Matrix.Translation((x, y, z_bottom))
                 @ Matrix.Rotation(facing, 4, 'Z')
                 @ Matrix.Rotation(math.radians(-34), 4, 'X')
                 @ Matrix.Translation((0.0, 0.0, -0.30)))
    parts.append(shoe)

    obj = mk.join(parts, name, col)
    mk.set_material(obj, lib.lead)
    return obj


def build(lib: Library, col) -> list[bpy.types.Object]:
    """Downpipes at the internal angles and the rear corners of each block.

    They are kept off the entrance front, which is where a house of this date
    would have run its water back into a concealed box gutter instead.
    """
    made = []
    eave = config.Z_CORNICE + 0.30
    grade = config.Z_BASE + 0.55

    #: (x, y, top, bottom, which way the pipe's ear faces)
    runs = [
        (config.MAIN.x0 + 0.34, config.MAIN.y0 + 0.34, eave, grade,
         math.radians(225)),
        (config.MAIN.x1 - 0.34, config.MAIN.y0 + 0.34, eave, grade,
         math.radians(315)),
        (config.MAIN.x0 + 0.34, config.MAIN.y1 - 0.34, eave, grade,
         math.radians(135)),
        (config.WING.x0 + 0.30, config.WING.y0 + 0.30,
         config.WING.z1 + 0.28, grade, math.radians(225)),
        (config.WING.x1 - 0.30, config.WING.y0 + 0.30,
         config.WING.z1 + 0.28, grade, math.radians(315)),
        (config.PAVILION.x1 - 0.30, config.PAVILION.y0 + 0.30,
         config.PAVILION.z1 + 0.28, grade, math.radians(315)),
    ]
    for i, (x, y, top, bottom, facing) in enumerate(runs):
        h = hopper(f"rw.hopper{i}", lib, col)
        mk.transform(h, Matrix.Translation((x, y, top - 0.46))
                     @ Matrix.Rotation(facing, 4, 'Z'))
        made.append(h)
        made.append(downpipe(f"rw.pipe{i}", lib, col, x, y, top - 0.44,
                             bottom, facing=facing))
    return made
