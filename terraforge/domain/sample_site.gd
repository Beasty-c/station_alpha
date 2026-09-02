class_name TFSampleSite
extends RefCounted

## Deterministic generator for the one-click demonstration scenario:
## a large hill, a road spiralling up to the summit, and a tower on top.
## Everything it produces is an ordinary editable sculpt / road / tower, so the
## user can keep working on the result exactly as if they had drawn it.

const DEFAULTS := {
	"hill_radius_m": 88.0,
	"hill_height_m": 34.0,
	"summit_flat_r_m": 20.0,
	"roughness_m": 1.1,
	"turns": 2.25,
	"road_width_m": 7.0,
	"road_shoulder_m": 5.0,
	"road_max_grade": 0.10,
	"tower_height_m": 45.0,
	"tower_pad_m": 26.0,
	"seed": 20260901,
}


static func params_with_defaults(p: Dictionary) -> Dictionary:
	var out := DEFAULTS.duplicate(true)
	for k in p.keys():
		out[k] = p[k]
	return out


## Sculpt the hill into `field` (which must already hold the existing ground).
static func sculpt(field: TFHeightfield, p: Dictionary) -> void:
	var q := params_with_defaults(p)
	var radius := float(q["hill_radius_m"])
	var height := float(q["hill_height_m"])
	var flat_r := minf(float(q["summit_flat_r_m"]), radius * 0.6)
	var rough := float(q["roughness_m"])
	var center := field.center_xz()

	# Deterministic low-frequency variation. Seeded, so the sample scenario is
	# byte-identical every time it is generated or replayed from history.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(q["seed"])
	var waves := []
	for i in 5:
		waves.append({
			"a": rng.randf_range(0.35, 1.0),
			"fx": rng.randf_range(0.008, 0.035),
			"fy": rng.randf_range(0.008, 0.035),
			"px": rng.randf_range(0.0, TAU),
			"py": rng.randf_range(0.0, TAU),
		})

	for r in field.rows:
		for c in field.cols:
			var wp := field.node_position(c, r)
			var d := wp.distance_to(center)
			var t: float = clampf((d - flat_r) / maxf(1e-6, radius - flat_r), 0.0, 1.0)
			var dome := height * (1.0 - smoothstep(0.0, 1.0, t))
			var n := 0.0
			if dome > 0.01:
				for w in waves:
					n += float(w["a"]) * sin(wp.x * float(w["fx"]) + float(w["px"])) \
						* sin(wp.y * float(w["fy"]) + float(w["py"]))
				n *= rough * clampf(dome / maxf(1.0, height), 0.0, 1.0)
			field.set_h(c, r, field.get_h(c, r) + dome + n)


## Spiral road control points, from the toe of the hill up to the summit pad.
static func road(field: TFHeightfield, p: Dictionary) -> TFRoad:
	var q := params_with_defaults(p)
	var radius := float(q["hill_radius_m"])
	var flat_r := float(q["summit_flat_r_m"])
	var turns := float(q["turns"])
	var center := field.center_xz()

	var rd := TFRoad.new()
	rd.id = "road_1"
	rd.name = "Summit access road"
	rd.width_m = float(q["road_width_m"])
	rd.shoulder_m = float(q["road_shoulder_m"])
	rd.max_grade = float(q["road_max_grade"])
	rd.target_grade = minf(0.08, rd.max_grade)
	rd.closed_loop = false

	var pts := PackedVector2Array()
	var start_r := radius * 1.18
	var end_r := maxf(flat_r * 0.55, 8.0)
	var steps := int(round(turns * 16.0))
	for i in range(steps + 1):
		var f := float(i) / float(steps)
		var ang := -TAU * turns * f + 0.6
		var rr := lerpf(start_r, end_r, smoothstep(0.0, 1.0, f))
		pts.append(center + Vector2(cos(ang), sin(ang)) * rr)
	# A short straight approach so the alignment starts at the site edge.
	var first := pts[0]
	var dir := (first - center).normalized()
	pts.insert(0, first + dir * 26.0)
	rd.set_control_points(pts)
	return rd


static func tower(field: TFHeightfield, p: Dictionary) -> TFTower:
	var q := params_with_defaults(p)
	var tw := TFTower.new()
	tw.id = "tower_1"
	tw.name = "Summit communications tower"
	tw.position_xz = field.center_xz()
	tw.pad_size_m = float(q["tower_pad_m"])
	tw.pad_apron_m = 9.0
	tw.pad_elevation_auto = true
	tw.height_m = float(q["tower_height_m"])
	tw.footprint_m = 6.0
	tw.foundation_depth_m = 3.0
	tw.foundation_pad_m = 10.0
	return tw
