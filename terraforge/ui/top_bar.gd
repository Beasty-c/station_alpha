class_name TFTopBar
extends PanelContainer

## Project identity, units, mode switch, file actions, and the persistent
## concept-simulation label that must never leave the screen.

var app: TFApp
var _name_edit: LineEdit
var _units_option: OptionButton
var _status_chip: PanelContainer
var _edit_btn: Button
var _play_btn: Button
var _file_dialog: FileDialog
var _export_dir_dialog: FileDialog
var _pending_file_action := ""

const UNIT_PRESETS := ["Metric (m, m3)", "Imperial (ft, CY)", "US survey (US ft, CY)"]
const PRESET_KEYS := ["metric", "imperial", "us_survey"]


func bind(a: TFApp) -> void:
	app = a


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = TFPalette.BG_PANEL_ALT
	sb.border_color = TFPalette.BORDER
	sb.border_width_bottom = 1
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	add_theme_stylebox_override("panel", sb)

	# A toolbar full of buttons has a large minimum width, and a VBoxContainer
	# adopts the widest minimum of its children - which would push the whole
	# workspace wider than the window and clip the inspector off the right edge
	# on a small laptop. Scrolling the toolbar instead keeps the layout honest
	# at any width; follow_focus means keyboard users still reach every control.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.custom_minimum_size = Vector2(0, 32)
	add_child(scroll)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(row)

	var brand := TFWidgets.label("TERRAFORGE", 14, TFPalette.SURVEY_ORANGE)
	brand.tooltip_text = "TerraForge - terrain design and earthworks concept simulation"
	row.add_child(brand)

	var vs := VSeparator.new()
	row.add_child(vs)

	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(210, 26)
	_name_edit.tooltip_text = "Project name. Stored in the project file and shown on every export."
	_name_edit.text_submitted.connect(func(t): _rename(t))
	_name_edit.focus_exited.connect(func(): _rename(_name_edit.text))
	row.add_child(_name_edit)

	_units_option = TFWidgets.option(UNIT_PRESETS,
		"Display units. The model is always stored in metres and cubic metres; this only changes how numbers are shown and entered.")
	_units_option.custom_minimum_size = Vector2(178, 26)
	_units_option.item_selected.connect(_on_units_selected)
	row.add_child(_units_option)

	row.add_child(TFWidgets.hfill())

	_edit_btn = TFWidgets.toggle("Design", "Sculpt terrain and place features  (mode)")
	_edit_btn.custom_minimum_size = Vector2(92, 28)
	_edit_btn.pressed.connect(func(): app.set_mode(TFApp.Mode.EDIT))
	row.add_child(_edit_btn)

	_play_btn = TFWidgets.toggle("Construction Playback",
		"Step through how the design would be built. Requires a generated construction sequence.")
	_play_btn.custom_minimum_size = Vector2(178, 28)
	_play_btn.pressed.connect(func(): app.set_mode(TFApp.Mode.PLAYBACK))
	row.add_child(_play_btn)

	row.add_child(VSeparator.new())

	var new_btn := TFWidgets.button("New", "Start a new project on flat ground")
	new_btn.pressed.connect(func(): app.new_project())
	row.add_child(new_btn)

	var open_btn := TFWidgets.button("Open", "Open a TerraForge project file (.tfproj.json)")
	open_btn.pressed.connect(func(): _open_dialog("open"))
	row.add_child(open_btn)

	var save_btn := TFWidgets.button("Save", "Save the project locally  (Ctrl+S)")
	save_btn.pressed.connect(save_project)
	row.add_child(save_btn)

	var export_btn := MenuButton.new()
	export_btn.text = "Export"
	export_btn.tooltip_text = "Export project JSON, quantity and estimate CSVs, or a printable summary"
	export_btn.focus_mode = Control.FOCUS_ALL
	export_btn.custom_minimum_size = Vector2(0, 28)
	var pm := export_btn.get_popup()
	pm.add_item("Project JSON (versioned)", 0)
	pm.add_item("Quantities CSV", 1)
	pm.add_item("Estimate CSV", 2)
	pm.add_item("Construction sequence CSV", 3)
	pm.add_item("Equipment CSV", 4)
	pm.add_separator()
	pm.add_item("All CSV tables", 5)
	pm.add_item("Printable summary (HTML)", 6)
	pm.id_pressed.connect(_on_export_selected)
	row.add_child(export_btn)

	row.add_child(VSeparator.new())

	_status_chip = TFWidgets.chip(TFProjectSettings.DISCLAIMER, TFPalette.CONSTRUCTION_YELLOW, 0.16)
	_status_chip.tooltip_text = TFProjectSettings.LONG_DISCLAIMER
	_status_chip.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(_status_chip)

	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = false
	_file_dialog.size = Vector2i(880, 560)
	_file_dialog.file_selected.connect(_on_file_selected)
	add_child(_file_dialog)

	_export_dir_dialog = FileDialog.new()
	_export_dir_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_export_dir_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_export_dir_dialog.use_native_dialog = false
	_export_dir_dialog.size = Vector2i(880, 560)
	_export_dir_dialog.dir_selected.connect(_on_dir_selected)
	add_child(_export_dir_dialog)

	await get_tree().process_frame
	app.project_changed.connect(refresh)
	app.mode_changed.connect(refresh)
	refresh()


func refresh() -> void:
	if app == null or app.project == null:
		return
	if not _name_edit.has_focus():
		_name_edit.text = app.project.settings.project_name
	var preset := app.project.settings.units.preset_name()
	var idx := PRESET_KEYS.find(preset)
	if idx >= 0 and _units_option.selected != idx:
		_units_option.selected = idx
	_edit_btn.button_pressed = app.mode == TFApp.Mode.EDIT
	_play_btn.button_pressed = app.mode == TFApp.Mode.PLAYBACK
	_play_btn.disabled = not app.playback.has_sequence()
	_play_btn.tooltip_text = ("Step through how the design would be built."
		if app.playback.has_sequence()
		else "Generate a construction sequence first (Analysis tab -> Generate construction sequence).")


func _rename(t: String) -> void:
	var clean := t.strip_edges()
	if clean == "" or clean == app.project.settings.project_name:
		return
	app.project.change_setting("project_name", clean)
	app.status_bar.flash("Project renamed to '%s'." % clean)


func _on_units_selected(i: int) -> void:
	var preset := TFUnitSystem.preset(PRESET_KEYS[i])
	app.project.change_setting("length_unit", preset.length_unit)
	app.project.change_setting("volume_unit", preset.volume_unit)
	app.project_changed.emit()
	app.analysis_changed.emit()
	app.sequence_changed.emit()
	app.status_bar.flash("Display units: %s / %s. Stored values are unchanged." % [
		preset.length_label(), preset.volume_label()])


# --- File actions ------------------------------------------------------------
func _open_dialog(action: String) -> void:
	_pending_file_action = action
	_file_dialog.clear_filters()
	_file_dialog.add_filter("*.json", "TerraForge project (JSON)")
	match action:
		"open":
			_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
			_file_dialog.title = "Open TerraForge project"
		"save":
			_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
			_file_dialog.title = "Save TerraForge project"
			_file_dialog.current_file = TFProjectIO.suggest_filename(app.project)
	_file_dialog.popup_centered()


func save_project() -> void:
	if app.project.file_path != "":
		_write_project(app.project.file_path)
	else:
		_open_dialog("save")


func _on_file_selected(path: String) -> void:
	if _pending_file_action == "open":
		_load_project(path)
	elif _pending_file_action == "save":
		_write_project(path)


func _write_project(path: String) -> void:
	var res := TFProjectIO.save_project(path, app.project, app.analysis, app.sequence)
	if bool(res["ok"]):
		app.status_bar.flash("Saved %s (%d bytes). Nothing left this machine." % [path, int(res["bytes"])])
	else:
		app.status_bar.flash(String(res["error"]), "error")


func _load_project(path: String) -> void:
	var res := TFProjectIO.load_project(path)
	if not bool(res["ok"]):
		var msg := ", ".join(res.get("errors", PackedStringArray(["Unknown error."])))
		app.status_bar.flash("Could not open that file: %s" % msg, "error")
		return
	app.adopt_project(res["project"], res.get("sequence"))
	var warn: PackedStringArray = res.get("warnings", PackedStringArray())
	if warn.size() > 0:
		app.status_bar.flash("Opened %s - %s" % [path.get_file(), " ".join(warn)], "warning")
	else:
		app.status_bar.flash("Opened %s." % path.get_file())


func _on_export_selected(id: int) -> void:
	if id == 0:
		_pending_file_action = "save"
		_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		_file_dialog.title = "Export versioned project JSON"
		_file_dialog.clear_filters()
		_file_dialog.add_filter("*.json", "TerraForge project (JSON)")
		_file_dialog.current_file = TFProjectIO.suggest_filename(app.project)
		_file_dialog.popup_centered()
		return
	if app.analysis == null:
		app.status_bar.flash("Nothing to export yet - the analysis has not finished.", "warning")
		return
	if id in [2, 3, 4, 5] and app.sequence == null:
		app.status_bar.flash("Generate a construction sequence before exporting that table.", "warning")
		return
	_pending_file_action = "export_%d" % id
	_export_dir_dialog.title = "Choose a folder for the export"
	_export_dir_dialog.popup_centered()


func _on_dir_selected(dir: String) -> void:
	if not _pending_file_action.begins_with("export_"):
		return
	var id := int(_pending_file_action.split("_")[1])
	var base := TFProjectIO.suggest_filename(app.project).replace(".tfproj.json", "")
	var written: Array[String] = []
	var p := app.project
	var an := app.analysis
	var sq := app.sequence

	if id == 1 or id == 5:
		written.append(_write(dir, "%s_quantities.csv" % base, TFCsvExport.quantities_csv(p, an)))
	if id == 2 or id == 5:
		written.append(_write(dir, "%s_estimate.csv" % base, TFCsvExport.estimate_csv(p, an, sq)))
	if id == 3 or id == 5:
		written.append(_write(dir, "%s_sequence.csv" % base, TFCsvExport.sequence_csv(p, an, sq)))
	if id == 4 or id == 5:
		written.append(_write(dir, "%s_equipment.csv" % base, TFCsvExport.equipment_csv(p, an, sq)))
	if id == 6:
		written.append(_write(dir, "%s_summary.html" % base,
			TFReport.html(p, an, sq, app.validation_issues())))

	var ok: Array[String] = []
	for w in written:
		if w != "":
			ok.append(w)
	if ok.is_empty():
		app.status_bar.flash("Nothing was written. Check that the folder is writable.", "error")
	else:
		app.status_bar.flash("Exported %d file(s) to %s: %s" % [ok.size(), dir, ", ".join(ok)])


func _write(dir: String, filename: String, text: String) -> String:
	var res := TFCsvExport.write(dir.path_join(filename), text)
	if bool(res["ok"]):
		return filename
	app.status_bar.flash(String(res.get("error", "Write failed.")), "error")
	return ""
