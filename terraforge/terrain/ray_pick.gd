class_name TFRayPick
extends RefCounted

## Analytic ray / heightfield intersection.
##
## Picking reads the SAME authoritative surface the quantities come from, so
## where the user clicks and what the calculation sees can never disagree.
## There is no collision body, no HeightMapShape3D and no physics tick to
## throttle: an edit is pickable the instant the model changes, and the result
## does not depend on frame rate or on how far the mesh rebuild has got.
##
## Method: march the ray in world space with a step tied to the grid spacing,
## detecting the crossing where the ray passes from above the surface to below
## it, then refine that bracket by bisection. Robust for the near-horizontal
## grazing rays a low camera produces, which is where a fixed-step march alone
## would punch through a ridge.

const MAX_DISTANCE := 4000.0
const REFINE_STEPS := 24


## Returns {hit: bool, position: Vector3, distance: float, grid: Vector2}.
## `position.y` is the surface elevation in metres.
static func cast(field: TFHeightfield, origin: Vector3, direction: Vector3,
		max_distance: float = MAX_DISTANCE) -> Dictionary:
	var miss := {"hit": false, "position": Vector3.ZERO, "distance": 0.0, "grid": Vector2.ZERO}
	if field == null or field.heights.is_empty():
		return miss
	var dir := direction.normalized()
	if dir.length_squared() < 0.5:
		return miss

	var mm := field.min_max()
	var lo := mm.x - 1.0
	var hi := mm.y + 1.0

	# Clip the ray to the site's bounding box first, so a long ray from a
	# zoomed-out camera does not waste its budget in empty space.
	var span := _clip_to_site(field, origin, dir, lo, hi, max_distance)
	if span.x > span.y:
		return miss

	var step: float = maxf(field.spacing * 0.5, 0.25)
	var t: float = span.x
	var prev_t := t
	var prev_gap := _gap(field, origin, dir, t)

	while t < span.y:
		t = minf(t + step, span.y)
		var gap := _gap(field, origin, dir, t)
		if prev_gap >= 0.0 and gap < 0.0:
			return _refine(field, origin, dir, prev_t, t)
		if gap < 0.0 and prev_gap < 0.0 and is_equal_approx(t, span.x):
			# Started underground (camera below the surface): treat the entry
			# point itself as the hit rather than reporting a miss.
			return _result(field, origin, dir, t)
		prev_gap = gap
		prev_t = t
		if is_equal_approx(t, span.y):
			break
	return miss


## Signed distance from the ray point to the surface: positive above ground.
static func _gap(field: TFHeightfield, origin: Vector3, dir: Vector3, t: float) -> float:
	var p := origin + dir * t
	return p.y - field.sample(Vector2(p.x, p.z))


static func _refine(field: TFHeightfield, origin: Vector3, dir: Vector3,
		t_above: float, t_below: float) -> Dictionary:
	var a := t_above
	var b := t_below
	for i in REFINE_STEPS:
		var m := (a + b) * 0.5
		if _gap(field, origin, dir, m) >= 0.0:
			a = m
		else:
			b = m
	return _result(field, origin, dir, (a + b) * 0.5)


static func _result(field: TFHeightfield, origin: Vector3, dir: Vector3, t: float) -> Dictionary:
	var p := origin + dir * t
	var xz := Vector2(p.x, p.z)
	return {
		"hit": true,
		"position": Vector3(p.x, field.sample(xz), p.z),
		"distance": t,
		"grid": field.grid_coords(xz),
	}


## Ray parameter range over which the ray is inside the site's bounding box.
## Returns Vector2(t_enter, t_exit); t_enter > t_exit means "never inside".
static func _clip_to_site(field: TFHeightfield, origin: Vector3, dir: Vector3,
		y_lo: float, y_hi: float, max_distance: float) -> Vector2:
	var bmin := field.aabb_min()
	var bmax := field.aabb_max()
	var lo := Vector3(bmin.x, y_lo, bmin.y)
	var hi := Vector3(bmax.x, y_hi, bmax.y)
	var t0 := 0.0
	var t1 := max_distance
	for axis in 3:
		var d: float = dir[axis]
		var o: float = origin[axis]
		if absf(d) < 1.0e-9:
			if o < lo[axis] or o > hi[axis]:
				return Vector2(1.0, 0.0)
			continue
		var ta := (lo[axis] - o) / d
		var tb := (hi[axis] - o) / d
		if ta > tb:
			var tmp := ta
			ta = tb
			tb = tmp
		t0 = maxf(t0, ta)
		t1 = minf(t1, tb)
		if t0 > t1:
			return Vector2(1.0, 0.0)
	return Vector2(t0, t1)


## Where a ray meets a horizontal plane at elevation `y`. Used for camera
## panning, which must not be affected by the terrain under the cursor.
static func plane_hit(origin: Vector3, direction: Vector3, y: float) -> Dictionary:
	var dir := direction.normalized()
	if absf(dir.y) < 1.0e-6:
		return {"hit": false, "position": Vector3.ZERO}
	var t := (y - origin.y) / dir.y
	if t < 0.0:
		return {"hit": false, "position": Vector3.ZERO}
	return {"hit": true, "position": origin + dir * t}
