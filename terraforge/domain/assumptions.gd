class_name TFAssumptions
extends RefCounted

## Editable estimating assumptions.
##
## IMPORTANT: every default here is an ILLUSTRATIVE PLACEHOLDER, not a live
## supplier quote, not a published index, and not a local market rate. The UI
## and every export label them as user-supplied / illustrative. Replace them
## with your own verified rates before the numbers mean anything.

const SOURCE_LABEL := "User-supplied / illustrative default - not a supplier quote"

# --- Material -----------------------------------------------------------------
var soil_type: String = "common_earth"
## Shrinkage: fraction of BANK volume lost when compacted into fill.
##   compacted = bank * (1 - shrinkage)
var shrinkage: float = 0.12
## Swell: fraction of BANK volume gained when excavated to LOOSE (haul) state.
##   loose = bank * (1 + swell)
var swell: float = 0.25
## Fraction of excavated material judged unsuitable for structural fill.
var unsuitable_fraction: float = 0.05

# --- Trucking -----------------------------------------------------------------
var truck_capacity_loose_m3: float = 12.0
var haul_distance_one_way_m: float = 8000.0
var truck_cycle_minutes: float = 45.0
var onsite_haul_distance_m: float = 250.0
var onsite_cycle_minutes: float = 8.0

# --- Calendar / crew ----------------------------------------------------------
var workday_hours: float = 9.0
var workdays_per_week: float = 5.0
var crew_size: int = 6
var efficiency_factor: float = 0.75   # job efficiency (50 min hour etc.)

# --- Production rates (bank m3 per machine-hour unless noted) -----------------
var excavator_bcm_per_hour: float = 110.0
var dozer_bcm_per_hour: float = 150.0
var loader_bcm_per_hour: float = 130.0
var compactor_ccm_per_hour: float = 180.0    # compacted m3 per hour
var grader_m2_per_hour: float = 3000.0       # finished surface area per hour
var stripping_m2_per_hour: float = 2200.0    # topsoil strip area per hour
var clearing_m2_per_hour: float = 2600.0

# --- Rates (currency per unit) -------------------------------------------------
var currency: String = "USD"
var labor_rate_per_hour: float = 48.0
var equipment_rate_per_hour: float = 145.0
var trucking_rate_per_hour: float = 105.0
var import_material_price_per_m3: float = 18.0
var disposal_price_per_m3: float = 14.0
var mobilization_cost: float = 8500.0
var testing_allowance: float = 2500.0
var erosion_control_per_m: float = 12.0
var concrete_price_per_m3: float = 210.0

# --- Uncertainty ---------------------------------------------------------------
var cost_low_factor: float = 0.80
var cost_high_factor: float = 1.45

# --- Layer / lift geometry -----------------------------------------------------
var topsoil_depth_m: float = 0.15
var lift_thickness_m: float = 0.30

## Soil presets are textbook ranges, included so a first-time user has a sane
## starting point. They are still illustrative.
const SOIL_PRESETS := {
	"sand_gravel": {"label": "Sand / gravel", "shrinkage": 0.06, "swell": 0.14, "excavator_bcm_per_hour": 130.0},
	"common_earth": {"label": "Common earth / loam", "shrinkage": 0.12, "swell": 0.25, "excavator_bcm_per_hour": 110.0},
	"clay": {"label": "Clay", "shrinkage": 0.18, "swell": 0.35, "excavator_bcm_per_hour": 85.0},
	"weathered_rock": {"label": "Weathered rock", "shrinkage": -0.10, "swell": 0.50, "excavator_bcm_per_hour": 55.0},
}


func apply_soil_preset(key: String) -> void:
	if not SOIL_PRESETS.has(key):
		return
	soil_type = key
	var p: Dictionary = SOIL_PRESETS[key]
	shrinkage = float(p["shrinkage"])
	swell = float(p["swell"])
	excavator_bcm_per_hour = float(p["excavator_bcm_per_hour"])


func soil_label() -> String:
	if SOIL_PRESETS.has(soil_type):
		return String(SOIL_PRESETS[soil_type]["label"])
	return soil_type


## Bank volume needed to build one cubic metre of compacted fill.
func bank_per_compacted() -> float:
	var denom := 1.0 - shrinkage
	if denom <= 0.01:
		denom = 0.01
	return 1.0 / denom


## Loose (hauled) volume produced by one cubic metre of bank material.
func loose_per_bank() -> float:
	return 1.0 + maxf(swell, -0.9)


func duplicate_assumptions() -> TFAssumptions:
	var a := TFAssumptions.new()
	for k in _fields():
		a.set(k, get(k))
	return a


func _fields() -> PackedStringArray:
	var out := PackedStringArray()
	for p in get_property_list():
		if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out.append(String(p["name"]))
	return out


func to_dict() -> Dictionary:
	var d := {}
	for k in _fields():
		d[k] = get(k)
	d["_source"] = SOURCE_LABEL
	return d


static func from_dict(d: Dictionary) -> TFAssumptions:
	var a := TFAssumptions.new()
	for k in a._fields():
		if d.has(k):
			var cur = a.get(k)
			var v = d[k]
			if cur is int:
				a.set(k, int(v))
			elif cur is float:
				a.set(k, float(v))
			elif cur is String:
				a.set(k, String(v))
			else:
				a.set(k, v)
	return a


## Human-readable, unit-carrying descriptors used by the UI and the exports.
## key -> {label, unit, min, max, step, group, help}
const SPEC := {
	"soil_type": {"label": "Soil category", "unit": "", "group": "Material", "kind": "soil", "help": "Drives shrinkage, swell and excavator production defaults."},
	"shrinkage": {"label": "Shrinkage", "unit": "fraction", "group": "Material", "min": -0.5, "max": 0.6, "step": 0.01, "help": "Bank volume lost when compacted: compacted = bank x (1 - shrinkage)."},
	"swell": {"label": "Swell", "unit": "fraction", "group": "Material", "min": -0.5, "max": 1.5, "step": 0.01, "help": "Bank volume gained when loosened for haul: loose = bank x (1 + swell)."},
	"unsuitable_fraction": {"label": "Unsuitable material", "unit": "fraction", "group": "Material", "min": 0.0, "max": 0.9, "step": 0.01, "help": "Share of excavated material assumed unusable as structural fill."},
	"topsoil_depth_m": {"label": "Topsoil depth", "unit": "length", "group": "Material", "min": 0.0, "max": 1.5, "step": 0.01, "help": "Strip depth assumed over the disturbed area."},
	"lift_thickness_m": {"label": "Compacted lift", "unit": "length", "group": "Material", "min": 0.05, "max": 1.0, "step": 0.01, "help": "Thickness of each placed and compacted layer."},
	"truck_capacity_loose_m3": {"label": "Truck capacity (loose)", "unit": "volume", "group": "Trucking", "min": 0.0, "max": 100.0, "step": 0.5, "help": "Struck+heaped loose volume per haul truck."},
	"haul_distance_one_way_m": {"label": "Off-site haul distance", "unit": "length", "group": "Trucking", "min": 0.0, "max": 200000.0, "step": 100.0, "help": "One-way distance to borrow pit or disposal site."},
	"truck_cycle_minutes": {"label": "Off-site truck cycle", "unit": "min", "group": "Trucking", "min": 1.0, "max": 600.0, "step": 1.0, "help": "Load + haul + dump + return, per truck."},
	"onsite_haul_distance_m": {"label": "On-site haul distance", "unit": "length", "group": "Trucking", "min": 0.0, "max": 20000.0, "step": 10.0},
	"onsite_cycle_minutes": {"label": "On-site truck cycle", "unit": "min", "group": "Trucking", "min": 0.5, "max": 240.0, "step": 0.5},
	"workday_hours": {"label": "Workday", "unit": "h", "group": "Calendar", "min": 1.0, "max": 24.0, "step": 0.5},
	"workdays_per_week": {"label": "Workdays / week", "unit": "d", "group": "Calendar", "min": 1.0, "max": 7.0, "step": 0.5},
	"crew_size": {"label": "Crew size", "unit": "people", "group": "Calendar", "min": 1, "max": 60, "step": 1},
	"efficiency_factor": {"label": "Job efficiency", "unit": "fraction", "group": "Calendar", "min": 0.2, "max": 1.0, "step": 0.05, "help": "Productive fraction of each machine hour."},
	"excavator_bcm_per_hour": {"label": "Excavator production", "unit": "vol/h", "group": "Production", "min": 1.0, "max": 1000.0, "step": 5.0},
	"dozer_bcm_per_hour": {"label": "Dozer production", "unit": "vol/h", "group": "Production", "min": 1.0, "max": 1000.0, "step": 5.0},
	"loader_bcm_per_hour": {"label": "Loader production", "unit": "vol/h", "group": "Production", "min": 1.0, "max": 1000.0, "step": 5.0},
	"compactor_ccm_per_hour": {"label": "Compactor production", "unit": "vol/h", "group": "Production", "min": 1.0, "max": 2000.0, "step": 5.0},
	"grader_m2_per_hour": {"label": "Grader production", "unit": "area/h", "group": "Production", "min": 10.0, "max": 50000.0, "step": 50.0},
	"stripping_m2_per_hour": {"label": "Topsoil strip production", "unit": "area/h", "group": "Production", "min": 10.0, "max": 50000.0, "step": 50.0},
	"clearing_m2_per_hour": {"label": "Clearing production", "unit": "area/h", "group": "Production", "min": 10.0, "max": 50000.0, "step": 50.0},
	"labor_rate_per_hour": {"label": "Labor rate", "unit": "cur/h", "group": "Rates", "min": 0.0, "max": 1000.0, "step": 1.0},
	"equipment_rate_per_hour": {"label": "Equipment rate", "unit": "cur/h", "group": "Rates", "min": 0.0, "max": 5000.0, "step": 1.0},
	"trucking_rate_per_hour": {"label": "Trucking rate", "unit": "cur/h", "group": "Rates", "min": 0.0, "max": 5000.0, "step": 1.0},
	"import_material_price_per_m3": {"label": "Import material price", "unit": "cur/vol", "group": "Rates", "min": 0.0, "max": 1000.0, "step": 0.5},
	"disposal_price_per_m3": {"label": "Disposal price", "unit": "cur/vol", "group": "Rates", "min": 0.0, "max": 1000.0, "step": 0.5},
	"concrete_price_per_m3": {"label": "Concrete price", "unit": "cur/vol", "group": "Rates", "min": 0.0, "max": 5000.0, "step": 1.0},
	"erosion_control_per_m": {"label": "Erosion control", "unit": "cur/len", "group": "Rates", "min": 0.0, "max": 1000.0, "step": 0.5},
	"mobilization_cost": {"label": "Mobilization", "unit": "cur", "group": "Rates", "min": 0.0, "max": 1000000.0, "step": 100.0},
	"testing_allowance": {"label": "Testing allowance", "unit": "cur", "group": "Rates", "min": 0.0, "max": 1000000.0, "step": 100.0},
	"cost_low_factor": {"label": "Low estimate factor", "unit": "x", "group": "Uncertainty", "min": 0.1, "max": 1.0, "step": 0.01},
	"cost_high_factor": {"label": "High estimate factor", "unit": "x", "group": "Uncertainty", "min": 1.0, "max": 5.0, "step": 0.01},
}
