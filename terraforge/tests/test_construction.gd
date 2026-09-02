extends RefCounted

## Loaded by path from tests/run_tests.gd, so it deliberately has no
## class_name: test suites should not occupy global names in the product.


static func _site() -> TFProject:
	var p := TFProject.create_default(81, 81, 2.0, 0.0)
	p.generate_sample_site()
	return p


static func run(t: TFTest) -> void:
	_sequence_shape(t)
	_prerequisites(t)
	_schedule_rollup(t)
	_not_applicable_steps(t)
	_surface_endpoints(t)
	_surface_monotonic(t)
	_playback(t)
	_playback_frame_rate_independence(t)
	_playback_with_nothing_to_do(t)


static func _sequence_shape(t: TFTest) -> void:
	var p := _site()
	var q := TFSequenceGenerator.generate(p.analyze(), p.assumptions, p.road, p.tower)
	var required := ["survey_stakeout", "clearing_grubbing", "topsoil_strip", "temporary_access",
		"erosion_control", "subgrade_prep", "mass_excavation", "import_delivery",
		"fill_placement", "compaction", "road_formation", "summit_pad",
		"tower_foundation", "tower_erection", "drainage", "fine_grading",
		"topsoil_replacement", "stabilization", "final_inspection"]
	var ids := PackedStringArray()
	for s in q.steps:
		ids.append(s.id)
	for r in required:
		t.ok(ids.has(r), "the sequence contains the '%s' step" % r)
	t.greater(float(q.applicable_steps().size()), 12.0, "most steps apply to the sample scenario")
	for s in q.steps:
		t.eq_str(s.status, "simulated", "step '%s' is labelled simulated" % s.id)
	var stake := _step(q, "survey_stakeout")
	t.ok(str(stake.description).contains("PROPOSED"), "the stakeout step says the stakes are proposed")
	var final_step := _step(q, "final_inspection")
	t.ok(str(final_step.description).contains("PLANNED"), "the final walkthrough is labelled as planned only")
	t.ok(str(final_step.description).contains("not performed") or str(final_step.description).contains("has not performed"),
		"the final walkthrough states no inspection has happened")


static func _prerequisites(t: TFTest) -> void:
	var p := _site()
	var q := TFSequenceGenerator.generate(p.analyze(), p.assumptions, p.road, p.tower)
	var seen := {}
	var ok := true
	for s in q.steps:
		for pre in s.prerequisites:
			if not seen.has(pre):
				ok = false
		seen[s.id] = true
	t.ok(ok, "every prerequisite appears before the step that needs it")
	var unresolved := 0
	for s in q.steps:
		for w in s.warnings:
			if w.contains("Prerequisite"):
				unresolved += 1
	t.eq_int(unresolved, 0, "no step reports an unscheduled prerequisite")
	# Every prerequisite id must exist.
	var ids := {}
	for s in q.steps:
		ids[s.id] = true
	var dangling := 0
	for s in q.steps:
		for pre in s.prerequisites:
			if not ids.has(pre):
				dangling += 1
	t.eq_int(dangling, 0, "no prerequisite points at a step that does not exist")


static func _schedule_rollup(t: TFTest) -> void:
	var p := _site()
	var q := TFSequenceGenerator.generate(p.analyze(), p.assumptions, p.road, p.tower)
	var sum := 0.0
	for s in q.applicable_steps():
		sum += s.duration_hours
	t.near(q.total_duration_hours, sum, 0.01, "total duration is the sum of the applicable steps")
	t.near(q.total_duration_days, q.total_duration_hours / p.assumptions.workday_hours, 0.001,
		"duration in days uses the workday assumption")
	# Contiguity.
	var prev := 0.0
	var contiguous := true
	for s in q.applicable_steps():
		if absf(s.start_hours - prev) > 1e-6:
			contiguous = false
		prev = s.end_hours
	t.ok(contiguous, "applicable steps are scheduled back to back with no gaps")
	t.near(prev, q.total_duration_hours, 1e-6, "the last step ends at the total duration")

	# Changing the workday changes days but not hours.
	p.change_assumption("workday_hours", 12.0)
	var q2 := TFSequenceGenerator.generate(p.analyze(), p.assumptions, p.road, p.tower)
	t.near(q2.total_duration_hours, q.total_duration_hours, 0.5, "workday length does not change total hours")
	t.ok(q2.total_duration_days < q.total_duration_days, "a longer workday shortens the day count")


static func _not_applicable_steps(t: TFTest) -> void:
	# A flat, featureless project: most steps must be omitted with a reason.
	var p := TFProject.create_default(41, 41, 2.0, 0.0)
	var an := p.analyze()
	var q := TFSequenceGenerator.generate(an, p.assumptions, null, null)
	var na := 0
	for s in q.steps:
		if not s.applicable:
			na += 1
			t.ok(s.not_applicable_reason != "", "omitted step '%s' explains why" % s.id)
			t.near(s.duration_hours, 0.0, 1e-9, "omitted step '%s' contributes no time" % s.id)
			t.near(s.total_cost(), 0.0, 1e-9, "omitted step '%s' contributes no cost" % s.id)
	t.greater(float(na), 8.0, "an untouched flat site omits most construction steps")
	t.ok(not _step(q, "road_formation").applicable, "road formation is omitted with no road")
	t.ok(not _step(q, "tower_erection").applicable, "tower erection is omitted with no tower")
	t.ok(not _step(q, "mass_excavation").applicable, "mass excavation is omitted with no cut")
	var warned := false
	for w in q.warnings:
		if w.contains("no earthwork") or w.contains("matches existing"):
			warned = true
	t.ok(warned, "the sequence warns that there is nothing to build")


static func _surface_endpoints(t: TFTest) -> void:
	var p := _site()
	var cs := TFConstructionSurface.new()
	cs.prepare(p.existing, p.sculpt, p.proposed, p.assumptions.topsoil_depth_m)
	t.ok(cs.is_ready(), "the construction surface prepares from the three authoritative surfaces")

	var zero := cs.heightfield_at(TFStep.ZERO_STATE)
	t.eq_str(zero.checksum(), p.existing.checksum(),
		"at state 0 the construction surface reproduces the existing ground exactly")

	var one := cs.heightfield_at({"strip": 0.0, "cut": 1.0, "fill": 1.0, "form": 1.0, "tower": 1.0})
	var worst := 0.0
	for i in one.heights.size():
		worst = maxf(worst, absf(one.heights[i] - p.proposed.heights[i]))
	t.near(worst, 0.0, 1e-4, "at state 1 the construction surface reproduces the proposed surface")

	# A mismatched grid must refuse rather than produce nonsense.
	var bad := TFConstructionSurface.new()
	bad.prepare(p.existing, p.sculpt, TFHeightfield.create_flat(9, 9, 1.0), 0.15)
	t.ok(not bad.is_ready(), "mismatched surfaces refuse to prepare")
	t.ok(not bad.evaluate(TFStep.ZERO_STATE, PackedFloat32Array()), "an unprepared surface evaluates to nothing")


static func _surface_monotonic(t: TFTest) -> void:
	var p := _site()
	var cs := TFConstructionSurface.new()
	cs.prepare(p.existing, p.sculpt, p.proposed, p.assumptions.topsoil_depth_m)
	# The fill front must rise: total volume above existing never decreases.
	var prev := -1.0
	var rising := true
	for i in 11:
		var f := float(i) / 10.0
		var hf := cs.heightfield_at({"strip": 0.0, "cut": 0.0, "fill": f, "form": 0.0, "tower": 0.0})
		var v := TFEarthworks.integrate(p.existing, hf)
		var fill := float(v["fill_m3"])
		if fill < prev - 1.0:
			rising = false
		prev = fill
	t.ok(rising, "placed fill volume increases monotonically as the fill front rises")
	t.greater(prev, 1000.0, "the fill front eventually places the design volume")

	# And the surface at state 1 has the same volume as the analysis reports.
	var full := cs.heightfield_at({"strip": 0.0, "cut": 1.0, "fill": 1.0, "form": 1.0, "tower": 1.0})
	var an := p.analyze()
	var v_full := TFEarthworks.integrate(p.existing, full)
	t.near_pct(float(v_full["fill_m3"]), an.fill_compacted_m3, 0.5,
		"the finished playback surface carries the analysed fill volume")
	t.near_pct(float(v_full["cut_m3"]), an.cut_bank_m3, 2.0,
		"the finished playback surface carries the analysed cut volume")


static func _playback(t: TFTest) -> void:
	var p := _site()
	var q := TFSequenceGenerator.generate(p.analyze(), p.assumptions, p.road, p.tower)
	var pb := TFPlayback.new()
	pb.set_sequence(q)
	t.ok(pb.has_sequence(), "playback accepts the sequence")
	t.near(pb.position_hours, 0.0, 1e-9, "playback starts at hour zero")

	pb.seek_fraction(1.0)
	t.near(pb.position_hours, q.total_duration_hours, 1e-6, "seeking to 1.0 lands at the end")
	var cum := pb.cumulative()
	t.near(float(cum["cost"]), q.cost_expected, 1.0, "the end of the timeline shows the full cost")
	t.eq_int(int(cum["truckloads"]), _total_loads(q), "the end of the timeline shows every truckload")

	pb.seek_fraction(0.0)
	t.near(float(pb.cumulative()["cost"]), 0.0, 1e-6, "the start of the timeline shows no cost yet")

	# Clicking a step must move the scene to that step.
	var applicable := q.applicable_steps()
	for i in applicable.size():
		pb.goto_step(i)
		t.eq_int(pb.current_index(), i, "goto_step(%d) selects that step" % i)
	pb.goto_step(3)
	pb.next_step()
	t.eq_int(pb.current_index(), 4, "next advances one step")
	# goto/next land at the very START of a step, so prev moves back a step
	# rather than rewinding in place.
	pb.prev_step()
	t.eq_int(pb.current_index(), 3, "prev from the start of a step moves to the previous step")
	pb.prev_step()
	t.eq_int(pb.current_index(), 2, "prev again moves back another step")
	# From partway through a step, the first prev rewinds to that step's start.
	var s4 := applicable[4]
	pb.seek_hours(lerpf(s4.start_hours, s4.end_hours, 0.5))
	t.eq_int(pb.current_index(), 4, "seeking into the middle of a step selects it")
	pb.prev_step()
	t.eq_int(pb.current_index(), 4, "prev from mid-step rewinds to the start of the same step")
	t.near(pb.position_hours, s4.start_hours, 1e-3, "the rewind lands on the step's start time")
	pb.prev_step()
	t.eq_int(pb.current_index(), 3, "a second prev then moves to the previous step")

	# Cumulative quantities never go backwards along the timeline.
	var last := -1.0
	var mono := true
	for i in 60:
		pb.seek_fraction(float(i) / 59.0)
		var c := float(pb.cumulative()["cost"])
		if c < last - 0.01:
			mono = false
		last = c
	t.ok(mono, "cumulative cost never decreases as the timeline advances")

	# Out-of-range seeks clamp.
	pb.seek_hours(-500.0)
	t.near(pb.position_hours, 0.0, 1e-9, "seeking before the start clamps to zero")
	pb.seek_hours(1.0e9)
	t.near(pb.position_hours, q.total_duration_hours, 1e-6, "seeking past the end clamps to the end")
	pb.goto_step(9999)
	t.eq_int(pb.current_index(), applicable.size() - 1, "an out-of-range step index clamps to the last step")


static func _playback_frame_rate_independence(t: TFTest) -> void:
	var p := _site()
	var q := TFSequenceGenerator.generate(p.analyze(), p.assumptions, p.road, p.tower)
	# Advance the same wall-clock time in very different frame sizes.
	var a := TFPlayback.new()
	a.set_sequence(q)
	a.play()
	for i in 10:
		a.advance(0.1)
	var b := TFPlayback.new()
	b.set_sequence(q)
	b.play()
	for i in 200:
		b.advance(0.005)
	t.near(a.position_hours, b.position_hours, 1e-3,
		"1 second of playback lands in the same place at 10 fps and 200 fps")
	t.near(float(a.cumulative()["cost"]), float(b.cumulative()["cost"]), 1.0,
		"the quantity read-out is identical at both frame rates")

	# And scrubbing straight there gives the same answer as playing there.
	var c := TFPlayback.new()
	c.set_sequence(q)
	c.seek_hours(a.position_hours)
	t.near(float(c.cumulative()["cost"]), float(a.cumulative()["cost"]), 1e-6,
		"scrubbing to a position matches playing to it")
	var sa := a.state()
	var sc := c.state()
	for k in TFStep.ZERO_STATE.keys():
		t.near(float(sc[k]), float(sa[k]), 1e-6, "terrain progress '%s' matches when scrubbed" % k)


static func _playback_with_nothing_to_do(t: TFTest) -> void:
	var p := TFProject.create_default(21, 21, 2.0, 0.0)
	# Force every step to be inapplicable by removing area and features.
	var an := p.analyze()
	var a := p.assumptions.duplicate_assumptions()
	a.topsoil_depth_m = 0.0
	var q := TFSequenceGenerator.generate(an, a, null, null)
	var pb := TFPlayback.new()
	pb.set_sequence(q)
	# There is always at least the layout and closeout work, so playback stays
	# usable; what matters is that it never divides by zero or hangs.
	pb.play()
	for i in 50:
		pb.advance(0.5)
	t.ok(pb.position_hours <= q.total_duration_hours + 1e-6, "playback stops at the end of a trivial sequence")
	t.ok(not pb.playing, "playback stops itself when it reaches the end")
	pb.seek_fraction(0.5)
	var st := pb.state()
	for k in ["strip", "cut", "fill", "form", "tower"]:
		t.between(float(st[k]), 0.0, 1.0, "terrain progress '%s' stays in range with nothing to build" % k)

	var empty := TFPlayback.new()
	t.ok(not empty.has_sequence(), "playback with no sequence reports no sequence")
	empty.play()
	empty.advance(1.0)
	t.near(empty.position_hours, 0.0, 1e-9, "playback with no sequence does not move")
	t.ok(empty.current_step() == null, "playback with no sequence has no current step")


static func _total_loads(q: TFSequence) -> int:
	var n := 0
	for s in q.applicable_steps():
		n += s.truckloads
	return n


static func _step(q: TFSequence, id: String) -> TFStep:
	for s in q.steps:
		if s.id == id:
			return s
	return null
