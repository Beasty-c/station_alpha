class_name TFRoad
extends RefCounted

## A road alignment: a polyline centreline in local engineering coordinates
## (metres, X/Z ground plane) plus a corridor template.
##
## Engine-light. It knows how to resample itself, how to grade a heightfield
## corridor, and how to report its own geometry. It never touches a node.

var id: String = "road_1"
var name: String = "Access road"
var control_points: PackedVector2Array = PackedVector2Array()
var width_m: float = 6.0
var shoulder_m: float = 4.0            # side-slope transition each side
var max_grade: float = 0.10            # rise/run limit (10%)
var target_grade: float = 0.08
var surface_thickness_m: float = 0.20  # aggregate surfacing depth
var closed_loop: bool = false
var station_interval_m: float = 4.0

var _cache_points: PackedVector2Array = PackedVector2Array()
var _cache_stations: PackedFloat32Array = PackedFloat32Array()
var _cache_dirty: bool = true


func set_control_points(pts: PackedVector2Array) -> void:
	control_points = pts.duplicate()
	_cache_dirty = true


func add_control_point(p: Vector2) -> void:
	control_points.append(p)
	_cache_dirty = true


func point_count() -> int:
	return control_points.size()


func is_valid() -> bool:
	return control_points.size() >= 2 and width_m > 0.0


## Catmull-Rom smoothed, evenly-resampled centreline.
func centerline() -> PackedVector2Array:
	_rebuild()
	return _cache_points


## Chainage (distance along the centreline) for every centreline point.
func stations() -> PackedFloat32Array:
	_rebuild()
	return _cache_stations


func length_m() -> float:
	_rebuild()
	if _cache_stations.is_empty():
		return 0.0
	return _cache_stations[_cache_stations.size() - 1]


func corridor_area_m2() -> float:
	return length_m() * width_m


func disturbed_corridor_area_m2() -> float:
	return length_m() * (width_m + 2.0 * shoulder_m)


func _rebuild() -> void:
	if not _cache_dirty:
		return
	_cache_dirty = false
	_cache_points = PackedVector2Array()
	_cache_stations = PackedFloat32Array()
	if control_points.size() < 2:
		return
	var dense := _catmull_rom(control_points, closed_loop, 12)
	# Resample at a constant station interval so grade maths is uniform.
	var total := 0.0
	var lens := PackedFloat32Array()
	lens.append(0.0)
	for i in range(1, dense.size()):
		total += dense[i].distance_to(dense[i - 1])
		lens.append(total)
	if total <= 0.0:
		return
	var step: float = maxf(0.25, station_interval_m)
	var n: int = maxi(1, int(round(total / step)))
	var seg := 0
	for k in range(n + 1):
		var s: float = total * float(k) / float(n)
		while seg < lens.size() - 2 and lens[seg + 1] < s:
			seg += 1
		var span: float = maxf(1e-6, lens[seg + 1] - lens[seg])
		var t: float = clampf((s - lens[seg]) / span, 0.0, 1.0)
		_cache_points.append(dense[seg].lerp(dense[seg + 1], t))
		_cache_stations.append(s)


static func _catmull_rom(pts: PackedVector2Array, closed: bool, subdiv: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	if n < 2:
		return pts.duplicate()
	if n == 2:
		for k in range(subdiv + 1):
			out.append(pts[0].lerp(pts[1], float(k) / float(subdiv)))
		return out
	var last := n - 1 if not closed else n
	for i in range(last):
		var p0 := pts[maxi(i - 1, 0)] if not closed else pts[(i - 1 + n) % n]
		var p1 := pts[i % n]
		var p2 := pts[mini(i + 1, n - 1)] if not closed else pts[(i + 1) % n]
		var p3 := pts[mini(i + 2, n - 1)] if not closed else pts[(i + 2) % n]
		for k in range(subdiv):
			var t := float(k) / float(subdiv)
			out.append(_cr_point(p0, p1, p2, p3, t))
	out.append(pts[0] if closed else pts[n - 1])
	return out


static func _cr_point(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


# --- Vertical design ---------------------------------------------------------
## Design profile: sample the surface along the centreline, smooth it, then
## clamp the longitudinal grade to `max_grade` with a converging two-pass
## sweep. Deterministic and independent of the render state.
func design_profile(surface: TFHeightfield) -> PackedFloat32Array:
	var pts := centerline()
	var st := stations()
	var z := PackedFloat32Array()
	z.resize(pts.size())
	for i in pts.size():
		z[i] = surface.sample(pts[i])
	if pts.size() < 2:
		return z
	# 1. moving-average smoothing (window scaled to ~20 m of chainage)
	var win: int = maxi(1, int(round(20.0 / maxf(0.25, station_interval_m))))
	z = _smooth(z, win)
	# 2. grade clamp, 6 alternating passes (converges; verified in tests)
	var g: float = maxf(0.001, max_grade)
	for _pass in range(6):
		for i in range(1, z.size()):
			var ds: float = maxf(1e-6, st[i] - st[i - 1])
			z[i] = clampf(z[i], z[i - 1] - g * ds, z[i - 1] + g * ds)
		for i in range(z.size() - 2, -1, -1):
			var ds2: float = maxf(1e-6, st[i + 1] - st[i])
			z[i] = clampf(z[i], z[i + 1] - g * ds2, z[i + 1] + g * ds2)
	return z


static func _smooth(a: PackedFloat32Array, win: int) -> PackedFloat32Array:
	if win <= 0 or a.size() < 3:
		return a
	var out := PackedFloat32Array()
	out.resize(a.size())
	for i in a.size():
		var acc := 0.0
		var cnt := 0
		for k in range(-win, win + 1):
			var j := clampi(i + k, 0, a.size() - 1)
			acc += a[j]
			cnt += 1
		out[i] = acc / float(cnt)
	return out


## Grade of the design profile between successive stations, as rise/run.
func grade_profile(surface: TFHeightfield) -> PackedFloat32Array:
	var z := design_profile(surface)
	var st := stations()
	var out := PackedFloat32Array()
	for i in range(1, z.size()):
		var ds: float = maxf(1e-6, st[i] - st[i - 1])
		out.append((z[i] - z[i - 1]) / ds)
	return out


func max_grade_achieved(surface: TFHeightfield) -> float:
	var m := 0.0
	for g in grade_profile(surface):
		m = maxf(m, absf(g))
	return m


## Cut the corridor into `field`. The centreline is set to the design profile,
## the running surface is flat across `width_m`, and the shoulder blends back
## into the surrounding ground over `shoulder_m`.
## Returns the inclusive node window touched, so the renderer can rebuild only
## the affected tiles.
func apply_to(field: TFHeightfield, profile: PackedFloat32Array = PackedFloat32Array()) -> Vector4i:
	var pts := centerline()
	if pts.size() < 2:
		return Vector4i(0, 0, -1, -1)
	var z := profile
	if z.size() != pts.size():
		z = design_profile(field)
	var half := width_m * 0.5
	var outer := half + maxf(0.0, shoulder_m)

	var touched := Vector4i(field.cols, field.rows, -1, -1)
	# Per-node: find the nearest centreline segment, then blend.
	# Only nodes inside the corridor bounding box are visited.
	var bmin := pts[0]
	var bmax := pts[0]
	for p in pts:
		bmin = bmin.min(p)
		bmax = bmax.max(p)
	var g0 := field.grid_coords(bmin - Vector2(outer, outer))
	var g1 := field.grid_coords(bmax + Vector2(outer, outer))
	var c0 := clampi(int(floor(g0.x)), 0, field.cols - 1)
	var r0 := clampi(int(floor(g0.y)), 0, field.rows - 1)
	var c1 := clampi(int(ceil(g1.x)), 0, field.cols - 1)
	var r1 := clampi(int(ceil(g1.y)), 0, field.rows - 1)

	for r in range(r0, r1 + 1):
		for c in range(c0, c1 + 1):
			var wp := field.node_position(c, r)
			var res := _closest(pts, z, wp, outer)
			var d: float = res.x
			if d > outer:
				continue
			var target: float = res.y
			var w := 1.0
			if d > half:
				var t := (d - half) / maxf(1e-6, outer - half)
				w = 1.0 - smoothstep(0.0, 1.0, t)
			if w <= 0.0:
				continue
			var cur := field.get_h(c, r)
			field.set_h(c, r, lerpf(cur, target, w))
			touched = Vector4i(mini(touched.x, c), mini(touched.y, r),
				maxi(touched.z, c), maxi(touched.w, r))
	return touched


## Distance to the centreline and interpolated design elevation there.
## Returns Vector2(distance_m, elevation_m). `cutoff` prunes far segments.
static func _closest(pts: PackedVector2Array, z: PackedFloat32Array, p: Vector2, cutoff: float) -> Vector2:
	var best := INF
	var best_z := 0.0
	var cut2 := (cutoff + 1.0) * (cutoff + 1.0)
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		# quick reject on segment bounding box
		if minf(a.x, b.x) - cutoff > p.x or maxf(a.x, b.x) + cutoff < p.x:
			continue
		if minf(a.y, b.y) - cutoff > p.y or maxf(a.y, b.y) + cutoff < p.y:
			continue
		var ab := b - a
		var len2 := ab.length_squared()
		var t := 0.0
		if len2 > 1e-12:
			t = clampf((p - a).dot(ab) / len2, 0.0, 1.0)
		var proj := a + ab * t
		var d2 := p.distance_squared_to(proj)
		if d2 < best and d2 < cut2:
			best = d2
			best_z = lerpf(z[i], z[i + 1], t)
	if best == INF:
		return Vector2(INF, 0.0)
	return Vector2(sqrt(best), best_z)


## Distance from a world point to the centreline (metres), INF if far away.
func distance_to(p: Vector2) -> float:
	var pts := centerline()
	if pts.size() < 2:
		return INF
	var zz := PackedFloat32Array()
	zz.resize(pts.size())
	return _closest(pts, zz, p, 1.0e9).x


func metrics(surface: TFHeightfield) -> Dictionary:
	var grades := grade_profile(surface)
	var maxg := 0.0
	var sum := 0.0
	for g in grades:
		maxg = maxf(maxg, absf(g))
		sum += absf(g)
	var avg: float = (sum / float(grades.size())) if grades.size() > 0 else 0.0
	var prof := design_profile(surface)
	var lo := INF
	var hi := -INF
	for v in prof:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	return {
		"id": id,
		"name": name,
		"length_m": length_m(),
		"width_m": width_m,
		"shoulder_m": shoulder_m,
		"corridor_area_m2": corridor_area_m2(),
		"disturbed_corridor_area_m2": disturbed_corridor_area_m2(),
		"max_grade": maxg,
		"avg_grade": avg,
		"max_grade_limit": max_grade,
		"target_grade": target_grade,
		"grade_limit_met": maxg <= max_grade + 1.0e-4,
		"profile_min_m": lo if lo != INF else 0.0,
		"profile_max_m": hi if hi != -INF else 0.0,
		"elevation_gain_m": (hi - lo) if hi != -INF else 0.0,
		"station_count": stations().size(),
		"surface_thickness_m": surface_thickness_m,
		"surfacing_volume_m3": corridor_area_m2() * surface_thickness_m,
		"status": "proposed",
	}


func to_dict() -> Dictionary:
	var cps := []
	for p in control_points:
		cps.append([p.x, p.y])
	return {
		"id": id, "name": name, "control_points": cps, "width_m": width_m,
		"shoulder_m": shoulder_m, "max_grade": max_grade, "target_grade": target_grade,
		"surface_thickness_m": surface_thickness_m, "closed_loop": closed_loop,
		"station_interval_m": station_interval_m, "status": "proposed",
	}


static func from_dict(d: Dictionary) -> TFRoad:
	var r := TFRoad.new()
	r.id = String(d.get("id", "road_1"))
	r.name = String(d.get("name", "Access road"))
	var pts := PackedVector2Array()
	for e in d.get("control_points", []):
		if e is Array and e.size() >= 2:
			pts.append(Vector2(float(e[0]), float(e[1])))
	r.control_points = pts
	r.width_m = float(d.get("width_m", 6.0))
	r.shoulder_m = float(d.get("shoulder_m", 4.0))
	r.max_grade = float(d.get("max_grade", 0.10))
	r.target_grade = float(d.get("target_grade", 0.08))
	r.surface_thickness_m = float(d.get("surface_thickness_m", 0.20))
	r.closed_loop = bool(d.get("closed_loop", false))
	r.station_interval_m = float(d.get("station_interval_m", 4.0))
	r._cache_dirty = true
	return r
