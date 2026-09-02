class_name TFStep
extends RefCounted

## One construction activity.
##
## A step is the unit that drives BOTH the schedule/cost roll-up and the 3D
## playback. `state_from` / `state_to` are the terrain progress vector at the
## start and end of the step, so the playback surface is a pure function of
## (step, t) - it is never the other way round.

## Terrain progress vector. Each component is 0..1.
##   strip : topsoil stripped over the disturbed area
##   cut   : excavation front descending  (existing -> mass-grading target)
##   fill  : fill front rising            (existing -> mass-grading target)
##   form  : road corridor and pad formed (mass target -> final proposed)
##   tower : tower construction progress
const ZERO_STATE := {"strip": 0.0, "cut": 0.0, "fill": 0.0, "form": 0.0, "tower": 0.0}

var id: String = ""
var name: String = ""
var phase: String = ""
var description: String = ""
var prerequisites: PackedStringArray = PackedStringArray()

var zone: Dictionary = {"type": "site"}          # site | circle | corridor | rect
var material: Dictionary = {"bank_m3": 0.0, "loose_m3": 0.0, "compacted_m3": 0.0, "direction": "none"}
var equipment: Array[Dictionary] = []            # {key, count, hours, basis}
var crew_size: int = 0
var crew_hours: float = 0.0

var duration_hours: float = 0.0
var duration_days: float = 0.0
var cost: Dictionary = {"equipment": 0.0, "labor": 0.0, "trucking": 0.0,
	"material": 0.0, "disposal": 0.0, "other": 0.0, "total": 0.0}

var state_from: Dictionary = ZERO_STATE.duplicate()
var state_to: Dictionary = ZERO_STATE.duplicate()
var visual: Dictionary = {}                      # playback hints, see TFPlayback

var applicable: bool = true
var not_applicable_reason: String = ""
var status: String = "simulated"
var warnings: PackedStringArray = PackedStringArray()
var basis: PackedStringArray = PackedStringArray()   # formula trace

# Filled in by TFSequence.finalize()
var start_hours: float = 0.0
var end_hours: float = 0.0
var cumulative_cost: float = 0.0
var cumulative_bank_m3: float = 0.0
var cumulative_truckloads: int = 0
var truckloads: int = 0


func total_cost() -> float:
	return float(cost.get("total", 0.0))


func recompute_total() -> void:
	var t := 0.0
	for k in ["equipment", "labor", "trucking", "material", "disposal", "other"]:
		t += float(cost.get(k, 0.0))
	cost["total"] = t


func machine_hours() -> float:
	var h := 0.0
	for e in equipment:
		h += float(e.get("hours", 0.0))
	return h


func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "phase": phase, "description": description,
		"prerequisites": prerequisites, "zone": zone, "material": material,
		"equipment": equipment, "crew_size": crew_size, "crew_hours": crew_hours,
		"duration_hours": duration_hours, "duration_days": duration_days,
		"cost": cost, "state_from": state_from, "state_to": state_to,
		"visual": visual, "applicable": applicable,
		"not_applicable_reason": not_applicable_reason, "status": status,
		"warnings": warnings, "basis": basis,
		"start_hours": start_hours, "end_hours": end_hours,
		"truckloads": truckloads,
		"cumulative_cost": cumulative_cost,
		"cumulative_bank_m3": cumulative_bank_m3,
		"cumulative_truckloads": cumulative_truckloads,
	}


static func from_dict(d: Dictionary) -> TFStep:
	var s := TFStep.new()
	s.id = String(d.get("id", ""))
	s.name = String(d.get("name", ""))
	s.phase = String(d.get("phase", ""))
	s.description = String(d.get("description", ""))
	var pr := PackedStringArray()
	for p in d.get("prerequisites", []):
		pr.append(String(p))
	s.prerequisites = pr
	s.zone = d.get("zone", {"type": "site"})
	s.material = d.get("material", s.material)
	var eq: Array[Dictionary] = []
	for e in d.get("equipment", []):
		eq.append(e)
	s.equipment = eq
	s.crew_size = int(d.get("crew_size", 0))
	s.crew_hours = float(d.get("crew_hours", 0.0))
	s.duration_hours = float(d.get("duration_hours", 0.0))
	s.duration_days = float(d.get("duration_days", 0.0))
	s.cost = d.get("cost", s.cost)
	s.state_from = d.get("state_from", ZERO_STATE.duplicate())
	s.state_to = d.get("state_to", ZERO_STATE.duplicate())
	s.visual = d.get("visual", {})
	s.applicable = bool(d.get("applicable", true))
	s.not_applicable_reason = String(d.get("not_applicable_reason", ""))
	s.status = String(d.get("status", "simulated"))
	var w := PackedStringArray()
	for x in d.get("warnings", []):
		w.append(String(x))
	s.warnings = w
	var b := PackedStringArray()
	for x in d.get("basis", []):
		b.append(String(x))
	s.basis = b
	s.start_hours = float(d.get("start_hours", 0.0))
	s.end_hours = float(d.get("end_hours", 0.0))
	s.truckloads = int(d.get("truckloads", 0))
	s.cumulative_cost = float(d.get("cumulative_cost", 0.0))
	s.cumulative_bank_m3 = float(d.get("cumulative_bank_m3", 0.0))
	s.cumulative_truckloads = int(d.get("cumulative_truckloads", 0))
	return s
