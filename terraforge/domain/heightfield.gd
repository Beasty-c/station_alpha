class_name TFHeightfield
extends RefCounted

## Canonical terrain surface: an explicit, contiguous floating point grid.
##
## This - not the rendered mesh - is the project's truth. It is engine-light:
## no nodes, no viewport, no frame rate. Rendering reads from it; it never
## writes to it.
##
## Geometry convention
##   origin  : world position (metres) of grid node (0, 0), in the local
##             engineering coordinate system, on the X/Z ground plane.
##   spacing : node spacing in metres (square cells).
##   cols/rows: NUMBER OF NODES, so the extent is (cols-1) * spacing.
##   heights : row-major, index = row * cols + col. Elevation in metres.
##
## The grid is tile-aware by construction: any rectangular node window can be
## read or written independently (see `region_bounds`), which is what the
## renderer and the future tiled raster / TIN backends use.

const UNITS := "m"  # heights, spacing and origin are ALWAYS metres.

var cols: int = 0
var rows: int = 0
var spacing: float = 1.0
var origin: Vector2 = Vector2.ZERO
var heights: PackedFloat32Array = PackedFloat32Array()


static func create_flat(p_cols: int, p_rows: int, p_spacing: float,
		p_elevation: float = 0.0, p_origin: Vector2 = Vector2.ZERO) -> TFHeightfield:
	var hf := TFHeightfield.new()
	hf.cols = maxi(2, p_cols)
	hf.rows = maxi(2, p_rows)
	hf.spacing = maxf(0.0001, p_spacing)
	hf.origin = p_origin
	hf.heights = PackedFloat32Array()
	hf.heights.resize(hf.cols * hf.rows)
	hf.heights.fill(p_elevation)
	return hf


func clone() -> TFHeightfield:
	var hf := TFHeightfield.new()
	hf.cols = cols
	hf.rows = rows
	hf.spacing = spacing
	hf.origin = origin
	hf.heights = heights.duplicate()
	return hf


func same_grid_as(other: TFHeightfield) -> bool:
	return other != null and other.cols == cols and other.rows == rows \
		and is_equal_approx(other.spacing, spacing) and other.origin.is_equal_approx(origin)


func node_count() -> int:
	return cols * rows


func cell_count() -> int:
	return maxi(0, cols - 1) * maxi(0, rows - 1)


func cell_area() -> float:
	return spacing * spacing


func extent() -> Vector2:
	return Vector2(float(cols - 1) * spacing, float(rows - 1) * spacing)


func total_area() -> float:
	var e := extent()
	return e.x * e.y


func aabb_min() -> Vector2:
	return origin


func aabb_max() -> Vector2:
	return origin + extent()


func center_xz() -> Vector2:
	return origin + extent() * 0.5


# --- Node access -------------------------------------------------------------
func idx(col: int, row: int) -> int:
	return row * cols + col


func in_range(col: int, row: int) -> bool:
	return col >= 0 and col < cols and row >= 0 and row < rows


func get_h(col: int, row: int) -> float:
	if not in_range(col, row):
		return 0.0
	return heights[row * cols + col]


func get_h_clamped(col: int, row: int) -> float:
	var c := clampi(col, 0, cols - 1)
	var r := clampi(row, 0, rows - 1)
	return heights[r * cols + c]


func set_h(col: int, row: int, value: float) -> void:
	if in_range(col, row):
		heights[row * cols + col] = value


## World position (X,Z metres) of a grid node.
func node_position(col: int, row: int) -> Vector2:
	return origin + Vector2(float(col) * spacing, float(row) * spacing)


## Fractional grid coordinates for a world X/Z position.
func grid_coords(world_xz: Vector2) -> Vector2:
	return (world_xz - origin) / spacing


func contains_xz(world_xz: Vector2) -> bool:
	var g := grid_coords(world_xz)
	return g.x >= 0.0 and g.y >= 0.0 and g.x <= float(cols - 1) and g.y <= float(rows - 1)


## Bilinear elevation sample. Outside the grid it clamps to the edge, which is
## the documented behaviour everywhere in the domain.
func sample(world_xz: Vector2) -> float:
	var g := grid_coords(world_xz)
	return sample_grid(g.x, g.y)


## Bilinear sample in *grid* space (used by the volume integrator).
func sample_grid(fx: float, fy: float) -> float:
	var cx := clampf(fx, 0.0, float(cols - 1))
	var cy := clampf(fy, 0.0, float(rows - 1))
	var c0 := int(floor(cx))
	var r0 := int(floor(cy))
	var c1 := mini(c0 + 1, cols - 1)
	var r1 := mini(r0 + 1, rows - 1)
	var tx := cx - float(c0)
	var ty := cy - float(r0)
	var h00 := heights[r0 * cols + c0]
	var h10 := heights[r0 * cols + c1]
	var h01 := heights[r1 * cols + c0]
	var h11 := heights[r1 * cols + c1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), ty)


# --- Derived quantities ------------------------------------------------------
func min_max() -> Vector2:
	if heights.is_empty():
		return Vector2.ZERO
	var lo := heights[0]
	var hi := heights[0]
	for h in heights:
		if h < lo: lo = h
		if h > hi: hi = h
	return Vector2(lo, hi)


## Central-difference surface gradient at a node, as rise/run (dimensionless).
func gradient(col: int, row: int) -> Vector2:
	var cl := maxi(col - 1, 0)
	var cr := mini(col + 1, cols - 1)
	var rt := maxi(row - 1, 0)
	var rb := mini(row + 1, rows - 1)
	var span_x := float(cr - cl) * spacing
	var span_y := float(rb - rt) * spacing
	var dx := 0.0
	var dy := 0.0
	if span_x > 0.0:
		dx = (heights[row * cols + cr] - heights[row * cols + cl]) / span_x
	if span_y > 0.0:
		dy = (heights[rb * cols + col] - heights[rt * cols + col]) / span_y
	return Vector2(dx, dy)


## Slope magnitude at a node as rise/run.
func slope_ratio(col: int, row: int) -> float:
	return gradient(col, row).length()


func max_slope_ratio() -> float:
	var m := 0.0
	for r in rows:
		for c in cols:
			var s := slope_ratio(c, r)
			if s > m:
				m = s
	return m


func normal_at(col: int, row: int) -> Vector3:
	var g := gradient(col, row)
	return Vector3(-g.x, 1.0, -g.y).normalized()


# --- Region helpers (tile-aware editing) -------------------------------------
## Inclusive node window (min_col, min_row, max_col, max_row) covering a
## world-space circle, clamped to the grid.
func region_bounds(center_xz: Vector2, radius: float) -> Vector4i:
	var g0 := grid_coords(center_xz - Vector2(radius, radius))
	var g1 := grid_coords(center_xz + Vector2(radius, radius))
	var c0 := clampi(int(floor(g0.x)), 0, cols - 1)
	var r0 := clampi(int(floor(g0.y)), 0, rows - 1)
	var c1 := clampi(int(ceil(g1.x)), 0, cols - 1)
	var r1 := clampi(int(ceil(g1.y)), 0, rows - 1)
	return Vector4i(c0, r0, c1, r1)


func full_bounds() -> Vector4i:
	return Vector4i(0, 0, cols - 1, rows - 1)


func copy_region(b: Vector4i) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize((b.z - b.x + 1) * (b.w - b.y + 1))
	var k := 0
	for r in range(b.y, b.w + 1):
		for c in range(b.x, b.z + 1):
			out[k] = heights[r * cols + c]
			k += 1
	return out


func paste_region(b: Vector4i, data: PackedFloat32Array) -> void:
	var k := 0
	for r in range(b.y, b.w + 1):
		for c in range(b.x, b.z + 1):
			heights[r * cols + c] = data[k]
			k += 1


func fill_all(value: float) -> void:
	heights.fill(value)


# --- Serialization -----------------------------------------------------------
## Heights are stored as base64 of the raw little-endian float32 buffer so the
## round trip is bit-exact. `encoding` is explicit in the file for readability.
func to_dict() -> Dictionary:
	return {
		"units": UNITS,
		"cols": cols,
		"rows": rows,
		"spacing": spacing,
		"origin": [origin.x, origin.y],
		"encoding": "base64-float32-le-rowmajor",
		"heights": Marshalls.raw_to_base64(heights.to_byte_array()),
	}


static func from_dict(d: Dictionary) -> TFHeightfield:
	var hf := TFHeightfield.new()
	hf.cols = maxi(2, int(d.get("cols", 2)))
	hf.rows = maxi(2, int(d.get("rows", 2)))
	hf.spacing = maxf(0.0001, float(d.get("spacing", 1.0)))
	var o: Array = d.get("origin", [0.0, 0.0])
	if o.size() >= 2:
		hf.origin = Vector2(float(o[0]), float(o[1]))
	var enc := String(d.get("encoding", "base64-float32-le-rowmajor"))
	if enc == "array-float":
		var arr: Array = d.get("heights", [])
		hf.heights = PackedFloat32Array()
		hf.heights.resize(hf.cols * hf.rows)
		for i in mini(arr.size(), hf.heights.size()):
			hf.heights[i] = float(arr[i])
	else:
		var bytes := Marshalls.base64_to_raw(String(d.get("heights", "")))
		hf.heights = bytes.to_float32_array()
	if hf.heights.size() != hf.cols * hf.rows:
		var fixed := PackedFloat32Array()
		fixed.resize(hf.cols * hf.rows)
		for i in mini(fixed.size(), hf.heights.size()):
			fixed[i] = hf.heights[i]
		hf.heights = fixed
	return hf


## Content fingerprint - used to invalidate caches and to prove that a replayed
## operation history reproduces the same surface.
func checksum() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(("%d|%d|%.9f|%.9f|%.9f|" % [cols, rows, spacing, origin.x, origin.y]).to_utf8_buffer())
	ctx.update(heights.to_byte_array())
	return ctx.finish().hex_encode().substr(0, 16)
