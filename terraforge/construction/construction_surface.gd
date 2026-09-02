class_name TFConstructionSurface
extends RefCounted

## Builds the terrain surface shown at any point on the construction timeline.
##
## It is a PURE FUNCTION of the three authoritative surfaces and the step's
## terrain-progress vector:
##
##   existing    original ground (never modified)
##   mass_target the sculpted mass-grading surface
##   final       the proposed surface (mass target + pad + road corridor)
##
## Physical model
##   strip : topsoil is removed from the disturbed area
##   cut   : an excavation front descends from the high point of the site
##   fill  : a fill front rises from the low point, exactly like placed lifts
##   form  : the road corridor and pad are trimmed from mass target to final
##
## The endpoints are exact: state 0 reproduces `existing`, state 1 reproduces
## `final`. Nothing here reads the frame rate, the camera or the viewport, and
## nothing it produces ever feeds back into a quantity.

var existing: TFHeightfield = null
var mass_target: TFHeightfield = null
var final_surface: TFHeightfield = null

var _z_lo: float = 0.0
var _z_hi: float = 0.0
var _mask: PackedByteArray = PackedByteArray()
var _topsoil_m: float = 0.15
var _ready: bool = false


func prepare(p_existing: TFHeightfield, p_mass: TFHeightfield,
		p_final: TFHeightfield, topsoil_depth_m: float) -> void:
	existing = p_existing
	mass_target = p_mass
	final_surface = p_final
	_topsoil_m = maxf(0.0, topsoil_depth_m)
	_ready = false
	if existing == null or mass_target == null or final_surface == null:
		return
	if not existing.same_grid_as(final_surface) or not existing.same_grid_as(mass_target):
		return
	var n := existing.heights.size()
	_mask.resize(n)
	var lo := INF
	var hi := -INF
	for i in n:
		var e: float = existing.heights[i]
		var f: float = final_surface.heights[i]
		lo = minf(lo, minf(e, f))
		hi = maxf(hi, maxf(e, f))
		_mask[i] = 1 if absf(f - e) > TFEarthworks.DISTURBED_THRESHOLD_M else 0
	_z_lo = lo if lo != INF else 0.0
	_z_hi = hi if hi != -INF else 0.0
	if _z_hi - _z_lo < 0.01:
		_z_hi = _z_lo + 0.01
	_ready = true


func is_ready() -> bool:
	return _ready


## Evaluate the construction surface into `out` (a PackedFloat32Array sized to
## the grid). Returns false if not prepared.
func evaluate(state: Dictionary, out: PackedFloat32Array) -> bool:
	if not _ready:
		return false
	var n := existing.heights.size()
	if out.size() != n:
		out.resize(n)
	var strip: float = clampf(float(state.get("strip", 0.0)), 0.0, 1.0)
	var cut_p: float = clampf(float(state.get("cut", 0.0)), 0.0, 1.0)
	var fill_p: float = clampf(float(state.get("fill", 0.0)), 0.0, 1.0)
	var form_p: float = clampf(float(state.get("form", 0.0)), 0.0, 1.0)

	var cut_front := lerpf(_z_hi, _z_lo, cut_p)
	var fill_front := lerpf(_z_lo, _z_hi, fill_p)
	var strip_depth := _topsoil_m * strip

	var eh := existing.heights
	var mh := mass_target.heights
	var fh := final_surface.heights

	for i in n:
		var e: float = eh[i]
		if _mask[i] != 0:
			e -= strip_depth
		var m: float = mh[i]
		var h: float
		if m < e:
			# Cut: descending excavation front, never below the design surface.
			h = maxf(m, minf(e, cut_front))
		elif m > e:
			# Fill: rising lift front, never above the design surface.
			h = minf(m, maxf(e, fill_front))
		else:
			h = e
		# Road corridor / structure pad trimming from mass target to final.
		var f: float = fh[i]
		if form_p > 0.0 and absf(f - m) > 1.0e-6:
			h = lerpf(h, f, form_p)
		out[i] = h
	return true


## Convenience: a fresh heightfield at the given state.
func heightfield_at(state: Dictionary) -> TFHeightfield:
	var hf := final_surface.clone()
	var buf := PackedFloat32Array()
	if evaluate(state, buf):
		hf.heights = buf
	return hf
