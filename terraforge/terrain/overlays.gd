class_name TFOverlays
extends Node3D

## Non-terrain 3D content: the finished-surface ghost, feature geometry, work
## zones, haul arrows, and the batched markers and machines used in playback.
##
## Everything here is DRIVEN BY DATA from the domain and construction models.
## Nothing in this file computes a quantity, and nothing it draws feeds back
## into one.

const STAKE_HEIGHT := 1.6
const ARROW_Y := 2.5

var _ghost: MeshInstance3D
var _road: MeshInstance3D
var _tower: Node3D
var _zone: MeshInstance3D
var _arrows: MeshInstance3D
var _stakes: MultiMeshInstance3D
var _trucks: MultiMeshInstance3D
var _machines: MultiMeshInstance3D
var _stockpile: MeshInstance3D
var _erosion: MeshInstance3D
var _access: MeshInstance3D

var _mat_ghost: StandardMaterial3D
var _mat_zone: StandardMaterial3D
var _mat_flat: StandardMaterial3D
var _mat_stake: StandardMaterial3D
var _mat_truck: StandardMaterial3D
var _mat_machine: StandardMaterial3D


func _ready() -> void:
	_mat_ghost = _make_material(Color(0.62, 0.72, 0.85, 0.22), true)
	_mat_ghost.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_zone = _make_material(Color(TFPalette.SURVEY_ORANGE, 0.20), true)
	_mat_zone.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_flat = _make_material(Color.WHITE, false)
	_mat_flat.vertex_color_use_as_albedo = true
	_mat_flat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_stake = _make_material(TFPalette.SURVEY_ORANGE, false)
	_mat_stake.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_truck = _make_material(Color(0.90, 0.60, 0.20), false)
	_mat_machine = _make_material(Color(0.95, 0.76, 0.13), false)

	_ghost = _add_mesh(_mat_ghost)
	_zone = _add_mesh(_mat_zone)
	var access_mat := _make_material(Color(0.55, 0.50, 0.44, 0.85), true)
	access_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_access = _add_mesh(access_mat)
	_road = _add_mesh(_mat_flat)
	_arrows = _add_mesh(_make_unshaded(TFPalette.CONSTRUCTION_YELLOW))
	var fence_mat := _make_unshaded(TFPalette.VERIFIED_GREEN)
	fence_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_erosion = _add_mesh(fence_mat)
	_stockpile = _add_mesh(_make_material(Color(0.52, 0.45, 0.35), false))
	_tower = Node3D.new()
	add_child(_tower)

	_stakes = _add_multimesh(_stake_mesh(), _mat_stake)
	_trucks = _add_multimesh(_truck_mesh(), _mat_truck)
	_machines = _add_multimesh(_machine_mesh(), _mat_machine)


func _make_material(c: Color, transparent: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	m.metallic = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _make_unshaded(c: Color) -> StandardMaterial3D:
	var m := _make_material(c, false)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _add_mesh(mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.material_override = mat
	add_child(mi)
	return mi


func _add_multimesh(mesh: Mesh, mat: Material) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = 0
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)
	return mmi


# --- Ghost of the finished surface -------------------------------------------
## A translucent shell of the proposed design, shown during playback so the
## user can see where the ground is heading.
func set_ghost(surface: TFHeightfield, visible_: bool) -> void:
	_ghost.visible = visible_
	if not visible_ or surface == null:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Decimated: the ghost only has to read as a shape, not carry detail.
	var stride: int = maxi(1, int(round(float(surface.cols) / 60.0)))
	var c := 0
	while c + stride < surface.cols:
		var r := 0
		while r + stride < surface.rows:
			_ghost_quad(st, surface, c, r, stride)
			r += stride
		c += stride
	st.generate_normals()
	_ghost.mesh = st.commit()


func _ghost_quad(st: SurfaceTool, s: TFHeightfield, c: int, r: int, k: int) -> void:
	var a := _pt(s, c, r)
	var b := _pt(s, c + k, r)
	var d := _pt(s, c, r + k)
	var e := _pt(s, c + k, r + k)
	# Clockwise winding: Godot's front faces, so the ghost is not inside out.
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(e)
	st.add_vertex(a); st.add_vertex(e); st.add_vertex(d)


func _pt(s: TFHeightfield, c: int, r: int) -> Vector3:
	var p := s.node_position(mini(c, s.cols - 1), mini(r, s.rows - 1))
	return Vector3(p.x, s.get_h(mini(c, s.cols - 1), mini(r, s.rows - 1)) + 0.06, p.y)


# --- Features ----------------------------------------------------------------
## The road running surface, drawn as a ribbon that follows the design profile.
func set_road(road: TFRoad, surface: TFHeightfield, show: bool, complete: float = 1.0) -> void:
	_road.visible = show and road != null and road.is_valid()
	if not _road.visible:
		return
	var pts := road.centerline()
	if pts.size() < 2:
		_road.visible = false
		return
	var count: int = maxi(2, int(round(float(pts.size()) * clampf(complete, 0.05, 1.0))))
	var half := road.width_m * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var built := 0
	for i in range(count - 1):
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var dir := (p1 - p0)
		if dir.length_squared() < 1.0e-9:
			continue
		var n := Vector2(-dir.y, dir.x).normalized() * half
		var a := _road_pt(surface, p0 - n)
		var b := _road_pt(surface, p0 + n)
		var c := _road_pt(surface, p1 - n)
		var d := _road_pt(surface, p1 + n)
		st.set_color(TFPalette.ROAD_SURFACE)
		st.add_vertex(a); st.add_vertex(d); st.add_vertex(b)
		st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)
		built += 1
	if built == 0:
		_road.visible = false
		return
	st.generate_normals()
	_road.mesh = st.commit()


func _road_pt(s: TFHeightfield, xz: Vector2) -> Vector3:
	return Vector3(xz.x, s.sample(xz) + 0.10, xz.y)


## The tower: a tapered lattice mast on a pad, built up to `progress`.
func set_tower(tower: TFTower, surface: TFHeightfield, show: bool, progress: float = 1.0) -> void:
	for c in _tower.get_children():
		c.queue_free()
	_tower.visible = show and tower != null
	if not _tower.visible:
		return
	var base_y := surface.sample(tower.position_xz)
	var p := clampf(progress, 0.0, 1.0)

	# Foundation block appears first (first 25% of tower progress).
	var found_t: float = clampf(p / 0.25, 0.0, 1.0)
	if found_t > 0.01:
		var f := MeshInstance3D.new()
		var fb := BoxMesh.new()
		fb.size = Vector3(tower.foundation_pad_m, 0.9 * found_t, tower.foundation_pad_m)
		f.mesh = fb
		f.material_override = _make_material(Color(0.72, 0.72, 0.74), false)
		f.position = Vector3(tower.position_xz.x, base_y + fb.size.y * 0.5, tower.position_xz.y)
		_tower.add_child(f)

	# Mast rises over the remaining 75%.
	var mast_t: float = clampf((p - 0.25) / 0.75, 0.0, 1.0)
	if mast_t <= 0.01:
		return
	var built_h := tower.height_m * mast_t
	var sections: int = maxi(1, int(ceil(built_h / 6.0)))
	var mat := _make_material(Color(0.78, 0.79, 0.82), false)
	for i in sections:
		var y0 := built_h * float(i) / float(sections)
		var y1 := built_h * float(i + 1) / float(sections)
		var f0 := 1.0 - 0.55 * (y0 / maxf(1.0, tower.height_m))
		var seg := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = tower.footprint_m * 0.5 * (1.0 - 0.55 * (y1 / maxf(1.0, tower.height_m)))
		cyl.bottom_radius = tower.footprint_m * 0.5 * f0
		cyl.height = maxf(0.1, y1 - y0)
		cyl.radial_segments = 6
		seg.mesh = cyl
		seg.material_override = mat
		seg.position = Vector3(tower.position_xz.x, base_y + (y0 + y1) * 0.5 + 0.9,
			tower.position_xz.y)
		_tower.add_child(seg)


# --- Work zones and flows ----------------------------------------------------
## Highlight the area a construction step is working in.
func set_zone(kind: String, project: TFProject, surface: TFHeightfield) -> void:
	_zone.visible = kind != ""
	if not _zone.visible or surface == null:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		"corridor":
			if project.road == null or not project.road.is_valid():
				_zone.visible = false
				return
			var pts := project.road.centerline()
			var half := project.road.width_m * 0.5 + project.road.shoulder_m
			for i in range(pts.size() - 1):
				var dir := pts[i + 1] - pts[i]
				if dir.length_squared() < 1e-9:
					continue
				var n := Vector2(-dir.y, dir.x).normalized() * half
				_quad(st, surface, pts[i] - n, pts[i] + n, pts[i + 1] - n, pts[i + 1] + n, 0.35)
		"pad":
			if project.tower == null:
				_zone.visible = false
				return
			var c := project.tower.position_xz
			var h := project.tower.pad_size_m * 0.5 + project.tower.pad_apron_m
			_quad(st, surface, c + Vector2(-h, -h), c + Vector2(h, -h),
				c + Vector2(-h, h), c + Vector2(h, h), 0.35)
		_:
			var mn := surface.aabb_min()
			var mx := surface.aabb_max()
			_quad(st, surface, mn, Vector2(mx.x, mn.y), Vector2(mn.x, mx.y), mx, 0.25)
	_zone.mesh = st.commit()


func _quad(st: SurfaceTool, s: TFHeightfield, a: Vector2, b: Vector2, c: Vector2, d: Vector2, lift: float) -> void:
	var pa := Vector3(a.x, s.sample(a) + lift, a.y)
	var pb := Vector3(b.x, s.sample(b) + lift, b.y)
	var pc := Vector3(c.x, s.sample(c) + lift, c.y)
	var pd := Vector3(d.x, s.sample(d) + lift, d.y)
	st.add_vertex(pa); st.add_vertex(pd); st.add_vertex(pb)
	st.add_vertex(pa); st.add_vertex(pc); st.add_vertex(pd)


## Haul direction arrows along a path.
func set_haul_arrows(path: PackedVector2Array, surface: TFHeightfield, show: bool) -> void:
	_arrows.visible = show and path.size() >= 2 and surface != null
	if not _arrows.visible:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step: int = maxi(1, path.size() / 10)
	var i := 0
	while i < path.size() - step:
		var a := path[i]
		var b := path[i + step]
		var dir := (b - a)
		if dir.length() > 2.0:
			_arrow(st, surface, a, dir.normalized(), 6.0)
		i += step
	_arrows.mesh = st.commit()


func _arrow(st: SurfaceTool, s: TFHeightfield, at: Vector2, dir: Vector2, size: float) -> void:
	var n := Vector2(-dir.y, dir.x)
	var y := s.sample(at) + ARROW_Y
	var tip := Vector3(at.x + dir.x * size, y, at.y + dir.y * size)
	var l := Vector3(at.x - n.x * size * 0.4, y, at.y - n.y * size * 0.4)
	var r := Vector3(at.x + n.x * size * 0.4, y, at.y + n.y * size * 0.4)
	st.add_vertex(tip); st.add_vertex(r); st.add_vertex(l)
	st.add_vertex(tip); st.add_vertex(l); st.add_vertex(r)


## Perimeter erosion-control fence.
func set_erosion_fence(surface: TFHeightfield, show: bool) -> void:
	_erosion.visible = show and surface != null
	if not _erosion.visible:
		return
	var mn := surface.aabb_min() + Vector2(6.0, 6.0)
	var mx := surface.aabb_max() - Vector2(6.0, 6.0)
	var corners := [mn, Vector2(mx.x, mn.y), mx, Vector2(mn.x, mx.y), mn]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(4):
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[i + 1]
		var seg: int = maxi(2, int(a.distance_to(b) / 8.0))
		for k in range(seg):
			var p0 := a.lerp(b, float(k) / float(seg))
			var p1 := a.lerp(b, float(k + 1) / float(seg))
			var y0 := surface.sample(p0)
			var y1 := surface.sample(p1)
			var q0 := Vector3(p0.x, y0, p0.y)
			var q1 := Vector3(p1.x, y1, p1.y)
			var q2 := Vector3(p1.x, y1 + 0.8, p1.y)
			var q3 := Vector3(p0.x, y0 + 0.8, p0.y)
			st.add_vertex(q0); st.add_vertex(q1); st.add_vertex(q2)
			st.add_vertex(q0); st.add_vertex(q2); st.add_vertex(q3)
	_erosion.mesh = st.commit()


## Temporary haul access ribbon.
func set_temp_access(road: TFRoad, surface: TFHeightfield, show: bool) -> void:
	_access.visible = show and road != null and road.is_valid() and surface != null
	if not _access.visible:
		return
	var pts := road.centerline()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(pts.size() - 1):
		var dir := pts[i + 1] - pts[i]
		if dir.length_squared() < 1e-9:
			continue
		var n := Vector2(-dir.y, dir.x).normalized() * 2.5
		_quad(st, surface, pts[i] - n, pts[i] + n, pts[i + 1] - n, pts[i + 1] + n, 0.16)
	_access.mesh = st.commit()


## Topsoil / material stockpile, sized to the volume it represents.
func set_stockpile(at: Vector2, volume_m3: float, surface: TFHeightfield, show: bool) -> void:
	_stockpile.visible = show and volume_m3 > 1.0 and surface != null
	if not _stockpile.visible:
		return
	# Cone at a 1.5:1 side slope: V = pi r^2 h / 3 with h = r / 1.5.
	var r: float = pow(maxf(volume_m3, 1.0) * 4.5 / PI, 1.0 / 3.0)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = r
	cone.height = r / 1.5
	cone.radial_segments = 14
	_stockpile.mesh = cone
	_stockpile.position = Vector3(at.x, surface.sample(at) + cone.height * 0.5, at.y)


# --- Batched instances -------------------------------------------------------
## Proposed stakeout locations. These are DESIGN OUTPUT, not field marks; the
## UI labels them that way wherever they are shown.
func set_stakes(points: PackedVector2Array, surface: TFHeightfield, show: bool) -> void:
	_stakes.visible = show
	if not show or surface == null:
		_stakes.multimesh.instance_count = 0
		return
	_fill(_stakes.multimesh, points, surface, STAKE_HEIGHT * 0.5, 1.0)


func set_trucks(points: PackedVector2Array, surface: TFHeightfield, show: bool) -> void:
	_trucks.visible = show
	if not show or surface == null:
		_trucks.multimesh.instance_count = 0
		return
	_fill(_trucks.multimesh, points, surface, 1.2, 1.0)


func set_machines(points: PackedVector2Array, surface: TFHeightfield, show: bool, color: Color = TFPalette.CONSTRUCTION_YELLOW) -> void:
	_machines.visible = show
	_mat_machine.albedo_color = color
	if not show or surface == null:
		_machines.multimesh.instance_count = 0
		return
	_fill(_machines.multimesh, points, surface, 1.4, 1.0)


func _fill(mm: MultiMesh, points: PackedVector2Array, surface: TFHeightfield,
		lift: float, scale: float) -> void:
	mm.instance_count = points.size()
	for i in points.size():
		var p := points[i]
		var t := Transform3D(Basis().scaled(Vector3(scale, scale, scale)),
			Vector3(p.x, surface.sample(p) + lift, p.y))
		mm.set_instance_transform(i, t)


func _stake_mesh() -> Mesh:
	var m := BoxMesh.new()
	m.size = Vector3(0.16, STAKE_HEIGHT, 0.16)
	return m


func _truck_mesh() -> Mesh:
	var m := BoxMesh.new()
	m.size = Vector3(2.6, 2.4, 6.4)
	return m


func _machine_mesh() -> Mesh:
	var m := BoxMesh.new()
	m.size = Vector3(3.0, 2.8, 4.4)
	return m


## Hide everything that only belongs to playback, so the editor view is clean.
func clear_construction() -> void:
	_zone.visible = false
	_arrows.visible = false
	_erosion.visible = false
	_access.visible = false
	_stockpile.visible = false
	_ghost.visible = false
	_stakes.visible = false
	_trucks.visible = false
	_machines.visible = false
