"""Orchestrates the whole model: house, then grounds."""

from __future__ import annotations

import math
import time
from dataclasses import dataclass

import bpy

from .core import config, meshkit as mk, materials as mat
from .core.render import Shot
from .grounds import furniture, hardscape, layout, outbuildings, terrain
from .mansion import interior, rainwater, roof, shell, tower, veranda


@dataclass(frozen=True)
class View:
    """A camera together with the light it is meant to be seen in.

    Sun angle is part of the shot, not a global: a facade is modelled by the
    shadows its own mouldings throw, so each elevation wants the sun raking
    across it rather than sitting behind the camera.  One global sun would
    leave half these views flat.
    """
    shot: Shot
    elevation: float = 22.0
    rotation: float = 196.0
    exposure: float = -0.55
    sky: float = 0.44
    energy: float = 5.6
    softness: float = 0.55

    @property
    def key(self) -> str:
        return self.shot.name.split(".")[-1].lower()


#: The set of views the project renders from, saved into the .blend.
VIEWS = (
    # Looking north up the drive at the entrance front: sun from the east so
    # the front is lit and the tower throws its shadow west.
    View(Shot("Cam.Approach", (3.0, 58.0, 7.0), (0.0, 6.0, 12.5), lens=46),
         elevation=21, rotation=58, exposure=-0.55),
    # The three-quarter view: the sun rakes the west front almost edge on,
    # which is what pulls the bay, the brackets and the cornice out of it.
    View(Shot("Cam.SouthWest", (-42.0, 48.0, 12.0), (-3.0, 2.0, 11.0), lens=50),
         elevation=18, rotation=196, exposure=-0.60),
    View(Shot("Cam.SouthEast", (44.0, 52.0, 12.0), (0.0, 0.0, 11.0), lens=50),
         elevation=20, rotation=18, exposure=-0.58),
    View(Shot("Cam.Estate", (96.0, 118.0, 86.0), (-4.0, 6.0, 6.0), lens=52),
         elevation=33, rotation=126, exposure=-0.45, sky=0.50, energy=4.8),
    View(Shot("Cam.Garden", (-62.0, -18.0, 16.0), (-24.0, 6.0, 10.0), lens=48),
         elevation=24, rotation=232, exposure=-0.55),
    View(Shot("Cam.Stables", (-48.0, -54.0, 14.0), (-24.0, -26.0, 6.0), lens=50),
         elevation=23, rotation=286, exposure=-0.55),
    # Under the veranda roof, so the key has to come in almost horizontally.
    View(Shot("Cam.Veranda", (7.2, 19.5, 2.3), (-4.0, 8.0, 3.2), lens=34),
         elevation=13, rotation=64, exposure=-0.45, sky=0.55, energy=6.4,
         softness=0.4),
)

SHOTS = tuple(v.shot for v in VIEWS)


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

    stage("shell", lambda: shell.build(lib, house, detail))
    if detail.interior:
        stage("interior", lambda: interior.build(lib, house))

    porch = mk.collection("Veranda", root)
    plan = veranda.front_plan()
    stage("veranda", lambda: veranda.build(plan, lib, porch))
    stage("porte-cochere", lambda: veranda.porte_cochere(
        "portecochere", lib, porch, config.PAVILION.x1, config.PAVILION.cy,
        -math.pi / 2))
    stage("steps", lambda: [veranda.steps(
        "veranda.steps", (1.10, config.MAIN.y1 + config.VERANDA_DEPTH),
        (0.0, 1.0), 3.30, plan.deck_z, lib, porch)])

    stage("rainwater", lambda: rainwater.build(lib, house))

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

    stage("furniture", lambda: furniture.build(lib, site, lit=detail.lit))

    green = mk.collection("Planting", root)
    stage("planting", lambda: layout.build(lib, green, detail))

    total_v = sum(len(o.data.vertices) for group in out.values() for o in group)
    total_f = sum(len(o.data.polygons) for group in out.values() for o in group)
    print(f"  TOTAL      {total_v:>8d} verts  {total_f:>8d} faces")
    return out
