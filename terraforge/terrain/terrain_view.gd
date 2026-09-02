class_name TFTerrainView
extends Node3D

## Tiled renderer for a TFHeightfield.
##
## The mesh is a VIEW. It never stores terrain: every vertex is read from the
## authoritative heightfield each time a tile is rebuilt, and nothing here ever
## writes back into the model.
##
## Partial updates: the project reports the inclusive node window an operation
## touched, and only the tiles overlapping that window are marked dirty. Dirty
## tiles are rebuilt over subsequent frames under a budget, so a fast brush
## drag never stalls the main thread rebuilding the whole site.

const TILE_CELLS := 20          # cells per tile edge
const REBUILD_BUDGET_MS := 6.0  # per frame, main thread

enum Mode { PROPOSED, EXISTING, CUT_FILL, SLOPE, ELEVATION }

const MODE_NAMES := {
	Mode.PROPOSED: "Proposed",
	Mode.EXISTING: "Existing",
	Mode.CUT_FILL: "Cut / fill",
	Mode.SLOPE: "Slope",
	Mode.ELEVATION: "Elevation",
}

## Plain-language description shown beside the legend, so the display mode is
## never conveyed by colour alone.
const MODE_HELP := {
	Mode.PROPOSED: "The design surface as it would be built.",
	Mode.EXISTING: "The original ground before any earthwork.",
	Mode.CUT_FILL: "Blue where material is removed, red where it is added.",
	Mode.SLOPE: "Green is gentle, yellow is steep, red is steeper than 1:1.",
	Mode.ELEVATION: "Low ground dark, high ground light.",
}

signal rebuilt(tiles: int)

var mode: Mode = Mode.PROPOSED

var _surface: TFHeightfield = null      # what is drawn
var _existing: TFHeightfield = null     # reference for cut/fill shading
var _tiles: Array[MeshInstance3D] = []
var _tile_bounds: Array[Vector4i] = []
var _dirty: PackedByteArray = PackedByteArray()
var _dirty_count: int = 0
var _tiles_x: int = 0
var _tiles_y: int = 0
var _material: StandardMaterial3D = null
var _cut_fill_scale: float = 5.0


func _ready() -> void:
	set_process(true)
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 0.94
	_material.metallic = 0.0
	_material.cull_mode = BaseMaterial3D.CULL_BACK
	_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED


## Point the view at a pair of surfaces. Rebuilds the tile grid if the terrain
## dimensions changed; otherwise just marks everything dirty.
func set_surfaces(surface: TFHeightfield, existing: TFHeightfield) -> void:
	var reshape := _surface == null or surface == null \
		or _surface.cols != surface.cols or _surface.rows != surface.rows \
		or not is_equal_approx(_surface.spacing, surface.spacing) \
		or not _surface.origin.is_equal_approx(surface.origin)
	_surface = surface
	_existing = existing
	if surface == null:
		_clear_tiles()
		return
	if reshape:
		_build_tile_grid()
	mark_all_dirty()


func set_mode(m: Mode) -> void:
	if mode == m:
		return
	mode = m
	mark_all_dirty()


func mode_name() -> String:
	return String(MODE_NAMES.get(mode, "Proposed"))


func mode_help() -> String:
	return String(MODE_HELP.get(mode, ""))


func surface() -> TFHeightfield:
	return _surface


func tile_count() -> int:
	return _tiles.size()


func pending_tiles() -> int:
	return _dirty_count


# --- Dirty tracking ----------------------------------------------------------
func mark_all_dirty() -> void:
	for i in _dirty.size():
		if _dirty[i] == 0:
			_dirty[i] = 1
			_dirty_count += 1


## Mark the tiles overlapping an inclusive node window. Tiles share their edge
## nodes with their neighbours, so the window is widened by one node to keep
## the seams watertight.
func mark_region_dirty(b: Vector4i) -> void:
	if b.z < b.x or b.w < b.y or _tiles.is_empty():
		return
	var x0: int = maxi(0, (b.x - 1) / TILE_CELLS)
	var y0: int = maxi(0, (b.y - 1) / TILE_CELLS)
	var x1: int = mini(_tiles_x - 1, (b.z + 1) / TILE_CELLS)
	var y1: int = mini(_tiles_y - 1, (b.w + 1) / TILE_CELLS)
	for ty in range(y0, y1 + 1):
		for tx in range(x0, x1 + 1):
			var i := ty * _tiles_x + tx
			if i >= 0 and i < _dirty.size() and _dirty[i] == 0:
				_dirty[i] = 1
				_dirty_count += 1


func _process(_delta: float) -> void:
	if _dirty_count <= 0 or _surface == null:
		return
	var started := Time.get_ticks_usec()
	var done := 0
	for i in _tiles.size():
		if _dirty[i] == 0:
			continue
		_rebuild_tile(i)
		_dirty[i] = 0
		_dirty_count -= 1
		done += 1
		if float(Time.get_ticks_usec() - started) / 1000.0 >= REBUILD_BUDGET_MS:
			break
	if done > 0:
		rebuilt.emit(done)


## Rebuild every dirty tile immediately. Used before a screenshot or an export,
## where a partially updated view would be misleading.
func flush() -> void:
	if _surface == null:
		return
	for i in _tiles.size():
		if _dirty[i] != 0:
			_rebuild_tile(i)
			_dirty[i] = 0
	_dirty_count = 0


# --- Tile construction -------------------------------------------------------
func _clear_tiles() -> void:
	for t in _tiles:
		t.queue_free()
	_tiles.clear()
	_tile_bounds.clear()
	_dirty = PackedByteArray()
	_dirty_count = 0
	_tiles_x = 0
	_tiles_y = 0


func _build_tile_grid() -> void:
	_clear_tiles()
	var cells_x := _surface.cols - 1
	var cells_y := _surface.rows - 1
	_tiles_x = int(ceil(float(cells_x) / float(TILE_CELLS)))
	_tiles_y = int(ceil(float(cells_y) / float(TILE_CELLS)))
	_dirty.resize(_tiles_x * _tiles_y)
	_dirty.fill(0)
	for ty in _tiles_y:
		for tx in _tiles_x:
			var c0 := tx * TILE_CELLS
			var r0 := ty * TILE_CELLS
			var c1: int = mini(c0 + TILE_CELLS, cells_x)
			var r1: int = mini(r0 + TILE_CELLS, cells_y)
			var mi := MeshInstance3D.new()
			mi.name = "Tile_%d_%d" % [tx, ty]
			mi.material_override = _material
			add_child(mi)
			_tiles.append(mi)
			_tile_bounds.append(Vector4i(c0, r0, c1, r1))


func _rebuild_tile(index: int) -> void:
	var b := _tile_bounds[index]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var lo_hi := _elevation_range()
	for r in range(b.y, b.w):
		for c in range(b.x, b.z):
			# Two triangles, split along the shorter diagonal so the mesh
			# follows ridges and valleys instead of cutting across them.
			var h00 := _surface.get_h(c, r)
			var h10 := _surface.get_h(c + 1, r)
			var h01 := _surface.get_h(c, r + 1)
			var h11 := _surface.get_h(c + 1, r + 1)
			if absf(h00 - h11) <= absf(h10 - h01):
				_tri(st, c, r, c + 1, r + 1, c + 1, r, lo_hi)
				_tri(st, c, r, c, r + 1, c + 1, r + 1, lo_hi)
			else:
				_tri(st, c, r, c, r + 1, c + 1, r, lo_hi)
				_tri(st, c + 1, r, c, r + 1, c + 1, r + 1, lo_hi)

	st.generate_normals()
	_tiles[index].mesh = st.commit()


## Emits one triangle. Godot treats CLOCKWISE winding as front-facing, so the
## vertices go out in reverse of the natural (row, column) order - otherwise
## every normal points into the ground and the whole site renders back-faced.
func _tri(st: SurfaceTool, c0: int, r0: int, c1: int, r1: int, c2: int, r2: int, lo_hi: Vector2) -> void:
	_vertex(st, c0, r0, lo_hi)
	_vertex(st, c2, r2, lo_hi)
	_vertex(st, c1, r1, lo_hi)


func _vertex(st: SurfaceTool, c: int, r: int, lo_hi: Vector2) -> void:
	var p := _surface.node_position(c, r)
	var h := _surface.get_h(c, r)
	st.set_color(_color_at(c, r, h, lo_hi))
	st.add_vertex(Vector3(p.x, h, p.y))


func _elevation_range() -> Vector2:
	if _surface == null:
		return Vector2(0.0, 1.0)
	var mm := _surface.min_max()
	if mm.y - mm.x < 0.5:
		return Vector2(mm.x - 0.25, mm.x + 0.25)
	return mm


func _color_at(c: int, r: int, h: float, lo_hi: Vector2) -> Color:
	match mode:
		Mode.EXISTING:
			return TFPalette.GROUND_EXISTING
		Mode.CUT_FILL:
			if _existing == null:
				return TFPalette.NO_CHANGE
			return TFPalette.cut_fill_color(h - _existing.get_h(c, r), _cut_fill_scale)
		Mode.SLOPE:
			return TFPalette.slope_color(_surface.slope_ratio(c, r))
		Mode.ELEVATION:
			var span: float = maxf(0.001, lo_hi.y - lo_hi.x)
			return TFPalette.elevation_color((h - lo_hi.x) / span)
		_:
			# Proposed: a neutral ground tone lifted slightly by elevation, so
			# the landform reads without implying a data classification.
			var span2: float = maxf(0.001, lo_hi.y - lo_hi.x)
			var t: float = clampf((h - lo_hi.x) / span2, 0.0, 1.0)
			return Color("#6b7358").lerp(Color("#9aa085"), t * 0.85)


## The cut/fill ramp saturates at this depth. Set from the analysis so the
## legend and the shading always agree on what "deep" means.
func set_cut_fill_scale(metres: float) -> void:
	var s: float = maxf(0.5, metres)
	if is_equal_approx(s, _cut_fill_scale):
		return
	_cut_fill_scale = s
	if mode == Mode.CUT_FILL:
		mark_all_dirty()


func cut_fill_scale() -> float:
	return _cut_fill_scale
