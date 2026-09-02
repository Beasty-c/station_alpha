class_name TFToolPanel
extends ScrollContainer

## Left column: display mode, terrain tools, features, and the operation
## history that the whole document is derived from.

var app: TFApp
var _col: VBoxContainer
var _tool_buttons := {}
var _mode_option: OptionButton
var _radius_slider: HSlider
var _radius_value: Label
var _strength_slider: HSlider
var _strength_value: Label
var _flatten_row: HBoxContainer
var _flatten_spin: SpinBox
var _flatten_pick: CheckBox
var _history_list: ItemList
var _undo_btn: Button
var _redo_btn: Button
var _road_status: Label
var _tower_status: Label
var _compact := false

const TOOLS := [
	[TFBrush.Mode.RAISE, "Raise", "Push ground up under the brush. Hold and drag."],
	[TFBrush.Mode.LOWER, "Lower", "Pull ground down under the brush. Hold and drag."],
	[TFBrush.Mode.SMOOTH, "Smooth", "Average out bumps and sharp edges under the brush."],
	[TFBrush.Mode.FLATTEN, "Flatten", "Drive ground towards a chosen elevation."],
]


func bind(a: TFApp) -> void:
	app = a


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(margin)
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", 7)
	_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(_col)

	_build_display()
	_build_tools()
	_build_features()
	_build_history()

	await get_tree().process_frame
	app.project_changed.connect(_refresh_all)
	app.mode_changed.connect(_refresh_all)
	_refresh_all()


func set_compact(on: bool) -> void:
	_compact = on
	if _history_list != null:
		_history_list.custom_minimum_size.y = 130.0 if on else 200.0


# --- Display mode ------------------------------------------------------------
func _build_display() -> void:
	_col.add_child(TFWidgets.section("View"))
	var names := []
	for i in range(TFTerrainView.MODE_NAMES.size()):
		names.append(TFTerrainView.MODE_NAMES[i])
	_mode_option = TFWidgets.option(names,
		"Change what the terrain colouring shows. This is a display setting only; it never changes the model.")
	_mode_option.item_selected.connect(func(i):
		app.terrain_view.set_mode(i as TFTerrainView.Mode)
		app.hud.refresh()
		app.status_bar.flash("Display mode: %s. %s" % [
			app.terrain_view.mode_name(), app.terrain_view.mode_help()]))
	_col.add_child(_mode_option)

	var compare := TFWidgets.button("Before / after  (hold)",
		"Hold to see the original ground, release to return to the proposed design.")
	compare.button_down.connect(func():
		compare.set_meta("prev", app.terrain_view.mode)
		app.terrain_view.set_mode(TFTerrainView.Mode.EXISTING)
		app.hud.refresh())
	compare.button_up.connect(func():
		app.terrain_view.set_mode(compare.get_meta("prev", TFTerrainView.Mode.PROPOSED))
		app.hud.refresh())
	_col.add_child(compare)

	var frame := TFWidgets.button("Frame site  (Home)", "Move the camera to see the whole site.")
	frame.pressed.connect(func(): app.camera_rig.frame_site(app.terrain_view.surface()))
	_col.add_child(frame)


# --- Terrain tools -----------------------------------------------------------
func _build_tools() -> void:
	_col.add_child(TFWidgets.spacer(4))
	_col.add_child(TFWidgets.section("Terrain tools"))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	_col.add_child(grid)
	for entry in TOOLS:
		var m: TFBrush.Mode = entry[0]
		var b := TFWidgets.toggle(String(entry[1]), String(entry[2]))
		b.pressed.connect(func(): app.set_brush_mode(m))
		grid.add_child(b)
		_tool_buttons[m] = b

	_radius_slider = HSlider.new()
	_radius_slider.min_value = 2.0
	_radius_slider.max_value = 90.0
	_radius_slider.step = 0.5
	_radius_slider.value = app.brush_radius
	_radius_slider.focus_mode = Control.FOCUS_ALL
	_radius_slider.custom_minimum_size = Vector2(0, 18)
	_radius_slider.tooltip_text = "Brush radius. The brush fades from full strength at the centre to nothing at the rim."
	_radius_slider.value_changed.connect(func(v):
		app.set_brush_radius(v)
		_update_brush_labels())
	var radius_head := HBoxContainer.new()
	radius_head.add_child(TFWidgets.label("Brush radius", 12, TFPalette.TEXT_DIM))
	radius_head.add_child(TFWidgets.hfill())
	_radius_value = TFWidgets.label("", 12, TFPalette.TEXT)
	radius_head.add_child(_radius_value)
	_col.add_child(radius_head)
	_col.add_child(_radius_slider)

	_strength_slider = HSlider.new()
	_strength_slider.min_value = 0.0
	_strength_slider.max_value = 30.0
	_strength_slider.step = 0.1
	_strength_slider.value = app.brush_strength
	_strength_slider.focus_mode = Control.FOCUS_ALL
	_strength_slider.custom_minimum_size = Vector2(0, 18)
	_strength_slider.tooltip_text = "How fast the ground moves while the pointer is held down, in metres per second of drag."
	_strength_slider.value_changed.connect(func(v):
		app.set_brush_strength(v)
		_update_brush_labels())
	var strength_head := HBoxContainer.new()
	strength_head.add_child(TFWidgets.label("Brush strength", 12, TFPalette.TEXT_DIM))
	strength_head.add_child(TFWidgets.hfill())
	_strength_value = TFWidgets.label("", 12, TFPalette.TEXT)
	strength_head.add_child(_strength_value)
	_col.add_child(strength_head)
	_col.add_child(_strength_slider)

	_flatten_row = TFWidgets.number_row("Flatten to", "", 0.0, -500.0, 500.0, 0.1,
		"The elevation the Flatten tool drives ground towards.")
	_flatten_spin = _flatten_row.get_meta("spin")
	_flatten_spin.value_changed.connect(func(v):
		app.flatten_target = app.units().length_in(v))
	_col.add_child(_flatten_row)

	_flatten_pick = CheckBox.new()
	_flatten_pick.text = "Pick target from first click"
	_flatten_pick.button_pressed = true
	_flatten_pick.focus_mode = Control.FOCUS_ALL
	_flatten_pick.tooltip_text = "When on, the Flatten tool adopts the elevation you first click on."
	_flatten_pick.toggled.connect(func(v): app.flatten_pick_from_terrain = v)
	_col.add_child(_flatten_pick)

	var undo_row := HBoxContainer.new()
	undo_row.add_theme_constant_override("separation", 5)
	_undo_btn = TFWidgets.button("Undo", "Ctrl+Z")
	_undo_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_undo_btn.pressed.connect(func(): app.undo())
	undo_row.add_child(_undo_btn)
	_redo_btn = TFWidgets.button("Redo", "Ctrl+Shift+Z")
	_redo_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_redo_btn.pressed.connect(func(): app.redo())
	undo_row.add_child(_redo_btn)
	_col.add_child(undo_row)

	var reset := TFWidgets.button("Reset terrain to existing ground",
		"Return the proposed surface to the original flat ground. This is recorded as an operation, so it can be undone.")
	reset.pressed.connect(func():
		app.project.reset_terrain()
		app.terrain_view.mark_all_dirty()
		app.request_analysis()
		app.status_bar.flash("Terrain reset to the existing ground surface."))
	_col.add_child(reset)


func _update_brush_labels() -> void:
	var u := app.units()
	_radius_value.text = u.fmt_length(app.brush_radius, 1)
	_strength_value.text = "%.1f %s/s" % [u.length(app.brush_strength), u.length_label()]


func refresh_tool_buttons() -> void:
	for m in _tool_buttons.keys():
		(_tool_buttons[m] as Button).button_pressed = (m == app.brush_mode)
	_flatten_row.visible = app.brush_mode == TFBrush.Mode.FLATTEN
	_flatten_pick.visible = app.brush_mode == TFBrush.Mode.FLATTEN


func refresh_flatten_target() -> void:
	var u := app.units()
	_flatten_spin.set_block_signals(true)
	_flatten_spin.value = u.length(app.flatten_target)
	_flatten_spin.set_block_signals(false)
	(_flatten_row.get_meta("unit_label") as Label).text = u.length_label()


# --- Features ----------------------------------------------------------------
func _build_features() -> void:
	_col.add_child(TFWidgets.spacer(4))
	_col.add_child(TFWidgets.section("Site features"))

	var sample := TFWidgets.button("Generate sample site",
		"Create a large hill with a road spiralling to the summit and a tower on top. The result stays fully editable.")
	sample.pressed.connect(func():
		app.project.generate_sample_site()
		app.terrain_view.mark_all_dirty()
		app.camera_rig.frame_site(app.project.proposed)
		app.request_analysis(true)
		app.status_bar.flash("Sample site generated. Sculpt it, edit the road, or move the tower - it is ordinary geometry."))
	_col.add_child(sample)

	_road_status = TFWidgets.label("", 11, TFPalette.TEXT_FAINT, true)
	_col.add_child(_road_status)
	var road_row := HBoxContainer.new()
	road_row.add_theme_constant_override("separation", 5)
	var add_road := TFWidgets.button("Add road",
		"Lay a road alignment across the site. Edit its width and grade limit in the Design tab.")
	add_road.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_road.pressed.connect(_add_default_road)
	road_row.add_child(add_road)
	var del_road := TFWidgets.button("Remove", "Remove the road alignment")
	del_road.pressed.connect(func():
		if app.project.road == null:
			app.status_bar.flash("There is no road to remove.", "warning")
			return
		app.project.remove_road()
		app.terrain_view.mark_all_dirty()
		app.request_analysis()
		app.status_bar.flash("Road alignment removed."))
	road_row.add_child(del_road)
	_col.add_child(road_row)

	_tower_status = TFWidgets.label("", 11, TFPalette.TEXT_FAINT, true)
	_col.add_child(_tower_status)
	var tower_row := HBoxContainer.new()
	tower_row.add_theme_constant_override("separation", 5)
	var add_tower := TFWidgets.button("Place tower",
		"Place a structure pad and tower at the site's high point. Edit it in the Design tab.")
	add_tower.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_tower.pressed.connect(_add_default_tower)
	tower_row.add_child(add_tower)
	var del_tower := TFWidgets.button("Remove", "Remove the tower")
	del_tower.pressed.connect(func():
		if app.project.tower == null:
			app.status_bar.flash("There is no tower to remove.", "warning")
			return
		app.project.remove_tower()
		app.terrain_view.mark_all_dirty()
		app.request_analysis()
		app.status_bar.flash("Tower removed."))
	tower_row.add_child(del_tower)
	_col.add_child(tower_row)


func _add_default_road() -> void:
	var f := app.project.sculpt
	var c := f.center_xz()
	var e := f.extent()
	var rd := TFRoad.new()
	if app.project.road != null:
		rd = TFRoad.from_dict(app.project.road.to_dict())
	else:
		# A gentle S across the site, so there is something to edit rather than
		# an empty alignment the user has to build from nothing.
		rd.set_control_points(PackedVector2Array([
			c + Vector2(-e.x * 0.46, -e.y * 0.30),
			c + Vector2(-e.x * 0.18, e.y * 0.05),
			c + Vector2(e.x * 0.14, -e.y * 0.08),
			c + Vector2(e.x * 0.46, e.y * 0.26)]))
	app.project.set_road(rd)
	app.terrain_view.mark_all_dirty()
	app.request_analysis()
	app.status_bar.flash("Road alignment added: %s at %s wide. Adjust it in the Design tab." % [
		app.units().fmt_length(rd.length_m()), app.units().fmt_length(rd.width_m, 1)])


func _add_default_tower() -> void:
	var f := app.project.sculpt
	# Put it on the high point, which is where a tower usually goes.
	var best := f.center_xz()
	var best_h := -INF
	for r in range(0, f.rows, 3):
		for c in range(0, f.cols, 3):
			var h := f.get_h(c, r)
			if h > best_h:
				best_h = h
				best = f.node_position(c, r)
	var tw := TFTower.new()
	if app.project.tower != null:
		tw = TFTower.from_dict(app.project.tower.to_dict())
	else:
		tw.position_xz = best
	app.project.set_tower(tw)
	app.terrain_view.mark_all_dirty()
	app.request_analysis()
	app.status_bar.flash("Tower placed at the site high point, pad elevation %s." % [
		app.units().fmt_length(best_h, 2)])


# --- History -----------------------------------------------------------------
func _build_history() -> void:
	_col.add_child(TFWidgets.spacer(4))
	_col.add_child(TFWidgets.section("Operation history"))
	_col.add_child(TFWidgets.help(
		"Every edit is a command. The design is rebuilt by replaying them, so undo, redo and reopening a saved file all give the same result."))
	_history_list = ItemList.new()
	_history_list.custom_minimum_size = Vector2(0, 200)
	_history_list.focus_mode = Control.FOCUS_ALL
	_history_list.auto_height = false
	_history_list.tooltip_text = "Click an operation to roll the design back or forward to that point."
	_history_list.item_selected.connect(_on_history_selected)
	_col.add_child(_history_list)


func _on_history_selected(index: int) -> void:
	# Selecting entry i means "the state after operation i has been applied".
	var target := index + 1
	if target == app.project.cursor:
		return
	while app.project.cursor > target and app.project.can_undo():
		app.project.undo()
	while app.project.cursor < target and app.project.can_redo():
		app.project.redo()
	app.terrain_view.set_surfaces(app.project.proposed, app.project.existing)
	app.terrain_view.mark_all_dirty()
	app._refresh_overlays()
	app.project_changed.emit()
	app.request_analysis()
	app.status_bar.flash("Rolled the design to: %s" % app.project.ops[target - 1].label)


func _refresh_all() -> void:
	if app == null or app.project == null:
		return
	refresh_tool_buttons()
	refresh_flatten_target()
	_update_brush_labels()
	_undo_btn.disabled = not app.project.can_undo()
	_redo_btn.disabled = not app.project.can_redo()
	_undo_btn.tooltip_text = ("Undo: %s  (Ctrl+Z)" % app.project.undo_label()) if app.project.can_undo() else "Nothing to undo"
	_redo_btn.tooltip_text = ("Redo: %s  (Ctrl+Shift+Z)" % app.project.redo_label()) if app.project.can_redo() else "Nothing to redo"

	var u := app.units()
	if app.project.road != null:
		var g := app.project.road.max_grade_achieved(app.project.proposed)
		_road_status.text = "Road: %s long, %s wide, steepest %.1f%%." % [
			u.fmt_length(app.project.road.length_m()),
			u.fmt_length(app.project.road.width_m, 1), g * 100.0]
	else:
		_road_status.text = "No road alignment."
	if app.project.tower != null:
		_tower_status.text = "Tower: %s tall on a %s pad." % [
			u.fmt_length(app.project.tower.height_m, 1),
			u.fmt_length(app.project.tower.pad_size_m, 1)]
	else:
		_tower_status.text = "No structure placed."

	_history_list.clear()
	for i in app.project.ops.size():
		var op := app.project.ops[i]
		var applied := i < app.project.cursor
		var text := "%2d.  %s" % [i + 1, op.label]
		if not applied:
			text += "   (undone)"
		_history_list.add_item(text)
		_history_list.set_item_tooltip(i, "%s\n%s" % [op.type,
			TFProjectSettings.format_time(op.created_unix)])
		if not applied:
			_history_list.set_item_custom_fg_color(i, TFPalette.TEXT_FAINT)
	if app.project.cursor > 0:
		_history_list.select(app.project.cursor - 1)
		_history_list.ensure_current_is_visible()
