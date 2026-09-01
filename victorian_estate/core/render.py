"""
World, lighting, cameras and render presets.

Rendering happens on CPU Cycles here, so the presets are built around a
sampling budget rather than a time budget: ``draft`` exists to check that
geometry is where you think it is, ``preview`` to judge composition and
materials, and ``final`` for the actual images.
"""

from __future__ import annotations

import math
import os
from dataclasses import dataclass

import bpy
from mathutils import Euler, Vector

from . import config


# ---------------------------------------------------------------------------
# World
# ---------------------------------------------------------------------------

def sky_world(name: str = "World", sun_elevation: float = 22.0,
              sun_rotation: float = 214.0, turbidity: float = 3.4,
              strength: float = 1.0, dust: float = 0.02,
              ozone: float = 1.6, altitude: float = 180.0,
              sun_disc: bool = True, sun_intensity: float = 0.9
              ) -> bpy.types.World:
    """Nishita physical sky.  Low sun elevations give the long raking light
    that makes bracket-and-cornice shadow work legible.

    Set ``sun_disc=False`` when pairing the sky with an explicit sun lamp -
    leaving both on lights the scene twice and blows every highlight out."""
    world = bpy.data.worlds.get(name) or bpy.data.worlds.new(name)
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    sky = nt.nodes.new("ShaderNodeTexSky")
    sky.location = (-400, 0)
    sky.sky_type = 'NISHITA'
    sky.sun_elevation = math.radians(sun_elevation)
    sky.sun_rotation = math.radians(sun_rotation)
    sky.altitude = altitude
    sky.air_density = 1.0
    sky.dust_density = dust
    sky.ozone_density = ozone
    sky.sun_intensity = sun_intensity
    sky.sun_disc = sun_disc
    sky.sun_size = math.radians(0.545)

    bg = nt.nodes.new("ShaderNodeBackground")
    bg.location = (-140, 0)
    bg.inputs["Strength"].default_value = strength
    out = nt.nodes.new("ShaderNodeOutputWorld")
    out.location = (80, 0)
    nt.links.new(sky.outputs[0], bg.inputs["Color"])
    nt.links.new(bg.outputs[0], out.inputs["Surface"])
    bpy.context.scene.world = world
    return world


def studio_world(name: str = "Studio", top: tuple = (0.62, 0.68, 0.78),
                 bottom: tuple = (0.16, 0.15, 0.14),
                 strength: float = 1.0) -> bpy.types.World:
    """A neutral gradient dome, for the ornament catalogue sheets."""
    world = bpy.data.worlds.get(name) or bpy.data.worlds.new(name)
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    tex = nt.nodes.new("ShaderNodeTexCoord"); tex.location = (-800, 0)
    sep = nt.nodes.new("ShaderNodeSeparateXYZ"); sep.location = (-620, 0)
    nt.links.new(tex.outputs["Generated"], sep.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB"); ramp.location = (-440, 0)
    ramp.color_ramp.elements[0].position = 0.30
    ramp.color_ramp.elements[0].color = (*bottom, 1)
    ramp.color_ramp.elements[1].position = 0.72
    ramp.color_ramp.elements[1].color = (*top, 1)
    nt.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
    bg = nt.nodes.new("ShaderNodeBackground"); bg.location = (-160, 0)
    bg.inputs["Strength"].default_value = strength
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    out = nt.nodes.new("ShaderNodeOutputWorld"); out.location = (40, 0)
    nt.links.new(bg.outputs[0], out.inputs["Surface"])
    bpy.context.scene.world = world
    return world


def sun_lamp(name: str = "Sun", elevation: float = 22.0,
             rotation: float = 214.0, energy: float = 3.6,
             angle: float = 0.9, color=(1.0, 0.93, 0.82)) -> bpy.types.Object:
    """A sun matched to the sky's direction.

    The Nishita sky already carries a sun disc; this adds a controllable key
    on top so the shadow softness can be dialled independently of the sky.
    """
    data = bpy.data.lights.new(name, 'SUN')
    data.energy = energy
    data.angle = math.radians(angle)
    data.color = color
    obj = bpy.data.objects.new(name, data)
    el = math.radians(elevation)
    az = math.radians(rotation)
    obj.rotation_euler = Euler((math.pi / 2 - el, 0.0, az + math.pi / 2), 'XYZ')
    obj.location = (0, 0, 60)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def daylight(elevation: float = 22.0, rotation: float = 214.0,
             sky_strength: float = 1.0, sun_energy: float = 2.6,
             softness: float = 0.9, warmth: float = 0.0
             ) -> tuple[bpy.types.World, bpy.types.Object]:
    """Sky plus a matched key light, with the sky's own sun disc turned off.

    This is the pairing every exterior render wants: the sky supplies the blue
    fill and the horizon gradient, and one sun lamp supplies the key, so
    shadow softness can be tuned without touching the ambient level.
    """
    world = sky_world(sun_elevation=elevation, sun_rotation=rotation,
                      strength=sky_strength, sun_disc=False)
    colour = (1.0, 0.93 - warmth * 0.10, 0.82 - warmth * 0.24)
    sun = sun_lamp(elevation=elevation, rotation=rotation, energy=sun_energy,
                   angle=softness, color=colour)
    return world, sun


# ---------------------------------------------------------------------------
# Cameras
# ---------------------------------------------------------------------------

@dataclass
class Shot:
    """A named camera setup."""
    name: str
    location: tuple
    target: tuple
    lens: float = 50.0
    shift_y: float = 0.0
    fstop: float | None = None
    roll: float = 0.0
    sensor: float = 36.0


def make_camera(shot: Shot) -> bpy.types.Object:
    data = bpy.data.cameras.new(shot.name)
    data.lens = shot.lens
    data.sensor_width = shot.sensor
    data.shift_y = shot.shift_y
    data.clip_start = 0.05
    data.clip_end = 2000.0
    if shot.fstop:
        data.dof.use_dof = True
        data.dof.aperture_fstop = shot.fstop
    obj = bpy.data.objects.new(shot.name, data)
    obj.location = shot.location
    bpy.context.scene.collection.objects.link(obj)

    direction = Vector(shot.target) - Vector(shot.location)
    if shot.fstop:
        data.dof.focus_distance = direction.length
    rot = direction.to_track_quat('-Z', 'Y').to_euler()
    rot.rotate_axis('Z', 0.0)
    obj.rotation_euler = rot
    if shot.roll:
        obj.rotation_euler.rotate_axis('Z', 0.0)
    return obj


def two_point(shot: Shot) -> bpy.types.Object:
    """An architectural camera: level, with lens shift instead of tilt, so
    verticals stay vertical the way a view camera would render them."""
    data = bpy.data.cameras.new(shot.name)
    data.lens = shot.lens
    data.sensor_width = shot.sensor
    data.clip_start = 0.05
    data.clip_end = 2000.0
    if shot.fstop:
        data.dof.use_dof = True
        data.dof.aperture_fstop = shot.fstop
    obj = bpy.data.objects.new(shot.name, data)
    obj.location = shot.location
    bpy.context.scene.collection.objects.link(obj)

    loc = Vector(shot.location)
    tgt = Vector(shot.target)
    flat = Vector((tgt.x - loc.x, tgt.y - loc.y, 0.0))
    yaw = math.atan2(flat.y, flat.x) - math.pi / 2
    obj.rotation_euler = Euler((math.pi / 2, 0.0, yaw), 'XYZ')

    # Shift so the target height lands where a tilt would have put it.
    dist = flat.length
    if dist > 1e-6:
        rise = (tgt.z - loc.z) / dist
        data.shift_y = rise * (data.lens / data.sensor_width) + shot.shift_y
    if shot.fstop:
        data.dof.focus_distance = (tgt - loc).length
    return obj


# ---------------------------------------------------------------------------
# Render presets
# ---------------------------------------------------------------------------

PRESETS = {
    #             width  height  samples  bounces  denoise
    "thumb":      (480,   270,    16,      3,      True),
    "draft":      (960,   540,    32,      4,      True),
    "preview":    (1600,  900,    96,      6,      True),
    "final":      (2560,  1440,   512,     10,     True),
    "hero":       (3840,  2160,   1200,    12,     True),
    "sheet":      (1400,  1000,   64,      5,      True),
}


def configure(preset: str = "preview", engine: str = 'CYCLES',
              transparent: bool = False, threads: int = 0,
              exposure: float = 0.0, view: str = 'AgX') -> bpy.types.Scene:
    scene = bpy.context.scene
    w, h, samples, bounces, denoise = PRESETS[preset]
    r = scene.render
    r.engine = engine
    r.resolution_x = w
    r.resolution_y = h
    r.resolution_percentage = 100
    r.film_transparent = transparent
    r.image_settings.file_format = 'PNG'
    r.image_settings.color_depth = '8'
    r.image_settings.compression = 15
    if threads:
        r.threads_mode = 'FIXED'
        r.threads = threads

    if engine == 'CYCLES':
        c = scene.cycles
        c.samples = samples
        c.preview_samples = max(8, samples // 8)
        c.use_adaptive_sampling = True
        c.adaptive_threshold = 0.012
        c.max_bounces = bounces
        c.diffuse_bounces = max(2, bounces - 2)
        c.glossy_bounces = bounces
        c.transmission_bounces = bounces
        c.transparent_max_bounces = max(8, bounces)
        c.volume_bounces = 1
        c.use_denoising = denoise
        c.denoiser = 'OPENIMAGEDENOISE'
        c.denoising_input_passes = 'RGB_ALBEDO_NORMAL'
        c.caustics_reflective = False
        c.caustics_refractive = False
        c.blur_glossy = 1.0
        c.use_light_tree = True
        c.device = 'CPU'
        c.tile_size = 256
        c.use_auto_tile = True
    elif engine == 'BLENDER_EEVEE_NEXT':
        scene.eevee.taa_render_samples = max(32, samples)
        scene.eevee.use_raytracing = True

    vs = scene.view_settings
    try:
        vs.view_transform = view
        vs.look = 'AgX - Medium Contrast' if view == 'AgX' else 'None'
    except TypeError:
        vs.view_transform = 'Standard'
    vs.exposure = exposure
    return scene


def render_to(path: str, camera: bpy.types.Object | None = None) -> str:
    """Render the current scene to ``path`` and return the path."""
    scene = bpy.context.scene
    if camera is not None:
        scene.camera = camera
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path
