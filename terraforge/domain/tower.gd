class_name TFTower
extends RefCounted

## A simple tower / structure with a level pad and a placeholder spread footing.
## The foundation is a VOLUME PLACEHOLDER for quantity take-off only; it is not
## a structural or geotechnical foundation design.

var id: String = "tower_1"
var name: String = "Summit tower"
var position_xz: Vector2 = Vector2.ZERO
var pad_size_m: float = 24.0           # square pad, side length
var pad_apron_m: float = 8.0           # graded transition beyond the pad
var pad_elevation_m: float = 0.0       # design pad elevation (metres)
var pad_elevation_auto: bool = true    # follow the sculpted terrain
var height_m: float = 45.0
var footprint_m: float = 6.0           # tower base footprint (square)
var foundation_depth_m: float = 3.0
var foundation_pad_m: float = 10.0     # spread footing plan size (square)


func pad_area_m2() -> float:
	return pad_size_m * pad_size_m


func disturbed_area_m2() -> float:
	var s := pad_size_m + 2.0 * pad_apron_m
	return s * s


func excavation_volume_m3() -> float:
	return foundation_pad_m * foundation_pad_m * foundation_depth_m


## Placeholder concrete quantity: footing slab plus a nominal shaft.
func concrete_volume_m3() -> float:
	var footing := foundation_pad_m * foundation_pad_m * minf(1.2, foundation_depth_m)
	var shaft := footprint_m * footprint_m * 0.35 * (height_m / 10.0)
	return footing + shaft


func resolve_pad_elevation(surface: TFHeightfield) -> float:
	if pad_elevation_auto:
		return surface.sample(position_xz)
	return pad_elevation_m


## Level the pad into `field` and blend the apron back to existing ground.
## Returns the inclusive node window touched.
func apply_to(field: TFHeightfield, elevation: float) -> Vector4i:
	var half := pad_size_m * 0.5
	var outer := half + maxf(0.0, pad_apron_m)
	var b := field.region_bounds(position_xz, outer)
	if b.z < b.x or b.w < b.y:
		return Vector4i(0, 0, -1, -1)
	for r in range(b.y, b.w + 1):
		for c in range(b.x, b.z + 1):
			var wp := field.node_position(c, r)
			var d := wp - position_xz
			var cheb: float = maxf(absf(d.x), absf(d.y))
			if cheb > outer:
				continue
			var w := 1.0
			if cheb > half:
				var t := (cheb - half) / maxf(1e-6, outer - half)
				w = 1.0 - smoothstep(0.0, 1.0, t)
			if w <= 0.0:
				continue
			field.set_h(c, r, lerpf(field.get_h(c, r), elevation, w))
	return b


func metrics(surface: TFHeightfield) -> Dictionary:
	var elev := resolve_pad_elevation(surface)
	return {
		"id": id,
		"name": name,
		"position_xz": [position_xz.x, position_xz.y],
		"pad_size_m": pad_size_m,
		"pad_area_m2": pad_area_m2(),
		"pad_elevation_m": elev,
		"disturbed_area_m2": disturbed_area_m2(),
		"height_m": height_m,
		"footprint_m": footprint_m,
		"foundation_depth_m": foundation_depth_m,
		"foundation_pad_m": foundation_pad_m,
		"excavation_volume_m3": excavation_volume_m3(),
		"concrete_volume_m3": concrete_volume_m3(),
		"status": "proposed",
		"note": "Foundation is a quantity placeholder. Structural and geotechnical design required.",
	}


func to_dict() -> Dictionary:
	return {
		"id": id, "name": name,
		"position_xz": [position_xz.x, position_xz.y],
		"pad_size_m": pad_size_m, "pad_apron_m": pad_apron_m,
		"pad_elevation_m": pad_elevation_m, "pad_elevation_auto": pad_elevation_auto,
		"height_m": height_m, "footprint_m": footprint_m,
		"foundation_depth_m": foundation_depth_m, "foundation_pad_m": foundation_pad_m,
		"status": "proposed",
	}


static func from_dict(d: Dictionary) -> TFTower:
	var t := TFTower.new()
	t.id = String(d.get("id", "tower_1"))
	t.name = String(d.get("name", "Summit tower"))
	var p: Array = d.get("position_xz", [0.0, 0.0])
	if p.size() >= 2:
		t.position_xz = Vector2(float(p[0]), float(p[1]))
	t.pad_size_m = float(d.get("pad_size_m", 24.0))
	t.pad_apron_m = float(d.get("pad_apron_m", 8.0))
	t.pad_elevation_m = float(d.get("pad_elevation_m", 0.0))
	t.pad_elevation_auto = bool(d.get("pad_elevation_auto", true))
	t.height_m = float(d.get("height_m", 45.0))
	t.footprint_m = float(d.get("footprint_m", 6.0))
	t.foundation_depth_m = float(d.get("foundation_depth_m", 3.0))
	t.foundation_pad_m = float(d.get("foundation_pad_m", 10.0))
	return t
