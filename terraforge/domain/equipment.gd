class_name TFEquipment
extends RefCounted

## Representative equipment classes and the reasoning that selects them.
##
## These are generic machine CLASSES, not specific makes, models, or rental
## listings. Hours come from the production assumptions the user can edit, and
## every selection carries the reason it was made.

const CATALOG := {
	"survey_crew": {
		"label": "Survey crew + total station",
		"category": "layout",
		"color": [0.98, 0.55, 0.13],
		"reason": "Control points and proposed stakeout locations must be set out before earthmoving begins.",
	},
	"dozer_d6": {
		"label": "Crawler dozer (~145 kW / D6 class)",
		"category": "earthmoving",
		"color": [0.95, 0.76, 0.13],
		"reason": "Efficient for pushing, spreading and rough grading over short distances on an open site.",
	},
	"excavator_20t": {
		"label": "Hydraulic excavator (20 t class)",
		"category": "earthmoving",
		"color": [0.95, 0.70, 0.10],
		"reason": "Selected for bulk excavation and truck loading where material must be lifted rather than pushed.",
	},
	"wheel_loader": {
		"label": "Wheel loader (3.5 m3 bucket)",
		"category": "earthmoving",
		"color": [0.93, 0.66, 0.15],
		"reason": "Loads stockpiled and imported material into haul trucks and feeds the placement crew.",
	},
	"motor_grader": {
		"label": "Motor grader (~4.0 m blade)",
		"category": "grading",
		"color": [0.86, 0.72, 0.25],
		"reason": "Required to hold line and grade on the road running surface and the finished site surface.",
	},
	"sheepsfoot_compactor": {
		"label": "Padfoot / sheepsfoot compactor",
		"category": "compaction",
		"color": [0.65, 0.72, 0.40],
		"reason": "Chosen for cohesive structural fill placed in lifts, where kneading action is needed.",
	},
	"smooth_drum_roller": {
		"label": "Smooth drum vibratory roller",
		"category": "compaction",
		"color": [0.60, 0.70, 0.48],
		"reason": "Seals and finishes the road running surface and granular capping layers.",
	},
	"water_truck": {
		"label": "Water truck (10 000 L)",
		"category": "support",
		"color": [0.35, 0.62, 0.82],
		"reason": "Moisture conditioning for compaction and dust control over the disturbed area.",
	},
	"haul_truck": {
		"label": "Articulated haul truck",
		"category": "hauling",
		"color": [0.90, 0.60, 0.20],
		"reason": "Moves material between cut and fill areas on unfinished ground.",
	},
	"highway_dump": {
		"label": "Highway dump truck / tandem",
		"category": "hauling",
		"color": [0.88, 0.52, 0.18],
		"reason": "Carries imported or exported material over public roads to and from the site.",
	},
	"skid_steer": {
		"label": "Skid steer loader",
		"category": "support",
		"color": [0.80, 0.62, 0.28],
		"reason": "Handles erosion control, small trenching and detail work around structures.",
	},
	"mobile_crane": {
		"label": "Mobile crane (50 t class)",
		"category": "structures",
		"color": [0.75, 0.75, 0.78],
		"reason": "Lifts tower sections; capacity class assumed from tower height and section weight placeholder.",
	},
	"concrete_truck": {
		"label": "Concrete mixer truck",
		"category": "structures",
		"color": [0.72, 0.72, 0.74],
		"reason": "Delivers the placeholder foundation concrete quantity.",
	},
	"hydroseeder": {
		"label": "Hydroseeder / mulcher",
		"category": "stabilisation",
		"color": [0.45, 0.68, 0.42],
		"reason": "Establishes vegetative cover for permanent surface stabilisation.",
	},
}


static func label(key: String) -> String:
	if CATALOG.has(key):
		return String(CATALOG[key]["label"])
	return key


static func reason(key: String) -> String:
	if CATALOG.has(key):
		return String(CATALOG[key]["reason"])
	return ""


static func category(key: String) -> String:
	if CATALOG.has(key):
		return String(CATALOG[key]["category"])
	return "other"


static func color(key: String) -> Color:
	if CATALOG.has(key):
		var c: Array = CATALOG[key]["color"]
		return Color(c[0], c[1], c[2])
	return Color(0.7, 0.7, 0.7)


## Aggregate a fleet from generated construction steps.
## Returns an array of {key, label, category, reason, machine_hours, peak_count,
## steps, production_basis}.
static func plan_from_steps(steps: Array) -> Array[Dictionary]:
	var acc := {}
	for s in steps:
		if not s.applicable:
			continue
		for e in s.equipment:
			var k := String(e["key"])
			if not acc.has(k):
				acc[k] = {
					"key": k,
					"label": label(k),
					"category": category(k),
					"reason": reason(k),
					"machine_hours": 0.0,
					"peak_count": 0,
					"steps": PackedStringArray(),
					"production_basis": PackedStringArray(),
				}
			var rec: Dictionary = acc[k]
			rec["machine_hours"] = float(rec["machine_hours"]) + float(e.get("hours", 0.0))
			rec["peak_count"] = maxi(int(rec["peak_count"]), int(e.get("count", 1)))
			(rec["steps"] as PackedStringArray).append(s.name)
			var basis := String(e.get("basis", ""))
			if basis != "" and not (rec["production_basis"] as PackedStringArray).has(basis):
				(rec["production_basis"] as PackedStringArray).append(basis)
	var out: Array[Dictionary] = []
	for k in acc.keys():
		out.append(acc[k])
	out.sort_custom(func(a, b): return float(a["machine_hours"]) > float(b["machine_hours"]))
	return out
