"""
Procedural material library.

Everything here is node-based and texture-free, so the .blend is self
contained and nothing depends on assets that would have to be shipped
alongside it.  The workhorse is :func:`painted`, which builds a Principled
surface whose roughness and normal are broken up by layered noise - paint on
a hundred-year-old house is never uniform, and the variation is most of what
sells the material at render scale.
"""

from __future__ import annotations

from typing import Sequence

import bpy

from . import config

RGB = Sequence[float]

_CACHE: dict[str, bpy.types.Material] = {}


# ---------------------------------------------------------------------------
# Node graph helpers
# ---------------------------------------------------------------------------

def _new(name: str) -> tuple[bpy.types.Material, bpy.types.NodeTree]:
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    return mat, nt


def _node(nt, kind: str, x: float = 0.0, y: float = 0.0, **props):
    n = nt.nodes.new(kind)
    n.location = (x, y)
    for key, value in props.items():
        if "." in key:
            head, tail = key.split(".", 1)
            setattr(getattr(n, head), tail, value)
        else:
            setattr(n, key, value)
    return n


def _set(node, socket, value) -> None:
    node.inputs[socket].default_value = value


def _rgba(color: RGB, alpha: float = 1.0) -> tuple[float, float, float, float]:
    return (color[0], color[1], color[2], alpha)


def _out(nt, surface_node, x: float = 600.0):
    out = _node(nt, "ShaderNodeOutputMaterial", x, 0)
    nt.links.new(surface_node.outputs[0], out.inputs["Surface"])
    return out


def _noise(nt, x, y, scale=8.0, detail=8.0, roughness=0.55, distortion=0.0,
           coords=None, dimension=3):
    n = _node(nt, "ShaderNodeTexNoise", x, y)
    n.noise_dimensions = f"{dimension}D"
    _set(n, "Scale", scale)
    _set(n, "Detail", detail)
    _set(n, "Roughness", roughness)
    _set(n, "Distortion", distortion)
    if coords is not None:
        nt.links.new(coords, n.inputs["Vector"])
    return n


def _musgrave_like(nt, x, y, scale=6.0, detail=10.0, coords=None):
    """Blender 4.x dropped the Musgrave node; a high-detail noise with a
    ramp gives the same broken, fractal-edged look."""
    n = _noise(nt, x, y, scale=scale, detail=detail, roughness=0.72,
               coords=coords)
    ramp = _node(nt, "ShaderNodeValToRGB", x + 180, y)
    ramp.color_ramp.elements[0].position = 0.32
    ramp.color_ramp.elements[1].position = 0.72
    nt.links.new(n.outputs["Fac"], ramp.inputs["Fac"])
    return ramp


def _obj_coords(nt, x=-1200.0, y=0.0):
    return _node(nt, "ShaderNodeTexCoord", x, y)


def _bump(nt, height_socket, strength=0.25, distance=0.02, x=380.0, y=-260.0):
    b = _node(nt, "ShaderNodeBump", x, y)
    _set(b, "Strength", strength)
    _set(b, "Distance", distance)
    nt.links.new(height_socket, b.inputs["Height"])
    return b


def _principled(nt, x=380.0, y=140.0, **inputs):
    bsdf = _node(nt, "ShaderNodeBsdfPrincipled", x, y)
    for key, value in inputs.items():
        key = key.replace("_", " ").title()
        aliases = {"Ior": "IOR", "Ior Level": "IOR Level"}
        key = aliases.get(key, key)
        if key in bsdf.inputs:
            _set(bsdf, key, value)
    return bsdf


# ---------------------------------------------------------------------------
# Core surfaces
# ---------------------------------------------------------------------------

def painted(name: str, color: RGB, roughness: float = 0.42,
            wear: float = 0.35, bump_scale: float = 34.0,
            sheen: float = 0.0) -> bpy.types.Material:
    """Oil-painted joinery: chalked, unevenly weathered, faintly orange-peeled."""
    key = f"paint::{name}"
    if key in _CACHE:
        return _CACHE[key]
    mat, nt = _new(name)
    coords = _obj_coords(nt)

    grime = _noise(nt, -900, 300, scale=2.4, detail=6.0,
                   coords=coords.outputs["Object"])
    fine = _noise(nt, -900, 0, scale=bump_scale, detail=6.0, roughness=0.6,
                  coords=coords.outputs["Object"])
    micro = _noise(nt, -900, -300, scale=bump_scale * 7.0, detail=3.0,
                   coords=coords.outputs["Object"])

    # Colour: darken slightly where grime collects.
    dark = [c * 0.62 for c in color]
    mix = _node(nt, "ShaderNodeMixRGB", -560, 260, blend_type='MIX')
    _set(mix, "Color1", _rgba(color))
    _set(mix, "Color2", _rgba(dark))
    nt.links.new(grime.outputs["Fac"], mix.inputs["Fac"])
    _set(mix, "Fac", wear)

    rough = _node(nt, "ShaderNodeMapRange", -560, -40)
    _set(rough, "From Min", 0.25)
    _set(rough, "From Max", 0.75)
    _set(rough, "To Min", max(0.05, roughness - 0.14))
    _set(rough, "To Max", min(1.0, roughness + 0.18))
    nt.links.new(fine.outputs["Fac"], rough.inputs["Value"])

    bsdf = _principled(nt, base_color=_rgba(color), roughness=roughness,
                       sheen_weight=sheen)
    nt.links.new(mix.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(rough.outputs["Result"], bsdf.inputs["Roughness"])
    bump = _bump(nt, micro.outputs["Fac"], strength=0.12, distance=0.0025)
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    _out(nt, bsdf)
    _CACHE[key] = mat
    return mat


def clapboard(name: str, color: RGB, board: float = 0.155
              ) -> bpy.types.Material:
    """Painted lap siding - horizontal shadow lines driven by world Z."""
    key = f"clap::{name}:{board}"
    if key in _CACHE:
        return _CACHE[key]
    mat, nt = _new(name)
    coords = _obj_coords(nt)
    sep = _node(nt, "ShaderNodeSeparateXYZ", -1000, -180)
    nt.links.new(coords.outputs["Object"], sep.inputs["Vector"])

    # Sawtooth in Z at the board pitch: a wave texture is the cheapest way in.
    wave = _node(nt, "ShaderNodeTexWave", -1000, 160)
    wave.wave_type = 'BANDS'
    wave.bands_direction = 'Z'
    wave.wave_profile = 'SAW'
    _set(wave, "Scale", 1.0 / board)
    _set(wave, "Distortion", 0.6)
    _set(wave, "Detail", 2.0)
    _set(wave, "Detail Scale", 0.4)
    nt.links.new(coords.outputs["Object"], wave.inputs["Vector"])

    grain = _noise(nt, -1000, -440, scale=90.0, detail=6.0,
                   coords=coords.outputs["Object"])
    grime = _noise(nt, -1000, 440, scale=1.8, detail=7.0,
                   coords=coords.outputs["Object"])

    ramp = _node(nt, "ShaderNodeValToRGB", -760, 160)
    ramp.color_ramp.interpolation = 'EASE'
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = (0.25, 0.25, 0.25, 1)
    ramp.color_ramp.elements[1].position = 0.16
    ramp.color_ramp.elements[1].color = (1, 1, 1, 1)
    nt.links.new(wave.outputs["Fac"], ramp.inputs["Fac"])

    dark = [c * 0.5 for c in color]
    shade = _node(nt, "ShaderNodeMixRGB", -520, 200)
    _set(shade, "Color1", _rgba(dark))
    _set(shade, "Color2", _rgba(color))
    nt.links.new(ramp.outputs["Color"], shade.inputs["Fac"])

    weather = _node(nt, "ShaderNodeMixRGB", -300, 240)
    _set(weather, "Fac", 0.22)
    _set(weather, "Color2", _rgba([c * 0.7 + 0.05 for c in color]))
    nt.links.new(shade.outputs["Color"], weather.inputs["Color1"])
    nt.links.new(grime.outputs["Fac"], weather.inputs["Fac"])

    bsdf = _principled(nt, roughness=0.56)
    nt.links.new(weather.outputs["Color"], bsdf.inputs["Base Color"])

    # Two-stage bump: board steps, then wood grain inside each board.
    grain_bump = _bump(nt, grain.outputs["Fac"], 0.10, 0.0015, x=100, y=-460)
    step_bump = _node(nt, "ShaderNodeBump", 260, -320)
    _set(step_bump, "Strength", 0.55)
    _set(step_bump, "Distance", 0.012)
    nt.links.new(ramp.outputs["Color"], step_bump.inputs["Height"])
    nt.links.new(grain_bump.outputs["Normal"], step_bump.inputs["Normal"])
    nt.links.new(step_bump.outputs["Normal"], bsdf.inputs["Normal"])
    _out(nt, bsdf)
    _CACHE[key] = mat
    return mat


def shingle_scale(name: str, color: RGB, accent: RGB, scale: float = 7.0
                  ) -> bpy.types.Material:
    """Fish-scale shingles for gable fields - Voronoi cells read as scallops."""
    key = f"scale::{name}"
    if key in _CACHE:
        return _CACHE[key]
    mat, nt = _new(name)
    coords = _obj_coords(nt)
    vor = _node(nt, "ShaderNodeTexVoronoi", -940, 120)
    vor.feature = 'DISTANCE_TO_EDGE'
    vor.voronoi_dimensions = '3D'
    _set(vor, "Scale", scale)
    _set(vor, "Randomness", 0.18)
    nt.links.new(coords.outputs["Object"], vor.inputs["Vector"])

    cell = _node(nt, "ShaderNodeTexVoronoi", -940, -220)
    cell.feature = 'F1'
    cell.voronoi_dimensions = '3D'
    _set(cell, "Scale", scale)
    _set(cell, "Randomness", 0.18)
    nt.links.new(coords.outputs["Object"], cell.inputs["Vector"])

    ramp = _node(nt, "ShaderNodeValToRGB", -700, 120)
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[1].position = 0.09
    nt.links.new(vor.outputs["Distance"], ramp.inputs["Fac"])

    tint = _node(nt, "ShaderNodeMixRGB", -700, -220)
    _set(tint, "Color1", _rgba(color))
    _set(tint, "Color2", _rgba(accent))
    nt.links.new(cell.outputs["Color"], tint.inputs["Fac"])

    groove = _node(nt, "ShaderNodeMixRGB", -460, 0)
    _set(groove, "Color2", (0.02, 0.02, 0.02, 1))
    nt.links.new(ramp.outputs["Color"], groove.inputs["Fac"])
    nt.links.new(tint.outputs["Color"], groove.inputs["Color1"])

    bsdf = _principled(nt, roughness=0.6)
    nt.links.new(groove.outputs["Color"], bsdf.inputs["Base Color"])
    bump = _bump(nt, ramp.outputs["Color"], 0.7, 0.02)
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    _out(nt, bsdf)
    _CACHE[key] = mat
    return mat


def slate(name: str = "Slate", color: RGB | None = None) -> bpy.types.Material:
    """Welsh slate: near-black, faintly purple, with a cleaved sheen."""
    key = f"slate::{name}"
    if key in _CACHE:
        return _CACHE[key]
    color = color or config.PALETTE["slate"]
    mat, nt = _new(name)
    coords = _obj_coords(nt)
    cleave = _noise(nt, -940, 200, scale=110.0, detail=8.0, roughness=0.75,
                    coords=coords.outputs["Object"])
    patch = _noise(nt, -940, -160, scale=3.6, detail=5.0,
                   coords=coords.outputs["Object"])

    tint = _node(nt, "ShaderNodeMixRGB", -680, -60)
    _set(tint, "Color1", _rgba(color))
    _set(tint, "Color2", _rgba([c * 1.9 + 0.02 for c in color]))
    nt.links.new(patch.outputs["Fac"], tint.inputs["Fac"])
    _set(tint, "Fac", 0.55)

    rough = _node(nt, "ShaderNodeMapRange", -680, -340)
    _set(rough, "From Min", 0.3); _set(rough, "From Max", 0.7)
    _set(rough, "To Min", 0.20); _set(rough, "To Max", 0.48)
    nt.links.new(cleave.outputs["Fac"], rough.inputs["Value"])

    bsdf = _principled(nt, specular_ior_level=0.45)
    nt.links.new(tint.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(rough.outputs["Result"], bsdf.inputs["Roughness"])
    bump = _bump(nt, cleave.outputs["Fac"], 0.25, 0.004)
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    _out(nt, bsdf)
    _CACHE[key] = mat
    return mat


def stone(name: str = "Limestone", color: RGB | None = None,
          rough: float = 0.75, pit: float = 0.5) -> bpy.types.Material:
    key = f"stone::{name}"
    if key in _CACHE:
        return _CACHE[key]
    color = color or config.PALETTE["stone"]
    mat, nt = _new(name)
    coords = _obj_coords(nt)
    grain = _noise(nt, -940, 120, scale=42.0, detail=9.0, roughness=0.68,
                   coords=coords.outputs["Object"])
    blotch = _noise(nt, -940, -180, scale=2.1, detail=6.0,
                    coords=coords.outputs["Object"])
    pits = _node(nt, "ShaderNodeTexVoronoi", -940, -460)
    pits.voronoi_dimensions = '3D'
    _set(pits, "Scale", 70.0)
    nt.links.new(coords.outputs["Object"], pits.inputs["Vector"])

    mix = _node(nt, "ShaderNodeMixRGB", -660, -30)
    _set(mix, "Color1", _rgba(color))
    _set(mix, "Color2", _rgba([c * 0.68 for c in color]))
    nt.links.new(blotch.outputs["Fac"], mix.inputs["Fac"])
    _set(mix, "Fac", 0.6)

    mix2 = _node(nt, "ShaderNodeMixRGB", -440, -30)
    _set(mix2, "Fac", 0.35)
    _set(mix2, "Color2", _rgba([min(1.0, c * 1.28 + 0.04) for c in color]))
    nt.links.new(mix.outputs["Color"], mix2.inputs["Color1"])
    nt.links.new(grain.outputs["Fac"], mix2.inputs["Fac"])

    bsdf = _principled(nt, roughness=rough)
    nt.links.new(mix2.outputs["Color"], bsdf.inputs["Base Color"])
    b1 = _bump(nt, grain.outputs["Fac"], 0.35, 0.006, x=80, y=-480)
    b2 = _node(nt, "ShaderNodeBump", 240, -360)
    _set(b2, "Strength", pit)
    _set(b2, "Distance", 0.012)
    nt.links.new(pits.outputs["Distance"], b2.inputs["Height"])
    nt.links.new(b1.outputs["Normal"], b2.inputs["Normal"])
    nt.links.new(b2.outputs["Normal"], bsdf.inputs["Normal"])
    _out(nt, bsdf)
    _CACHE[key] = mat
    return mat


def brick(name: str = "Brick", color: RGB | None = None,
          mortar: RGB = (0.55, 0.53, 0.49), course: float = 0.075
          ) -> bpy.types.Material:
    """Running-bond brick driven by a brick texture node in object space."""
    key = f"brick::{name}"
    if key in _CACHE:
        return _CACHE[key]
    color = color or config.PALETTE["brick"]
    mat, nt = _new(name)
    coords = _obj_coords(nt)
    bt = _node(nt, "ShaderNodeTexBrick", -940, 100)
    _set(bt, "Color1", _rgba(color))
    _set(bt, "Color2", _rgba([min(1.0, c * 1.45 + 0.02) for c in color]))
    _set(bt, "Mortar", _rgba(mortar))
    _set(bt, "Scale", 1.0)
    _set(bt, "Mortar Size", 0.006)
    _set(bt, "Mortar Smooth", 0.15)
    _set(bt, "Bias", 0.0)
    _set(bt, "Brick Width", 0.23)
    _set(bt, "Row Height", course)
    bt.offset = 0.5
    bt.squash = 1.0
    nt.links.new(coords.outputs["Object"], bt.inputs["Vector"])

    soot = _noise(nt, -940, -260, scale=1.6, detail=6.0,
                  coords=coords.outputs["Object"])
    weather = _node(nt, "ShaderNodeMixRGB", -600, 40)
    _set(weather, "Fac", 0.3)
    _set(weather, "Color2", (0.05, 0.045, 0.04, 1))
    nt.links.new(bt.outputs["Color"], weather.inputs["Color1"])
    nt.links.new(soot.outputs["Fac"], weather.inputs["Fac"])

    bsdf = _principled(nt, roughness=0.82)
    nt.links.new(weather.outputs["Color"], bsdf.inputs["Base Color"])
    bump = _bump(nt, bt.outputs["Fac"], 0.6, 0.008)
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    _out(nt, bsdf)
    _CACHE[key] = mat
    return mat


def glass(name: str = "Glass", tint: RGB = (0.86, 0.90, 0.88),
          rough: float = 0.02, wavy: float = 0.6) -> bpy.types.Material:
    """Cylinder glass - slightly green, slightly rippled, as pre-float glass is."""
    key = f"glass::{name}"
    if key in _CACHE:
        return _CACHE[key]
    mat, nt = _new(name)
    mat.use_backface_culling = False
    coords = _obj_coords(nt)
    ripple = _noise(nt, -940, -220, scale=9.0, detail=3.0, roughness=0.4,
                    coords=coords.outputs["Object"])
    bsdf = _principled(nt, base_color=_rgba(tint), roughness=rough,
                       transmission_weight=1.0, ior=1.52)
    bump = _bump(nt, ripple.outputs["Fac"], wavy * 0.16, 0.004)
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    _out(nt, bsdf)
    _CACHE[key] = mat
    return mat


def stained_glass(name: str, palette: Sequence[RGB], scale: float = 26.0
                  ) -> bpy.types.Material:
    """Leaded coloured glass - Voronoi cells stand in for the quarries, and
    the cell borders darken into came."""
    key = f"stained::{name}"
    if key in _CACHE:
        return _CACHE[key]
    mat, nt = _new(name)
    coords = _obj_coords(nt)
    cells = _node(nt, "ShaderNodeTexVoronoi", -1000, 120)
    cells.voronoi_dimensions = '3D'
    _set(cells, "Scale", scale)
    _set(cells, "Randomness", 0.85)
    nt.links.new(coords.outputs["Object"], cells.inputs["Vector"])

    edge = _node(nt, "ShaderNodeTexVoronoi", -1000, -200)
    edge.feature = 'DISTANCE_TO_EDGE'
    edge.voronoi_dimensions = '3D'
    _set(edge, "Scale", scale)
    _set(edge, "Randomness", 0.85)
    nt.links.new(coords.outputs["Object"], edge.inputs["Vector"])

    ramp = _node(nt, "ShaderNodeValToRGB", -740, 160)
    cr = ramp.color_ramp
    cr.interpolation = 'CONSTANT'
    while len(cr.elements) > 1:
        cr.elements.remove(cr.elements[-1])
    cr.elements[0].position = 0.0
    cr.elements[0].color = _rgba(palette[0])
    for i, c in enumerate(palette[1:], start=1):
        el = cr.elements.new(i / len(palette))
        el.color = _rgba(c)
    nt.links.new(cells.outputs["Color"], ramp.inputs["Fac"])

    came = _node(nt, "ShaderNodeValToRGB", -740, -200)
    came.color_ramp.elements[0].position = 0.005
    came.color_ramp.elements[1].position = 0.030
    nt.links.new(edge.outputs["Distance"], came.inputs["Fac"])

    lead = _principled(nt, x=-380, y=-320, base_color=(0.05, 0.05, 0.055, 1),
                       roughness=0.55, metallic=0.9)
    col = _principled(nt, x=-380, y=180, roughness=0.08,
                      transmission_weight=1.0, ior=1.52)
    nt.links.new(ramp.outputs["Color"], col.inputs["Base Color"])

    mix = _node(nt, "ShaderNodeMixShader", 100, 0)
    nt.links.new(came.outputs["Color"], mix.inputs["Fac"])
    nt.links.new(lead.outputs[0], mix.inputs[1])
    nt.links.new(col.outputs[0], mix.inputs[2])
    _out(nt, mix)
    _CACHE[key] = mat
    return mat


def metal(name: str, color: RGB, rough: float = 0.35, metallic: float = 1.0,
          grain: float = 40.0) -> bpy.types.Material:
    key = f"metal::{name}"
    if key in _CACHE:
        return _CACHE[key]
    mat, nt = _new(name)
    coords = _obj_coords(nt)
    n = _noise(nt, -900, -80, scale=grain, detail=6.0,
               coords=coords.outputs["Object"])
    rr = _node(nt, "ShaderNodeMapRange", -640, -80)
    _set(rr, "From Min", 0.3); _set(rr, "From Max", 0.7)
    _set(rr, "To Min", max(0.03, rough - 0.12))
    _set(rr, "To Max", min(1.0, rough + 0.16))
    nt.links.new(n.outputs["Fac"], rr.inputs["Value"])
    bsdf = _principled(nt, base_color=_rgba(color), metallic=metallic)
    nt.links.new(rr.outputs["Result"], bsdf.inputs["Roughness"])
    bump = _bump(nt, n.outputs["Fac"], 0.12, 0.002)
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    _out(nt, bsdf)
    _CACHE[key] = mat
    return mat


def copper_patina(name: str = "CopperPatina") -> bpy.types.Material:
    """Verdigris over copper - the finials, cresting caps and conservatory ribs."""
    key = "patina"
    if key in _CACHE:
        return _CACHE[key]
    mat, nt = _new(name)
    coords = _obj_coords(nt)
    n = _musgrave_like(nt, -1000, 100, scale=5.5, detail=10.0,
                       coords=coords.outputs["Object"])
    streak = _noise(nt, -1000, -260, scale=2.0, detail=8.0, distortion=1.4,
                    coords=coords.outputs["Object"])
    blend = _node(nt, "ShaderNodeMixRGB", -560, -60, blend_type='MULTIPLY')
    _set(blend, "Fac", 0.6)
    nt.links.new(n.outputs["Color"], blend.inputs["Color1"])
    nt.links.new(streak.outputs["Fac"], blend.inputs["Color2"])

    base = _node(nt, "ShaderNodeMixRGB", -320, 60)
    _set(base, "Color1", (0.42, 0.20, 0.10, 1))          # bare copper
    _set(base, "Color2", _rgba(config.PALETTE["copper"]))  # verdigris
    nt.links.new(blend.outputs["Color"], base.inputs["Fac"])

    met = _node(nt, "ShaderNodeMapRange", -320, -240)
    _set(met, "To Min", 1.0); _set(met, "To Max", 0.0)
    nt.links.new(blend.outputs["Color"], met.inputs["Value"])
    rgh = _node(nt, "ShaderNodeMapRange", -320, -430)
    _set(rgh, "To Min", 0.24); _set(rgh, "To Max", 0.86)
    nt.links.new(blend.outputs["Color"], rgh.inputs["Value"])

    bsdf = _principled(nt)
    nt.links.new(base.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(met.outputs["Result"], bsdf.inputs["Metallic"])
    nt.links.new(rgh.outputs["Result"], bsdf.inputs["Roughness"])
    bump = _bump(nt, blend.outputs["Color"], 0.3, 0.006)
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    _out(nt, bsdf)
    _CACHE[key] = mat
    return mat


def gravel(name: str = "Gravel") -> bpy.types.Material:
    key = "gravel"
    if key in _CACHE:
        return _CACHE[key]
    mat, nt = _new(name)
    coords = _obj_coords(nt)
    stones = _node(nt, "ShaderNodeTexVoronoi", -1000, 100)
    stones.voronoi_dimensions = '3D'
    _set(stones, "Scale", 55.0)
    nt.links.new(coords.outputs["Object"], stones.inputs["Vector"])
    edge = _node(nt, "ShaderNodeTexVoronoi", -1000, -220)
    edge.feature = 'DISTANCE_TO_EDGE'
    edge.voronoi_dimensions = '3D'
    _set(edge, "Scale", 55.0)
    nt.links.new(coords.outputs["Object"], edge.inputs["Vector"])
    drift = _noise(nt, -1000, -500, scale=1.4, detail=6.0,
                   coords=coords.outputs["Object"])

    base = config.PALETTE["gravel"]
    tint = _node(nt, "ShaderNodeMixRGB", -700, 60)
    _set(tint, "Color1", _rgba([c * 0.72 for c in base]))
    _set(tint, "Color2", _rgba([min(1, c * 1.5) for c in base]))
    nt.links.new(stones.outputs["Color"], tint.inputs["Fac"])

    wear = _node(nt, "ShaderNodeMixRGB", -460, 60)
    _set(wear, "Fac", 0.3)
    _set(wear, "Color2", _rgba([c * 0.8 for c in base]))
    nt.links.new(tint.outputs["Color"], wear.inputs["Color1"])
    nt.links.new(drift.outputs["Fac"], wear.inputs["Fac"])

    bsdf = _principled(nt, roughness=0.92)
    nt.links.new(wear.outputs["Color"], bsdf.inputs["Base Color"])
    b = _bump(nt, edge.outputs["Distance"], 1.0, 0.03)
    nt.links.new(b.outputs["Normal"], bsdf.inputs["Normal"])
    _out(nt, bsdf)
    _CACHE[key] = mat
    return mat


def cobbles(name: str = "Cobbles", color: RGB = (0.135, 0.125, 0.118)
            ) -> bpy.types.Material:
    """Setts laid to a fan - larger and more regular than gravel, with the
    joints reading as dark lines rather than as shadow between stones."""
    key = f"cobbles::{name}"
    if key in _CACHE:
        return _CACHE[key]
    mat, nt = _new(name)
    coords = _obj_coords(nt)
    cells = _node(nt, "ShaderNodeTexVoronoi", -1000, 120)
    cells.voronoi_dimensions = '3D'
    _set(cells, "Scale", 9.0)
    _set(cells, "Randomness", 0.62)
    nt.links.new(coords.outputs["Object"], cells.inputs["Vector"])
    joints = _node(nt, "ShaderNodeTexVoronoi", -1000, -200)
    joints.feature = 'DISTANCE_TO_EDGE'
    joints.voronoi_dimensions = '3D'
    _set(joints, "Scale", 9.0)
    _set(joints, "Randomness", 0.62)
    nt.links.new(coords.outputs["Object"], joints.inputs["Vector"])
    grain = _noise(nt, -1000, -470, scale=140.0, detail=6.0,
                   coords=coords.outputs["Object"])

    tint = _node(nt, "ShaderNodeMixRGB", -720, 80)
    _set(tint, "Color1", _rgba([c * 0.62 for c in color]))
    _set(tint, "Color2", _rgba([min(1.0, c * 1.75) for c in color]))
    nt.links.new(cells.outputs["Color"], tint.inputs["Fac"])

    ramp = _node(nt, "ShaderNodeValToRGB", -720, -200)
    ramp.color_ramp.elements[0].position = 0.005
    ramp.color_ramp.elements[1].position = 0.055
    nt.links.new(joints.outputs["Distance"], ramp.inputs["Fac"])

    grout = _node(nt, "ShaderNodeMixRGB", -460, 0)
    _set(grout, "Color1", (0.055, 0.050, 0.045, 1))
    nt.links.new(ramp.outputs["Color"], grout.inputs["Fac"])
    nt.links.new(tint.outputs["Color"], grout.inputs["Color2"])

    bsdf = _principled(nt, roughness=0.62)
    nt.links.new(grout.outputs["Color"], bsdf.inputs["Base Color"])
    b1 = _bump(nt, grain.outputs["Fac"], 0.14, 0.002, x=80, y=-470)
    b2 = _node(nt, "ShaderNodeBump", 250, -340)
    _set(b2, "Strength", 0.85)
    _set(b2, "Distance", 0.022)
    nt.links.new(ramp.outputs["Color"], b2.inputs["Height"])
    nt.links.new(b1.outputs["Normal"], b2.inputs["Normal"])
    nt.links.new(b2.outputs["Normal"], bsdf.inputs["Normal"])
    _out(nt, bsdf)
    _CACHE[key] = mat
    return mat


def turf(name: str = "Lawn", color: RGB | None = None,
         scale: float = 260.0, variation: float = 0.5) -> bpy.types.Material:
    """Mown lawn seen from a distance: colour break-up plus a fine normal."""
    key = f"turf::{name}"
    if key in _CACHE:
        return _CACHE[key]
    color = color or config.PALETTE["lawn"]
    mat, nt = _new(name)
    coords = _obj_coords(nt)
    fine = _noise(nt, -1000, 120, scale=scale, detail=6.0, roughness=0.7,
                  coords=coords.outputs["Generated"])
    broad = _noise(nt, -1000, -180, scale=22.0, detail=9.0, roughness=0.62,
                   coords=coords.outputs["Generated"])
    stripe = _node(nt, "ShaderNodeTexWave", -1000, -460)
    stripe.wave_type = 'BANDS'
    stripe.bands_direction = 'X'
    _set(stripe, "Scale", 90.0)
    _set(stripe, "Distortion", 2.4)
    nt.links.new(coords.outputs["Generated"], stripe.inputs["Vector"])

    m1 = _node(nt, "ShaderNodeMixRGB", -700, 0)
    _set(m1, "Color1", _rgba([c * 0.55 for c in color]))
    _set(m1, "Color2", _rgba([min(1, c * 1.22 + 0.008) for c in color]))
    nt.links.new(broad.outputs["Fac"], m1.inputs["Fac"])

    m2 = _node(nt, "ShaderNodeMixRGB", -460, 0)
    _set(m2, "Fac", variation)
    _set(m2, "Color2", _rgba([c * 0.92 for c in color]))
    nt.links.new(m1.outputs["Color"], m2.inputs["Color1"])
    nt.links.new(fine.outputs["Fac"], m2.inputs["Fac"])

    m3 = _node(nt, "ShaderNodeMixRGB", -240, 0)
    _set(m3, "Fac", 0.022)                     # mower stripes, barely there
    _set(m3, "Color2", _rgba([min(1, c * 1.18) for c in color]))
    nt.links.new(m2.outputs["Color"], m3.inputs["Color1"])
    nt.links.new(stripe.outputs["Fac"], m3.inputs["Fac"])

    bsdf = _principled(nt, roughness=0.92, sheen_weight=0.18)
    nt.links.new(m3.outputs["Color"], bsdf.inputs["Base Color"])
    b = _bump(nt, fine.outputs["Fac"], 0.5, 0.02)
    nt.links.new(b.outputs["Normal"], bsdf.inputs["Normal"])
    _out(nt, bsdf)
    _CACHE[key] = mat
    return mat


def foliage(name: str, color: RGB | None = None, translucency: float = 0.35,
            scale: float = 40.0) -> bpy.types.Material:
    """Leaf mass with subsurface-ish backlight - what makes trees glow at dusk."""
    key = f"foliage::{name}"
    if key in _CACHE:
        return _CACHE[key]
    color = color or config.PALETTE["leaf"]
    mat, nt = _new(name)
    coords = _obj_coords(nt)
    n = _noise(nt, -960, 60, scale=scale, detail=8.0, roughness=0.65,
               coords=coords.outputs["Object"])
    mix = _node(nt, "ShaderNodeMixRGB", -680, 60)
    _set(mix, "Color1", _rgba([c * 0.5 for c in color]))
    _set(mix, "Color2", _rgba([min(1, c * 2.1 + 0.02) for c in color]))
    nt.links.new(n.outputs["Fac"], mix.inputs["Fac"])

    diff = _principled(nt, x=-380, y=180, roughness=0.62)
    nt.links.new(mix.outputs["Color"], diff.inputs["Base Color"])
    trans = _node(nt, "ShaderNodeBsdfTranslucent", -380, -140)
    nt.links.new(mix.outputs["Color"], trans.inputs["Color"])
    mixsh = _node(nt, "ShaderNodeMixShader", 60, 0)
    _set(mixsh, "Fac", translucency)
    nt.links.new(diff.outputs[0], mixsh.inputs[1])
    nt.links.new(trans.outputs[0], mixsh.inputs[2])
    _out(nt, mixsh)
    _CACHE[key] = mat
    return mat


def bark(name: str = "Bark", color: RGB | None = None) -> bpy.types.Material:
    key = f"bark::{name}"
    if key in _CACHE:
        return _CACHE[key]
    color = color or config.PALETTE["bark"]
    mat, nt = _new(name)
    coords = _obj_coords(nt)
    fis = _node(nt, "ShaderNodeTexWave", -960, 100)
    fis.wave_type = 'BANDS'
    fis.bands_direction = 'Z'
    fis.wave_profile = 'SIN'
    _set(fis, "Scale", 3.0)
    _set(fis, "Distortion", 14.0)
    _set(fis, "Detail", 5.0)
    _set(fis, "Detail Scale", 2.0)
    nt.links.new(coords.outputs["Object"], fis.inputs["Vector"])
    n = _noise(nt, -960, -220, scale=25.0, detail=8.0,
               coords=coords.outputs["Object"])
    mix = _node(nt, "ShaderNodeMixRGB", -660, 0)
    _set(mix, "Color1", _rgba([c * 0.45 for c in color]))
    _set(mix, "Color2", _rgba([min(1, c * 1.8) for c in color]))
    nt.links.new(fis.outputs["Fac"], mix.inputs["Fac"])
    bsdf = _principled(nt, roughness=0.9)
    nt.links.new(mix.outputs["Color"], bsdf.inputs["Base Color"])
    b1 = _bump(nt, n.outputs["Fac"], 0.2, 0.004, x=60, y=-420)
    b2 = _node(nt, "ShaderNodeBump", 230, -300)
    _set(b2, "Strength", 0.8); _set(b2, "Distance", 0.03)
    nt.links.new(fis.outputs["Fac"], b2.inputs["Height"])
    nt.links.new(b1.outputs["Normal"], b2.inputs["Normal"])
    nt.links.new(b2.outputs["Normal"], bsdf.inputs["Normal"])
    _out(nt, bsdf)
    _CACHE[key] = mat
    return mat


def water(name: str = "Water", color: RGB | None = None,
          ripple: float = 1.0) -> bpy.types.Material:
    key = f"water::{name}"
    if key in _CACHE:
        return _CACHE[key]
    color = color or config.PALETTE["water"]
    mat, nt = _new(name)
    coords = _obj_coords(nt)
    n1 = _noise(nt, -960, 100, scale=14.0, detail=6.0, distortion=0.4,
                coords=coords.outputs["Object"])
    n2 = _noise(nt, -960, -180, scale=70.0, detail=4.0,
                coords=coords.outputs["Object"])
    bsdf = _principled(nt, base_color=_rgba(color), roughness=0.045,
                       transmission_weight=0.55, ior=1.333)
    _set(bsdf, "Specular IOR Level", 0.62)
    b1 = _bump(nt, n1.outputs["Fac"], 0.22 * ripple, 0.04, x=60, y=-380)
    b2 = _node(nt, "ShaderNodeBump", 230, -260)
    _set(b2, "Strength", 0.10 * ripple); _set(b2, "Distance", 0.006)
    nt.links.new(n2.outputs["Fac"], b2.inputs["Height"])
    nt.links.new(b1.outputs["Normal"], b2.inputs["Normal"])
    nt.links.new(b2.outputs["Normal"], bsdf.inputs["Normal"])
    _out(nt, bsdf)
    _CACHE[key] = mat
    return mat


def marble(name: str = "Marble", color: RGB | None = None,
           vein: RGB = (0.28, 0.27, 0.30)) -> bpy.types.Material:
    key = f"marble::{name}"
    if key in _CACHE:
        return _CACHE[key]
    color = color or config.PALETTE["marble"]
    mat, nt = _new(name)
    coords = _obj_coords(nt)
    w = _node(nt, "ShaderNodeTexWave", -960, 100)
    w.wave_type = 'BANDS'
    w.wave_profile = 'SIN'
    _set(w, "Scale", 1.6)
    _set(w, "Distortion", 12.0)
    _set(w, "Detail", 8.0)
    _set(w, "Detail Scale", 3.0)
    nt.links.new(coords.outputs["Object"], w.inputs["Vector"])
    ramp = _node(nt, "ShaderNodeValToRGB", -700, 100)
    ramp.color_ramp.elements[0].position = 0.42
    ramp.color_ramp.elements[0].color = _rgba(color)
    ramp.color_ramp.elements[1].position = 0.62
    ramp.color_ramp.elements[1].color = _rgba(vein)
    nt.links.new(w.outputs["Fac"], ramp.inputs["Fac"])
    bsdf = _principled(nt, roughness=0.18, specular_ior_level=0.6)
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    _set(bsdf, "Subsurface Weight", 0.12)
    _set(bsdf, "Subsurface Radius", (0.6, 0.55, 0.5))
    _out(nt, bsdf)
    _CACHE[key] = mat
    return mat


def emissive(name: str, color: RGB = (1.0, 0.78, 0.46), strength: float = 12.0
             ) -> bpy.types.Material:
    """Gas-lamp / window glow."""
    key = f"emit::{name}:{strength}"
    if key in _CACHE:
        return _CACHE[key]
    mat, nt = _new(name)
    e = _node(nt, "ShaderNodeEmission", 300, 0)
    _set(e, "Color", _rgba(color))
    _set(e, "Strength", strength)
    _out(nt, e)
    _CACHE[key] = mat
    return mat


def fabric(name: str, color: RGB, rough: float = 0.85,
           sheen: float = 0.6) -> bpy.types.Material:
    key = f"fabric::{name}"
    if key in _CACHE:
        return _CACHE[key]
    mat, nt = _new(name)
    coords = _obj_coords(nt)
    weave = _noise(nt, -900, 0, scale=380.0, detail=3.0,
                   coords=coords.outputs["Object"])
    bsdf = _principled(nt, base_color=_rgba(color), roughness=rough,
                       sheen_weight=sheen)
    _set(bsdf, "Sheen Tint", _rgba([min(1, c * 1.6 + 0.2) for c in color]))
    b = _bump(nt, weave.outputs["Fac"], 0.15, 0.001)
    nt.links.new(b.outputs["Normal"], bsdf.inputs["Normal"])
    _out(nt, bsdf)
    _CACHE[key] = mat
    return mat


# ---------------------------------------------------------------------------
# The named palette used across the build
# ---------------------------------------------------------------------------

class Library:
    """Lazily-built, cached set of every material the estate uses."""

    def __init__(self) -> None:
        P = config.PALETTE
        self.body = clapboard("Siding.Body", P["body"])
        self.body_upper = shingle_scale("Siding.Shingle", P["accent_dark"],
                                        [c * 1.5 for c in P["accent_dark"]])
        self.trim = painted("Paint.Trim", P["trim"], roughness=0.34, wear=0.28)
        self.trim_crisp = painted("Paint.TrimCrisp", P["trim"], roughness=0.26,
                                  wear=0.12)
        self.accent = painted("Paint.Accent", P["accent"], roughness=0.30,
                              wear=0.32)
        self.accent_dark = painted("Paint.AccentDark", P["accent_dark"],
                                   roughness=0.38, wear=0.4)
        self.gilt = metal("Metal.Gilt", P["gilt"], rough=0.22, metallic=1.0)
        self.iron = metal("Metal.Iron", P["iron"], rough=0.44, metallic=1.0,
                          grain=70.0)
        self.lead = metal("Metal.Lead", (0.13, 0.14, 0.15), rough=0.55)
        self.copper = copper_patina()
        self.slate = slate()
        self.slate_band = slate("Slate.Band", config.PALETTE["slate_band"])
        self.stone = stone()
        self.stone_dark = stone("Stone.Plinth", [c * 0.62 for c in P["stone"]],
                                rough=0.85, pit=0.8)
        self.marble = marble()
        self.brick = brick()
        self.brick_chimney = brick("Brick.Chimney",
                                   [c * 0.85 for c in P["brick"]])
        self.glass = glass()
        self.glass_old = glass("Glass.Old", rough=0.045, wavy=1.4)
        self.stained = stained_glass("Glass.Stained", [
            (0.42, 0.09, 0.10), (0.10, 0.20, 0.42), (0.62, 0.48, 0.12),
            (0.10, 0.30, 0.16), (0.68, 0.62, 0.50), (0.34, 0.14, 0.34)])
        self.gravel = gravel()
        self.cobbles = cobbles()
        self.lawn = turf()
        self.lawn_rough = turf("Lawn.Meadow", [0.115, 0.155, 0.052],
                               scale=140.0, variation=0.75)
        self.hedge = foliage("Foliage.Hedge", P["hedge"], translucency=0.2,
                             scale=90.0)
        self.leaf = foliage("Foliage.Leaf", P["leaf"], translucency=0.4)
        self.leaf_copper = foliage("Foliage.Copper", (0.115, 0.030, 0.018),
                                   translucency=0.45)
        self.bark = bark()
        self.water = water()
        self.wood_dark = painted("Wood.Mahogany", (0.085, 0.028, 0.018),
                                 roughness=0.22, wear=0.15)
        self.wood_oak = painted("Wood.Oak", (0.155, 0.098, 0.052),
                                roughness=0.36, wear=0.2)
        self.lamp = emissive("Lamp.Gas", (1.0, 0.74, 0.40), 22.0)
        self.window_glow = emissive("Window.Glow", (1.0, 0.80, 0.52), 4.0)
        self.carpet = fabric("Fabric.Carpet", (0.24, 0.055, 0.052))
        self.drape = fabric("Fabric.Drape", (0.12, 0.075, 0.14), sheen=0.8)


_LIB: Library | None = None


def library() -> Library:
    global _LIB
    if _LIB is None:
        _LIB = Library()
    return _LIB


def reset() -> None:
    """Drop caches - call after ``read_factory_settings`` wipes the datablocks."""
    global _LIB
    _LIB = None
    _CACHE.clear()
