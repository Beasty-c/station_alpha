extends SceneTree

## End-to-end UI harness. Loads the real main scene into a real window and
## drives the primary workflow the way a user would, capturing screenshots and
## asserting that the visible controls actually moved the model.
##
##   godot --path terraforge --rendering-driver opengl3 \
##         --script res://tests/ui_smoke.gd -- --out=/tmp/shots [--size=1440x900]
##
## Exit code 0 = every check passed.

var app: TFApp
var _frame := 0
var _stage := 0
var _sub := 0
var _wait := 0
var _awaiting := false
var _pending_shot := ""
var _shot_delay := 0
var _out := "/tmp/tf_shots"
var _t: TFTest
var _shots: Array[String] = []
var _baseline := {}


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	_t = TFTest.new("UI")

	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		print("FATAL: could not load res://scenes/main.tscn")
		quit(1)
		return
	app = packed.instantiate()
	root.add_child(app)
	print("")
	print("TerraForge UI smoke test - %s" % Engine.get_version_info()["string"])
	print("output: ", _out)
	print("=".repeat(74))


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 12:
		return false          # let the shell build and the first frames render
	# Screenshots are deferred by a couple of frames. Control text is redrawn
	# during the normal main-loop iteration, so capturing in the same call that
	# changed the state would photograph stale labels over a fresh 3D view.
	if _pending_shot != "":
		if _shot_delay > 0:
			_shot_delay -= 1
			return false
		_capture(_pending_shot)
		_pending_shot = ""
		return false
	if _wait > 0:
		_wait -= 1
		return false
	# The analysis runs on a worker thread and reports back with call_deferred,
	# so a stage that has just asked for one must let frames pass before it
	# reads the result. Reading it immediately would test nothing.
	if _awaiting:
		if app.analysis_job.is_running():
			return false
		_awaiting = false
	var done := true
	match _stage:
		0: done = _stage_flat()
		1: done = _stage_sculpt()
		2: done = _stage_sample()
		3: done = _stage_display_modes()
		4: done = _stage_assumption_change()
		5: done = _stage_sequence()
		6: done = _stage_playback_start()
		7: done = _stage_playback_mid()
		8: done = _stage_playback_end()
		9: done = _stage_pointer_and_keys()
		10: done = _stage_leave_playback()
		11: done = _stage_undo_redo()
		12: done = _stage_persistence()
		13: done = _stage_exports()
		14: done = _stage_edge_cases()
		15: return _finish()
	if done:
		_stage += 1
		_sub = 0
	return false


## Kick off an analysis and pause the state machine until it has landed.
func _analyze() -> bool:
	app.request_analysis(true)
	_awaiting = true
	_sub += 1
	return false


func _pause(frames: int) -> void:
	_wait = frames


## Queue a capture for a couple of frames' time. Must be the LAST thing a
## stage does, since anything after it would be photographed instead.
func _shot(name: String) -> void:
	app.terrain_view.flush()
	_pending_shot = name
	_shot_delay = 3


func _capture(name: String) -> void:
	var img := root.get_texture().get_image()
	var path := "%s/%s.png" % [_out, name]
	if img.save_png(path) == OK:
		_shots.append(path)
	else:
		print("  (could not save %s)" % path)


# --- stages ------------------------------------------------------------------
func _stage_flat() -> bool:
	var p := app.project
	_t.ok(p != null, "the app opens with a project already loaded")
	_t.ok(p.existing != null and p.sculpt != null, "a terrain surface exists on startup")
	_t.near(p.existing.min_max().y, 0.0, 1e-6, "the startup terrain is flat")
	_t.greater(float(app.terrain_view.tile_count()), 1.0, "the terrain is drawn as multiple tiles")
	_t.ok(app.mode == TFApp.Mode.EDIT, "the app opens in Design mode, not a menu")
	_t.ok(app.top_bar.visible and app.tool_panel.visible and app.inspector.visible,
		"the workspace panels are present on startup")
	_t.ok(not app.playback_bar.visible, "the playback transport is hidden until there is a sequence")
	_shot("01_flat_site")
	_pause(2)
	return true


func _stage_sculpt() -> bool:
	# Sculpt a hill through the same path a pointer drag uses.
	var p := app.project
	var before := p.sculpt.checksum()
	var centre := p.sculpt.center_xz()
	app.set_brush_mode(TFBrush.Mode.RAISE)
	app.set_brush_radius(34.0)
	app.set_brush_strength(9.0)
	p.begin_live_stroke()
	var stamps := []
	for i in 12:
		var s := TFBrush.make_stamp(centre + Vector2(sin(float(i)) * 6.0, cos(float(i)) * 6.0),
			34.0, 9.0, 0.05)
		stamps.append(s)
		p.live_stamp(TFBrush.Mode.RAISE, s)
	p.commit_live_stroke(TFBrush.Mode.RAISE, stamps)
	app.terrain_view.mark_all_dirty()
	_t.ok(p.sculpt.checksum() != before, "a brush stroke changes the terrain model")
	_t.greater(p.sculpt.min_max().y, 1.0, "the stroke raised real elevation")
	_t.eq_int(p.ops.size(), 2, "the whole drag is recorded as exactly one operation")
	_t.near(p.existing.min_max().y, 0.0, 1e-6, "sculpting never touches the existing surface")
	_shot("02_sculpted_hill")
	_pause(2)
	return true


func _stage_sample() -> bool:
	if _sub == 0:
		app.project.generate_sample_site()
		app.terrain_view.mark_all_dirty()
		app.camera_rig.frame_site(app.project.proposed)
		return _analyze()
	var an := app.analysis
	_t.ok(an != null, "the analysis produced a result")
	if an != null:
		_t.greater(an.fill_compacted_m3, 1000.0, "the sample hill produces a real fill volume")
		_t.greater(float(an.total_truckloads), 0.0, "the sample site produces truckloads")
		_baseline = {
			"loads": an.total_truckloads,
			"fill": an.fill_compacted_m3,
			"import": an.import_bank_m3,
		}
	_t.ok(app.project.road != null, "the sample site created a road")
	_t.ok(app.project.tower != null, "the sample site created a tower")
	_shot("03_sample_site")
	_pause(3)
	return true


func _stage_display_modes() -> bool:
	for m in [TFTerrainView.Mode.EXISTING, TFTerrainView.Mode.SLOPE,
			TFTerrainView.Mode.ELEVATION, TFTerrainView.Mode.CUT_FILL]:
		app.terrain_view.set_mode(m)
		app.hud.refresh()
		app.terrain_view.flush()
		_t.ok(app.terrain_view.mode == m, "display mode '%s' is applied" % app.terrain_view.mode_name())
	_shot("04_cut_fill_mode")
	_pause(2)
	return true


## Editing an estimating assumption must move the numbers it should move, and
## leave the geometric ones alone. Each edit re-analyses, so each gets its own
## await; reading straight after the call would just read the previous result.
func _stage_assumption_change() -> bool:
	var before := int(_baseline.get("loads", 0))
	match _sub:
		0:
			app.terrain_view.set_mode(TFTerrainView.Mode.PROPOSED)
			app.hud.refresh()
			app.project.change_assumption("truck_capacity_loose_m3", 6.0)
			return _analyze()
		1:
			var after := app.analysis.total_truckloads
			_t.greater(float(after), float(before) * 1.7,
				"halving truck capacity roughly doubles the truckloads (%d -> %d)" % [before, after])
			_t.near_pct(app.analysis.fill_compacted_m3, float(_baseline.get("fill", 0.0)), 0.001,
				"truck capacity does not change the geometric fill volume")
			app.project.change_assumption("truck_capacity_loose_m3", 12.0)
			return _analyze()
		2:
			_t.eq_int(app.analysis.total_truckloads, before,
				"restoring truck capacity restores the original load count")
			_baseline["import"] = app.analysis.import_bank_m3
			app.project.change_assumption("shrinkage", 0.30)
			return _analyze()
		3:
			_t.greater(app.analysis.import_bank_m3, float(_baseline["import"]),
				"raising shrinkage increases the imported material")
			app.project.change_assumption("shrinkage", 0.12)
			return _analyze()
	_pause(2)
	return true


func _stage_sequence() -> bool:
	app.generate_sequence()
	var q := app.sequence
	_t.ok(q != null, "a construction sequence is generated")
	_t.greater(float(q.applicable_steps().size()), 10.0, "the sequence has a meaningful number of steps")
	_t.greater(q.total_duration_hours, 0.0, "the sequence has a duration")
	_t.greater(q.cost_expected, 0.0, "the sequence has a cost")
	_t.ok(app.playback.has_sequence(), "playback accepts the generated sequence")
	app.inspector.current_tab = 3
	_shot("05_sequence_tab")
	_pause(2)
	return true


func _stage_playback_start() -> bool:
	app.set_mode(TFApp.Mode.PLAYBACK)
	_t.ok(app.in_playback(), "the app enters Construction Playback")
	_t.ok(app.playback_bar.visible, "the playback transport becomes visible")
	app.playback.seek_fraction(0.0)
	app.terrain_view.flush()
	var shown := app.terrain_view.surface()
	_t.eq_str(shown.checksum(), app.project.existing.checksum(),
		"playback starts on the original ground, exactly")
	_shot("06_playback_start")
	_pause(2)
	return true


func _stage_playback_mid() -> bool:
	app.playback.seek_fraction(0.55)
	app.terrain_view.flush()
	var cum := app.playback.cumulative()
	_t.greater(float(cum["cost"]), 0.0, "the live panel shows cost accrued part-way through")
	_t.ok(float(cum["cost"]) < app.sequence.cost_expected,
		"part-way through, the cost is below the total")
	var mid := app.terrain_view.surface()
	_t.ok(mid.checksum() != app.project.existing.checksum(),
		"the terrain has changed from the original ground part-way through")
	_t.ok(mid.checksum() != app.project.proposed.checksum(),
		"the terrain is not yet the finished design part-way through")
	# The fill front should have risen part of the way, not all of it: the
	# landform must be visibly and measurably half-built.
	var mid_top := mid.min_max().y
	var final_top := app.project.proposed.min_max().y
	var start_top := app.project.existing.min_max().y
	_t.between(mid_top, start_top + 0.5, final_top - 0.5,
		"part-way through, the high point is between original ground (%.1f m) and design (%.1f m)"
		% [start_top, final_top])
	_shot("07_playback_mid")
	_pause(2)
	return true


func _stage_playback_end() -> bool:
	app.playback.seek_fraction(1.0)
	app.terrain_view.flush()
	var shown := app.terrain_view.surface()
	var worst := 0.0
	for i in shown.heights.size():
		worst = maxf(worst, absf(shown.heights[i] - app.project.proposed.heights[i]))
	_t.near(worst, 0.0, 1e-3, "playback ends on the proposed surface, exactly")
	var cum := app.playback.cumulative()
	_t.near(float(cum["cost"]), app.sequence.cost_expected, 1.0,
		"the live panel ends on the full expected cost")
	# Stepping must move the scene.
	app.playback.goto_step(2)
	var a_state := app.playback.state()
	app.playback.goto_step(9)
	var b_state := app.playback.state()
	var moved := false
	for k in a_state.keys():
		if absf(float(a_state[k]) - float(b_state[k])) > 1e-6:
			moved = true
	_t.ok(moved, "clicking a different step changes the terrain progress state")
	app.playback.seek_fraction(1.0)
	_shot("08_playback_complete")
	_pause(2)
	return true


## Drive the real pointer path, not the model directly: synthesised mouse
## events into the viewport overlay must pick the terrain, sculpt it, and
## record one operation - the same route a user's hand takes.
func _stage_pointer_and_keys() -> bool:
	app.set_mode(TFApp.Mode.EDIT)
	var p := app.project
	var before := p.sculpt.checksum()
	var ops_before := p.ops.size()
	var centre := app.input_overlay.size * 0.5

	app.set_brush_mode(TFBrush.Mode.RAISE)
	app.set_brush_radius(18.0)
	app.set_brush_strength(8.0)

	# Hover first: the cursor read-out must resolve a point on the ground.
	var hover := InputEventMouseMotion.new()
	hover.position = centre
	app._on_viewport_input(hover)
	_t.ok(app._cursor_valid, "a pointer move over the site picks a point on the terrain")
	var picked := app._cursor_world
	_t.near(picked.y, p.proposed.sample(Vector2(picked.x, picked.z)), 0.05,
		"the picked point sits on the authoritative surface, not on the mesh")

	# Press, drag, release.
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = centre
	app._on_viewport_input(down)
	_t.ok(app._stroking, "pressing the left button starts a stroke")
	for i in 8:
		app._stroke_accum = 0.05
		var move := InputEventMouseMotion.new()
		move.position = centre + Vector2(float(i) * 4.0, float(i) * 2.0)
		app._on_viewport_input(move)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = centre
	app._on_viewport_input(up)

	_t.ok(not app._stroking, "releasing the button ends the stroke")
	_t.ok(p.sculpt.checksum() != before, "a synthesised pointer drag sculpts the terrain")
	_t.eq_int(p.ops.size(), ops_before + 1, "the whole drag records exactly one operation")

	# Camera: a middle-drag must orbit, and must not sculpt.
	var yaw_before := app.camera_rig.yaw
	var terrain_before := p.sculpt.checksum()
	var mid_down := InputEventMouseButton.new()
	mid_down.button_index = MOUSE_BUTTON_MIDDLE
	mid_down.pressed = true
	mid_down.position = centre
	app._on_viewport_input(mid_down)
	var orbit := InputEventMouseMotion.new()
	orbit.position = centre + Vector2(60.0, 0.0)
	orbit.relative = Vector2(60.0, 0.0)
	app._on_viewport_input(orbit)
	var mid_up := InputEventMouseButton.new()
	mid_up.button_index = MOUSE_BUTTON_MIDDLE
	mid_up.pressed = false
	app._on_viewport_input(mid_up)
	_t.ok(absf(app.camera_rig.yaw - yaw_before) > 0.01, "a middle drag orbits the camera")
	_t.eq_str(p.sculpt.checksum(), terrain_before, "orbiting the camera never edits the terrain")

	# Wheel zoom.
	var dist_before := app.camera_rig.distance
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = centre
	app._on_viewport_input(wheel)
	_t.ok(app.camera_rig.distance < dist_before, "the wheel zooms the camera in")

	# Editing is refused while in playback, rather than silently corrupting it.
	app.set_mode(TFApp.Mode.PLAYBACK)
	var guarded := p.sculpt.checksum()
	app._on_viewport_input(down)
	_t.ok(not app._stroking, "the terrain cannot be sculpted during playback")
	_t.eq_str(p.sculpt.checksum(), guarded, "playback mode leaves the design untouched")

	# Every interactive control must be reachable by keyboard.
	var unfocusable := 0
	var checked := 0
	for c in _all_controls(app):
		if c is Button or c is OptionButton or c is LineEdit or c is SpinBox \
				or c is HSlider or c is ItemList or c is CheckBox:
			if not c.visible:
				continue
			checked += 1
			# A SpinBox may legitimately delegate focus to its inner LineEdit;
			# what matters is that a keyboard can reach the field either way.
			var reachable: bool = c.focus_mode != Control.FOCUS_NONE
			if not reachable and c is SpinBox:
				reachable = (c as SpinBox).get_line_edit().focus_mode != Control.FOCUS_NONE
			if not reachable:
				unfocusable += 1
				print("    not focusable: %s '%s' parent=%s" % [
					c.get_class(), String(c.name), c.get_parent().get_class()])
	_t.greater(float(checked), 20.0, "there are interactive controls to check")
	_t.eq_int(unfocusable, 0, "every visible interactive control is keyboard focusable")
	return true


func _all_controls(n: Node, out: Array = []) -> Array:
	if n is Control:
		out.append(n)
	for c in n.get_children():
		_all_controls(c, out)
	return out


func _stage_leave_playback() -> bool:
	app.set_mode(TFApp.Mode.EDIT)
	_t.ok(not app.in_playback(), "the app returns to Design mode")
	return true


func _stage_undo_redo() -> bool:
	var p := app.project
	var before := p.sculpt.checksum()
	var n := p.ops.size()
	app.undo()
	_t.ok(p.sculpt.checksum() != before or p.cursor == n - 1, "undo rolls the document back")
	app.redo()
	_t.eq_str(p.sculpt.checksum(), before, "redo restores the surface exactly")
	_t.eq_int(p.cursor, n, "redo restores the history cursor")

	# Reset, then undo the reset.
	p.reset_terrain()
	_t.eq_str(p.sculpt.checksum(), p.existing.checksum(), "reset returns to the existing ground")
	app.undo()
	_t.eq_str(p.sculpt.checksum(), before, "undoing the reset brings the design back")
	_pause(1)
	return true


func _stage_persistence() -> bool:
	var path := "%s/roundtrip.tfproj.json" % _out
	var res := TFProjectIO.save_project(path, app.project, app.analysis, app.sequence)
	_t.ok(bool(res["ok"]), "the project saves from the running app")
	var before := app.project.sculpt.checksum()
	var loaded := TFProjectIO.load_project(path)
	_t.ok(bool(loaded["ok"]), "the saved project reopens")
	if bool(loaded["ok"]):
		app.adopt_project(loaded["project"], loaded.get("sequence"))
		_t.eq_str(app.project.sculpt.checksum(), before, "the reopened design is identical")
		_t.ok(app.project.road != null, "the reopened project still has its road")
		_t.ok(app.project.tower != null, "the reopened project still has its tower")
		_t.ok(app.sequence != null, "the reopened project still has its construction sequence")
	app.request_analysis(true)
	_awaiting = true
	_pause(2)
	return true


func _stage_exports() -> bool:
	var p := app.project
	var an := app.analysis
	var q := app.sequence
	for pair in [["quantities.csv", TFCsvExport.quantities_csv(p, an)],
			["estimate.csv", TFCsvExport.estimate_csv(p, an, q)],
			["sequence.csv", TFCsvExport.sequence_csv(p, an, q)],
			["equipment.csv", TFCsvExport.equipment_csv(p, an, q)],
			["summary.html", TFReport.html(p, an, q, app.validation_issues())]]:
		var name: String = pair[0]
		var text: String = pair[1]
		var r := TFCsvExport.write("%s/%s" % [_out, name], text)
		_t.ok(bool(r["ok"]), "exported %s" % name)
		_t.greater(float(text.length()), 200.0, "%s has content" % name)
	_pause(1)
	return true


func _stage_edge_cases() -> bool:
	var p := app.project
	match _sub:
		0:
			# Zero brush strength must be a no-op, not a crash.
			var before := p.sculpt.checksum()
			app.set_brush_strength(0.0)
			p.begin_live_stroke()
			var s := TFBrush.make_stamp(p.sculpt.center_xz(), 20.0, 0.0, 0.1)
			p.live_stamp(TFBrush.Mode.RAISE, s)
			p.commit_live_stroke(TFBrush.Mode.RAISE, [s])
			_t.eq_str(p.sculpt.checksum(), before, "a zero-strength stroke changes nothing")
			app.set_brush_strength(6.0)

			# A brush entirely off the site must also do nothing.
			p.begin_live_stroke()
			var off := TFBrush.make_stamp(Vector2(9.0e5, 9.0e5), 20.0, 6.0, 0.1)
			p.live_stamp(TFBrush.Mode.RAISE, off)
			p.commit_live_stroke(TFBrush.Mode.RAISE, [off])
			_t.eq_str(p.sculpt.checksum(), before, "a stroke entirely off the site changes nothing")

			p.change_assumption("truck_capacity_loose_m3", 0.0)
			return _analyze()
		1:
			_t.eq_int(app.analysis.total_truckloads, 0, "zero truck capacity yields no truckloads")
			app.generate_sequence()
			_t.greater(app.sequence.total_duration_hours, 0.0,
				"the sequence still schedules with hauling omitted")
			var found := false
			for i in app.validation_issues():
				if String(i["code"]) == "truck_capacity":
					found = true
			_t.ok(found, "validation surfaces the zero truck capacity")
			# A malformed project file must be refused with a message.
			var bad := "%s/broken.json" % _out
			var f := FileAccess.open(bad, FileAccess.WRITE)
			f.store_string("{ not json at all ")
			f.close()
			_t.ok(not bool(TFProjectIO.load_project(bad)["ok"]),
				"a malformed project file is refused")

			app.inspector.current_tab = 4
			app.inspector._build_checks()
			_shot("09_validation_tab")
			_sub += 1
			return false
		2:
			p.change_assumption("truck_capacity_loose_m3", 12.0)
			return _analyze()
		3:
			_baseline["fill_before_units"] = app.analysis.fill_compacted_m3
			p.change_setting("length_unit", "ft")
			p.change_setting("volume_unit", "yd3")
			return _analyze()
		4:
			_t.near_pct(app.analysis.fill_compacted_m3,
				float(_baseline["fill_before_units"]), 0.001,
				"switching to imperial units does not change the stored volume")
			app.top_bar.refresh()
			app.inspector._refresh_all()
			app.hud.refresh()
			_shot("10_imperial_units")
	_pause(2)
	return true


func _finish() -> bool:
	print("")
	for line in _t.log_lines:
		if line.begins_with("    FAIL"):
			print(line)
	print("=".repeat(74))
	print("  UI smoke: %d passed, %d failed" % [_t.passed, _t.failed])
	print("  screenshots: %d" % _shots.size())
	for s in _shots:
		print("    ", s)
	print("")
	quit(1 if _t.failed > 0 else 0)
	return true
