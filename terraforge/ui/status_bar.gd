class_name TFStatusBar
extends PanelContainer

## The bottom strip: what the app is doing, what the data status is, what units
## are active, and the most recent actionable message.

var app: TFApp
var _message: Label
var _progress: ProgressBar
var _units_label: Label
var _status_label: Label
var _confidence: Label
var _tiles_label: Label
var _flash_until: float = 0.0


func bind(a: TFApp) -> void:
	app = a


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = TFPalette.BG_PANEL_ALT
	sb.border_color = TFPalette.BORDER
	sb.border_width_top = 1
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	add_theme_stylebox_override("panel", sb)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 20)
	add_child(scroll)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(row)

	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(120, 8)
	_progress.show_percentage = false
	_progress.visible = false
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_progress)

	_message = TFWidgets.label("Ready.", 12, TFPalette.TEXT_DIM)
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message.clip_text = true
	row.add_child(_message)

	_tiles_label = TFWidgets.label("", 11, TFPalette.TEXT_FAINT)
	row.add_child(_tiles_label)

	_confidence = TFWidgets.label("", 11, TFPalette.TEXT_FAINT)
	row.add_child(_confidence)

	_units_label = TFWidgets.label("", 11, TFPalette.TEXT_DIM)
	_units_label.tooltip_text = "Active display units. All stored values are metric."
	_units_label.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(_units_label)

	_status_label = TFWidgets.label("", 11, TFPalette.CONSTRUCTION_YELLOW)
	_status_label.tooltip_text = TFProjectSettings.LONG_DISCLAIMER
	_status_label.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(_status_label)

	set_process(true)
	await get_tree().process_frame
	app.project_changed.connect(refresh)
	app.analysis_changed.connect(refresh)
	refresh()


func refresh() -> void:
	if app == null or app.project == null:
		return
	var u := app.project.settings.units
	_units_label.text = "Units: %s / %s / %s" % [u.length_label(), u.area_label(), u.volume_label()]
	_status_label.text = "Data status: %s - %s" % [
		app.project.settings.status_label(), TFProjectSettings.DISCLAIMER]
	if app.analysis != null:
		_confidence.text = "Confidence: %s" % app.analysis.confidence
		_confidence.tooltip_text = "\n".join(app.analysis.confidence_reasons)
		_confidence.mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		_confidence.text = ""


func _process(_delta: float) -> void:
	if app == null or app.terrain_view == null:
		return
	var pending := app.terrain_view.pending_tiles()
	_tiles_label.text = "Rebuilding %d tiles" % pending if pending > 0 else ""
	if _flash_until > 0.0 and Time.get_ticks_msec() > _flash_until:
		_flash_until = 0.0
		_message.text = "Ready."
		_message.add_theme_color_override("font_color", TFPalette.TEXT_DIM)


## Show a message. `kind` is "info", "warning" or "error"; the colour is
## always paired with a word so it is never the only signal.
func flash(text: String, kind: String = "info") -> void:
	var prefix := ""
	var color := TFPalette.TEXT_DIM
	match kind:
		"warning":
			prefix = "%s WARNING  " % TFPalette.severity_glyph("warning")
			color = TFPalette.CONSTRUCTION_YELLOW
		"error":
			prefix = "%s ERROR  " % TFPalette.severity_glyph("error")
			color = TFPalette.ALERT_RED
	_message.text = prefix + text
	_message.tooltip_text = prefix + text
	_message.add_theme_color_override("font_color", color)
	_flash_until = Time.get_ticks_msec() + (9000 if kind != "info" else 6000)


func set_busy(busy: bool, text: String) -> void:
	_progress.visible = busy
	if busy:
		_progress.value = 0.0
		_message.text = text
		_message.add_theme_color_override("font_color", TFPalette.TEXT_DIM)
		_flash_until = 0.0


func set_progress(f: float) -> void:
	_progress.value = clampf(f, 0.0, 1.0) * 100.0
