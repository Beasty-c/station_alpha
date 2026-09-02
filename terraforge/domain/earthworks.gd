class_name TFEarthworks
extends RefCounted

## Authoritative, deterministic cut/fill and material-balance engine.
##
## CPU reference implementation. GPU shaders in this application only colour
## pixels; they never feed a quantity back into the model.
##
## Integration method
## ------------------
## Between four grid nodes the surface is defined as BILINEAR. The mean of a
## bilinear patch over its cell equals the average of its four corner values,
## so for each cell:
##
##     net_cell = mean(d00, d10, d01, d11) * cell_area          [exact]
##
## where d = proposed - existing. Summing that over every cell gives the net
## volume EXACTLY for the bilinear surface definition - no approximation.
##
## Cut and fill must be separated, and a cell whose corner deltas change sign
## contains a daylight line inside it. Those cells (and only those) are
## refined into an N x N sub-grid of bilinearly sampled sub-cells, each
## integrated by the same exact rule. `subdivision` is 4 by default, which
## bounds the cut/fill split error at roughly (spacing/4) of misplaced
## daylight line. `cells_refined` is reported so the error source is visible.
##
## Everything here is a pure function of its inputs. Same surfaces plus same
## assumptions always produce the same numbers, on any machine, at any frame
## rate, at any window size.

const DEFAULT_SUBDIVISION := 4
const DISTURBED_THRESHOLD_M := 0.01   # 10 mm: below this a node counts as untouched


## Core volume integral. Returns
## {cut_m3, fill_m3, net_m3, cells, refined, max_cut_m, max_fill_m, disturbed_m2}
static func integrate(existing: TFHeightfield, proposed: TFHeightfield,
		subdivision: int = DEFAULT_SUBDIVISION) -> Dictionary:
	var out := {
		"cut_m3": 0.0, "fill_m3": 0.0, "net_m3": 0.0,
		"cells": 0, "refined": 0,
		"max_cut_m": 0.0, "max_fill_m": 0.0, "disturbed_m2": 0.0,
	}
	if existing == null or proposed == null:
		return out
	if not existing.same_grid_as(proposed):
		push_error("TFEarthworks.integrate: surfaces are on different grids; refusing to mix them.")
		return out

	var cols := existing.cols
	var rows := existing.rows
	var area := existing.cell_area()
	var sub: int = clampi(subdivision, 1, 16)

	# Node-wise delta buffer (one pass, cache friendly).
	var d := PackedFloat32Array()
	d.resize(cols * rows)
	var eh := existing.heights
	var ph := proposed.heights
	var max_cut := 0.0
	var max_fill := 0.0
	for i in d.size():
		var v: float = ph[i] - eh[i]
		d[i] = v
		if v < 0.0:
			max_cut = maxf(max_cut, -v)
		else:
			max_fill = maxf(max_fill, v)

	var cut := 0.0
	var fill := 0.0
	var net := 0.0
	var refined := 0
	var disturbed_cells := 0
	var thr := DISTURBED_THRESHOLD_M

	for r in range(rows - 1):
		var base := r * cols
		var base2 := base + cols
		for c in range(cols - 1):
			var d00: float = d[base + c]
			var d10: float = d[base + c + 1]
			var d01: float = d[base2 + c]
			var d11: float = d[base2 + c + 1]
			var mean := (d00 + d10 + d01 + d11) * 0.25
			net += mean * area

			if absf(d00) > thr or absf(d10) > thr or absf(d01) > thr or absf(d11) > thr:
				disturbed_cells += 1

			var has_pos := d00 > 0.0 or d10 > 0.0 or d01 > 0.0 or d11 > 0.0
			var has_neg := d00 < 0.0 or d10 < 0.0 or d01 < 0.0 or d11 < 0.0
			if not (has_pos and has_neg):
				# Uniform-sign cell: the exact bilinear mean already separates.
				if mean >= 0.0:
					fill += mean * area
				else:
					cut += -mean * area
				continue

			# Mixed cell: refine.
			refined += 1
			var inv := 1.0 / float(sub)
			var sub_area := area * inv * inv
			for sr in range(sub):
				var v0 := float(sr) * inv
				var v1 := float(sr + 1) * inv
				for sc in range(sub):
					var u0 := float(sc) * inv
					var u1 := float(sc + 1) * inv
					var a := _bilerp(d00, d10, d01, d11, u0, v0)
					var b := _bilerp(d00, d10, d01, d11, u1, v0)
					var e := _bilerp(d00, d10, d01, d11, u0, v1)
					var f := _bilerp(d00, d10, d01, d11, u1, v1)
					var m := (a + b + e + f) * 0.25
					if m >= 0.0:
						fill += m * sub_area
					else:
						cut += -m * sub_area

	out["cut_m3"] = cut
	out["fill_m3"] = fill
	out["net_m3"] = net
	out["cells"] = (cols - 1) * (rows - 1)
	out["refined"] = refined
	out["max_cut_m"] = max_cut
	out["max_fill_m"] = max_fill
	out["disturbed_m2"] = float(disturbed_cells) * area
	return out


static func _bilerp(v00: float, v10: float, v01: float, v11: float, u: float, v: float) -> float:
	return lerpf(lerpf(v00, v10, u), lerpf(v01, v11, u), v)


## Full analysis: geometry + material balance + trucking.
## `progress` (optional) is called with a 0..1 float; `is_cancelled` (optional)
## is polled and, if it returns true, analysis aborts and returns null.
static func analyze(existing: TFHeightfield, proposed: TFHeightfield,
		a: TFAssumptions, road: TFRoad = null, tower: TFTower = null,
		progress: Callable = Callable(), is_cancelled: Callable = Callable()) -> TFAnalysis:
	var res := TFAnalysis.new()
	if existing == null or proposed == null or a == null:
		return res
	res.computed_at_unix = int(Time.get_unix_time_from_system())
	res.status = "simulated"
	res.grid_spacing_m = existing.spacing
	res.subdivision = DEFAULT_SUBDIVISION

	if progress.is_valid():
		progress.call(0.05)
	if is_cancelled.is_valid() and bool(is_cancelled.call()):
		return null

	var vol := integrate(existing, proposed, DEFAULT_SUBDIVISION)

	if progress.is_valid():
		progress.call(0.55)
	if is_cancelled.is_valid() and bool(is_cancelled.call()):
		return null

	res.site_area_m2 = existing.total_area()
	res.disturbed_area_m2 = float(vol["disturbed_m2"])
	var emm := existing.min_max()
	var pmm := proposed.min_max()
	res.existing_min_m = emm.x
	res.existing_max_m = emm.y
	res.proposed_min_m = pmm.x
	res.proposed_max_m = pmm.y
	res.max_cut_depth_m = float(vol["max_cut_m"])
	res.max_fill_depth_m = float(vol["max_fill_m"])
	res.cut_bank_m3 = float(vol["cut_m3"])
	res.fill_compacted_m3 = float(vol["fill_m3"])
	res.net_geometric_m3 = float(vol["net_m3"])
	res.cells_evaluated = int(vol["cells"])
	res.cells_refined = int(vol["refined"])

	if progress.is_valid():
		progress.call(0.7)
	res.max_slope_ratio = proposed.max_slope_ratio()

	if progress.is_valid():
		progress.call(0.85)
	if is_cancelled.is_valid() and bool(is_cancelled.call()):
		return null

	_material_balance(res, a)

	if road != null and road.is_valid():
		res.road = road.metrics(proposed)
		res.disturbed_area_m2 = maxf(res.disturbed_area_m2,
			minf(res.site_area_m2, float(res.road["disturbed_corridor_area_m2"])))
	if tower != null:
		res.tower = tower.metrics(proposed)

	res.assumptions_used = a.to_dict()
	res.formulas = _formulas(res, a)
	_grade_confidence(res, existing, proposed)

	if progress.is_valid():
		progress.call(1.0)
	return res


static func _material_balance(res: TFAnalysis, a: TFAssumptions) -> void:
	var bank_per_comp := a.bank_per_compacted()
	var loose_per_bank := a.loose_per_bank()

	res.fill_bank_required_m3 = res.fill_compacted_m3 * bank_per_comp
	var usable_cut := res.cut_bank_m3 * clampf(1.0 - a.unsuitable_fraction, 0.0, 1.0)
	res.onsite_reuse_bank_m3 = minf(usable_cut, res.fill_bank_required_m3)

	var shortfall := res.fill_bank_required_m3 - res.onsite_reuse_bank_m3
	var surplus := res.cut_bank_m3 - res.onsite_reuse_bank_m3
	res.import_bank_m3 = maxf(0.0, shortfall)
	res.export_bank_m3 = maxf(0.0, surplus)

	res.import_loose_m3 = res.import_bank_m3 * loose_per_bank
	res.export_loose_m3 = res.export_bank_m3 * loose_per_bank
	res.onsite_haul_loose_m3 = res.onsite_reuse_bank_m3 * loose_per_bank
	res.total_haul_loose_m3 = res.import_loose_m3 + res.export_loose_m3 + res.onsite_haul_loose_m3

	var cap := a.truck_capacity_loose_m3
	res.truck_capacity_loose_m3 = cap
	if cap > 0.0:
		res.import_truckloads = int(ceil(res.import_loose_m3 / cap - 1.0e-9))
		res.export_truckloads = int(ceil(res.export_loose_m3 / cap - 1.0e-9))
		res.onsite_truckloads = int(ceil(res.onsite_haul_loose_m3 / cap - 1.0e-9))
	else:
		# Guarded: a non-positive truck capacity cannot produce a load count.
		res.import_truckloads = 0
		res.export_truckloads = 0
		res.onsite_truckloads = 0
	res.total_truckloads = res.import_truckloads + res.export_truckloads + res.onsite_truckloads


static func _formulas(res: TFAnalysis, a: TFAssumptions) -> Array[Dictionary]:
	var f: Array[Dictionary] = []
	f.append({
		"name": "Net volume (exact bilinear grid integral)",
		"expr": "net = SUM(cells) mean(d00,d10,d01,d11) x cell_area,  d = proposed - existing",
		"value": res.net_geometric_m3, "unit": "m3",
	})
	f.append({
		"name": "Cut / fill separation",
		"expr": "sign-uniform cells use the exact cell mean; sign-mixed cells are refined %d x %d" % [res.subdivision, res.subdivision],
		"value": float(res.cells_refined), "unit": "cells refined",
	})
	f.append({
		"name": "Bank volume needed per compacted fill",
		"expr": "bank = compacted / (1 - shrinkage) = 1 / (1 - %.3f) = %.4f" % [a.shrinkage, a.bank_per_compacted()],
		"value": res.fill_bank_required_m3, "unit": "m3 bank",
	})
	f.append({
		"name": "Loose (haul) volume",
		"expr": "loose = bank x (1 + swell) = bank x %.4f" % a.loose_per_bank(),
		"value": res.total_haul_loose_m3, "unit": "m3 loose",
	})
	f.append({
		"name": "On-site reuse",
		"expr": "reuse = min(cut_bank x (1 - unsuitable %.2f), fill_bank_required)" % a.unsuitable_fraction,
		"value": res.onsite_reuse_bank_m3, "unit": "m3 bank",
	})
	f.append({
		"name": "Truckloads",
		"expr": "loads = ceil(loose_volume / truck_capacity_loose)  [capacity %.2f m3]" % a.truck_capacity_loose_m3,
		"value": float(res.total_truckloads), "unit": "loads",
	})
	f.append({
		"name": "Disturbed area",
		"expr": "cells where any corner |proposed - existing| > %.3f m, x cell area" % DISTURBED_THRESHOLD_M,
		"value": res.disturbed_area_m2, "unit": "m2",
	})
	return f


static func _grade_confidence(res: TFAnalysis, existing: TFHeightfield, proposed: TFHeightfield) -> void:
	var reasons := PackedStringArray()
	var score := 3  # 3 = moderate, 4 = good, lower = weaker

	reasons.append("Existing ground is a synthetic flat datum surface at the project's assumed elevation, not a survey.")
	score -= 1

	var depth: float = maxf(res.max_cut_depth_m, res.max_fill_depth_m)
	if depth > 0.0 and existing.spacing > depth * 0.75:
		reasons.append("Grid spacing (%.2f m) is coarse relative to the deepest change (%.2f m)." % [existing.spacing, depth])
		score -= 1
	else:
		reasons.append("Grid spacing (%.2f m) resolves the design changes adequately." % existing.spacing)

	if res.cells_evaluated > 0:
		var frac := float(res.cells_refined) / float(res.cells_evaluated)
		if frac > 0.25:
			reasons.append("%.0f%% of cells straddle the daylight line; cut/fill split carries more uncertainty than the net." % (frac * 100.0))
			score -= 1
		else:
			reasons.append("%.1f%% of cells straddle the daylight line; cut/fill split is well conditioned." % (frac * 100.0))

	reasons.append("Shrink/swell, production and pricing inputs are user-supplied illustrative values.")

	match score:
		4, 3: res.confidence = "moderate"
		2: res.confidence = "low"
		_: res.confidence = "very low"
	res.confidence_reasons = reasons
