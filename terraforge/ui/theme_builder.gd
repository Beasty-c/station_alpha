class_name TFThemeBuilder
extends RefCounted

## The workspace theme, built in code so there is no binary theme resource to
## drift out of sync with the palette.
##
## Contrast: body text (#e6ebf0) on panel (#1b1f24) is about 12:1, and the
## dimmest text still in use (#9aa5b1) is about 6.5:1 - both above WCAG AA.
## Focus is drawn as a survey-orange ring that is visible on every control,
## because keyboard users need to see where they are.

const FOCUS_WIDTH := 2


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 13

	_panel(t)
	_buttons(t)
	_inputs(t)
	_lists(t)
	_containers(t)
	_misc(t)
	return t


static func _sb(color: Color, radius: int = 3) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 5
	s.content_margin_bottom = 5
	return s


static func _focus_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)
	s.border_color = TFPalette.SURVEY_ORANGE
	s.set_border_width_all(FOCUS_WIDTH)
	s.corner_radius_top_left = 3
	s.corner_radius_top_right = 3
	s.corner_radius_bottom_left = 3
	s.corner_radius_bottom_right = 3
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 5
	s.content_margin_bottom = 5
	return s


static func _panel(t: Theme) -> void:
	var p := _sb(TFPalette.BG_PANEL, 0)
	p.content_margin_left = 0
	p.content_margin_right = 0
	p.content_margin_top = 0
	p.content_margin_bottom = 0
	t.set_stylebox("panel", "Panel", p)
	t.set_stylebox("panel", "PanelContainer", _sb(TFPalette.BG_PANEL, 3))
	t.set_color("font_color", "Label", TFPalette.TEXT)
	t.set_color("font_color", "RichTextLabel", TFPalette.TEXT)
	t.set_stylebox("normal", "RichTextLabel", _sb(Color(0, 0, 0, 0), 0))


static func _buttons(t: Theme) -> void:
	var normal := _sb(TFPalette.BG_PANEL_ALT)
	normal.border_color = TFPalette.BORDER
	normal.set_border_width_all(1)
	var hover := _sb(TFPalette.BG_HOVER)
	hover.border_color = TFPalette.BORDER_STRONG
	hover.set_border_width_all(1)
	var pressed := _sb(Color(TFPalette.SURVEY_ORANGE, 0.28))
	pressed.border_color = TFPalette.SURVEY_ORANGE
	pressed.set_border_width_all(1)
	var disabled := _sb(Color(TFPalette.BG_PANEL_ALT, 0.45))
	disabled.border_color = Color(TFPalette.BORDER, 0.5)
	disabled.set_border_width_all(1)

	for cls in ["Button", "OptionButton", "MenuButton", "CheckButton", "CheckBox"]:
		t.set_stylebox("normal", cls, normal)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("disabled", cls, disabled)
		t.set_stylebox("focus", cls, _focus_style())
		t.set_color("font_color", cls, TFPalette.TEXT)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, TFPalette.SURVEY_ORANGE)
		t.set_color("font_focus_color", cls, Color.WHITE)
		t.set_color("font_disabled_color", cls, TFPalette.TEXT_FAINT)
		t.set_font_size("font_size", cls, 13)


static func _inputs(t: Theme) -> void:
	var normal := _sb(TFPalette.BG_INPUT)
	normal.border_color = TFPalette.BORDER
	normal.set_border_width_all(1)
	var focus := _sb(TFPalette.BG_INPUT)
	focus.border_color = TFPalette.SURVEY_ORANGE
	focus.set_border_width_all(FOCUS_WIDTH)

	for cls in ["LineEdit", "SpinBox", "TextEdit"]:
		t.set_stylebox("normal", cls, normal)
		t.set_stylebox("focus", cls, focus)
		t.set_color("font_color", cls, TFPalette.TEXT)
		t.set_color("font_placeholder_color", cls, TFPalette.TEXT_FAINT)
		t.set_color("caret_color", cls, TFPalette.SURVEY_ORANGE)
		t.set_color("selection_color", cls, Color(TFPalette.SURVEY_ORANGE, 0.35))
		t.set_font_size("font_size", cls, 13)

	t.set_stylebox("read_only", "LineEdit", _sb(Color(TFPalette.BG_INPUT, 0.6)))

	var slider_bg := _sb(TFPalette.BG_INPUT, 2)
	slider_bg.content_margin_top = 2
	slider_bg.content_margin_bottom = 2
	t.set_stylebox("slider", "HSlider", slider_bg)
	t.set_stylebox("grabber_area", "HSlider", _sb(TFPalette.SURVEY_ORANGE, 2))
	t.set_stylebox("grabber_area_highlight", "HSlider", _sb(TFPalette.SURVEY_ORANGE, 2))


static func _lists(t: Theme) -> void:
	var bg := _sb(TFPalette.BG_INPUT, 3)
	bg.border_color = TFPalette.BORDER
	bg.set_border_width_all(1)
	for cls in ["ItemList", "Tree"]:
		t.set_stylebox("panel", cls, bg)
		t.set_stylebox("focus", cls, _focus_style())
		t.set_color("font_color", cls, TFPalette.TEXT)
		t.set_color("font_selected_color", cls, Color.WHITE)
		t.set_font_size("font_size", cls, 13)
	var sel := _sb(Color(TFPalette.SURVEY_ORANGE, 0.30), 2)
	t.set_stylebox("selected", "ItemList", sel)
	t.set_stylebox("selected_focus", "ItemList", sel)
	t.set_stylebox("cursor", "ItemList", _focus_style())
	t.set_stylebox("cursor_unfocused", "ItemList", _sb(Color(0, 0, 0, 0)))
	t.set_stylebox("hovered", "ItemList", _sb(TFPalette.BG_HOVER, 2))
	t.set_constant("v_separation", "ItemList", 3)


static func _containers(t: Theme) -> void:
	var tab_selected := _sb(TFPalette.BG_PANEL_ALT, 0)
	tab_selected.border_color = TFPalette.SURVEY_ORANGE
	tab_selected.border_width_top = 2
	tab_selected.content_margin_left = 12
	tab_selected.content_margin_right = 12
	tab_selected.content_margin_top = 6
	tab_selected.content_margin_bottom = 6
	var tab_unselected := _sb(TFPalette.BG_PANEL, 0)
	tab_unselected.content_margin_left = 12
	tab_unselected.content_margin_right = 12
	tab_unselected.content_margin_top = 6
	tab_unselected.content_margin_bottom = 6

	for cls in ["TabContainer", "TabBar"]:
		t.set_stylebox("tab_selected", cls, tab_selected)
		t.set_stylebox("tab_unselected", cls, tab_unselected)
		t.set_stylebox("tab_hovered", cls, _sb(TFPalette.BG_HOVER, 0))
		t.set_color("font_selected_color", cls, Color.WHITE)
		t.set_color("font_unselected_color", cls, TFPalette.TEXT_DIM)
		t.set_color("font_hovered_color", cls, TFPalette.TEXT)
		t.set_font_size("font_size", cls, 13)
	t.set_stylebox("panel", "TabContainer", _sb(TFPalette.BG_PANEL_ALT, 0))

	t.set_stylebox("panel", "ScrollContainer", _sb(Color(0, 0, 0, 0), 0))
	t.set_stylebox("scroll", "VScrollBar", _sb(TFPalette.BG_DEEP, 4))
	t.set_stylebox("grabber", "VScrollBar", _sb(TFPalette.BORDER_STRONG, 4))
	t.set_stylebox("grabber_highlight", "VScrollBar", _sb(TFPalette.TEXT_FAINT, 4))
	t.set_stylebox("scroll", "HScrollBar", _sb(TFPalette.BG_DEEP, 4))
	t.set_stylebox("grabber", "HScrollBar", _sb(TFPalette.BORDER_STRONG, 4))

	t.set_stylebox("panel", "PopupMenu", _sb(TFPalette.BG_PANEL_ALT, 3))
	t.set_color("font_color", "PopupMenu", TFPalette.TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_stylebox("hover", "PopupMenu", _sb(Color(TFPalette.SURVEY_ORANGE, 0.30), 2))

	t.set_stylebox("panel", "AcceptDialog", _sb(TFPalette.BG_PANEL, 4))
	t.set_stylebox("embedded_border", "Window", _sb(TFPalette.BG_PANEL_ALT, 4))
	t.set_color("title_color", "Window", TFPalette.TEXT)


static func _misc(t: Theme) -> void:
	t.set_color("font_color", "TooltipLabel", TFPalette.TEXT)
	var tip := _sb(TFPalette.BG_DEEP, 3)
	tip.border_color = TFPalette.BORDER_STRONG
	tip.set_border_width_all(1)
	t.set_stylebox("panel", "TooltipPanel", tip)

	t.set_stylebox("background", "ProgressBar", _sb(TFPalette.BG_INPUT, 2))
	t.set_stylebox("fill", "ProgressBar", _sb(TFPalette.SURVEY_ORANGE, 2))
	t.set_color("font_color", "ProgressBar", TFPalette.TEXT)

	t.set_stylebox("separator", "HSeparator", _line_style())
	t.set_stylebox("separator", "VSeparator", _line_style())


static func _line_style() -> StyleBoxLine:
	var s := StyleBoxLine.new()
	s.color = TFPalette.BORDER
	s.thickness = 1
	return s
