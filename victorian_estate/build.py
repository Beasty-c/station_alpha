"""Orchestrates the whole model: house, then grounds."""

from __future__ import annotations

import time

import bpy

from .core import config, meshkit as mk, materials as mat
from .grounds import hardscape, layout, outbuildings, terrain
from .mansion import roof, shell, tower, veranda


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mat.reset()


def build_all(detail: config.Detail | None = None, fresh: bool = True) -> dict:
    """Build every part that currently exists, returning the collections."""
    if fresh:
        reset_scene()
    detail = detail or config.DETAIL
    lib = mat.library()

    root = mk.collection("Estate")
    house = mk.collection("House", root)
    out: dict[str, list] = {}

    def stage(label: str, fn):
        t0 = time.time()
        made = fn()
        out[label] = made
        print(f"  {label:<11s}{time.time() - t0:6.1f}s "
              f"{sum(len(o.data.vertices) for o in made):>9d} verts")

    stage("shell", lambda: shell.build(lib, house))

    porch = mk.collection("Veranda", root)
    plan = veranda.front_plan()
    stage("veranda", lambda: veranda.build(plan, lib, porch))
    stage("steps", lambda: [veranda.steps(
        "veranda.steps", (1.10, config.MAIN.y1 + config.VERANDA_DEPTH),
        (0.0, 1.0), 3.30, plan.deck_z, lib, porch)])

    tow = mk.collection("Tower", root)
    stage("tower", lambda: tower.build(lib, tow))

    roofs = mk.collection("Roof", root)
    eave = config.Z_CORNICE + 0.86
    stage("mansard", lambda: roof.mansard(config.MAIN, lib, roofs, eave))
    stage("dormers", lambda: roof.place_dormers(
        config.MAIN, lib, roofs, eave,
        {"south": 4, "north": 4, "east": 3, "west": 3}, inset=0.42))
    stage("wing roof", lambda: roof.gable_roof(
        config.WING, lib, roofs, config.WING.z1 + 0.70, pitch=50.0,
        along_x=False))
    stage("pavilion roof", lambda: roof.gable_roof(
        config.PAVILION, lib, roofs, config.PAVILION.z1 + 0.86, pitch=54.0,
        along_x=False))
    stage("chimneys", lambda: [
        roof.chimney("chimney.west", lib, roofs, -5.4, 1.2, config.Z_F3,
                     eave + 8.2, 1.45, 1.05, 3),
        roof.chimney("chimney.east", lib, roofs, 6.2, -2.4, config.Z_F3,
                     eave + 7.6, 1.30, 0.95, 3),
        roof.chimney("chimney.wing", lib, roofs, -2.0, -13.6, config.Z_F2,
                     config.WING.z1 + 5.4, 1.10, 0.85, 2),
    ])

    site = mk.collection("Grounds", root)
    stage("terrain", lambda: terrain.build(lib, site))
    stage("drive", lambda: hardscape.drive(lib, site))
    stage("terrace", lambda: hardscape.terrace(lib, site))
    stage("fountain", lambda: hardscape.fountain(lib, site))
    stage("perimeter", lambda: hardscape.perimeter(lib, site))

    works = mk.collection("Outbuildings", root)
    stage("carriage house", lambda: outbuildings.carriage_house(lib, works))
    stage("conservatory", lambda: outbuildings.conservatory(lib, works))
    stage("gazebo", lambda: outbuildings.gazebo(lib, works))
    stage("lodge", lambda: outbuildings.lodge(lib, works))
    stage("pond", lambda: outbuildings.pond(lib, works))

    green = mk.collection("Planting", root)
    stage("planting", lambda: layout.build(lib, green, detail))

    total_v = sum(len(o.data.vertices) for group in out.values() for o in group)
    total_f = sum(len(o.data.polygons) for group in out.values() for o in group)
    print(f"  TOTAL      {total_v:>8d} verts  {total_f:>8d} faces")
    return out
