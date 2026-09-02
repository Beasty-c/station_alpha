class_name TFAnalysis
extends RefCounted

## Result container for a deterministic earthworks analysis.
## Every stored quantity is SI (metres, square metres, cubic metres, hours).
## Display conversion happens only through TFUnitSystem.

const CALC_ENGINE_VERSION := "1.2.0"

var calc_version: String = CALC_ENGINE_VERSION
var computed_at_unix: int = 0
var status: String = "simulated"      # proposed | simulated | field_measured | certified

# --- Geometry ---------------------------------------------------------------
var site_area_m2: float = 0.0
var disturbed_area_m2: float = 0.0
var existing_min_m: float = 0.0
var existing_max_m: float = 0.0
var proposed_min_m: float = 0.0
var proposed_max_m: float = 0.0
var max_cut_depth_m: float = 0.0
var max_fill_depth_m: float = 0.0
var max_slope_ratio: float = 0.0      # rise/run on the proposed surface

# --- Geometric (bank / in-place) volumes ------------------------------------
var cut_bank_m3: float = 0.0          # material removed, measured in place
var fill_compacted_m3: float = 0.0    # designed fill, measured compacted
var net_geometric_m3: float = 0.0     # fill - cut, exact bilinear integral

# --- Adjusted volumes (shrink / swell applied) ------------------------------
var fill_bank_required_m3: float = 0.0
var onsite_reuse_bank_m3: float = 0.0
var import_bank_m3: float = 0.0
var export_bank_m3: float = 0.0
var import_loose_m3: float = 0.0
var export_loose_m3: float = 0.0
var onsite_haul_loose_m3: float = 0.0
var total_haul_loose_m3: float = 0.0

# --- Trucking ---------------------------------------------------------------
var truck_capacity_loose_m3: float = 0.0
var import_truckloads: int = 0
var export_truckloads: int = 0
var onsite_truckloads: int = 0
var total_truckloads: int = 0

# --- Numerical quality ------------------------------------------------------
var cells_evaluated: int = 0
var cells_refined: int = 0
var grid_spacing_m: float = 0.0
var subdivision: int = 4
var confidence: String = "low"
var confidence_reasons: PackedStringArray = PackedStringArray()

# --- Features ---------------------------------------------------------------
var road: Dictionary = {}    # see TFRoad.metrics()
var tower: Dictionary = {}   # see TFTower.metrics()

# --- Traceability -----------------------------------------------------------
var formulas: Array[Dictionary] = []
var assumptions_used: Dictionary = {}


func balance_label() -> String:
	if import_bank_m3 > 0.001:
		return "Import required"
	if export_bank_m3 > 0.001:
		return "Export required"
	return "Balanced on site"


func to_dict() -> Dictionary:
	return {
		"calc_version": calc_version,
		"computed_at_unix": computed_at_unix,
		"status": status,
		"units": {"length": "m", "area": "m2", "volume": "m3", "time": "h"},
		"geometry": {
			"site_area_m2": site_area_m2,
			"disturbed_area_m2": disturbed_area_m2,
			"existing_min_m": existing_min_m,
			"existing_max_m": existing_max_m,
			"proposed_min_m": proposed_min_m,
			"proposed_max_m": proposed_max_m,
			"max_cut_depth_m": max_cut_depth_m,
			"max_fill_depth_m": max_fill_depth_m,
			"max_slope_ratio": max_slope_ratio,
		},
		"volumes": {
			"cut_bank_m3": cut_bank_m3,
			"fill_compacted_m3": fill_compacted_m3,
			"net_geometric_m3": net_geometric_m3,
			"fill_bank_required_m3": fill_bank_required_m3,
			"onsite_reuse_bank_m3": onsite_reuse_bank_m3,
			"import_bank_m3": import_bank_m3,
			"export_bank_m3": export_bank_m3,
			"import_loose_m3": import_loose_m3,
			"export_loose_m3": export_loose_m3,
			"onsite_haul_loose_m3": onsite_haul_loose_m3,
			"total_haul_loose_m3": total_haul_loose_m3,
		},
		"trucking": {
			"truck_capacity_loose_m3": truck_capacity_loose_m3,
			"import_truckloads": import_truckloads,
			"export_truckloads": export_truckloads,
			"onsite_truckloads": onsite_truckloads,
			"total_truckloads": total_truckloads,
		},
		"numerics": {
			"cells_evaluated": cells_evaluated,
			"cells_refined": cells_refined,
			"grid_spacing_m": grid_spacing_m,
			"subdivision": subdivision,
			"confidence": confidence,
			"confidence_reasons": confidence_reasons,
		},
		"road": road,
		"tower": tower,
		"formulas": formulas,
		"assumptions_used": assumptions_used,
	}
