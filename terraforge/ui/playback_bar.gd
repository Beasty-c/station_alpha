class_name TFPlaybackBar
extends PanelContainer

## The 4D transport. Visible only in Construction Playback.
##
## The scrub bar is in SCHEDULE HOURS, and the live read-out beside it is the
## sequence's own cumulative roll-up at that position - the same numbers
## whether the user played there or dragged there.

var app: TFApp
var _play_btn: Button
var _prev_btn: Button
var _next_btn: Button
var _speed_option: OptionButton
var _scrub: HSlider
var _time_label: Label
var _step_label: Label
var _phase_label: Label
var _cost_label: Label
var _volume_label: Label
var _loads_label: Label
var _progress_label: Label
var _scrubbing := false


func bind(a: TFApp) -> void:
	app = a


func _ready() -> void:
	visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = TFPalette.BG_PANEL_ALT
	sb.border_color = TFPalette.BORDER
	sb.border_width_top = 1
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	add_theme_stylebox_override("panel", sb)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.custom_minimum_size = Vector2(0, 62)
	add_child(scroll)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)

	# --- transport -----------------------------------------------------------
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	col.add_child(row)

	_prev_btn = TFWidgets.button("|< Previous", "Go to the previous construction step")
	_prev_btn.pressed.connect(func(): app.playback.prev_step())
	row.add_child(_prev_btn)

	_play_btn = TFWidgets.button("> Play", "Play or pause the construction timeline  (Space)")
	_play_btn.custom_minimum_size = Vector2(92, 28)
	_play_btn.pressed.connect(func(): app.playback.toggle())
	row.add_child(_play_btn)

	_next_btn = TFWidgets.button("Next >|", "Go to the next construction step")
	_next_btn.pressed.connect(func(): app.playback.next_step())
	row.add_child(_next_btn)

	var stop := TFWidgets.button("|< Start", "Return to the original ground")
	stop.pressed.connect(func(): app.playback.stop())
	row.add_child(stop)

	var speeds := []
	for s in TFPlayback.SPEEDS:
		speeds.append("%sx" % String.num(s, 2 if s < 1.0 else 0))
	_speed_option = TFWidgets.option(speeds,
		"Playback speed. At 1x, one real second is one modelled day.")
	_speed_option.custom_minimum_size = Vector2(80, 28)
	_speed_option.selected = app.playback.speed_index
	_speed_option.item_selected.connect(func(i): app.playback.set_speed_index(i))
	row.add_child(_speed_option)

	_scrub = HSlider.new()
	_scrub.min_value = 0.0
	_scrub.max_value = 1.0
	_scrub.step = 0.0005
	_scrub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scrub.custom_minimum_size = Vector2(180, 24)
	_scrub.focus_mode = Control.FOCUS_ALL
	_scrub.tooltip_text = "Drag to scrub through the construction programme."
	_scrub.value_changed.connect(func(v):
		if _scrubbing:
			app.playback.seek_fraction(v))
	_scrub.drag_started.connect(func(): _scrubbing = true)
	_scrub.drag_ended.connect(func(_c): _scrubbing = false)
	# Keyboard use of the slider must scrub too, not only mouse dragging.
	_scrub.gui_input.connect(func(e):
		if e is InputEventKey and e.pressed:
			_scrubbing = true
			app.playback.seek_fraction(_scrub.value)
			_scrubbing = false)
	row.add_child(_scrub)

	_time_label = TFWidgets.label("", 12, TFPalette.TEXT)
	_time_label.custom_minimum_size = Vector2(150, 0)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_time_label)

	# --- live read-out -------------------------------------------------------
	var info := HBoxContainer.new()
	info.add_theme_constant_override("separation", 18)
	col.add_child(info)

	_step_label = TFWidgets.label("", 12, TFPalette.SURVEY_ORANGE)
	_step_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_step_label.clip_text = true
	info.add_child(_step_label)

	_phase_label = _stat("Phase")
	info.add_child(_phase_label.get_parent())
	_progress_label = _stat("Complete")
	info.add_child(_progress_label.get_parent())
	_volume_label = _stat("Material moved")
	info.add_child(_volume_label.get_parent())
	_loads_label = _stat("Truckloads")
	info.add_child(_loads_label.get_parent())
	_cost_label = _stat("Cost to date")
	info.add_child(_cost_label.get_parent())

	await get_tree().process_frame
	app.mode_changed.connect(_on_mode_changed)
	app.sequence_changed.connect(refresh)
	_on_mode_changed()


func _stat(caption: String) -> Label:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.add_child(TFWidgets.label(caption.to_upper(), 9, TFPalette.TEXT_FAINT))
	var v := TFWidgets.label("-", 13, TFPalette.TEXT)
	box.add_child(v)
	return v


func _on_mode_changed() -> void:
	visible = app.in_playback()
	refresh()


func refresh() -> void:
	if app == null or not visible or app.sequence == null:
		return
	var pb := app.playback
	var q := app.sequence
	var u := app.units()
	var a := app.project.assumptions

	_play_btn.text = "|| Pause" if pb.playing else "> Play"
	_speed_option.selected = pb.speed_index
	if not _scrubbing:
		_scrub.set_block_signals(true)
		_scrub.value = pb.fraction()
		_scrub.set_block_signals(false)

	var cum := pb.cumulative()
	var hours := float(cum["hours"])
	_time_label.text = "%.1f h / %.1f h  (day %.1f)" % [
		hours, q.total_duration_hours, hours / maxf(0.5, q.workday_hours)]

	var step := pb.current_step()
	var idx := pb.current_index()
	var total := q.applicable_steps().size()
	if step != null:
		_step_label.text = "Step %d of %d  -  %s" % [idx + 1, total, step.name]
		_step_label.tooltip_text = step.description
		_phase_label.text = step.phase
	else:
		_step_label.text = "-"
		_phase_label.text = "-"

	_progress_label.text = "%.0f%%" % (pb.fraction() * 100.0)
	_volume_label.text = u.fmt_volume(float(cum["bank_m3"]))
	_loads_label.text = str(int(cum["truckloads"]))
	_cost_label.text = "%s %s" % [a.currency, TFUnits.fmt(float(cum["cost"]), 0)]

	_prev_btn.disabled = idx <= 0 and pb.fraction() <= 0.001
	_next_btn.disabled = idx >= total - 1 and pb.fraction() >= 0.999
