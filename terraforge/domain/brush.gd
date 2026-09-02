class_name TFBrush
extends RefCounted

## Pure terrain brush kernels.
##
## A brush "stamp" is a value object: {x, z, r, s, dt, target}. Applying a list
## of stamps to a heightfield is a deterministic function of that list, which
## is what makes an operation history replayable. Nothing here reads the clock,
## the frame rate or the viewport; `dt` is recorded by the caller and stored.

enum Mode { RAISE, LOWER, SMOOTH, FLATTEN }

const MODE_NAMES := ["raise", "lower", "smooth", "flatten"]


static func mode_from_name(n: String) -> Mode:
	var i := MODE_NAMES.find(n)
	return (i as Mode) if i >= 0 else Mode.RAISE


static func mode_name(m: Mode) -> String:
	return MODE_NAMES[int(m)]


static func make_stamp(center_xz: Vector2, radius: float, strength: float,
		dt: float, target: float = 0.0) -> Dictionary:
	return {
		"x": center_xz.x, "z": center_xz.y,
		"r": maxf(0.01, radius),
		"s": strength,
		"dt": maxf(0.0, dt),
		"target": target,
	}


## Radial falloff, 1.0 at the centre, 0.0 at the rim, C1 continuous.
static func falloff(d: float, r: float) -> float:
	if r <= 0.0:
		return 0.0
	var x := clampf(d / r, 0.0, 1.0)
	return 1.0 - smoothstep(0.0, 1.0, x)


## Apply a single stamp. Returns the inclusive node window touched
## (Vector4i(min_col, min_row, max_col, max_row)); z > x means "nothing".
static func apply_stamp(field: TFHeightfield, mode: Mode, stamp: Dictionary) -> Vector4i:
	var center := Vector2(float(stamp["x"]), float(stamp["z"]))
	var radius := float(stamp["r"])
	var strength := float(stamp["s"])
	var dt := float(stamp["dt"])
	var target := float(stamp.get("target", 0.0))
	if radius <= 0.0 or dt <= 0.0 or (strength == 0.0 and mode != Mode.FLATTEN):
		return Vector4i(0, 0, -1, -1)

	var b := field.region_bounds(center, radius)
	if b.z < b.x or b.w < b.y:
		return Vector4i(0, 0, -1, -1)

	# Snapshot first so neighbourhood reads (smooth) are order independent.
	var before := field.copy_region(b)
	var bw := b.z - b.x + 1

	match mode:
		Mode.RAISE, Mode.LOWER:
			var sign_ := 1.0 if mode == Mode.RAISE else -1.0
			for r in range(b.y, b.w + 1):
				for c in range(b.x, b.z + 1):
					var w := falloff(field.node_position(c, r).distance_to(center), radius)
					if w <= 0.0:
						continue
					field.set_h(c, r, field.get_h(c, r) + sign_ * strength * w * dt)
		Mode.SMOOTH:
			var rate: float = clampf(strength * dt, 0.0, 1.0)
			for r in range(b.y, b.w + 1):
				for c in range(b.x, b.z + 1):
					var w := falloff(field.node_position(c, r).distance_to(center), radius)
					if w <= 0.0:
						continue
					var acc := 0.0
					var cnt := 0
					for dr in range(-1, 2):
						for dc in range(-1, 2):
							var cc := clampi(c + dc, b.x, b.z)
							var rr := clampi(r + dr, b.y, b.w)
							acc += before[(rr - b.y) * bw + (cc - b.x)]
							cnt += 1
					var avg := acc / float(cnt)
					field.set_h(c, r, lerpf(field.get_h(c, r), avg, clampf(w * rate, 0.0, 1.0)))
		Mode.FLATTEN:
			var rate2: float = clampf(maxf(strength, 0.0) * dt, 0.0, 1.0)
			for r in range(b.y, b.w + 1):
				for c in range(b.x, b.z + 1):
					var w := falloff(field.node_position(c, r).distance_to(center), radius)
					if w <= 0.0:
						continue
					field.set_h(c, r, lerpf(field.get_h(c, r), target, clampf(w * rate2, 0.0, 1.0)))
	return b


## Apply a whole stroke. Returns the union of every touched node window.
static func apply_stroke(field: TFHeightfield, mode: Mode, stamps: Array) -> Vector4i:
	var acc := Vector4i(field.cols, field.rows, -1, -1)
	for s in stamps:
		var b := apply_stamp(field, mode, s)
		if b.z < b.x:
			continue
		acc = Vector4i(mini(acc.x, b.x), mini(acc.y, b.y), maxi(acc.z, b.z), maxi(acc.w, b.w))
	return acc
