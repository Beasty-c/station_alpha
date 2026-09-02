class_name TFApp
extends Control

## TerraForge application shell.
##
## Owns the document, the 3D view and the panels, and is the single place that
## decides what happens when the model changes. Panels read from here and call
## back into here; they never mutate the project behind its back.
##
## The layout is Onshape-flavoured: a large central 3D canvas, a compact tool
## and history column on the left, an inspectable property column on the right,
## a persistent status strip, and a playback transport that only appears when
## there is a sequence to play.

signal project_changed()
signal analysis_changed()
signal sequence_changed()
signal mode_changed()

enum Mode { EDIT, PLAYBACK }

const NARROW_WIDTH := 1180.0     # below this, side panels collapse to tabs
const STROKE_INTERVAL := 0.016   # minimum seconds between recorded stamps

# --- Document ----------------------------------------------------------------
var project: TFProject
var analysis: TFAnalysis
var sequence: TFSequence
var playback := TFPlayback.new()
var mode: Mode = Mode.EDIT

# --- Tool state --------------------------------------------------------------
var brush_mode: TFBrush.Mode = TFBrush.Mode.RAISE
var brush_radius: float = 22.0
var brush_strength: float = 6.0
var flatten_target: float = 0.0
var flatten_pick_from_terrain: bool = true
var reduced_motion: bool = false

# --- 3D ----------------------------------------------------------------------
var subviewport: SubViewport
var viewport_container: SubViewportContainer
var input_overlay: Control
var camera_rig: TFCameraRig
var terrain_view: TFTerrainView
var overlays: TFOverlays
var brush_ring: MeshInstance3D
var _construction_surface := TFConstructionSurface.new()
var _playback_field: TFHeightfield = null
var _playback_buffer := PackedFloat32Array()

# --- Panels ------------------------------------------------------------------
var top_bar: TFTopBar
var tool_panel: TFToolPanel
var inspector: TFInspector
var playback_bar: TFPlaybackBar
var status_bar: TFStatusBar
var left_holder: PanelContainer
var right_holder: PanelContainer
var main_split: HBoxContainer
var hud: TFViewportHud

# --- Analysis ----------------------------------------------------------------
var analysis_job: TFAnalysisJob

# --- Stroke ------------------------------------------------------------------
var _stroking := false
var _stroke_stamps: Array = []
var _stroke_accum: float = 0.0
var _cursor_world := Vector3.ZERO
var _cursor_valid := false
var _last_pick_grid := Vector2.ZERO


func _ready() -> void:
	name = "TerraForge"
	theme = TFThemeBuilder.build()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_layout()

	analysis_job = TFAnalysisJob.new()
	add_child(analysis_job)
	analysis_job.started.connect(_on_analysis_started)
	analysis_job.progress.connect(_on_analysis_progress)
	analysis_job.finished.connect(_on_analysis_finished)
	analysis_job.cancelled.connect(func(): status_bar.set_busy(false, ""))

	playback.changed.connect(_on_playback_changed)

	new_project()
	get_viewport().size_changed.connect(_on_window_resized)
	_on_window_resized()
	set_process(true)


# =============================================================================
#  Layout
# =============================================================================
func _build_layout() -> void:
	var bg := ColorRect.new()
	bg.color = TFPalette.BG_DEEP
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 1)
	add_child(root)

	top_bar = TFTopBar.new()
	top_bar.bind(self)
	root.add_child(top_bar)

	main_split = HBoxContainer.new()
	main_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_split.add_theme_constant_override("separation", 1)
	root.add_child(main_split)

	# --- left column ---------------------------------------------------------
	left_holder = PanelContainer.new()
	left_holder.custom_minimum_size = Vector2(264, 0)
	left_holder.add_theme_stylebox_override("panel", _panel_style())
	main_split.add_child(left_holder)
	tool_panel = TFToolPanel.new()
	tool_panel.bind(self)
	left_holder.add_child(tool_panel)

	# --- centre --------------------------------------------------------------
	var centre := VBoxContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.size_flags_stretch_ratio = 3.0
	centre.add_theme_constant_override("separation", 1)
	main_split.add_child(centre)

	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.clip_contents = true
	centre.add_child(stack)

	viewport_container = SubViewportContainer.new()
	viewport_container.stretch = true
	viewport_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(viewport_container)

	subviewport = SubViewport.new()
	subviewport.own_world_3d = true
	subviewport.handle_input_locally = false
	subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	subviewport.msaa_3d = Viewport.MSAA_2X
	viewport_container.add_child(subviewport)
	_build_world()

	input_overlay = Control.new()
	input_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	input_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	input_overlay.focus_mode = Control.FOCUS_ALL
	input_overlay.gui_input.connect(_on_viewport_input)
	input_overlay.mouse_exited.connect(func(): _cursor_valid = false; _update_brush_ring())
	stack.add_child(input_overlay)

	hud = TFViewportHud.new()
	hud.bind(self)
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(hud)

	playback_bar = TFPlaybackBar.new()
	playback_bar.bind(self)
	centre.add_child(playback_bar)

	# --- right column --------------------------------------------------------
	right_holder = PanelContainer.new()
	right_holder.custom_minimum_size = Vector2(360, 0)
	right_holder.add_theme_stylebox_override("panel", _panel_style())
	main_split.add_child(right_holder)
	inspector = TFInspector.new()
	inspector.bind(self)
	right_holder.add_child(inspector)

	status_bar = TFStatusBar.new()
	status_bar.bind(self)
	root.add_child(status_bar)


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = TFPalette.BG_PANEL
	sb.border_color = TFPalette.BORDER
	sb.border_width_left = 1
	sb.border_width_right = 1
	return sb


func _build_world() -> void:
	var world := Node3D.new()
	world.name = "World"
	subviewport.add_child(world)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#10131a")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#5c6878")
	e.ambient_light_energy = 0.55
	e.fog_enabled = true
	e.fog_light_color = Color("#10131a")
	e.fog_density = 0.0009
	env.environment = e
	world.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.15
	sun.light_color = Color("#fff2e0")
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	sun.shadow_enabled = true
	world.add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.30
	fill.light_color = Color("#9fb6d0")
	fill.rotation_degrees = Vector3(-24.0, 140.0, 0.0)
	world.add_child(fill)

	terrain_view = TFTerrainView.new()
	world.add_child(terrain_view)

	overlays = TFOverlays.new()
	world.add_child(overlays)

	brush_ring = MeshInstance3D.new()
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = TFPalette.SURVEY_ORANGE
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.no_depth_test = true
	brush_ring.material_override = ring_mat
	world.add_child(brush_ring)

	camera_rig = TFCameraRig.new()
	world.add_child(camera_rig)


# =============================================================================
#  Document lifecycle
# =============================================================================
func new_project() -> void:
	_disconnect_project()
	project = TFProject.create_default(121, 121, 2.0, 0.0)
	_connect_project()
	analysis = null
	sequence = null
	playback.set_sequence(null)
	set_mode(Mode.EDIT)
	terrain_view.set_surfaces(project.proposed, project.existing)
	camera_rig.frame_site(project.existing)
	_refresh_overlays()
	project_changed.emit()
	analysis_changed.emit()
	sequence_changed.emit()
	status_bar.flash("New project: flat site %s at assumed elevation %s." % [
		project.settings.units.fmt_area(project.settings.site_area_m2()),
		project.settings.units.fmt_length(project.settings.assumed_elevation_m, 2)])
	request_analysis()


func adopt_project(p: TFProject, seq: TFSequence = null) -> void:
	_disconnect_project()
	project = p
	_connect_project()
	analysis = null
	sequence = seq
	playback.set_sequence(seq)
	set_mode(Mode.EDIT)
	terrain_view.set_surfaces(project.proposed, project.existing)
	camera_rig.frame_site(project.existing)
	_refresh_overlays()
	project_changed.emit()
	analysis_changed.emit()
	sequence_changed.emit()
	request_analysis()


func _connect_project() -> void:
	project.terrain_changed.connect(_on_terrain_changed)
	project.structure_changed.connect(_on_structure_changed)


func _disconnect_project() -> void:
	if project == null:
		return
	if project.terrain_changed.is_connected(_on_terrain_changed):
		project.terrain_changed.disconnect(_on_terrain_changed)
	if project.structure_changed.is_connected(_on_structure_changed):
		project.structure_changed.disconnect(_on_structure_changed)


func _on_terrain_changed(bounds: Vector4i) -> void:
	if mode == Mode.PLAYBACK:
		return
	terrain_view.set_surfaces(project.proposed, project.existing)
	if bounds.z >= bounds.x:
		terrain_view.mark_region_dirty(bounds)
	else:
		terrain_view.mark_all_dirty()


func _on_structure_changed() -> void:
	_refresh_overlays()
	project_changed.emit()
	if not project.is_stroking():
		request_analysis()


# =============================================================================
#  Mode
# =============================================================================
func set_mode(m: Mode) -> void:
	if mode == m:
		return
	if m == Mode.PLAYBACK and not playback.has_sequence():
		status_bar.flash("Generate a construction sequence before entering playback.", "warning")
		return
	mode = m
	if mode == Mode.PLAYBACK:
		_construction_surface.prepare(project.existing, project.sculpt, project.proposed,
			project.assumptions.topsoil_depth_m)
		_playback_field = project.existing.clone()
		terrain_view.set_surfaces(_playback_field, project.existing)
		playback.seek_hours(0.0)
		_apply_playback_state()
	else:
		playback.pause()
		_playback_field = null
		terrain_view.set_surfaces(project.proposed, project.existing)
		_refresh_overlays()
	mode_changed.emit()


func in_playback() -> bool:
	return mode == Mode.PLAYBACK


# =============================================================================
#  Analysis
# =============================================================================
func request_analysis(immediate: bool = false) -> void:
	if project == null or project.existing == null:
		return
	if immediate:
		analysis_job.request_now(project.analysis_inputs())
	else:
		analysis_job.request(project.analysis_inputs())


func _on_analysis_started() -> void:
	status_bar.set_busy(true, "Analysing surfaces...")


func _on_analysis_progress(f: float) -> void:
	status_bar.set_progress(f)


func _on_analysis_finished(result: TFAnalysis) -> void:
	analysis = result
	status_bar.set_busy(false, "")
	var depth: float = maxf(result.max_cut_depth_m, result.max_fill_depth_m)
	terrain_view.set_cut_fill_scale(maxf(1.0, depth))
	analysis_changed.emit()


func generate_sequence() -> void:
	if analysis == null:
		status_bar.flash("Run the analysis first.", "warning")
		return
	sequence = TFSequenceGenerator.generate(analysis, project.assumptions,
		project.road, project.tower)
	playback.set_sequence(sequence)
	sequence_changed.emit()
	status_bar.flash("Construction sequence generated: %d applicable steps, %s." % [
		sequence.applicable_steps().size(),
		_duration_text(sequence.total_duration_hours)])


func _duration_text(hours: float) -> String:
	if sequence == null:
		return "%.1f h" % hours
	return "%.1f h (%.1f workdays)" % [hours, hours / maxf(0.5, sequence.workday_hours)]


# =============================================================================
#  Viewport input
# =============================================================================
func _on_viewport_input(event: InputEvent) -> void:
	if project == null:
		return
	var vsize := input_overlay.size
	if camera_rig.handle_input(event, vsize):
		_update_cursor_from_last()
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				input_overlay.grab_focus()
				_begin_stroke(mb.position)
			else:
				_end_stroke()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_pick(mm.position)
		if _stroking:
			_continue_stroke()


func _pick(screen_pos: Vector2) -> void:
	var field := terrain_view.surface()
	if field == null:
		_cursor_valid = false
		return
	var ray := camera_rig.ray_from(_to_viewport(screen_pos))
	var hit := TFRayPick.cast(field, ray["origin"], ray["direction"])
	_cursor_valid = bool(hit["hit"])
	if _cursor_valid:
		_cursor_world = hit["position"]
		_last_pick_grid = hit["grid"]
	_update_brush_ring()
	hud.update_cursor(_cursor_valid, _cursor_world, field, project)


## The overlay and the SubViewport are the same size (stretch = true), so the
## position maps straight through; this exists so the assumption is stated once.
func _to_viewport(p: Vector2) -> Vector2:
	return p


func _update_cursor_from_last() -> void:
	_update_brush_ring()


func _begin_stroke(screen_pos: Vector2) -> void:
	if in_playback():
		status_bar.flash("Leave Construction Playback to edit the terrain.", "warning")
		return
	_pick(screen_pos)
	if not _cursor_valid:
		return
	if brush_mode == TFBrush.Mode.FLATTEN and flatten_pick_from_terrain:
		flatten_target = _cursor_world.y
		tool_panel.refresh_flatten_target()
	_stroking = true
	_stroke_stamps = []
	_stroke_accum = STROKE_INTERVAL
	project.begin_live_stroke()
	_continue_stroke()


func _continue_stroke() -> void:
	if not _stroking or not _cursor_valid:
		return
	if _stroke_accum < STROKE_INTERVAL:
		return
	var dt := _stroke_accum
	_stroke_accum = 0.0
	var stamp := TFBrush.make_stamp(
		Vector2(_cursor_world.x, _cursor_world.z),
		brush_radius, brush_strength, dt, flatten_target)
	_stroke_stamps.append(stamp)
	var b := project.live_stamp(brush_mode, stamp)
	if b.z >= b.x:
		terrain_view.mark_region_dirty(b)


func _end_stroke() -> void:
	if not _stroking:
		return
	_stroking = false
	if _stroke_stamps.is_empty():
		project.cancel_live_stroke()
		return
	project.commit_live_stroke(brush_mode, _stroke_stamps)
	_stroke_stamps = []
	terrain_view.mark_all_dirty()
	request_analysis()


func _process(delta: float) -> void:
	if _stroking:
		_stroke_accum += delta
		_continue_stroke()
	if mode == Mode.PLAYBACK and playback.playing:
		playback.advance(delta)


# --- Brush cursor ------------------------------------------------------------
func _update_brush_ring() -> void:
	if brush_ring == null:
		return
	var show := _cursor_valid and not in_playback()
	brush_ring.visible = show
	if not show:
		return
	var field := terrain_view.surface()
	var st := SurfaceTool.new()
	# Two separate rings, so PRIMITIVE_LINES rather than a strip: a strip would
	# draw a stray segment joining the end of one ring to the start of the next.
	st.begin(Mesh.PRIMITIVE_LINES)
	var centre := Vector2(_cursor_world.x, _cursor_world.z)
	# The outer ring is the brush edge; the inner one marks the full-strength
	# core of the falloff, so the user can see where the tool bites hardest.
	_ring(st, field, centre, brush_radius)
	_ring(st, field, centre, brush_radius * 0.4)
	brush_ring.mesh = st.commit()


func _ring(st: SurfaceTool, field: TFHeightfield, centre: Vector2, radius: float) -> void:
	var segments := 72
	var prev := Vector3.ZERO
	for i in range(segments + 1):
		var a := TAU * float(i) / float(segments)
		var p := centre + Vector2(cos(a), sin(a)) * radius
		var v := Vector3(p.x, field.sample(p) + 0.25, p.y)
		if i > 0:
			st.add_vertex(prev)
			st.add_vertex(v)
		prev = v


func set_brush_radius(v: float) -> void:
	brush_radius = clampf(v, 1.0, 120.0)
	_update_brush_ring()


func set_brush_strength(v: float) -> void:
	brush_strength = maxf(0.0, v)


func set_brush_mode(m: TFBrush.Mode) -> void:
	brush_mode = m
	tool_panel.refresh_tool_buttons()
	hud.refresh()


# =============================================================================
#  Overlays
# =============================================================================
func _refresh_overlays() -> void:
	if overlays == null or project == null:
		return
	if in_playback():
		return
	overlays.clear_construction()
	overlays.set_road(project.road, project.proposed, project.road != null)
	overlays.set_tower(project.tower, project.proposed, project.tower != null, 1.0)


# =============================================================================
#  Playback
# =============================================================================
func _on_playback_changed() -> void:
	if mode != Mode.PLAYBACK:
		return
	_apply_playback_state()


func _apply_playback_state() -> void:
	if _playback_field == null or not _construction_surface.is_ready():
		return
	var state := playback.state()
	if _construction_surface.evaluate(state, _playback_buffer):
		_playback_field.heights = _playback_buffer.duplicate()
		terrain_view.mark_all_dirty()
	_apply_playback_visuals(state)
	playback_bar.refresh()
	inspector.refresh_playback()


## Everything shown during playback is derived from the CURRENT STEP'S data.
## No visual here is prerecorded, and none of it feeds a quantity.
func _apply_playback_visuals(state: Dictionary) -> void:
	var step := playback.current_step()
	if step == null:
		overlays.clear_construction()
		return
	var vis: Dictionary = step.visual
	var field := _playback_field

	overlays.set_ghost(project.proposed, true)
	overlays.set_zone(String(vis.get("highlight", "site")), project, field)
	overlays.set_stakes(_stake_points() if bool(vis.get("stakes", false)) else PackedVector2Array(),
		field, bool(vis.get("stakes", false)))
	overlays.set_erosion_fence(field, bool(vis.get("erosion_fence", false)))
	overlays.set_temp_access(project.road, field, bool(vis.get("temp_access", false)))

	var stockpile_v := 0.0
	if bool(vis.get("stockpile", false)) and analysis != null:
		stockpile_v = maxf(analysis.disturbed_area_m2 * project.assumptions.topsoil_depth_m * 0.35, 40.0)
	overlays.set_stockpile(_stockpile_at(), stockpile_v, field, stockpile_v > 0.0)

	var truck_count := int(vis.get("trucks", 0))
	overlays.set_trucks(_truck_points(truck_count), field, truck_count > 0)
	overlays.set_haul_arrows(_haul_path(), field, truck_count > 0)

	var machines: Array = vis.get("machines", [])
	var pts := PackedVector2Array()
	var colour := TFPalette.CONSTRUCTION_YELLOW
	for m in machines:
		colour = TFEquipment.color(String(m.get("key", "")))
		pts.append_array(_machine_points(String(m.get("motion", "area")), int(m.get("count", 1))))
	overlays.set_machines(pts, field, pts.size() > 0, colour)

	var road_progress: float = clampf(float(state.get("form", 0.0)) / 0.7, 0.0, 1.0)
	overlays.set_road(project.road, field, project.road != null and road_progress > 0.02, road_progress)
	overlays.set_tower(project.tower, field, project.tower != null and float(state.get("tower", 0.0)) > 0.01,
		float(state.get("tower", 0.0)))


## Proposed stakeout locations on a coarse grid over the disturbed area, plus
## the road centreline. Labelled as PROPOSED everywhere they are shown.
func _stake_points() -> PackedVector2Array:
	var out := PackedVector2Array()
	var f := project.proposed
	var e := project.existing
	var stride := 8
	for r in range(0, f.rows, stride):
		for c in range(0, f.cols, stride):
			if absf(f.get_h(c, r) - e.get_h(c, r)) > 0.25:
				out.append(f.node_position(c, r))
	if project.road != null and project.road.is_valid():
		var pts := project.road.centerline()
		var k := 0
		while k < pts.size():
			out.append(pts[k])
			k += 6
	return out


func _stockpile_at() -> Vector2:
	var mn := project.existing.aabb_min()
	var mx := project.existing.aabb_max()
	return Vector2(lerpf(mn.x, mx.x, 0.12), lerpf(mn.y, mx.y, 0.12))


## Trucks ride the alignment when there is one, otherwise the site diagonal.
func _haul_path() -> PackedVector2Array:
	if project.road != null and project.road.is_valid():
		return project.road.centerline()
	var mn := project.existing.aabb_min()
	var mx := project.existing.aabb_max()
	var out := PackedVector2Array()
	for i in 20:
		out.append(mn.lerp(mx, float(i) / 19.0))
	return out


func _truck_points(count: int) -> PackedVector2Array:
	var path := _haul_path()
	var out := PackedVector2Array()
	if path.size() < 2 or count <= 0:
		return out
	# Trucks are spaced along the haul path and advance with the timeline, so
	# the motion is a readout of schedule position, not a free-running loop.
	var t := playback.fraction()
	for i in count:
		var f := fposmod(t * 3.0 + float(i) / float(count), 1.0)
		var idx: int = clampi(int(f * float(path.size() - 1)), 0, path.size() - 1)
		out.append(path[idx])
	return out


func _machine_points(motion: String, count: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var t := playback.fraction()
	match motion:
		"corridor":
			var path := _haul_path()
			if path.size() < 2:
				return out
			for i in count:
				var f := fposmod(t * 2.0 + float(i) * 0.37, 1.0)
				out.append(path[clampi(int(f * float(path.size() - 1)), 0, path.size() - 1)])
		"pad":
			if project.tower != null:
				var c := project.tower.position_xz
				for i in count:
					var a := TAU * (t * 1.5 + float(i) / float(maxi(1, count)))
					out.append(c + Vector2(cos(a), sin(a)) * project.tower.pad_size_m * 0.35)
		_:
			var mn := project.existing.aabb_min()
			var mx := project.existing.aabb_max()
			var centre := (mn + mx) * 0.5
			var span: float = minf(mx.x - mn.x, mx.y - mn.y) * 0.3
			for i in count:
				var a2 := TAU * (t * 1.2 + float(i) / float(maxi(1, count)))
				out.append(centre + Vector2(cos(a2) * span, sin(a2 * 1.3) * span))
	return out


func set_reduced_motion(on: bool) -> void:
	reduced_motion = on
	playback.reduced_motion = on
	status_bar.flash("Reduced motion %s." % ("on: playback advances in step jumps" if on else "off"))


# =============================================================================
#  Responsive layout
# =============================================================================
func _on_window_resized() -> void:
	var w := size.x
	if w <= 1.0:
		w = float(get_viewport_rect().size.x)
	var narrow := w < NARROW_WIDTH
	# Below the narrow threshold the left column collapses to icons-plus-labels
	# in a scrolling strip and the inspector loses its minimum width, so the 3D
	# canvas keeps a usable share of a small laptop screen.
	left_holder.custom_minimum_size.x = 208.0 if narrow else 264.0
	right_holder.custom_minimum_size.x = 268.0 if narrow else 360.0
	if tool_panel != null:
		tool_panel.set_compact(narrow)
	if inspector != null:
		inspector.set_compact(narrow)
	if hud != null:
		hud.set_compact(narrow)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.ctrl_pressed and k.keycode == KEY_Z:
			if k.shift_pressed:
				redo()
			else:
				undo()
			get_viewport().set_input_as_handled()
		elif k.ctrl_pressed and k.keycode == KEY_Y:
			redo()
			get_viewport().set_input_as_handled()
		elif k.ctrl_pressed and k.keycode == KEY_S:
			top_bar.save_project()
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_HOME:
			camera_rig.frame_site(terrain_view.surface())
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_SPACE and mode == Mode.PLAYBACK:
			playback.toggle()
			get_viewport().set_input_as_handled()


func undo() -> void:
	if project.can_undo():
		var label := project.undo_label()
		project.undo()
		terrain_view.set_surfaces(project.proposed, project.existing)
		_refresh_overlays()
		project_changed.emit()
		request_analysis()
		status_bar.flash("Undid: %s" % label)
	else:
		status_bar.flash("Nothing left to undo.", "warning")


func redo() -> void:
	if project.can_redo():
		var label := project.redo_label()
		project.redo()
		terrain_view.set_surfaces(project.proposed, project.existing)
		_refresh_overlays()
		project_changed.emit()
		request_analysis()
		status_bar.flash("Redid: %s" % label)
	else:
		status_bar.flash("Nothing left to redo.", "warning")


func units() -> TFUnitSystem:
	return project.settings.units


func validation_issues() -> Array[Dictionary]:
	if project == null:
		return []
	return TFValidation.all(project, analysis)
