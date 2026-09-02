class_name TFTestFeatures
extends RefCounted


static func run(t: TFTest) -> void:
	_road_geometry(t)
	_road_grade_limit(t)
	_road_corridor(t)
	_road_edge_cases(t)
	_tower(t)


static func _hill(radius: float = 80.0, height: float = 30.0) -> TFHeightfield:
	var hf := TFHeightfield.create_flat(101, 101, 2.0, 0.0, Vector2(-100.0, -100.0))
	for r in hf.rows:
		for c in hf.cols:
			var d := hf.node_position(c, r).length()
			var f: float = clampf(d / radius, 0.0, 1.0)
			hf.set_h(c, r, height * (1.0 - smoothstep(0.0, 1.0, f)))
	return hf


static func _road_geometry(t: TFTest) -> void:
	var rd := TFRoad.new()
	rd.station_interval_m = 5.0
	rd.set_control_points(PackedVector2Array([Vector2(0.0, 0.0), Vector2(100.0, 0.0)]))
	t.ok(rd.is_valid(), "a two-point alignment is valid")
	t.near(rd.length_m(), 100.0, 0.5, "a straight 100 m alignment measures 100 m")
	t.near(rd.corridor_area_m2(), rd.length_m() * rd.width_m, 1e-6, "corridor area = length x width")
	t.greater(float(rd.centerline().size()), 15.0, "the centreline is resampled at the station interval")
	var st := rd.stations()
	t.near(st[0], 0.0, 1e-9, "chainage starts at zero")
	t.near(st[st.size() - 1], rd.length_m(), 1e-4, "chainage ends at the alignment length")
	var monotonic := true
	for i in range(1, st.size()):
		if st[i] <= st[i - 1]:
			monotonic = false
	t.ok(monotonic, "chainage increases monotonically")
	# A curved alignment is longer than the straight line between its ends.
	var curve := TFRoad.new()
	curve.set_control_points(PackedVector2Array([Vector2(0, 0), Vector2(50, 60), Vector2(100, 0)]))
	t.greater(curve.length_m(), 100.0, "a curved alignment is longer than its chord")


static func _road_grade_limit(t: TFTest) -> void:
	var hf := _hill()
	var rd := TFRoad.new()
	rd.station_interval_m = 4.0
	rd.max_grade = 0.08
	# Straight up the side of the hill: the raw ground grade is far too steep.
	rd.set_control_points(PackedVector2Array([Vector2(-95.0, 0.0), Vector2(-40.0, 0.0), Vector2(0.0, 0.0)]))
	var raw_max := 0.0
	var pts := rd.centerline()
	var st := rd.stations()
	for i in range(1, pts.size()):
		var ds: float = maxf(1e-6, st[i] - st[i - 1])
		raw_max = maxf(raw_max, absf(hf.sample(pts[i]) - hf.sample(pts[i - 1])) / ds)
	t.greater(raw_max, rd.max_grade, "the raw ground profile exceeds the grade limit")
	t.ok(rd.max_grade_achieved(hf) <= rd.max_grade + 1e-3,
		"the design profile is clamped to the grade limit (%.4f <= %.4f)" % [rd.max_grade_achieved(hf), rd.max_grade])
	var m := rd.metrics(hf)
	t.ok(bool(m["grade_limit_met"]), "metrics report the grade limit as met")
	t.greater(float(m["elevation_gain_m"]), 0.0, "the profile still climbs the hill")

	rd.max_grade = 0.02
	t.ok(rd.max_grade_achieved(hf) <= 0.02 + 1e-3, "a tighter limit is also respected")


static func _road_corridor(t: TFTest) -> void:
	var hf := _hill()
	var before := hf.clone()
	var rd := TFRoad.new()
	rd.station_interval_m = 4.0
	rd.width_m = 10.0
	rd.shoulder_m = 6.0
	rd.max_grade = 0.08
	rd.set_control_points(PackedVector2Array([Vector2(-95.0, 0.0), Vector2(-40.0, 0.0), Vector2(0.0, 0.0)]))
	var touched := rd.apply_to(hf)
	t.ok(touched.z >= touched.x, "applying the road reports a touched node window")
	t.ok(hf.checksum() != before.checksum(), "applying the road changes the surface")

	# The running surface must be flat across the corridor at a given station.
	var profile := rd.design_profile(hf)
	var mid := rd.centerline()[rd.centerline().size() / 2]
	var h_center := hf.sample(mid)
	var h_edge := hf.sample(mid + Vector2(0.0, 3.0))
	t.near(h_edge, h_center, 0.35, "the running surface is level across its width")

	# Far from the alignment nothing moved.
	var far := Vector2(60.0, 60.0)
	t.near(hf.sample(far), before.sample(far), 1e-4, "ground far from the corridor is untouched")

	# The graded corridor now respects the grade limit on the modified surface.
	t.ok(rd.max_grade_achieved(hf) <= rd.max_grade + 5e-3, "the graded corridor holds its grade")


static func _road_edge_cases(t: TFTest) -> void:
	var hf := _hill()
	var rd := TFRoad.new()
	t.ok(not rd.is_valid(), "an alignment with no points is invalid")
	t.near(rd.length_m(), 0.0, 1e-9, "an empty alignment has zero length")
	var b := rd.apply_to(hf)
	t.ok(b.z < b.x, "an empty alignment touches nothing")
	rd.set_control_points(PackedVector2Array([Vector2(10.0, 10.0), Vector2(10.0, 10.0)]))
	t.near(rd.length_m(), 0.0, 1e-6, "coincident control points give zero length")
	var m := rd.metrics(hf)
	t.near(float(m["max_grade"]), 0.0, 1e-6, "a zero-length alignment reports zero grade, not NaN")
	rd.width_m = 0.0
	t.ok(not rd.is_valid(), "a zero-width road is invalid")
	# Round trip.
	var rd2 := TFRoad.new()
	rd2.set_control_points(PackedVector2Array([Vector2(1, 2), Vector2(3, 4), Vector2(9, -2)]))
	rd2.width_m = 7.5
	rd2.max_grade = 0.123
	var back := TFRoad.from_dict(rd2.to_dict())
	t.eq_int(back.control_points.size(), 3, "control points survive a round trip")
	t.near(back.width_m, 7.5, 1e-9, "width survives a round trip")
	t.near(back.max_grade, 0.123, 1e-9, "grade limit survives a round trip")
	t.near(back.length_m(), rd2.length_m(), 1e-4, "length is reproduced after a round trip")


static func _tower(t: TFTest) -> void:
	var hf := _hill()
	var tw := TFTower.new()
	tw.position_xz = Vector2.ZERO
	tw.pad_size_m = 20.0
	tw.pad_apron_m = 8.0
	tw.height_m = 40.0
	tw.foundation_pad_m = 10.0
	tw.foundation_depth_m = 3.0
	t.near(tw.pad_area_m2(), 400.0, 1e-9, "pad area is the square of its side")
	t.near(tw.excavation_volume_m3(), 300.0, 1e-9, "foundation excavation = 10 x 10 x 3")
	t.greater(tw.concrete_volume_m3(), 0.0, "a placeholder concrete quantity is produced")
	var m := tw.metrics(hf)
	t.eq_str(String(m["status"]), "proposed", "the tower is labelled proposed")
	t.ok(String(m["note"]).contains("placeholder"), "the tower note calls the foundation a placeholder")

	var elev := tw.resolve_pad_elevation(hf)
	tw.apply_to(hf, elev)
	var h0 := hf.sample(Vector2(0.0, 0.0))
	var h1 := hf.sample(Vector2(8.0, 0.0))
	var h2 := hf.sample(Vector2(0.0, -8.0))
	t.near(h1, h0, 0.05, "the pad is level in x")
	t.near(h2, h0, 0.05, "the pad is level in z")
	t.near(h0, elev, 0.05, "the pad sits at the resolved design elevation")
	t.near(hf.sample(Vector2(60.0, 60.0)), 0.0, 0.6, "ground far from the pad is untouched")

	tw.pad_elevation_auto = false
	tw.pad_elevation_m = 12.5
	t.near(tw.resolve_pad_elevation(hf), 12.5, 1e-9, "a manual pad elevation overrides the terrain")
	var back := TFTower.from_dict(tw.to_dict())
	t.near(back.pad_elevation_m, 12.5, 1e-9, "pad elevation survives a round trip")
	t.ok(not back.pad_elevation_auto, "the auto flag survives a round trip")
