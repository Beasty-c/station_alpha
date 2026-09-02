class_name TFProject
extends RefCounted

## The document. Engine-light: no nodes, no viewport, no frame rate.
##
## State model (Onshape-flavoured, local):
##   existing  - the immutable original ground. Written once, by
##               CreateFlatTerrain, and never touched again.
##   sculpt    - the surface produced by replaying the terrain operations.
##   proposed  - DERIVED: sculpt with the tower pad and then the road corridor
##               applied on top. Recomputed whenever anything upstream changes,
##               which is what makes road width / grade genuinely parametric.
##
## Undo/redo moves `cursor` through `ops` and re-derives. Snapshots of `sculpt`
## are taken every SNAPSHOT_EVERY operations so replay stays cheap.

signal terrain_changed(bounds: Vector4i)   # inclusive node window, or full grid
signal structure_changed()                 # features / assumptions / history

const SNAPSHOT_EVERY := 10

var settings: TFProjectSettings = TFProjectSettings.new()
var assumptions: TFAssumptions = TFAssumptions.new()

var existing: TFHeightfield = null
var sculpt: TFHeightfield = null
var proposed: TFHeightfield = null

var road: TFRoad = null
var tower: TFTower = null

var ops: Array[TFOperation] = []
var cursor: int = 0                        # number of applied operations
var dirty_since_save: bool = false
var file_path: String = ""

var _snapshots: Dictionary = {}            # cursor -> PackedFloat32Array


# --- Construction ------------------------------------------------------------
static func create_default(cols: int = 121, rows: int = 121, spacing: float = 2.0,
		elevation: float = 0.0) -> TFProject:
	var p := TFProject.new()
	p.settings = TFProjectSettings.new()
	p.settings.site_cols = cols
	p.settings.site_rows = rows
	p.settings.site_spacing_m = spacing
	p.settings.site_origin = Vector2(-0.5 * float(cols - 1) * spacing, -0.5 * float(rows - 1) * spacing)
	p.settings.assumed_elevation_m = elevation
	p.push_operation(TFOperation.make(TFOperation.CREATE_FLAT_TERRAIN, {
		"cols": cols, "rows": rows, "spacing": spacing,
		"origin": [p.settings.site_origin.x, p.settings.site_origin.y],
		"elevation": elevation,
	}))
	p.dirty_since_save = false
	return p


# --- History -----------------------------------------------------------------
func can_undo() -> bool:
	return cursor > 1     # CreateFlatTerrain is never undone


func can_redo() -> bool:
	return cursor < ops.size()


func undo() -> bool:
	if not can_undo():
		return false
	cursor -= 1
	_rebuild()
	dirty_since_save = true
	structure_changed.emit()
	return true


func redo() -> bool:
	if not can_redo():
		return false
	cursor += 1
	_rebuild()
	dirty_since_save = true
	structure_changed.emit()
	return true


func undo_label() -> String:
	if not can_undo():
		return ""
	return ops[cursor - 1].label


func redo_label() -> String:
	if not can_redo():
		return ""
	return ops[cursor].label


## Append an operation at the cursor, discarding any redo tail.
func push_operation(op: TFOperation) -> void:
	if cursor < ops.size():
		ops.resize(cursor)
		var stale: Array = []
		for k in _snapshots.keys():
			if int(k) > cursor:
				stale.append(k)
		for k in stale:
			_snapshots.erase(k)
	ops.append(op)
	cursor = ops.size()
	settings.touch()
	dirty_since_save = true
	var bounds := _apply(op)
	_maybe_snapshot()
	_rederive(bounds)
	structure_changed.emit()


func history() -> Array[TFOperation]:
	return ops


## Rebuild the whole document by replaying operations, using the newest terrain
## snapshot at or before the cursor as a shortcut.
##
## A snapshot stored under key `n` holds the sculpted surface AFTER the first
## `n` operations. So the replay runs in three phases, in this order:
##   1. operations before the snapshot, skipping the surface-only ones the
##      snapshot already accounts for (features, assumptions and settings are
##      cheap and are always replayed exactly);
##   2. adopt the snapshot surface;
##   3. replay every operation after the snapshot in full.
## Applying the snapshot last would discard phase 3 entirely.
func _rebuild() -> void:
	var best := 0
	for k in _snapshots.keys():
		var ki := int(k)
		if ki <= cursor and ki > best:
			best = ki

	road = null
	tower = null
	assumptions = TFAssumptions.new()
	existing = null
	sculpt = null

	var resume: int = mini(best, cursor)

	for i in range(resume):
		var op := ops[i]
		if op.is_surface_only_op():
			continue
		_apply(op)

	if best > 0 and sculpt != null and _snapshots.has(best):
		var snap := _snapshots[best] as PackedFloat32Array
		if snap.size() == sculpt.heights.size():
			sculpt.heights = snap.duplicate()
		else:
			# The grid changed under the snapshot; fall back to a full replay
			# rather than pasting a mismatched buffer.
			push_warning("TerraForge: discarding a terrain snapshot that no longer matches the grid.")
			_snapshots.erase(best)
			resume = 0
			road = null
			tower = null
			assumptions = TFAssumptions.new()
			existing = null
			sculpt = null

	for i in range(resume, cursor):
		_apply(ops[i])

	_rederive(Vector4i(0, 0, -1, -1))


func _maybe_snapshot() -> void:
	if sculpt == null:
		return
	if cursor % SNAPSHOT_EVERY == 0:
		_snapshots[cursor] = sculpt.heights.duplicate()


# --- Operation dispatch ------------------------------------------------------
## Applies one operation to the state. Returns the inclusive node window
## touched on `sculpt`, or an empty window when nothing local changed.
func _apply(op: TFOperation) -> Vector4i:
	var p := op.params
	match op.type:
		TFOperation.CREATE_FLAT_TERRAIN:
			var cols := int(p.get("cols", 121))
			var rows := int(p.get("rows", 121))
			var spacing := float(p.get("spacing", 2.0))
			var o: Array = p.get("origin", [0.0, 0.0])
			var origin := Vector2(float(o[0]), float(o[1])) if o.size() >= 2 else Vector2.ZERO
			var elev := float(p.get("elevation", 0.0))
			existing = TFHeightfield.create_flat(cols, rows, spacing, elev, origin)
			sculpt = existing.clone()
			settings.site_cols = cols
			settings.site_rows = rows
			settings.site_spacing_m = spacing
			settings.site_origin = origin
			settings.assumed_elevation_m = elev
			return Vector4i(0, 0, -1, -1)

		TFOperation.RAISE_TERRAIN:
			return TFBrush.apply_stroke(sculpt, TFBrush.Mode.RAISE, p.get("stamps", []))
		TFOperation.LOWER_TERRAIN:
			return TFBrush.apply_stroke(sculpt, TFBrush.Mode.LOWER, p.get("stamps", []))
		TFOperation.SMOOTH_REGION:
			return TFBrush.apply_stroke(sculpt, TFBrush.Mode.SMOOTH, p.get("stamps", []))
		TFOperation.FLATTEN_REGION:
			return TFBrush.apply_stroke(sculpt, TFBrush.Mode.FLATTEN, p.get("stamps", []))

		TFOperation.RESET_TERRAIN:
			if existing != null:
				sculpt = existing.clone()
			return Vector4i(0, 0, -1, -1)

		TFOperation.GENERATE_SAMPLE_SITE:
			if existing != null:
				sculpt = existing.clone()
				TFSampleSite.sculpt(sculpt, p)
				road = TFSampleSite.road(sculpt, p)
				tower = TFSampleSite.tower(sculpt, p)
			return Vector4i(0, 0, -1, -1)

		TFOperation.ADD_ROAD_ALIGNMENT, TFOperation.UPDATE_ROAD_ALIGNMENT:
			road = TFRoad.from_dict(p.get("road", {}))
			return Vector4i(0, 0, -1, -1)
		TFOperation.REMOVE_ROAD_ALIGNMENT:
			road = null
			return Vector4i(0, 0, -1, -1)

		TFOperation.PLACE_TOWER, TFOperation.UPDATE_TOWER:
			tower = TFTower.from_dict(p.get("tower", {}))
			return Vector4i(0, 0, -1, -1)
		TFOperation.REMOVE_TOWER:
			tower = null
			return Vector4i(0, 0, -1, -1)

		TFOperation.CHANGE_ESTIMATE_ASSUMPTION:
			var key := String(p.get("key", ""))
			if key != "" and key in assumptions:
				var cur = assumptions.get(key)
				var v = p.get("value")
				if cur is int:
					assumptions.set(key, int(v))
				elif cur is float:
					assumptions.set(key, float(v))
				elif cur is String:
					assumptions.set(key, String(v))
				if key == "soil_type":
					assumptions.apply_soil_preset(String(v))
			return Vector4i(0, 0, -1, -1)

		TFOperation.CHANGE_PROJECT_SETTING:
			var k := String(p.get("key", ""))
			var val = p.get("value")
			match k:
				"project_name": settings.project_name = String(val)
				"author": settings.author = String(val)
				"notes": settings.notes = String(val)
				"length_unit": settings.units.set_length_unit(String(val))
				"volume_unit": settings.units.set_volume_unit(String(val))
				"coordinate_system_label": settings.coordinate_system_label = String(val)
				"horizontal_datum": settings.horizontal_datum = String(val)
				"vertical_datum": settings.vertical_datum = String(val)
			return Vector4i(0, 0, -1, -1)
	return Vector4i(0, 0, -1, -1)


# --- Derived surface ---------------------------------------------------------
## Rebuild `proposed` from `sculpt` + tower pad + road corridor.
## `hint` is the sculpt-space window that changed; features can widen it.
func _rederive(hint: Vector4i) -> void:
	if sculpt == null:
		return
	proposed = sculpt.clone()
	var touched := hint
	if tower != null:
		var elev := tower.resolve_pad_elevation(sculpt)
		var b := tower.apply_to(proposed, elev)
		touched = _union(touched, b)
	if road != null and road.is_valid():
		var b2 := road.apply_to(proposed)
		touched = _union(touched, b2)
	if touched.z < touched.x:
		touched = proposed.full_bounds()
	terrain_changed.emit(touched)


static func _union(a: Vector4i, b: Vector4i) -> Vector4i:
	if b.z < b.x:
		return a
	if a.z < a.x:
		return b
	return Vector4i(mini(a.x, b.x), mini(a.y, b.y), maxi(a.z, b.z), maxi(a.w, b.w))


## Force a full re-derive, e.g. after a road parameter edit made outside an op.
func rederive_all() -> void:
	_rederive(Vector4i(0, 0, -1, -1))


# --- Live stroke preview -----------------------------------------------------
## While the pointer is down the user must see the ground move, but the history
## must still contain exactly ONE operation for the whole stroke.
##
## So the preview edits the surface directly, and on commit the surface is
## rewound to where the stroke began and the operation is replayed from its
## recorded stamps. The committed state is therefore produced by the same code
## path as a reload or an undo/redo, and cannot drift from it.

var _stroke_backup: PackedFloat32Array = PackedFloat32Array()
var _stroke_active: bool = false


func begin_live_stroke() -> void:
	if sculpt == null:
		return
	_stroke_backup = sculpt.heights.duplicate()
	_stroke_active = true


func live_stamp(mode: TFBrush.Mode, stamp: Dictionary) -> Vector4i:
	if not _stroke_active or sculpt == null:
		return Vector4i(0, 0, -1, -1)
	var b := TFBrush.apply_stamp(sculpt, mode, stamp)
	if b.z >= b.x:
		_rederive(b)
	return b


func commit_live_stroke(mode: TFBrush.Mode, stamps: Array) -> void:
	if not _stroke_active:
		return
	_stroke_active = false
	if sculpt != null and _stroke_backup.size() == sculpt.heights.size():
		sculpt.heights = _stroke_backup
	_stroke_backup = PackedFloat32Array()
	if stamps.is_empty():
		_rederive(Vector4i(0, 0, -1, -1))
		return
	apply_stroke(mode, stamps)


func cancel_live_stroke() -> void:
	if not _stroke_active:
		return
	_stroke_active = false
	if sculpt != null and _stroke_backup.size() == sculpt.heights.size():
		sculpt.heights = _stroke_backup
	_stroke_backup = PackedFloat32Array()
	_rederive(Vector4i(0, 0, -1, -1))


func is_stroking() -> bool:
	return _stroke_active


# --- Convenience mutators (each records exactly one operation) ---------------
func apply_stroke(mode: TFBrush.Mode, stamps: Array) -> void:
	if stamps.is_empty():
		return
	var type := TFOperation.RAISE_TERRAIN
	match mode:
		TFBrush.Mode.LOWER: type = TFOperation.LOWER_TERRAIN
		TFBrush.Mode.SMOOTH: type = TFOperation.SMOOTH_REGION
		TFBrush.Mode.FLATTEN: type = TFOperation.FLATTEN_REGION
	var params := {"stamps": stamps}
	if mode == TFBrush.Mode.FLATTEN and stamps.size() > 0:
		params["target"] = float(stamps[0].get("target", 0.0))
	push_operation(TFOperation.make(type, params))


func reset_terrain() -> void:
	push_operation(TFOperation.make(TFOperation.RESET_TERRAIN, {}))


func generate_sample_site(params: Dictionary = {}) -> void:
	push_operation(TFOperation.make(TFOperation.GENERATE_SAMPLE_SITE,
		TFSampleSite.params_with_defaults(params)))


func set_road(r: TFRoad) -> void:
	var type := TFOperation.UPDATE_ROAD_ALIGNMENT if road != null else TFOperation.ADD_ROAD_ALIGNMENT
	push_operation(TFOperation.make(type, {"road": r.to_dict()}))


func remove_road() -> void:
	if road == null:
		return
	push_operation(TFOperation.make(TFOperation.REMOVE_ROAD_ALIGNMENT, {}))


func set_tower(t: TFTower) -> void:
	var type := TFOperation.UPDATE_TOWER if tower != null else TFOperation.PLACE_TOWER
	push_operation(TFOperation.make(type, {"tower": t.to_dict()}))


func remove_tower() -> void:
	if tower == null:
		return
	push_operation(TFOperation.make(TFOperation.REMOVE_TOWER, {}))


func change_assumption(key: String, value) -> void:
	push_operation(TFOperation.make(TFOperation.CHANGE_ESTIMATE_ASSUMPTION,
		{"key": key, "value": value}))


func change_setting(key: String, value) -> void:
	push_operation(TFOperation.make(TFOperation.CHANGE_PROJECT_SETTING,
		{"key": key, "value": value}))


# --- Analysis ----------------------------------------------------------------
func analyze(progress: Callable = Callable(), is_cancelled: Callable = Callable()) -> TFAnalysis:
	return TFEarthworks.analyze(existing, proposed, assumptions, road, tower, progress, is_cancelled)


## Snapshot of the inputs an analysis needs, safe to hand to a worker thread.
func analysis_inputs() -> Dictionary:
	return {
		"existing": existing.clone() if existing != null else null,
		"proposed": proposed.clone() if proposed != null else null,
		"assumptions": assumptions.duplicate_assumptions(),
		"road": TFRoad.from_dict(road.to_dict()) if road != null else null,
		"tower": TFTower.from_dict(tower.to_dict()) if tower != null else null,
	}
