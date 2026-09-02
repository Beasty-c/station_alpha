class_name TFSequence
extends RefCounted

## An ordered construction sequence plus its schedule and cost roll-up.

const SEQUENCE_VERSION := "1.1.0"

var version: String = SEQUENCE_VERSION
var generated_unix: int = 0
var status: String = "simulated"
var steps: Array[TFStep] = []

var total_duration_hours: float = 0.0
var total_duration_days: float = 0.0
var total_duration_weeks: float = 0.0
var workday_hours: float = 9.0
var workdays_per_week: float = 5.0

var cost_expected: float = 0.0
var cost_low: float = 0.0
var cost_high: float = 0.0
var currency: String = "USD"
var cost_breakdown: Dictionary = {}
var warnings: PackedStringArray = PackedStringArray()
var confidence: String = "low"


func applicable_steps() -> Array[TFStep]:
	var out: Array[TFStep] = []
	for s in steps:
		if s.applicable:
			out.append(s)
	return out


## Assigns start/end times, cumulative quantities and the cost roll-up.
## Prerequisites are respected because the generator emits steps in a valid
## topological order; this asserts it rather than assuming it.
func finalize(a: TFAssumptions, low_factor: float, high_factor: float) -> void:
	workday_hours = maxf(0.5, a.workday_hours)
	workdays_per_week = clampf(a.workdays_per_week, 1.0, 7.0)
	currency = a.currency

	var seen := {}
	var t := 0.0
	var cum_cost := 0.0
	var cum_bank := 0.0
	var cum_loads := 0
	var breakdown := {"equipment": 0.0, "labor": 0.0, "trucking": 0.0,
		"material": 0.0, "disposal": 0.0, "other": 0.0}

	for s in steps:
		for p in s.prerequisites:
			if not seen.has(p):
				s.warnings.append("Prerequisite '%s' is not scheduled before this step." % p)
		seen[s.id] = true
		if not s.applicable:
			s.start_hours = t
			s.end_hours = t
			s.cumulative_cost = cum_cost
			s.cumulative_bank_m3 = cum_bank
			s.cumulative_truckloads = cum_loads
			continue
		s.recompute_total()
		s.start_hours = t
		t += maxf(0.0, s.duration_hours)
		s.end_hours = t
		cum_cost += s.total_cost()
		cum_bank += float(s.material.get("bank_m3", 0.0))
		cum_loads += s.truckloads
		s.cumulative_cost = cum_cost
		s.cumulative_bank_m3 = cum_bank
		s.cumulative_truckloads = cum_loads
		for k in breakdown.keys():
			breakdown[k] = float(breakdown[k]) + float(s.cost.get(k, 0.0))

	total_duration_hours = t
	total_duration_days = t / workday_hours
	total_duration_weeks = total_duration_days / workdays_per_week
	cost_expected = cum_cost
	cost_low = cum_cost * low_factor
	cost_high = cum_cost * high_factor
	cost_breakdown = breakdown


## Terrain progress vector at a global timeline position (hours).
func state_at_hours(hours: float) -> Dictionary:
	var applicable := applicable_steps()
	if applicable.is_empty():
		return TFStep.ZERO_STATE.duplicate()
	var h: float = clampf(hours, 0.0, total_duration_hours)
	var last := applicable[applicable.size() - 1]
	if h >= last.end_hours:
		return last.state_to.duplicate()
	for s in applicable:
		if h <= s.end_hours:
			var span: float = maxf(1e-6, s.end_hours - s.start_hours)
			var f: float = clampf((h - s.start_hours) / span, 0.0, 1.0)
			return lerp_state(s.state_from, s.state_to, f)
	return last.state_to.duplicate()


## Which applicable step contains a timeline position, and how far into it.
func locate(hours: float) -> Dictionary:
	var applicable := applicable_steps()
	if applicable.is_empty():
		return {"step": null, "index": -1, "t": 0.0}
	var h: float = clampf(hours, 0.0, total_duration_hours)
	for i in applicable.size():
		var s := applicable[i]
		if h <= s.end_hours or i == applicable.size() - 1:
			var span: float = maxf(1e-6, s.end_hours - s.start_hours)
			return {"step": s, "index": i, "t": clampf((h - s.start_hours) / span, 0.0, 1.0)}
	return {"step": applicable[applicable.size() - 1], "index": applicable.size() - 1, "t": 1.0}


static func lerp_state(a: Dictionary, b: Dictionary, f: float) -> Dictionary:
	var out := {}
	for k in TFStep.ZERO_STATE.keys():
		out[k] = lerpf(float(a.get(k, 0.0)), float(b.get(k, 0.0)), f)
	return out


## Cumulative quantities at a timeline position, interpolated inside the
## running step so the live panel moves smoothly with the scrub bar.
func cumulative_at_hours(hours: float) -> Dictionary:
	var loc := locate(hours)
	var s: TFStep = loc["step"]
	if s == null:
		return {"cost": 0.0, "bank_m3": 0.0, "truckloads": 0, "hours": 0.0, "step_name": "-"}
	var f := float(loc["t"])
	var prev_cost: float = s.cumulative_cost - s.total_cost()
	var prev_bank: float = s.cumulative_bank_m3 - float(s.material.get("bank_m3", 0.0))
	var prev_loads: int = s.cumulative_truckloads - s.truckloads
	return {
		"cost": prev_cost + s.total_cost() * f,
		"bank_m3": prev_bank + float(s.material.get("bank_m3", 0.0)) * f,
		"truckloads": int(round(float(prev_loads) + float(s.truckloads) * f)),
		"hours": clampf(hours, 0.0, total_duration_hours),
		"step_name": s.name,
		"step_index": int(loc["index"]),
		"step_t": f,
	}


func to_dict() -> Dictionary:
	var arr := []
	for s in steps:
		arr.append(s.to_dict())
	return {
		"version": version,
		"generated_unix": generated_unix,
		"status": status,
		"steps": arr,
		"schedule": {
			"total_duration_hours": total_duration_hours,
			"total_duration_days": total_duration_days,
			"total_duration_weeks": total_duration_weeks,
			"workday_hours": workday_hours,
			"workdays_per_week": workdays_per_week,
		},
		"estimate": {
			"currency": currency,
			"expected": cost_expected,
			"low": cost_low,
			"high": cost_high,
			"breakdown": cost_breakdown,
			"confidence": confidence,
			"basis": "Preliminary modelled estimate from user-supplied illustrative rates. Not a quote, bid, or supplier pricing.",
		},
		"warnings": warnings,
	}


static func from_dict(d: Dictionary) -> TFSequence:
	var q := TFSequence.new()
	q.version = String(d.get("version", SEQUENCE_VERSION))
	q.generated_unix = int(d.get("generated_unix", 0))
	q.status = String(d.get("status", "simulated"))
	var steps_arr: Array[TFStep] = []
	for e in d.get("steps", []):
		steps_arr.append(TFStep.from_dict(e))
	q.steps = steps_arr
	var sch: Dictionary = d.get("schedule", {})
	q.total_duration_hours = float(sch.get("total_duration_hours", 0.0))
	q.total_duration_days = float(sch.get("total_duration_days", 0.0))
	q.total_duration_weeks = float(sch.get("total_duration_weeks", 0.0))
	q.workday_hours = float(sch.get("workday_hours", 9.0))
	q.workdays_per_week = float(sch.get("workdays_per_week", 5.0))
	var est: Dictionary = d.get("estimate", {})
	q.currency = String(est.get("currency", "USD"))
	q.cost_expected = float(est.get("expected", 0.0))
	q.cost_low = float(est.get("low", 0.0))
	q.cost_high = float(est.get("high", 0.0))
	q.cost_breakdown = est.get("breakdown", {})
	q.confidence = String(est.get("confidence", "low"))
	var w := PackedStringArray()
	for x in d.get("warnings", []):
		w.append(String(x))
	q.warnings = w
	return q
