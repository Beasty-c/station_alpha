class_name TFViewportHud
extends Control

## Non-blocking overlay on the 3D canvas: display-mode legend, cursor read-out
## and the current tool. Nothing here accepts input - it sits above the canvas
## with mouse filtering off so clicks always reach the terrain.

var app: TFApp
var _legend: PanelContainer
var _legend_rows: VBoxContainer
var _legend_title: Label
var _legend_help: Label
var _readout: PanelContainer
var _readout_lines: VBoxContainer
var _tool_label: Label
var _compact := false


func bind(a: TFApp) -> void:
	app = a


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# --- legend, bottom left -------------------------------------------------
	_legend = _card()
	_legend.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_legend.position = Vector2(12, -12)
	_legend.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_legend)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 4)
	_legend.add_child(lv)
	_legend_title = TFWidgets.label("", 11, TFPalette.TEXT)
	lv.add_child(_legend_title)
	_legend_help = TFWidgets.label("", 10, TFPalette.TEXT_FAINT, true)
	_legend_help.custom_minimum_size = Vector2(230, 0)
	lv.add_child(_legend_help)
	_legend_rows = VBoxContainer.new()
	_legend_rows.add_theme_constant_override("separation", 2)
	lv.add_child(_legend_rows)

	# --- cursor read-out, top left ------------------------------------------
	_readout = _card()
	_readout.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_readout.position = Vector2(12, 12)
	add_child(_readout)
	_readout_lines = VBoxContainer.new()
	_readout_lines.add_theme_constant_override("separation", 2)
	_readout.add_child(_readout_lines)
	_tool_label = TFWidgets.label("", 11, TFPalette.SURVEY_ORANGE)
	_readout_lines.add_child(_tool_label)

	await get_tree().process_frame
	app.analysis_changed.connect(refresh)
	app.mode_changed.connect(refresh)
	refresh()
	# Populate the read-out immediately so it is never an empty card sitting
	# over the canvas before the pointer has moved.
	update_cursor(false, Vector3.ZERO, app.terrain_view.surface(), app.project)


func _card() -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(TFPalette.BG_DEEP, 0.82)
	sb.border_color = Color(TFPalette.BORDER, 0.9)
	sb.set_border_width_all(1)
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	pc.add_theme_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pc


func set_compact(on: bool) -> void:
	_compact = on
	_legend.visible = not on or app.terrain_view.mode != TFTerrainView.Mode.PROPOSED
	refresh()


func refresh() -> void:
	if app == null or app.terrain_view == null:
		return
	_legend_title.text = "Display: %s" % app.terrain_view.mode_name()
	_legend_help.text = app.terrain_view.mode_help()
	TFWidgets.clear(_legend_rows)
	var u := app.units()
	match app.terrain_view.mode:
		TFTerrainView.Mode.CUT_FILL:
			var s := app.terrain_view.cut_fill_scale()
			_swatch(TFPalette.CUT_BLUE, "Cut - material removed (to %s deep)" % u.fmt_length(s, 1))
			_swatch(TFPalette.NO_CHANGE, "No change (within 20 mm)")
			_swatch(TFPalette.FILL_RED, "Fill - material added (to %s deep)" % u.fmt_length(s, 1))
		TFTerrainView.Mode.SLOPE:
			_swatch(TFPalette.slope_color(0.05), "Gentle - under 10%")
			_swatch(TFPalette.slope_color(0.4), "Moderate - about 2:1 (50%)")
			_swatch(TFPalette.slope_color(0.9), "Very steep - approaching 1:1")
		TFTerrainView.Mode.ELEVATION:
			if app.terrain_view.surface() != null:
				var mm := app.terrain_view.surface().min_max()
				_swatch(TFPalette.elevation_color(0.0), "Low: %s" % u.fmt_length(mm.x, 1))
				_swatch(TFPalette.elevation_color(1.0), "High: %s" % u.fmt_length(mm.y, 1))
		TFTerrainView.Mode.EXISTING:
			_swatch(TFPalette.GROUND_EXISTING, "Original ground - synthetic flat datum, not survey data")
		_:
			_swatch(Color("#8a9078"), "Proposed design surface")
	if app.in_playback():
		_swatch(Color(0.62, 0.72, 0.85), "Translucent shell: the finished design")
	_legend.visible = not _compact or app.terrain_view.mode != TFTerrainView.Mode.PROPOSED


func _swatch(c: Color, text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var box := ColorRect.new()
	box.color = c
	box.custom_minimum_size = Vector2(14, 10)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(box)
	row.add_child(TFWidgets.label(text, 10, TFPalette.TEXT_DIM))
	_legend_rows.add_child(row)


## Live cursor read-out: where the pointer is on the site and what the ground
## is doing there. This reads the authoritative surface, not the mesh.
func update_cursor(valid: bool, world: Vector3, field: TFHeightfield, project: TFProject) -> void:
	TFWidgets.clear(_readout_lines)
	_tool_label = TFWidgets.label(_tool_text(), 11, TFPalette.SURVEY_ORANGE)
	_readout_lines.add_child(_tool_label)
	if not valid or field == null:
		_readout_lines.add_child(TFWidgets.label("Pointer off the site", 11, TFPalette.TEXT_FAINT))
		return
	var u := project.settings.units
	var xz := Vector2(world.x, world.z)
	_readout_lines.add_child(TFWidgets.label(
		"E %s   N %s" % [TFUnits.fmt(u.length(xz.x), 1), TFUnits.fmt(u.length(xz.y), 1)],
		11, TFPalette.TEXT_DIM))
	_readout_lines.add_child(TFWidgets.label(
		"Elevation  %s" % u.fmt_length(world.y, 2), 12, TFPalette.TEXT))
	if project.existing != null:
		var d := world.y - project.existing.sample(xz)
		var word := "no change"
		var col := TFPalette.TEXT_DIM
		if d > 0.02:
			word = "fill"
			col = TFPalette.FILL_RED
		elif d < -0.02:
			word = "cut"
			col = TFPalette.CUT_BLUE
		_readout_lines.add_child(TFWidgets.label(
			"%s  %s" % [word.capitalize(), u.fmt_length(absf(d), 2)], 11, col))
	var g := field.grid_coords(xz)
	var c := clampi(int(round(g.x)), 0, field.cols - 1)
	var r := clampi(int(round(g.y)), 0, field.rows - 1)
	var slope := field.slope_ratio(c, r)
	_readout_lines.add_child(TFWidgets.label(
		"Slope  %.1f%%  (%s)" % [slope * 100.0, TFUnits.ratio_to_hv(slope)], 11, TFPalette.TEXT_DIM))


func _tool_text() -> String:
	if app.in_playback():
		return "CONSTRUCTION PLAYBACK"
	var names := {
		TFBrush.Mode.RAISE: "Raise",
		TFBrush.Mode.LOWER: "Lower",
		TFBrush.Mode.SMOOTH: "Smooth",
		TFBrush.Mode.FLATTEN: "Flatten",
	}
	var u := app.units()
	return "%s  -  radius %s, strength %.1f" % [
		String(names.get(app.brush_mode, "Raise")),
		u.fmt_length(app.brush_radius, 1), app.brush_strength]
