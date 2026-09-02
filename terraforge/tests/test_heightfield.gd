class_name TFTestHeightfield
extends RefCounted


static func run(t: TFTest) -> void:
	_creation(t)
	_sampling(t)
	_regions(t)
	_slope(t)
	_serialization(t)
	_brush(t)
	_brush_edge_cases(t)


static func _creation(t: TFTest) -> void:
	var hf := TFHeightfield.create_flat(11, 21, 2.5, 3.0, Vector2(-10.0, -20.0))
	t.eq_int(hf.cols, 11, "column count")
	t.eq_int(hf.rows, 21, "row count")
	t.eq_int(hf.node_count(), 231, "node count")
	t.eq_int(hf.cell_count(), 200, "cell count")
	t.near(hf.cell_area(), 6.25, 1e-9, "cell area")
	t.near(hf.extent().x, 25.0, 1e-9, "extent x = (cols-1) x spacing")
	t.near(hf.extent().y, 50.0, 1e-9, "extent y = (rows-1) x spacing")
	t.near(hf.total_area(), 1250.0, 1e-9, "total area")
	t.near(hf.get_h(5, 5), 3.0, 1e-9, "flat fill elevation")
	t.ok(hf.node_position(0, 0).is_equal_approx(Vector2(-10.0, -20.0)), "node 0,0 sits on the origin")
	# Degenerate requests are clamped, never accepted as-is.
	var tiny := TFHeightfield.create_flat(0, -5, 0.0, 0.0)
	t.eq_int(tiny.cols, 2, "zero columns clamp to the minimum grid")
	t.greater(tiny.spacing, 0.0, "zero spacing clamps to a positive value")


static func _sampling(t: TFTest) -> void:
	var hf := TFHeightfield.create_flat(5, 5, 10.0, 0.0, Vector2.ZERO)
	hf.set_h(0, 0, 0.0)
	hf.set_h(1, 0, 10.0)
	hf.set_h(0, 1, 20.0)
	hf.set_h(1, 1, 30.0)
	t.near(hf.sample(Vector2(5.0, 0.0)), 5.0, 1e-5, "bilinear sample along an edge")
	t.near(hf.sample(Vector2(5.0, 5.0)), 15.0, 1e-5, "bilinear sample in a cell centre")
	t.near(hf.sample(Vector2(0.0, 0.0)), 0.0, 1e-6, "sample at a node returns the node")
	# Outside the grid clamps to the edge - documented behaviour.
	t.near(hf.sample(Vector2(-100.0, -100.0)), 0.0, 1e-6, "sampling left of the grid clamps")
	t.ok(not hf.contains_xz(Vector2(-1.0, 0.0)), "point outside the grid is reported outside")
	t.ok(hf.contains_xz(Vector2(20.0, 20.0)), "point inside the grid is reported inside")
	var mm := hf.min_max()
	t.near(mm.x, 0.0, 1e-9, "min elevation")
	t.near(mm.y, 30.0, 1e-9, "max elevation")


static func _regions(t: TFTest) -> void:
	var hf := TFHeightfield.create_flat(21, 21, 1.0, 0.0, Vector2.ZERO)
	var b := hf.region_bounds(Vector2(10.0, 10.0), 3.0)
	t.eq_int(b.x, 7, "region min col")
	t.eq_int(b.z, 13, "region max col")
	var far := hf.region_bounds(Vector2(-500.0, -500.0), 1.0)
	t.ok(far.x == 0 and far.z == 0, "a region entirely off grid clamps to the edge")
	var data := hf.copy_region(b)
	t.eq_int(data.size(), 49, "copied region size")
	for i in data.size():
		data[i] = 5.0
	hf.paste_region(b, data)
	t.near(hf.get_h(10, 10), 5.0, 1e-9, "pasted region writes back")
	t.near(hf.get_h(6, 10), 0.0, 1e-9, "paste does not spill outside the region")


static func _slope(t: TFTest) -> void:
	var hf := TFHeightfield.create_flat(21, 21, 2.0, 0.0, Vector2.ZERO)
	for r in hf.rows:
		for c in hf.cols:
			hf.set_h(c, r, 0.25 * hf.node_position(c, r).x)   # 25% grade
	t.near(hf.slope_ratio(10, 10), 0.25, 1e-5, "25% plane reports a 0.25 slope ratio")
	t.near(hf.max_slope_ratio(), 0.25, 1e-5, "max slope of a plane equals its grade")
	var flat := TFHeightfield.create_flat(9, 9, 1.0, 7.0)
	t.near(flat.max_slope_ratio(), 0.0, 1e-9, "flat ground has zero slope")
	t.ok(flat.normal_at(4, 4).is_equal_approx(Vector3.UP), "flat ground normal points up")


static func _serialization(t: TFTest) -> void:
	var hf := TFHeightfield.create_flat(17, 13, 1.5, 0.0, Vector2(-3.0, 7.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in hf.heights.size():
		hf.heights[i] = rng.randf_range(-50.0, 50.0)
	var back := TFHeightfield.from_dict(hf.to_dict())
	t.eq_int(back.cols, hf.cols, "cols survive the round trip")
	t.eq_int(back.rows, hf.rows, "rows survive the round trip")
	t.near(back.spacing, hf.spacing, 0.0, "spacing survives exactly")
	t.ok(back.origin.is_equal_approx(hf.origin), "origin survives")
	var identical := true
	for i in hf.heights.size():
		if hf.heights[i] != back.heights[i]:
			identical = false
			break
	t.ok(identical, "every height survives bit-exactly through base64 float32")
	t.eq_str(back.checksum(), hf.checksum(), "checksum matches after the round trip")
	# A truncated payload must be repaired to the declared size, not crash.
	var d := hf.to_dict()
	d["heights"] = ""
	var broken := TFHeightfield.from_dict(d)
	t.eq_int(broken.heights.size(), broken.cols * broken.rows, "a truncated payload is padded to the declared grid")


static func _brush(t: TFTest) -> void:
	var hf := TFHeightfield.create_flat(41, 41, 1.0, 0.0, Vector2(-20.0, -20.0))
	var stamp := TFBrush.make_stamp(Vector2.ZERO, 8.0, 2.0, 1.0)
	TFBrush.apply_stamp(hf, TFBrush.Mode.RAISE, stamp)
	t.near(hf.get_h(20, 20), 2.0, 1e-5, "raise moves the centre by strength x dt")
	t.near(hf.get_h(20 + 8, 20), 0.0, 1e-5, "raise leaves the rim untouched")
	t.greater(hf.get_h(20 + 4, 20), 0.0, "raise falls off smoothly inside the radius")
	t.ok(hf.get_h(20 + 4, 20) < 2.0, "falloff is below the centre value")

	# Lower is the exact inverse of raise.
	TFBrush.apply_stamp(hf, TFBrush.Mode.LOWER, stamp)
	t.near(hf.get_h(20, 20), 0.0, 1e-5, "lower exactly undoes raise")

	# The same total strength split across N stamps equals one big stamp:
	# quantities cannot depend on how often the pointer fired.
	var a := TFHeightfield.create_flat(41, 41, 1.0, 0.0, Vector2(-20.0, -20.0))
	var b := TFHeightfield.create_flat(41, 41, 1.0, 0.0, Vector2(-20.0, -20.0))
	TFBrush.apply_stamp(a, TFBrush.Mode.RAISE, TFBrush.make_stamp(Vector2.ZERO, 8.0, 3.0, 1.0))
	for i in 60:
		TFBrush.apply_stamp(b, TFBrush.Mode.RAISE, TFBrush.make_stamp(Vector2.ZERO, 8.0, 3.0, 1.0 / 60.0))
	var worst := 0.0
	for i in a.heights.size():
		worst = maxf(worst, absf(a.heights[i] - b.heights[i]))
	t.near(worst, 0.0, 1e-4, "1 stamp of dt=1 equals 60 stamps of dt=1/60 (event-rate independent)")

	# Flatten drives towards the target, never past it.
	var f := TFHeightfield.create_flat(41, 41, 1.0, 10.0, Vector2(-20.0, -20.0))
	for i in 40:
		TFBrush.apply_stamp(f, TFBrush.Mode.FLATTEN, TFBrush.make_stamp(Vector2.ZERO, 8.0, 4.0, 0.1, 2.0))
	t.near(f.get_h(20, 20), 2.0, 0.01, "flatten converges on its target elevation")
	t.ok(f.get_h(20, 20) >= 2.0 - 1e-6, "flatten never overshoots below the target")

	# Smooth reduces roughness without moving the mean much.
	var sm := TFHeightfield.create_flat(41, 41, 1.0, 0.0, Vector2(-20.0, -20.0))
	for r in sm.rows:
		for c in sm.cols:
			sm.set_h(c, r, 1.0 if (c + r) % 2 == 0 else -1.0)
	var before_var := _variance(sm)
	for i in 12:
		TFBrush.apply_stamp(sm, TFBrush.Mode.SMOOTH, TFBrush.make_stamp(Vector2.ZERO, 10.0, 5.0, 0.2))
	t.ok(_variance(sm) < before_var * 0.5, "smoothing reduces surface variance")


static func _brush_edge_cases(t: TFTest) -> void:
	var hf := TFHeightfield.create_flat(21, 21, 1.0, 0.0, Vector2(-10.0, -10.0))
	var before := hf.checksum()
	TFBrush.apply_stamp(hf, TFBrush.Mode.RAISE, TFBrush.make_stamp(Vector2.ZERO, 5.0, 0.0, 1.0))
	t.eq_str(hf.checksum(), before, "zero strength changes nothing")
	TFBrush.apply_stamp(hf, TFBrush.Mode.RAISE, TFBrush.make_stamp(Vector2.ZERO, 5.0, 3.0, 0.0))
	t.eq_str(hf.checksum(), before, "zero dt changes nothing")
	TFBrush.apply_stamp(hf, TFBrush.Mode.RAISE, TFBrush.make_stamp(Vector2(9999.0, 9999.0), 5.0, 3.0, 1.0))
	t.eq_str(hf.checksum(), before, "a stamp entirely off site changes nothing")
	var bounds := TFBrush.apply_stroke(hf, TFBrush.Mode.RAISE, [])
	t.ok(bounds.z < bounds.x, "an empty stroke reports an empty touched window")
	# A brush at the very corner must clamp rather than run off the array.
	TFBrush.apply_stamp(hf, TFBrush.Mode.RAISE, TFBrush.make_stamp(Vector2(-10.0, -10.0), 4.0, 2.0, 1.0))
	t.near(hf.get_h(0, 0), 2.0, 1e-5, "a corner stamp applies without running off the grid")
	t.near(TFBrush.falloff(0.0, 5.0), 1.0, 1e-9, "falloff is 1 at the centre")
	t.near(TFBrush.falloff(5.0, 5.0), 0.0, 1e-9, "falloff is 0 at the rim")
	t.near(TFBrush.falloff(1.0, 0.0), 0.0, 1e-9, "a zero-radius brush has no effect")


static func _variance(hf: TFHeightfield) -> float:
	var mean := 0.0
	for h in hf.heights:
		mean += h
	mean /= float(hf.heights.size())
	var v := 0.0
	for h in hf.heights:
		v += (h - mean) * (h - mean)
	return v / float(hf.heights.size())
