class_name TFTestValidation
extends RefCounted


static func run(t: TFTest) -> void:
	_assumption_errors(t)
	_design_warnings(t)
	_scope_notes(t)
	_never_claims_professional_status(t)
	_exploration_is_not_blocked(t)


static func _codes(issues: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for i in issues:
		out.append(String(i["code"]))
	return out


static func _assumption_errors(t: TFTest) -> void:
	var a := TFAssumptions.new()
	t.eq_int(TFValidation.check_assumptions(a).size(), 0, "the shipped defaults raise no issues")

	a.truck_capacity_loose_m3 = 0.0
	t.ok(_codes(TFValidation.check_assumptions(a)).has("truck_capacity"), "zero truck capacity is caught")
	a.truck_capacity_loose_m3 = -3.0
	t.ok(_codes(TFValidation.check_assumptions(a)).has("truck_capacity"), "negative truck capacity is caught")
	a = TFAssumptions.new()

	a.shrinkage = 0.99
	t.ok(_codes(TFValidation.check_assumptions(a)).has("shrinkage_extreme"), "an impossible shrinkage is caught")
	a.shrinkage = 0.5
	t.ok(_codes(TFValidation.check_assumptions(a)).has("shrinkage_unusual"), "an unusual shrinkage is flagged")
	a = TFAssumptions.new()

	a.swell = -0.95
	t.ok(_codes(TFValidation.check_assumptions(a)).has("swell_invalid"), "an impossible swell is caught")
	a = TFAssumptions.new()
	a.shrinkage = -0.2
	a.swell = -0.2
	t.ok(_codes(TFValidation.check_assumptions(a)).has("factors_inconsistent"), "inconsistent factors are caught")
	a = TFAssumptions.new()

	a.workday_hours = 0.0
	t.ok(_codes(TFValidation.check_assumptions(a)).has("workday"), "a zero workday is caught")
	a = TFAssumptions.new()
	a.labor_rate_per_hour = 0.0
	t.ok(_codes(TFValidation.check_assumptions(a)).has("missing_rates"), "a missing cost rate is caught")
	a = TFAssumptions.new()
	a.excavator_bcm_per_hour = 0.0
	t.ok(_codes(TFValidation.check_assumptions(a)).has("production_rate"), "a zero production rate is caught")
	a = TFAssumptions.new()
	a.cost_low_factor = 1.6
	t.ok(_codes(TFValidation.check_assumptions(a)).has("cost_band"), "an inverted estimate band is caught")

	# Every issue has to be actionable.
	var all_issues: Array[Dictionary] = []
	var b := TFAssumptions.new()
	b.truck_capacity_loose_m3 = 0.0
	b.shrinkage = 0.99
	b.workday_hours = 0.0
	all_issues = TFValidation.check_assumptions(b)
	for i in all_issues:
		t.ok(String(i["message"]) != "", "issue '%s' has a message" % i["code"])
		t.ok(String(i["action"]) != "", "issue '%s' says what to do about it" % i["code"])


static func _design_warnings(t: TFTest) -> void:
	var p := TFProject.create_default(61, 61, 2.0, 0.0)
	var flat := TFValidation.check_design(p, p.analyze())
	t.ok(_codes(flat).has("no_change"), "an untouched site is reported as having no change")

	# A very steep landform.
	var stamps := []
	for i in 4:
		stamps.append(TFBrush.make_stamp(Vector2.ZERO, 8.0, 30.0, 0.5))
	p.apply_stroke(TFBrush.Mode.RAISE, stamps)
	var steep := TFValidation.check_design(p, p.analyze())
	var c := _codes(steep)
	t.ok(c.has("slope_steep") or c.has("slope_extreme"), "a very steep landform is flagged")

	# A road that cannot hold its own grade limit.
	var p2 := TFProject.create_default(81, 81, 2.0, 0.0)
	p2.generate_sample_site({"road_max_grade": 0.60})
	var rd := TFRoad.from_dict(p2.road.to_dict())
	rd.max_grade = 0.60
	p2.set_road(rd)
	var an2 := p2.analyze()
	t.ok(_codes(TFValidation.check_design(p2, an2)).has("road_limit_extreme"),
		"an unbuildable maximum grade limit is flagged")

	var rd2 := TFRoad.from_dict(p2.road.to_dict())
	rd2.width_m = 0.0
	p2.set_road(rd2)
	t.ok(_codes(TFValidation.check_design(p2, p2.analyze())).has("road_width"),
		"a zero road width is an error")

	var p3 := TFProject.create_default(41, 41, 2.0, 0.0)
	var tw := TFTower.new()
	tw.foundation_depth_m = 0.0
	tw.height_m = 0.0
	p3.set_tower(tw)
	var c3 := _codes(TFValidation.check_design(p3, p3.analyze()))
	t.ok(c3.has("foundation_depth"), "a zero foundation depth is flagged")
	t.ok(c3.has("tower_height"), "a zero tower height is flagged")


static func _scope_notes(t: TFTest) -> void:
	var notes := TFValidation.professional_scope_notes()
	t.greater(float(notes.size()), 4.0, "the professional scope notes are present")
	var text := ""
	for n in notes:
		text += String(n["message"]) + " " + String(n["action"]) + " "
	for topic in ["stability", "bearing capacity", "settlement", "groundwater",
			"Drainage", "boundaries", "permit", "survey"]:
		t.ok(text.contains(topic), "the scope notes mention %s" % topic)


static func _never_claims_professional_status(t: TFTest) -> void:
	var p := TFProject.create_default(61, 61, 2.0, 0.0)
	p.generate_sample_site()
	var an := p.analyze()
	var q := TFSequenceGenerator.generate(an, p.assumptions, p.road, p.tower)

	t.eq_str(an.status, "simulated", "the analysis is labelled simulated")
	t.eq_str(q.status, "simulated", "the sequence is labelled simulated")
	t.eq_str(p.settings.data_status, "simulated", "the project is labelled simulated")
	t.ok(TFProjectSettings.STATUS_LABELS.has("field_measured"), "the model can express field-measured status")
	t.ok(TFProjectSettings.STATUS_LABELS.has("professionally_certified"),
		"the model can express certified status, so a future module can use it honestly")

	# Nothing generated in V1 may claim a professional act was performed.
	var haystack := JSON.stringify(TFSchema.to_dict(p, an, q)).to_lower()
	for phrase in ["has been certified", "has been approved", "is approved",
			"survey completed", "field verified", "field-verified",
			"inspection completed", "permit approved", "sealed by",
			"construction ready", "construction-ready", "as-surveyed"]:
		t.ok(not haystack.contains(phrase), "the exported project never says '%s'" % phrase)
	t.ok(haystack.contains("not for construction"), "the exported project says it is not for construction")
	t.ok(haystack.contains("proposed stakeout"), "the exported project explains the stake status")


static func _exploration_is_not_blocked(t: TFTest) -> void:
	# A physically absurd design must still analyse and sequence: warnings, not
	# refusals. Conceptual exploration is allowed.
	var p := TFProject.create_default(41, 41, 2.0, 0.0)
	var stamps := []
	for i in 6:
		stamps.append(TFBrush.make_stamp(Vector2.ZERO, 6.0, 90.0, 0.4))
	p.apply_stroke(TFBrush.Mode.RAISE, stamps)
	var an := p.analyze()
	t.greater(an.fill_compacted_m3, 0.0, "an absurd landform still produces quantities")
	t.greater(an.max_slope_ratio, 1.0, "the absurd slope is measured, not clipped")
	var q := TFSequenceGenerator.generate(an, p.assumptions, null, null)
	t.greater(q.total_duration_hours, 0.0, "an absurd landform still produces a schedule")
	var issues := TFValidation.all(p, an)
	t.greater(float(issues.size()), 0.0, "the absurd landform produces warnings")
	var errors := int(TFValidation.count_by_severity(issues)["error"])
	t.eq_int(errors, 0, "a steep concept is a warning, not an error that blocks work")
