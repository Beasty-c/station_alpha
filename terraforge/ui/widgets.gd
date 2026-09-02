class_name TFWidgets
extends RefCounted

## Small factory helpers so every panel is built the same way, and so
## accessibility defaults (focus mode, tooltips, minimum sizes) are applied in
## exactly one place rather than remembered twenty times.


static func label(text: String, size: int = 13, color: Color = TFPalette.TEXT,
		autowrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if autowrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## A section heading: small, spaced capitals with a rule underneath.
static func section(text: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var l := label(text.to_upper(), 11, TFPalette.TEXT_DIM)
	l.add_theme_constant_override("outline_size", 0)
	box.add_child(l)
	var sep := HSeparator.new()
	box.add_child(sep)
	return box


static func button(text: String, tooltip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, 28)
	return b


static func toggle(text: String, tooltip: String = "") -> Button:
	var b := button(text, tooltip)
	b.toggle_mode = true
	return b


static func option(items: Array, tooltip: String = "") -> OptionButton:
	var o := OptionButton.new()
	o.tooltip_text = tooltip
	o.focus_mode = Control.FOCUS_ALL
	o.custom_minimum_size = Vector2(0, 28)
	for it in items:
		o.add_item(String(it))
	return o


## A labelled numeric field. Returns the row; the SpinBox is `row.spin`.
static func number_row(text: String, unit: String, value: float,
		min_v: float, max_v: float, step: float, tooltip: String = "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var name_label := label(text, 12, TFPalette.TEXT_DIM, true)
	name_label.custom_minimum_size = Vector2(104, 0)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.tooltip_text = tooltip
	name_label.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(name_label)

	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step
	spin.value = clampf(value, min_v, max_v)
	spin.custom_minimum_size = Vector2(88, 26)
	spin.select_all_on_focus = true
	spin.tooltip_text = tooltip
	# A SpinBox defaults to FOCUS_NONE and delegates focus to its internal
	# LineEdit. Setting both means Tab lands on the field itself, which is what
	# a keyboard user expects when walking down a column of numbers.
	spin.focus_mode = Control.FOCUS_ALL
	spin.get_line_edit().focus_mode = Control.FOCUS_ALL
	if step < 1.0:
		spin.step = step
		spin.custom_arrow_step = step
	row.add_child(spin)

	var unit_label := label(unit, 11, TFPalette.TEXT_FAINT)
	unit_label.custom_minimum_size = Vector2(46, 0)
	row.add_child(unit_label)

	row.set_meta("spin", spin)
	row.set_meta("unit_label", unit_label)
	row.set_meta("name_label", name_label)
	return row


## A read-only key/value row, the workhorse of the inspector panels.
static func kv_row(key: String, value: String, emphasis: bool = false,
		tooltip: String = "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var k := label(key, 12, TFPalette.TEXT_DIM, true)
	k.custom_minimum_size = Vector2(96, 0)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	k.size_flags_stretch_ratio = 1.1
	if tooltip != "":
		k.tooltip_text = tooltip
		k.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(k)
	var v := label(value, 13 if emphasis else 12,
		TFPalette.TEXT if emphasis else TFPalette.TEXT, true)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_stretch_ratio = 1.0
	row.add_child(v)
	row.set_meta("value_label", v)
	return row


## A coloured status chip. The colour is always accompanied by text, never
## used on its own to carry meaning.
static func chip(text: String, color: Color, bg_alpha: float = 0.18) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color, bg_alpha)
	sb.border_color = Color(color, 0.75)
	sb.set_border_width_all(1)
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	pc.add_theme_stylebox_override("panel", sb)
	var l := label(text, 11, color.lightened(0.35))
	pc.add_child(l)
	pc.set_meta("label", l)
	pc.set_meta("style", sb)
	return pc


## An issue row: severity glyph + word + message + what to do about it.
static func issue_row(issue: Dictionary) -> PanelContainer:
	var sev := String(issue.get("severity", "info"))
	var color := TFPalette.severity_color(sev)
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color, 0.09)
	sb.border_color = Color(color, 0.55)
	sb.border_width_left = 3
	sb.corner_radius_top_left = 2
	sb.corner_radius_bottom_left = 2
	sb.content_margin_left = 9
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	pc.add_theme_stylebox_override("panel", sb)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	head.add_child(label("%s %s" % [TFPalette.severity_glyph(sev),
		TFPalette.severity_label(sev)], 10, color))
	box.add_child(head)
	box.add_child(label(String(issue.get("message", "")), 12, TFPalette.TEXT, true))
	var action := String(issue.get("action", ""))
	if action != "":
		box.add_child(label(action, 11, TFPalette.TEXT_DIM, true))
	pc.add_child(box)
	return pc


static func spacer(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


static func hfill() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func scroll_column(margin: int = 12) -> Dictionary:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left", margin)
	mc.add_theme_constant_override("margin_right", margin)
	mc.add_theme_constant_override("margin_top", margin)
	mc.add_theme_constant_override("margin_bottom", margin)
	mc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(mc)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mc.add_child(col)
	return {"scroll": sc, "column": col}


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


## Help text block - plain language for a non-specialist, kept visually quiet.
static func help(text: String) -> Label:
	var l := label(text, 11, TFPalette.TEXT_FAINT, true)
	return l
