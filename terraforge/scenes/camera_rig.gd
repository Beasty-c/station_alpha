class_name TFCameraRig
extends Node3D

## Orbit / pan / zoom camera over the site.
##
## Bindings follow CAD convention rather than game convention:
##   middle drag            orbit
##   shift + middle drag    pan
##   right drag             pan
##   wheel                  zoom toward the cursor
##   arrow keys / WASD      pan       (keyboard accessible)
##   Q / E                  orbit
##   R / F                  zoom
##   Home                   frame the whole site
##
## The camera never touches the terrain model. Panning rides a horizontal plane
## at the pivot's own elevation, so dragging across a hill does not make the
## view lurch.

const MIN_DISTANCE := 12.0
const MAX_DISTANCE := 1400.0
const MIN_PITCH := -1.45      # looking almost straight down
const MAX_PITCH := -0.05      # just above the horizon
const KEY_PAN_SPEED := 0.55   # fraction of distance per second
const KEY_ORBIT_SPEED := 1.4  # radians per second

signal moved()

@export var distance: float = 340.0
@export var yaw: float = -0.7
@export var pitch: float = -0.62

var camera: Camera3D
var _orbiting := false
var _panning := false
var _site_extent := 240.0


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 55.0
	camera.near = 0.5
	camera.far = 6000.0
	camera.current = true
	add_child(camera)
	_apply()
	set_process(true)


func frame_site(field: TFHeightfield) -> void:
	if field == null:
		return
	var e := field.extent()
	_site_extent = maxf(e.x, e.y)
	var c := field.center_xz()
	var mm := field.min_max()
	position = Vector3(c.x, (mm.x + mm.y) * 0.5, c.y)
	distance = clampf(_site_extent * 1.35, MIN_DISTANCE, MAX_DISTANCE)
	yaw = -0.7
	pitch = -0.62
	_apply()


func _apply() -> void:
	distance = clampf(distance, MIN_DISTANCE, MAX_DISTANCE)
	pitch = clampf(pitch, MIN_PITCH, MAX_PITCH)
	if camera == null:
		return
	var dir := Vector3(
		cos(pitch) * sin(yaw),
		sin(pitch),
		cos(pitch) * cos(yaw))
	camera.position = -dir * distance
	camera.look_at_from_position(camera.position, Vector3.ZERO, Vector3.UP)
	moved.emit()


## Handle a viewport input event. Returns true if the camera consumed it, so
## the caller knows not to treat it as a terrain edit.
func handle_input(event: InputEvent, viewport_size: Vector2) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_MIDDLE:
				if mb.pressed:
					if mb.shift_pressed:
						_panning = true
					else:
						_orbiting = true
				else:
					_orbiting = false
					_panning = false
				return true
			MOUSE_BUTTON_RIGHT:
				_panning = mb.pressed
				return true
			MOUSE_BUTTON_WHEEL_UP:
				_zoom(-0.12, mb.position, viewport_size)
				return true
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom(0.12, mb.position, viewport_size)
				return true
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _orbiting:
			yaw -= mm.relative.x * 0.006
			pitch = clampf(pitch + mm.relative.y * 0.005, MIN_PITCH, MAX_PITCH)
			_apply()
			return true
		if _panning:
			_pan_by(mm.relative)
			return true
	return false


func _pan_by(screen_delta: Vector2) -> void:
	# Screen-space drag converted to world units at the pivot's depth, so the
	# ground appears to stick to the cursor.
	var scale := distance * 0.0022
	var right := camera.global_transform.basis.x
	var fwd := -camera.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 1e-6:
		fwd = Vector3(sin(yaw), 0.0, cos(yaw))
	fwd = fwd.normalized()
	right.y = 0.0
	right = right.normalized()
	position -= right * screen_delta.x * scale
	position -= fwd * -screen_delta.y * scale
	_clamp_pivot()
	_apply()


func _zoom(amount: float, at: Vector2, viewport_size: Vector2) -> void:
	var before := distance
	distance = clampf(distance * (1.0 + amount), MIN_DISTANCE, MAX_DISTANCE)
	# Zoom toward the cursor: shift the pivot a fraction of the way to the
	# point under the pointer, proportional to how much the distance changed.
	if viewport_size.x > 1.0 and viewport_size.y > 1.0 and camera != null:
		var ndc := (at / viewport_size) * 2.0 - Vector2.ONE
		var shift := (before - distance) * 0.5
		var right := camera.global_transform.basis.x
		var up := camera.global_transform.basis.y
		position += (right * ndc.x + up * -ndc.y) * shift * 0.35
		_clamp_pivot()
	_apply()


## Keep the pivot near the site so the user cannot lose the terrain entirely.
func _clamp_pivot() -> void:
	var limit := _site_extent * 1.2
	position.x = clampf(position.x, -limit, limit)
	position.z = clampf(position.z, -limit, limit)
	position.y = clampf(position.y, -200.0, 600.0)


func _process(delta: float) -> void:
	var pan := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		pan.x += 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		pan.x -= 1.0
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		pan.y += 1.0
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		pan.y -= 1.0
	if pan != Vector2.ZERO:
		# _pan_by works in screen pixels and scales them by distance * 0.0022,
		# so invert that to move a fixed fraction of the view distance per
		# second regardless of how far out the camera is.
		_pan_by(pan.normalized() * (KEY_PAN_SPEED * delta / 0.0022))

	var orbit := 0.0
	if Input.is_key_pressed(KEY_Q):
		orbit += 1.0
	if Input.is_key_pressed(KEY_E):
		orbit -= 1.0
	if orbit != 0.0:
		yaw += orbit * KEY_ORBIT_SPEED * delta
		_apply()

	var zoom := 0.0
	if Input.is_key_pressed(KEY_R):
		zoom -= 1.0
	if Input.is_key_pressed(KEY_F):
		zoom += 1.0
	if zoom != 0.0:
		distance = clampf(distance * (1.0 + zoom * 0.9 * delta), MIN_DISTANCE, MAX_DISTANCE)
		_apply()


## Ray from the camera through a viewport pixel.
func ray_from(screen_pos: Vector2) -> Dictionary:
	if camera == null:
		return {"origin": Vector3.ZERO, "direction": Vector3.FORWARD}
	return {
		"origin": camera.project_ray_origin(screen_pos),
		"direction": camera.project_ray_normal(screen_pos),
	}
