class_name TFInspector
extends TabContainer

## Right column. Five tabs, each reading straight from the domain model:
## Analysis, Design, Assumptions, Sequence, Checks.

var app: TFApp

var _analysis_col: VBoxContainer
var _design_col: VBoxContainer
var _assumptions_col: VBoxContainer
var _sequence_col: VBoxContainer
var _checks_col: VBoxContainer

var _step_list: ItemList
var _step_detail: VBoxContainer
var _live_panel: VBoxContainer
var _assumption_rows := {}
var _compact := false
var _rebuilding := false


func bind(a: TFApp) -> void:
	app = a


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	clip_tabs = true

	_analysis_col = _add_tab("Analysis")
	_design_col = _add_tab("Design")
	_assumptions_col = _add_tab("Assumptions")
	_sequence_col = _add_tab("Sequence")
	_checks_col = _add_tab("Checks")

	await get_tree().process_frame
	app.project_changed.connect(_refresh_all)
	app.analysis_changed.connect(_refresh_all)
	app.sequence_changed.connect(_refresh_all)
	app.mode_changed.connect(_refresh_all)
	_refresh_all()


func _add_tab(title: String) -> VBoxContainer:
	var built := TFWidgets.scroll_column(12)
	var sc: ScrollContainer = built["scroll"]
	sc.name = title
	add_child(sc)
	return built["column"]


func set_compact(on: bool) -> void:
	_compact = on


func _refresh_all() -> void:
	if app == null or app.project == null or _rebuilding:
		return
	_rebuilding = true
	_build_analysis()
	_build_design()
	_build_assumptions()
	_build_sequence()
	_build_checks()
	_rebuilding = false


# =============================================================================
#  Analysis
# =============================================================================
func _build_analysis() -> void:
	var col := _analysis_col
	TFWidgets.clear(col)
	var u := app.units()

	var run := TFWidgets.button("Analyze build",
		"Recalculate cut, fill, haulage and slopes from the current surfaces.")
	run.pressed.connect(func(): app.request_analysis(true))
	col.add_child(run)

	var an := app.analysis
	if an == null:
		col.add_child(TFWidgets.help("No analysis yet. Sculpt the terrain, then press Analyze build."))
		return

	col.add_child(TFWidgets.spacer(2))
	col.add_child(TFWidgets.section("Material balance"))
	var balance := TFWidgets.chip(an.balance_label(),
		TFPalette.INFO_BLUE if an.import_bank_m3 <= 0.001 and an.export_bank_m3 <= 0.001
		else TFPalette.CONSTRUCTION_YELLOW)
	col.add_child(balance)
	col.add_child(TFWidgets.kv_row("Cut (bank, in place)", u.fmt_volume(an.cut_bank_m3), true,
		"Material removed, measured where it sits in the ground."))
	col.add_child(TFWidgets.kv_row("Fill (compacted)", u.fmt_volume(an.fill_compacted_m3), true,
		"Designed fill volume, measured after compaction."))
	col.add_child(TFWidgets.kv_row("Net (fill - cut)", u.fmt_volume(an.net_geometric_m3), false,
		"Exact bilinear integral of the difference between the two surfaces."))
	col.add_child(TFWidgets.kv_row("Fill required (bank)", u.fmt_volume(an.fill_bank_required_m3), false,
		"compacted / (1 - shrinkage). More bank material is needed than the finished volume."))
	col.add_child(TFWidgets.kv_row("Reused on site (bank)", u.fmt_volume(an.onsite_reuse_bank_m3)))
	col.add_child(TFWidgets.kv_row("Import (bank)", u.fmt_volume(an.import_bank_m3)))
	col.add_child(TFWidgets.kv_row("Export (bank)", u.fmt_volume(an.export_bank_m3)))

	col.add_child(TFWidgets.spacer(4))
	col.add_child(TFWidgets.section("Hauling"))
	col.add_child(TFWidgets.kv_row("Total haul (loose)", u.fmt_volume(an.total_haul_loose_m3), false,
		"Loose volume as carried: bank x (1 + swell)."))
	col.add_child(TFWidgets.kv_row("Truck capacity (loose)", u.fmt_volume(an.truck_capacity_loose_m3, 2)))
	col.add_child(TFWidgets.kv_row("Truckloads total", str(an.total_truckloads), true))
	col.add_child(TFWidgets.kv_row("  import / export / on site",
		"%d / %d / %d" % [an.import_truckloads, an.export_truckloads, an.onsite_truckloads]))
	if an.truck_capacity_loose_m3 <= 0.0:
		col.add_child(TFWidgets.issue_row({
			"severity": "error",
			"message": "Truck capacity is not positive, so no load count can be produced.",
			"action": "Set a positive truck capacity in the Assumptions tab."}))

	col.add_child(TFWidgets.spacer(4))
	col.add_child(TFWidgets.section("Site geometry"))
	col.add_child(TFWidgets.kv_row("Site area", u.fmt_area(an.site_area_m2)))
	col.add_child(TFWidgets.kv_row("Disturbed area", u.fmt_area(an.disturbed_area_m2), false,
		"Cells where the design differs from existing ground by more than 10 mm."))
	col.add_child(TFWidgets.kv_row("Max cut depth", u.fmt_length(an.max_cut_depth_m)))
	col.add_child(TFWidgets.kv_row("Max fill depth", u.fmt_length(an.max_fill_depth_m)))
	col.add_child(TFWidgets.kv_row("Max proposed slope",
		"%.1f%%  (%s)" % [an.max_slope_ratio * 100.0, TFUnits.ratio_to_hv(an.max_slope_ratio)]))

	if not an.road.is_empty():
		col.add_child(TFWidgets.spacer(4))
		col.add_child(TFWidgets.section("Road"))
		col.add_child(TFWidgets.kv_row("Length", u.fmt_length(float(an.road["length_m"]))))
		col.add_child(TFWidgets.kv_row("Max grade", "%.1f%%" % (float(an.road["max_grade"]) * 100.0)))
		col.add_child(TFWidgets.kv_row("Grade limit", "%.1f%%" % (float(an.road["max_grade_limit"]) * 100.0)))
		col.add_child(TFWidgets.kv_row("Within limit",
			"Yes" if bool(an.road["grade_limit_met"]) else "NO - redesign needed"))
		col.add_child(TFWidgets.kv_row("Elevation gain", u.fmt_length(float(an.road["elevation_gain_m"]))))

	if not an.tower.is_empty():
		col.add_child(TFWidgets.spacer(4))
		col.add_child(TFWidgets.section("Structure (placeholder)"))
		col.add_child(TFWidgets.kv_row("Pad area", u.fmt_area(float(an.tower["pad_area_m2"]))))
		col.add_child(TFWidgets.kv_row("Pad elevation", u.fmt_length(float(an.tower["pad_elevation_m"]))))
		col.add_child(TFWidgets.kv_row("Foundation excavation",
			u.fmt_volume(float(an.tower["excavation_volume_m3"]))))
		col.add_child(TFWidgets.kv_row("Concrete", u.fmt_volume(float(an.tower["concrete_volume_m3"]))))
		col.add_child(TFWidgets.help(String(an.tower["note"])))

	col.add_child(TFWidgets.spacer(4))
	col.add_child(TFWidgets.section("How this was calculated"))
	col.add_child(TFWidgets.kv_row("Calculation engine", an.calc_version))
	col.add_child(TFWidgets.kv_row("Grid spacing", u.fmt_length(an.grid_spacing_m, 2)))
	col.add_child(TFWidgets.kv_row("Cells evaluated", str(an.cells_evaluated)))
	col.add_child(TFWidgets.kv_row("Cells refined", str(an.cells_refined), false,
		"Cells where the design crosses existing ground, subdivided to separate cut from fill."))
	col.add_child(TFWidgets.kv_row("Confidence", an.confidence, true))
	for reason in an.confidence_reasons:
		col.add_child(TFWidgets.help("- " + reason))
	for f in an.formulas:
		var fl := TFWidgets.label("%s\n    %s" % [String(f["name"]), String(f["expr"])],
			10, TFPalette.TEXT_FAINT, true)
		col.add_child(fl)

	col.add_child(TFWidgets.spacer(6))
	var gen := TFWidgets.button("Generate construction sequence",
		"Turn this analysis into an ordered, costed construction sequence you can play back in 3D.")
	gen.pressed.connect(func(): app.generate_sequence())
	col.add_child(gen)


# =============================================================================
#  Design (features + project settings)
# =============================================================================
func _build_design() -> void:
	var col := _design_col
	TFWidgets.clear(col)
	var u := app.units()
	var p := app.project

	col.add_child(TFWidgets.section("Road alignment"))
	if p.road == null:
		col.add_child(TFWidgets.help("No road alignment. Use 'Add road' or 'Generate sample site' on the left."))
	else:
		var r := p.road
		col.add_child(_road_number("Width", r.width_m, 1.0, 40.0, 0.5, "width_m",
			"Running surface width."))
		col.add_child(_road_number("Shoulder / batter", r.shoulder_m, 0.0, 40.0, 0.5, "shoulder_m",
			"Width of the graded transition each side of the running surface."))
		col.add_child(_road_grade("Maximum grade", r.max_grade, "max_grade",
			"The steepest longitudinal grade the design profile is allowed to reach."))
		col.add_child(_road_grade("Target grade", r.target_grade, "target_grade",
			"The grade the alignment aims for where the ground allows."))
		col.add_child(_road_number("Surfacing thickness", r.surface_thickness_m, 0.0, 2.0, 0.01,
			"surface_thickness_m", "Depth of imported surfacing over the corridor."))
		col.add_child(TFWidgets.kv_row("Control points", str(r.point_count())))
		col.add_child(TFWidgets.kv_row("Length", u.fmt_length(r.length_m())))
		col.add_child(TFWidgets.kv_row("Steepest achieved",
			"%.1f%%" % (r.max_grade_achieved(p.proposed) * 100.0)))
		col.add_child(TFWidgets.help(
			"The profile is smoothed and then clamped to the maximum grade, so raising the limit lets the road hug the ground more closely."))

	col.add_child(TFWidgets.spacer(6))
	col.add_child(TFWidgets.section("Structure"))
	if p.tower == null:
		col.add_child(TFWidgets.help("No structure placed. Use 'Place tower' on the left."))
	else:
		var t := p.tower
		col.add_child(_tower_number("Height", t.height_m, 1.0, 300.0, 1.0, "height_m"))
		col.add_child(_tower_number("Pad size", t.pad_size_m, 4.0, 120.0, 1.0, "pad_size_m",
			"Side length of the level square pad."))
		col.add_child(_tower_number("Pad apron", t.pad_apron_m, 0.0, 60.0, 0.5, "pad_apron_m",
			"Graded transition beyond the pad edge."))
		col.add_child(_tower_number("Base footprint", t.footprint_m, 1.0, 40.0, 0.5, "footprint_m"))
		col.add_child(_tower_number("Foundation depth", t.foundation_depth_m, 0.0, 20.0, 0.1,
			"foundation_depth_m", "Placeholder depth for quantity take-off only."))
		col.add_child(_tower_number("Foundation plan size", t.foundation_pad_m, 1.0, 40.0, 0.5,
			"foundation_pad_m", "Placeholder footing plan size for quantity take-off only."))
		col.add_child(TFWidgets.issue_row({"severity": "info",
			"message": "The foundation here is a volume placeholder for take-off only.",
			"action": "Structural and geotechnical design must come from a licensed engineer."}))

	col.add_child(TFWidgets.spacer(6))
	col.add_child(TFWidgets.section("Project and provenance"))
	var s := p.settings
	col.add_child(TFWidgets.kv_row("Coordinate system", s.coordinate_system_label))
	col.add_child(TFWidgets.kv_row("Horizontal datum", s.horizontal_datum))
	col.add_child(TFWidgets.kv_row("Vertical datum", s.vertical_datum))
	col.add_child(TFWidgets.kv_row("Assumed elevation", u.fmt_length(s.assumed_elevation_m, 2)))
	col.add_child(TFWidgets.kv_row("Existing surface", s.existing_surface_source))
	col.add_child(TFWidgets.kv_row("Site grid", "%d x %d nodes at %s" % [
		s.site_cols, s.site_rows, u.fmt_length(s.site_spacing_m, 2)]))
	col.add_child(TFWidgets.kv_row("Created", TFProjectSettings.format_time(s.created_unix)))
	col.add_child(TFWidgets.kv_row("Modified", TFProjectSettings.format_time(s.modified_unix)))
	col.add_child(TFWidgets.kv_row("Schema version", TFSchema.SCHEMA_VERSION))
	col.add_child(TFWidgets.kv_row("Data status", s.status_label(), true))

	col.add_child(TFWidgets.spacer(6))
	col.add_child(TFWidgets.section("Accessibility"))
	var rm := CheckBox.new()
	rm.text = "Reduced motion"
	rm.button_pressed = app.reduced_motion
	rm.focus_mode = Control.FOCUS_ALL
	rm.tooltip_text = "Playback advances in discrete step jumps instead of sliding continuously."
	rm.toggled.connect(func(v): app.set_reduced_motion(v))
	col.add_child(rm)
	col.add_child(TFWidgets.help(
		"Keyboard: arrow keys or WASD pan, Q/E orbit, R/F zoom, Home frames the site, Ctrl+Z undo, Ctrl+Shift+Z redo, Space plays or pauses the construction timeline."))

	col.add_child(TFWidgets.spacer(6))
	col.add_child(TFWidgets.section("Local data"))
	col.add_child(TFWidgets.help(
		"TerraForge keeps everything on this machine and makes no network calls. Saved projects live in the folder you choose; the button below clears only TerraForge's own local project folder."))
	var clear_btn := TFWidgets.button("Clear TerraForge's local project folder",
		"Deletes project files TerraForge saved to its own application data folder. Files you saved elsewhere are untouched.")
	clear_btn.pressed.connect(func():
		var n := TFProjectIO.clear_local_projects()
		app.status_bar.flash("Removed %d project file(s) from TerraForge's local folder." % n))
	col.add_child(clear_btn)


func _road_number(label: String, value_m: float, min_m: float, max_m: float,
		step_m: float, field: String, tip: String = "") -> HBoxContainer:
	var u := app.units()
	var row := TFWidgets.number_row(label, u.length_label(), u.length(value_m),
		u.length(min_m), u.length(max_m), maxf(0.01, u.length(step_m)), tip)
	var spin: SpinBox = row.get_meta("spin")
	spin.value_changed.connect(func(v):
		if _rebuilding:
			return
		var rd := TFRoad.from_dict(app.project.road.to_dict())
		rd.set(field, u.length_in(v))
		app.project.set_road(rd)
		app.terrain_view.mark_all_dirty()
		app.request_analysis())
	return row


func _road_grade(label: String, value: float, field: String, tip: String) -> HBoxContainer:
	var row := TFWidgets.number_row(label, "%", value * 100.0, 0.5, 60.0, 0.5, tip)
	var spin: SpinBox = row.get_meta("spin")
	spin.value_changed.connect(func(v):
		if _rebuilding:
			return
		var rd := TFRoad.from_dict(app.project.road.to_dict())
		rd.set(field, v / 100.0)
		app.project.set_road(rd)
		app.terrain_view.mark_all_dirty()
		app.request_analysis())
	return row


func _tower_number(label: String, value_m: float, min_m: float, max_m: float,
		step_m: float, field: String, tip: String = "") -> HBoxContainer:
	var u := app.units()
	var row := TFWidgets.number_row(label, u.length_label(), u.length(value_m),
		u.length(min_m), u.length(max_m), maxf(0.01, u.length(step_m)), tip)
	var spin: SpinBox = row.get_meta("spin")
	spin.value_changed.connect(func(v):
		if _rebuilding:
			return
		var tw := TFTower.from_dict(app.project.tower.to_dict())
		tw.set(field, u.length_in(v))
		app.project.set_tower(tw)
		app.terrain_view.mark_all_dirty()
		app.request_analysis())
	return row


# =============================================================================
#  Assumptions
# =============================================================================
func _build_assumptions() -> void:
	var col := _assumptions_col
	TFWidgets.clear(col)
	_assumption_rows.clear()
	var a := app.project.assumptions
	var u := app.units()

	col.add_child(TFWidgets.issue_row({"severity": "info",
		"message": "Every rate below is an illustrative placeholder, not a supplier quote or a local market rate.",
		"action": "Replace them with your own verified figures before relying on any cost."}))

	var groups := {}
	for key in TFAssumptions.SPEC.keys():
		var spec: Dictionary = TFAssumptions.SPEC[key]
		var g := String(spec.get("group", "Other"))
		if not groups.has(g):
			groups[g] = []
		groups[g].append(key)

	for g in ["Material", "Trucking", "Calendar", "Production", "Rates", "Uncertainty"]:
		if not groups.has(g):
			continue
		col.add_child(TFWidgets.spacer(4))
		col.add_child(TFWidgets.section(g))
		for key in groups[g]:
			var spec: Dictionary = TFAssumptions.SPEC[key]
			if String(spec.get("kind", "")) == "soil":
				col.add_child(_soil_row(a))
				continue
			col.add_child(_assumption_row(key, spec, a, u))

	col.add_child(TFWidgets.spacer(6))
	if app.sequence != null:
		col.add_child(TFWidgets.section("Preliminary estimate"))
		var q := app.sequence
		col.add_child(TFWidgets.kv_row("Expected", "%s %s" % [a.currency, TFUnits.fmt(q.cost_expected, 0)], true))
		col.add_child(TFWidgets.kv_row("Low (x%.2f)" % a.cost_low_factor,
			"%s %s" % [a.currency, TFUnits.fmt(q.cost_low, 0)]))
		col.add_child(TFWidgets.kv_row("High (x%.2f)" % a.cost_high_factor,
			"%s %s" % [a.currency, TFUnits.fmt(q.cost_high, 0)]))
		for k in ["equipment", "labor", "trucking", "material", "disposal", "other"]:
			col.add_child(TFWidgets.kv_row("  " + String(k).capitalize(),
				"%s %s" % [a.currency, TFUnits.fmt(float(q.cost_breakdown.get(k, 0.0)), 0)]))
		col.add_child(TFWidgets.help(
			"Preliminary modelled estimate from the assumptions above, generated %s. Not a quote, a bid or supplier pricing." %
			TFProjectSettings.format_time(q.generated_unix)))
	else:
		col.add_child(TFWidgets.help("Generate a construction sequence to see the estimate roll-up."))


func _soil_row(a: TFAssumptions) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := TFWidgets.label("Soil category", 12, TFPalette.TEXT_DIM)
	l.custom_minimum_size = Vector2(150, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var keys := TFAssumptions.SOIL_PRESETS.keys()
	var labels := []
	for k in keys:
		labels.append(String(TFAssumptions.SOIL_PRESETS[k]["label"]))
	var opt := TFWidgets.option(labels,
		"Sets shrinkage, swell and excavator production to textbook values for that material.")
	opt.custom_minimum_size = Vector2(162, 26)
	var idx := keys.find(a.soil_type)
	opt.selected = idx if idx >= 0 else 0
	opt.item_selected.connect(func(i):
		if _rebuilding:
			return
		app.project.change_assumption("soil_type", String(keys[i]))
		app.request_analysis(true)
		app.status_bar.flash("Soil set to %s: shrinkage %.2f, swell %.2f." % [
			app.project.assumptions.soil_label(),
			app.project.assumptions.shrinkage, app.project.assumptions.swell]))
	row.add_child(opt)
	return row


func _assumption_row(key: String, spec: Dictionary, a: TFAssumptions, u: TFUnitSystem) -> HBoxContainer:
	var unit := String(spec.get("unit", ""))
	var raw = a.get(key)
	var display := float(raw)
	var unit_label := unit
	var min_v := float(spec.get("min", 0.0))
	var max_v := float(spec.get("max", 1000000.0))
	var step := float(spec.get("step", 0.1))

	# Values stored in SI are shown in the active display units, and converted
	# straight back on the way in, so the user never types a mixed-unit number.
	match unit:
		"length":
			display = u.length(display); unit_label = u.length_label()
			min_v = u.length(min_v); max_v = u.length(max_v); step = maxf(0.01, u.length(step))
		"volume":
			display = u.volume(display); unit_label = u.volume_label()
			min_v = u.volume(min_v); max_v = u.volume(max_v); step = maxf(0.01, u.volume(step))
		"vol/h":
			display = u.volume(display); unit_label = "%s/h" % u.volume_label()
			min_v = u.volume(min_v); max_v = u.volume(max_v); step = maxf(0.1, u.volume(step))
		"area/h":
			display = u.area(display); unit_label = "%s/h" % u.area_label()
			min_v = u.area(min_v); max_v = u.area(max_v); step = maxf(1.0, u.area(step))
		"cur":
			unit_label = a.currency
		"cur/h":
			unit_label = "%s/h" % a.currency
		"cur/vol":
			# Stored per cubic metre. u.volume(1.0) is how many display units
			# one cubic metre is, so dividing gives price per display unit.
			display = display / maxf(1e-9, u.volume(1.0))
			unit_label = "%s/%s" % [a.currency, u.volume_label()]
			min_v = 0.0; max_v = 100000.0
		"cur/len":
			display = display / maxf(1e-9, u.length(1.0))
			unit_label = "%s/%s" % [a.currency, u.length_label()]
			min_v = 0.0; max_v = 100000.0

	var row := TFWidgets.number_row(String(spec["label"]), unit_label, display,
		min_v, max_v, step, String(spec.get("help", "")))
	var spin: SpinBox = row.get_meta("spin")
	spin.value_changed.connect(func(v):
		if _rebuilding:
			return
		var stored: float = float(v)
		match unit:
			"length": stored = u.length_in(float(v))
			"volume", "vol/h": stored = u.volume_in(float(v))
			"area/h": stored = TFUnits.area_to_m2(float(v), u.length_unit)
			"cur/vol": stored = float(v) * u.volume(1.0)
			"cur/len": stored = float(v) * u.length(1.0)
		var to_store: Variant = stored
		if typeof(a.get(key)) == TYPE_INT:
			to_store = int(round(stored))
		app.project.change_assumption(key, to_store)
		app.request_analysis(true)
		if app.sequence != null:
			app.generate_sequence()
		app.status_bar.flash("%s set to %s %s. Quantities, schedule and cost updated." % [
			String(spec["label"]), TFUnits.fmt(v, 2), unit_label]))
	_assumption_rows[key] = row
	return row


# =============================================================================
#  Sequence
# =============================================================================
func _build_sequence() -> void:
	var col := _sequence_col
	TFWidgets.clear(col)

	var gen := TFWidgets.button("Generate construction sequence",
		"Build an ordered, costed sequence from the current analysis.")
	gen.pressed.connect(func(): app.generate_sequence())
	col.add_child(gen)

	var q := app.sequence
	if q == null:
		col.add_child(TFWidgets.help("No sequence yet. Run the analysis, then generate the sequence."))
		return

	var a := app.project.assumptions
	col.add_child(TFWidgets.kv_row("Duration", "%.1f h  (%.1f workdays, %.1f weeks)" % [
		q.total_duration_hours, q.total_duration_days, q.total_duration_weeks], true))
	col.add_child(TFWidgets.kv_row("Expected cost",
		"%s %s" % [a.currency, TFUnits.fmt(q.cost_expected, 0)], true))
	col.add_child(TFWidgets.kv_row("Range", "%s %s  to  %s %s" % [
		a.currency, TFUnits.fmt(q.cost_low, 0), a.currency, TFUnits.fmt(q.cost_high, 0)]))
	col.add_child(TFWidgets.kv_row("Steps", "%d applicable of %d" % [
		q.applicable_steps().size(), q.steps.size()]))
	for w in q.warnings:
		col.add_child(TFWidgets.issue_row({"severity": "info", "message": w, "action": ""}))

	var enter := TFWidgets.button("Enter Construction Playback",
		"Watch the site change from original ground to the finished design.")
	enter.pressed.connect(func(): app.set_mode(TFApp.Mode.PLAYBACK))
	col.add_child(enter)

	col.add_child(TFWidgets.spacer(4))
	col.add_child(TFWidgets.section("Steps"))
	_step_list = ItemList.new()
	_step_list.custom_minimum_size = Vector2(0, 240)
	_step_list.focus_mode = Control.FOCUS_ALL
	_step_list.tooltip_text = "Click a step to jump the 3D scene to it."
	var idx := 0
	for s in q.steps:
		var text := "%2d.  %s" % [idx + 1, s.name]
		if not s.applicable:
			text += "   (not applicable)"
		_step_list.add_item(text)
		_step_list.set_item_tooltip(idx, "%s\n%s%s" % [s.phase, s.description,
			("\n\nOmitted: " + s.not_applicable_reason) if not s.applicable else ""])
		if not s.applicable:
			_step_list.set_item_custom_fg_color(idx, TFPalette.TEXT_FAINT)
		elif s.warnings.size() > 0:
			_step_list.set_item_custom_fg_color(idx, TFPalette.CONSTRUCTION_YELLOW)
		idx += 1
	_step_list.item_selected.connect(_on_step_selected)
	col.add_child(_step_list)

	_step_detail = VBoxContainer.new()
	_step_detail.add_theme_constant_override("separation", 4)
	col.add_child(_step_detail)

	col.add_child(TFWidgets.spacer(4))
	col.add_child(TFWidgets.section("Equipment plan"))
	for e in TFEquipment.plan_from_steps(q.steps):
		var card := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = TFPalette.BG_PANEL
		sb.border_color = TFPalette.BORDER
		sb.set_border_width_all(1)
		sb.content_margin_left = 9
		sb.content_margin_right = 9
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		card.add_theme_stylebox_override("panel", sb)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		var head := HBoxContainer.new()
		var swatch := ColorRect.new()
		swatch.color = TFEquipment.color(String(e["key"]))
		swatch.custom_minimum_size = Vector2(4, 0)
		head.add_child(swatch)
		head.add_child(TFWidgets.spacer(6))
		head.add_child(TFWidgets.label(String(e["label"]), 12, TFPalette.TEXT))
		v.add_child(head)
		v.add_child(TFWidgets.label("%d peak units  -  %.1f machine hours" % [
			int(e["peak_count"]), float(e["machine_hours"])], 11, TFPalette.TEXT_DIM))
		v.add_child(TFWidgets.help(String(e["reason"])))
		for b in e["production_basis"]:
			v.add_child(TFWidgets.help("Basis: " + String(b)))
		card.add_child(v)
		col.add_child(card)


func _on_step_selected(index: int) -> void:
	var q := app.sequence
	if q == null or index < 0 or index >= q.steps.size():
		return
	var step := q.steps[index]
	_show_step_detail(step)
	if not step.applicable:
		app.status_bar.flash("'%s' is not applicable: %s" % [step.name, step.not_applicable_reason], "warning")
		return
	# Clicking a step moves the scene to that step.
	if not app.in_playback():
		app.set_mode(TFApp.Mode.PLAYBACK)
	var applicable := q.applicable_steps()
	var target := applicable.find(step)
	if target >= 0:
		app.playback.goto_step(target)


func _show_step_detail(s: TFStep) -> void:
	if _step_detail == null:
		return
	TFWidgets.clear(_step_detail)
	var u := app.units()
	var a := app.project.assumptions
	_step_detail.add_child(TFWidgets.label(s.name, 13, TFPalette.TEXT))
	_step_detail.add_child(TFWidgets.label(s.phase, 11, TFPalette.SURVEY_ORANGE))
	_step_detail.add_child(TFWidgets.label(s.description, 11, TFPalette.TEXT_DIM, true))
	if not s.applicable:
		_step_detail.add_child(TFWidgets.issue_row({"severity": "info",
			"message": "Not applicable to this design.", "action": s.not_applicable_reason}))
		return
	if s.prerequisites.size() > 0:
		_step_detail.add_child(TFWidgets.kv_row("Prerequisites", ", ".join(s.prerequisites)))
	_step_detail.add_child(TFWidgets.kv_row("Work zone", String(s.zone.get("type", "site"))))
	_step_detail.add_child(TFWidgets.kv_row("Duration", "%.1f h  (%.2f workdays)" % [
		s.duration_hours, s.duration_days]))
	_step_detail.add_child(TFWidgets.kv_row("Starts / ends", "%.1f h  ->  %.1f h" % [
		s.start_hours, s.end_hours]))
	var bank := float(s.material.get("bank_m3", 0.0))
	if bank > 0.0:
		_step_detail.add_child(TFWidgets.kv_row("Material moved",
			"%s bank  (%s)" % [u.fmt_volume(bank), String(s.material.get("direction", "-"))]))
	if s.truckloads > 0:
		_step_detail.add_child(TFWidgets.kv_row("Truckloads", str(s.truckloads)))
	_step_detail.add_child(TFWidgets.kv_row("Crew", "%d for %.1f h" % [s.crew_size, s.crew_hours]))
	for e in s.equipment:
		_step_detail.add_child(TFWidgets.kv_row("  %s" % TFEquipment.label(String(e["key"])),
			"%d x %.1f h" % [int(e["count"]), float(e["hours"])], false, String(e.get("basis", ""))))
	_step_detail.add_child(TFWidgets.kv_row("Cost", "%s %s" % [a.currency, TFUnits.fmt(s.total_cost(), 0)], true))
	for k in ["equipment", "labor", "trucking", "material", "disposal", "other"]:
		var v := float(s.cost.get(k, 0.0))
		if v > 0.0:
			_step_detail.add_child(TFWidgets.kv_row("  " + String(k).capitalize(),
				"%s %s" % [a.currency, TFUnits.fmt(v, 0)]))
	for b in s.basis:
		_step_detail.add_child(TFWidgets.help(b))
	for w in s.warnings:
		_step_detail.add_child(TFWidgets.issue_row({"severity": "warning", "message": w, "action": ""}))


# =============================================================================
#  Checks
# =============================================================================
func _build_checks() -> void:
	var col := _checks_col
	TFWidgets.clear(col)
	var issues := app.validation_issues()
	var counts := TFValidation.count_by_severity(issues)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	head.add_child(TFWidgets.chip("%d errors" % counts["error"], TFPalette.ALERT_RED))
	head.add_child(TFWidgets.chip("%d warnings" % counts["warning"], TFPalette.CONSTRUCTION_YELLOW))
	head.add_child(TFWidgets.chip("%d notes" % counts["info"], TFPalette.INFO_BLUE))
	col.add_child(head)

	if issues.is_empty():
		col.add_child(TFWidgets.help("No validation issues with the current design and assumptions."))
	for i in issues:
		col.add_child(TFWidgets.issue_row(i))

	col.add_child(TFWidgets.spacer(8))
	col.add_child(TFWidgets.section("What TerraForge does not do"))
	for n in TFValidation.professional_scope_notes():
		col.add_child(TFWidgets.issue_row(n))

	col.add_child(TFWidgets.spacer(6))
	col.add_child(TFWidgets.section("Status of this information"))
	col.add_child(TFWidgets.label(TFProjectSettings.LONG_DISCLAIMER, 11, TFPalette.TEXT_DIM, true))


# =============================================================================
#  Playback live panel
# =============================================================================
func refresh_playback() -> void:
	if _step_list == null or app.sequence == null or not app.in_playback():
		return
	var idx := app.playback.current_index()
	var applicable := app.sequence.applicable_steps()
	if idx < 0 or idx >= applicable.size():
		return
	var step := applicable[idx]
	var full := app.sequence.steps.find(step)
	if full >= 0 and _step_list.get_selected_items() != PackedInt32Array([full]):
		_step_list.select(full)
		_step_list.ensure_current_is_visible()
		_show_step_detail(step)
