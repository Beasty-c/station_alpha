class_name TFTestEstimate
extends RefCounted

## Estimating: material factors, truckloads, durations and costs must respond
## to their inputs in a traceable, monotonic way.


static func _site() -> TFProject:
	var p := TFProject.create_default(81, 81, 2.0, 0.0)
	p.generate_sample_site()
	return p


static func run(t: TFTest) -> void:
	_material_factors(t)
	_truck_capacity(t)
	_zero_truck_capacity(t)
	_production_rate_traceability(t)
	_cost_traceability(t)
	_cost_band(t)
	_equipment_plan(t)
	_unit_display_does_not_change_maths(t)


static func _material_factors(t: TFTest) -> void:
	var a := TFAssumptions.new()
	a.shrinkage = 0.20
	a.swell = 0.25
	t.near(a.bank_per_compacted(), 1.25, 1e-9, "bank per compacted = 1/(1-0.20)")
	t.near(a.loose_per_bank(), 1.25, 1e-9, "loose per bank = 1+0.25")
	a.shrinkage = 0.0
	t.near(a.bank_per_compacted(), 1.0, 1e-9, "zero shrinkage needs no extra bank material")
	a.shrinkage = 0.99
	t.ok(a.bank_per_compacted() <= 100.0, "an extreme shrinkage is clamped rather than dividing by zero")
	a.swell = -5.0
	t.greater(a.loose_per_bank(), 0.0, "an extreme negative swell is clamped positive")

	# More shrinkage means more bank material and therefore more import.
	var p := _site()
	var base := p.analyze()
	p.change_assumption("shrinkage", 0.30)
	var more := p.analyze()
	t.greater(more.fill_bank_required_m3, base.fill_bank_required_m3, "higher shrinkage needs more bank fill")
	t.greater(more.import_bank_m3, base.import_bank_m3, "higher shrinkage increases import")
	t.near(more.fill_compacted_m3, base.fill_compacted_m3, 1e-3,
		"the geometric fill volume is unchanged by a material factor")
	t.near(more.cut_bank_m3, base.cut_bank_m3, 1e-3,
		"the geometric cut volume is unchanged by a material factor")


static func _truck_capacity(t: TFTest) -> void:
	var p := _site()
	p.change_assumption("truck_capacity_loose_m3", 10.0)
	var small := p.analyze()
	p.change_assumption("truck_capacity_loose_m3", 20.0)
	var big := p.analyze()
	t.greater(float(small.total_truckloads), float(big.total_truckloads),
		"a smaller truck needs more loads")
	t.near(float(small.total_haul_loose_m3), float(big.total_haul_loose_m3), 1e-3,
		"truck size does not change the volume that has to move")
	# Exact load arithmetic.
	var expected := int(ceil(big.import_loose_m3 / 20.0 - 1.0e-9))
	t.eq_int(big.import_truckloads, expected, "import loads = ceil(loose volume / capacity)")

	# And the sequence must follow.
	var seq_small := TFSequenceGenerator.generate(small, p.assumptions, p.road, p.tower)
	p.change_assumption("truck_capacity_loose_m3", 10.0)
	var seq_small2 := TFSequenceGenerator.generate(p.analyze(), p.assumptions, p.road, p.tower)
	p.change_assumption("truck_capacity_loose_m3", 20.0)
	var seq_big := TFSequenceGenerator.generate(p.analyze(), p.assumptions, p.road, p.tower)
	t.greater(seq_small2.total_duration_hours, seq_big.total_duration_hours,
		"smaller trucks lengthen the schedule")
	t.greater(seq_small2.cost_expected, seq_big.cost_expected,
		"smaller trucks raise the preliminary cost")
	t.ok(seq_small != null, "a sequence is produced for the small-truck case")


static func _zero_truck_capacity(t: TFTest) -> void:
	var p := _site()
	p.change_assumption("truck_capacity_loose_m3", 0.0)
	var an := p.analyze()
	t.eq_int(an.total_truckloads, 0, "zero truck capacity reports no truckloads rather than infinity")
	t.greater(an.total_haul_loose_m3, 0.0, "the volume still needs to move")
	var seq := TFSequenceGenerator.generate(an, p.assumptions, p.road, p.tower)
	var haul_applicable := false
	for s in seq.steps:
		if s.id == "onsite_haul" or s.id == "import_delivery":
			haul_applicable = haul_applicable or s.applicable
			t.ok(s.not_applicable_reason.contains("capacity"),
				"'%s' explains that truck capacity is the blocker" % s.id)
	t.ok(not haul_applicable, "hauling steps are marked not applicable with zero truck capacity")
	t.greater(seq.total_duration_hours, 0.0, "the rest of the sequence still schedules")
	var issues := TFValidation.check_assumptions(p.assumptions)
	var found := false
	for i in issues:
		if String(i["code"]) == "truck_capacity" and String(i["severity"]) == "error":
			found = true
	t.ok(found, "validation raises an error for non-positive truck capacity")

	p.change_assumption("truck_capacity_loose_m3", -5.0)
	var an2 := p.analyze()
	t.eq_int(an2.total_truckloads, 0, "negative truck capacity also reports no truckloads")


## A site with real cut as well as fill. The sample scenario alone will not do:
## its hill sits entirely ABOVE the flat existing datum, so it is pure fill and
## the mass excavation step is correctly omitted.
static func _cut_and_fill_site() -> TFProject:
	var p := TFProject.create_default(81, 81, 2.0, 0.0)
	var up := []
	var down := []
	for i in 8:
		up.append(TFBrush.make_stamp(Vector2(-45.0, 0.0), 34.0, 6.0, 0.5))
		down.append(TFBrush.make_stamp(Vector2(45.0, 0.0), 34.0, 5.0, 0.5))
	p.apply_stroke(TFBrush.Mode.RAISE, up)
	p.apply_stroke(TFBrush.Mode.LOWER, down)
	return p


static func _production_rate_traceability(t: TFTest) -> void:
	var sample := _site()
	var sample_an := sample.analyze()
	t.near(sample_an.cut_bank_m3, 0.0, 1.0,
		"the sample hill sits above the datum, so it has no cut")
	t.ok(not _step(TFSequenceGenerator.generate(sample_an, sample.assumptions, sample.road, sample.tower),
		"mass_excavation").applicable,
		"a pure-fill design correctly omits mass excavation")

	var p := _cut_and_fill_site()
	var an := p.analyze()
	t.greater(an.cut_bank_m3, 100.0, "the cut-and-fill site produces real cut volume")
	t.greater(an.fill_compacted_m3, 100.0, "the cut-and-fill site produces real fill volume")

	var slow := p.assumptions.duplicate_assumptions()
	slow.excavator_bcm_per_hour = 50.0
	var fast := p.assumptions.duplicate_assumptions()
	fast.excavator_bcm_per_hour = 200.0
	var qs := TFSequenceGenerator.generate(an, slow, p.road, p.tower)
	var qf := TFSequenceGenerator.generate(an, fast, p.road, p.tower)
	var ds := _step(qs, "mass_excavation")
	var df := _step(qf, "mass_excavation")
	t.ok(ds.applicable, "the cut-and-fill site produces an applicable mass excavation step")
	t.near(ds.duration_hours / df.duration_hours, 4.0, 0.01,
		"quartering excavator production quadruples the excavation duration")
	t.greater(qs.total_duration_hours, qf.total_duration_hours, "a slower fleet lengthens the programme")


static func _cost_traceability(t: TFTest) -> void:
	var p := _site()
	var an := p.analyze()
	var a1 := p.assumptions.duplicate_assumptions()
	var a2 := p.assumptions.duplicate_assumptions()
	a2.equipment_rate_per_hour = a1.equipment_rate_per_hour * 2.0
	var q1 := TFSequenceGenerator.generate(an, a1, p.road, p.tower)
	var q2 := TFSequenceGenerator.generate(an, a2, p.road, p.tower)
	t.near(float(q2.cost_breakdown["equipment"]), float(q1.cost_breakdown["equipment"]) * 2.0, 0.5,
		"doubling the equipment rate exactly doubles the equipment cost")
	t.near(float(q2.cost_breakdown["labor"]), float(q1.cost_breakdown["labor"]), 0.5,
		"the equipment rate does not move the labour cost")
	t.greater(q2.cost_expected, q1.cost_expected, "the total follows the equipment cost")

	var a3 := p.assumptions.duplicate_assumptions()
	a3.mobilization_cost = a1.mobilization_cost + 10000.0
	var q3 := TFSequenceGenerator.generate(an, a3, p.road, p.tower)
	t.near(q3.cost_expected - q1.cost_expected, 10000.0, 1.0,
		"a mobilisation change flows straight through to the total, once")

	# The roll-up must equal the sum of its steps.
	var sum := 0.0
	for s in q1.steps:
		sum += s.total_cost()
	t.near(q1.cost_expected, sum, 0.01, "the expected cost is exactly the sum of the step costs")
	var last_cum := 0.0
	for s in q1.applicable_steps():
		last_cum = s.cumulative_cost
	t.near(last_cum, q1.cost_expected, 0.01, "the cumulative running total ends at the expected cost")


static func _cost_band(t: TFTest) -> void:
	var p := _site()
	var an := p.analyze()
	var a := p.assumptions
	var q := TFSequenceGenerator.generate(an, a, p.road, p.tower)
	t.near(q.cost_low, q.cost_expected * a.cost_low_factor, 0.01, "the low estimate uses the low factor")
	t.near(q.cost_high, q.cost_expected * a.cost_high_factor, 0.01, "the high estimate uses the high factor")
	t.ok(q.cost_low <= q.cost_expected and q.cost_expected <= q.cost_high, "the estimate band is ordered")
	t.ok(q.to_dict()["estimate"]["basis"].contains("Not a quote"),
		"the exported estimate states it is not a quote")


static func _equipment_plan(t: TFTest) -> void:
	var p := _site()
	var q := TFSequenceGenerator.generate(p.analyze(), p.assumptions, p.road, p.tower)
	var plan := TFEquipment.plan_from_steps(q.steps)
	t.greater(float(plan.size()), 5.0, "a meaningful fleet is recommended")
	var hours := 0.0
	var keys := PackedStringArray()
	for e in plan:
		hours += float(e["machine_hours"])
		keys.append(String(e["key"]))
		t.ok(String(e["reason"]) != "", "%s carries a selection reason" % e["key"])
		t.greater(float(e["machine_hours"]), 0.0, "%s has non-zero machine hours" % e["key"])
	t.greater(hours, 0.0, "the fleet has machine hours")
	for expected in ["dozer_d6", "motor_grader", "sheepsfoot_compactor", "excavator_20t"]:
		t.ok(keys.has(expected), "the fleet includes %s" % expected)
	# Machine hours must be sorted so the biggest driver is first.
	var sorted := true
	for i in range(1, plan.size()):
		if float(plan[i]["machine_hours"]) > float(plan[i - 1]["machine_hours"]):
			sorted = false
	t.ok(sorted, "the fleet is ordered by machine hours")


static func _unit_display_does_not_change_maths(t: TFTest) -> void:
	var p := _site()
	var metric := p.analyze()
	p.change_setting("length_unit", "ft")
	p.change_setting("volume_unit", "yd3")
	var imperial := p.analyze()
	t.near(metric.cut_bank_m3, imperial.cut_bank_m3, 1e-6,
		"switching display units does not change the stored cut volume")
	t.near(metric.fill_compacted_m3, imperial.fill_compacted_m3, 1e-6,
		"switching display units does not change the stored fill volume")
	t.eq_int(metric.total_truckloads, imperial.total_truckloads,
		"switching display units does not change the truckload count")
	# ...but the display does change.
	var u := p.settings.units
	t.near(u.volume(metric.cut_bank_m3), metric.cut_bank_m3 / 0.764554857984, 1e-6,
		"the same volume is displayed in cubic yards")


static func _step(q: TFSequence, id: String) -> TFStep:
	for s in q.steps:
		if s.id == id:
			return s
	return null
