class_name TFCsvExport
extends RefCounted

## CSV writers. Units are carried in every column header, and each file starts
## with a small metadata block so a spreadsheet reader can never lose the
## project's status, units or calculation version.
##
## Format notes: RFC 4180 quoting, CRLF line endings, no BOM-dependent tricks.
## A UTF-8 BOM is written so Excel opens accented text correctly.

const NL := "\r\n"
const BOM := "﻿"


static func _q(v) -> String:
	var s := str(v)
	if s.contains("\"") or s.contains(",") or s.contains("\n") or s.contains("\r"):
		return "\"" + s.replace("\"", "\"\"") + "\""
	return s


static func _row(cells: Array) -> String:
	var parts := PackedStringArray()
	for c in cells:
		parts.append(_q(c))
	return ",".join(parts) + NL


static func _meta(p: TFProject, an: TFAnalysis, title: String) -> String:
	var u := p.settings.units
	var s := ""
	s += _row(["TerraForge export", title])
	s += _row(["Status", "CONCEPT SIMULATION - NOT FOR CONSTRUCTION"])
	s += _row(["Data status", p.settings.status_label()])
	s += _row(["Project", p.settings.project_name])
	s += _row(["Exported (UTC)", TFProjectSettings.format_time(int(Time.get_unix_time_from_system()))])
	s += _row(["Schema version", TFSchema.SCHEMA_VERSION])
	s += _row(["Calculation engine", TFAnalysis.CALC_ENGINE_VERSION])
	s += _row(["Length unit", u.length_label()])
	s += _row(["Area unit", u.area_label()])
	s += _row(["Volume unit", u.volume_label()])
	s += _row(["Coordinate system", p.settings.coordinate_system_label])
	s += _row(["Horizontal datum", p.settings.horizontal_datum])
	s += _row(["Vertical datum", p.settings.vertical_datum])
	if an != null:
		s += _row(["Calculation confidence", an.confidence])
	s += _row(["Estimate basis", "User-supplied illustrative rates. Not a quote, bid or supplier pricing."])
	s += NL
	return s


static func quantities_csv(p: TFProject, an: TFAnalysis) -> String:
	var u := p.settings.units
	var s := BOM + _meta(p, an, "Earthwork quantities")
	s += _row(["Item", "Value", "Unit", "Basis"])
	var L := u.length_label()
	var A := u.area_label()
	var V := u.volume_label()
	s += _row(["Site area", u.area(an.site_area_m2), A, "Grid extent"])
	s += _row(["Disturbed area", u.area(an.disturbed_area_m2), A, "Cells changed by more than 10 mm"])
	s += _row(["Existing minimum elevation", u.length(an.existing_min_m), L, "Original ground"])
	s += _row(["Existing maximum elevation", u.length(an.existing_max_m), L, "Original ground"])
	s += _row(["Proposed minimum elevation", u.length(an.proposed_min_m), L, "Design surface"])
	s += _row(["Proposed maximum elevation", u.length(an.proposed_max_m), L, "Design surface"])
	s += _row(["Maximum cut depth", u.length(an.max_cut_depth_m), L, "Node maximum of existing - proposed"])
	s += _row(["Maximum fill depth", u.length(an.max_fill_depth_m), L, "Node maximum of proposed - existing"])
	s += _row(["Maximum proposed slope", an.max_slope_ratio * 100.0, "percent", "Central-difference gradient magnitude"])
	s += _row(["Cut volume (bank, in place)", u.volume(an.cut_bank_m3), V, "Bilinear grid integral"])
	s += _row(["Fill volume (compacted, as designed)", u.volume(an.fill_compacted_m3), V, "Bilinear grid integral"])
	s += _row(["Net volume (fill - cut)", u.volume(an.net_geometric_m3), V, "Exact bilinear integral"])
	s += _row(["Fill required (bank)", u.volume(an.fill_bank_required_m3), V, "compacted / (1 - shrinkage %.3f)" % p.assumptions.shrinkage])
	s += _row(["On-site reuse (bank)", u.volume(an.onsite_reuse_bank_m3), V, "min(usable cut, fill required)"])
	s += _row(["Import required (bank)", u.volume(an.import_bank_m3), V, "Fill shortfall"])
	s += _row(["Export surplus (bank)", u.volume(an.export_bank_m3), V, "Unused cut"])
	s += _row(["Import (loose, hauled)", u.volume(an.import_loose_m3), V, "bank x (1 + swell %.3f)" % p.assumptions.swell])
	s += _row(["Export (loose, hauled)", u.volume(an.export_loose_m3), V, "bank x (1 + swell %.3f)" % p.assumptions.swell])
	s += _row(["On-site haul (loose)", u.volume(an.onsite_haul_loose_m3), V, "bank x (1 + swell)"])
	s += _row(["Total haul (loose)", u.volume(an.total_haul_loose_m3), V, "import + export + on-site"])
	s += _row(["Truck capacity (loose)", u.volume(an.truck_capacity_loose_m3), V, "User assumption"])
	s += _row(["Import truckloads", an.import_truckloads, "loads", "ceil(loose / capacity)"])
	s += _row(["Export truckloads", an.export_truckloads, "loads", "ceil(loose / capacity)"])
	s += _row(["On-site truckloads", an.onsite_truckloads, "loads", "ceil(loose / capacity)"])
	s += _row(["Total truckloads", an.total_truckloads, "loads", "Sum of the three"])
	s += _row(["Material balance", an.balance_label(), "-", "Comparison of usable cut with fill required"])
	if not an.road.is_empty():
		s += NL
		s += _row(["Road alignment (proposed)", "", "", ""])
		s += _row(["Length", u.length(float(an.road["length_m"])), L, "Resampled centreline"])
		s += _row(["Width", u.length(float(an.road["width_m"])), L, "User input"])
		s += _row(["Corridor area", u.area(float(an.road["corridor_area_m2"])), A, "length x width"])
		s += _row(["Maximum grade", float(an.road["max_grade"]) * 100.0, "percent", "Design profile"])
		s += _row(["Maximum grade limit", float(an.road["max_grade_limit"]) * 100.0, "percent", "User input"])
		s += _row(["Elevation gain", u.length(float(an.road["elevation_gain_m"])), L, "Profile maximum - minimum"])
		s += _row(["Surfacing volume", u.volume(float(an.road["surfacing_volume_m3"])), V, "corridor area x thickness"])
	if not an.tower.is_empty():
		s += NL
		s += _row(["Structure (proposed placeholder)", "", "", ""])
		s += _row(["Pad area", u.area(float(an.tower["pad_area_m2"])), A, "Square pad"])
		s += _row(["Pad elevation", u.length(float(an.tower["pad_elevation_m"])), L, "Design"])
		s += _row(["Height", u.length(float(an.tower["height_m"])), L, "User input"])
		s += _row(["Foundation excavation", u.volume(float(an.tower["excavation_volume_m3"])), V, "PLACEHOLDER - not a foundation design"])
		s += _row(["Concrete (placeholder)", u.volume(float(an.tower["concrete_volume_m3"])), V, "PLACEHOLDER - not a structural design"])
	s += NL
	s += _row(["Calculation confidence", an.confidence, "-", ""])
	for r in an.confidence_reasons:
		s += _row(["", "", "", r])
	return s


static func estimate_csv(p: TFProject, an: TFAnalysis, seq: TFSequence) -> String:
	var a := p.assumptions
	var u := p.settings.units
	var s := BOM + _meta(p, an, "Preliminary estimate")
	s += _row(["Cost category", "Expected (%s)" % a.currency, "Low (%s)" % a.currency, "High (%s)" % a.currency])
	var lo := a.cost_low_factor
	var hi := a.cost_high_factor
	for k in ["equipment", "labor", "trucking", "material", "disposal", "other"]:
		var v := float(seq.cost_breakdown.get(k, 0.0))
		s += _row([k.capitalize(), v, v * lo, v * hi])
	s += _row(["TOTAL", seq.cost_expected, seq.cost_low, seq.cost_high])
	s += NL
	s += _row(["Schedule", "Value", "Unit", ""])
	s += _row(["Total duration", seq.total_duration_hours, "h", ""])
	s += _row(["Total duration", seq.total_duration_days, "workdays of %.1f h" % seq.workday_hours, ""])
	s += _row(["Total duration", seq.total_duration_weeks, "weeks of %.1f workdays" % seq.workdays_per_week, ""])
	s += NL
	s += _row(["Assumption", "Value", "Unit", "Source"])
	for key in TFAssumptions.SPEC.keys():
		var spec: Dictionary = TFAssumptions.SPEC[key]
		var raw = a.get(key)
		var unit := String(spec.get("unit", ""))
		var display = raw
		var unit_label := unit
		match unit:
			"length":
				display = u.length(float(raw)); unit_label = u.length_label()
			"volume":
				display = u.volume(float(raw)); unit_label = u.volume_label()
			"vol/h":
				display = u.volume(float(raw)); unit_label = "%s/h" % u.volume_label()
			"area/h":
				display = u.area(float(raw)); unit_label = "%s/h" % u.area_label()
			"cur":
				unit_label = a.currency
			"cur/h":
				unit_label = "%s/h" % a.currency
			"cur/vol":
				display = float(raw) / (u.volume(1.0) if u.volume(1.0) != 0.0 else 1.0)
				unit_label = "%s/%s" % [a.currency, u.volume_label()]
			"cur/len":
				display = float(raw) / (u.length(1.0) if u.length(1.0) != 0.0 else 1.0)
				unit_label = "%s/%s" % [a.currency, u.length_label()]
		s += _row([String(spec["label"]), display, unit_label, TFAssumptions.SOURCE_LABEL])
	return s


static func sequence_csv(p: TFProject, an: TFAnalysis, seq: TFSequence) -> String:
	var u := p.settings.units
	var a := p.assumptions
	var s := BOM + _meta(p, an, "Construction sequence")
	s += _row(["#", "Step ID", "Step", "Phase", "Applicable", "Reason if omitted",
		"Prerequisites", "Start (h)", "End (h)", "Duration (h)", "Duration (workdays)",
		"Material moved (%s bank)" % u.volume_label(), "Truckloads",
		"Machine hours", "Crew size", "Crew hours",
		"Equipment cost (%s)" % a.currency, "Labor cost (%s)" % a.currency,
		"Trucking cost (%s)" % a.currency, "Material cost (%s)" % a.currency,
		"Disposal cost (%s)" % a.currency, "Other cost (%s)" % a.currency,
		"Total cost (%s)" % a.currency, "Cumulative cost (%s)" % a.currency,
		"Equipment", "Status", "Warnings"])
	var i := 0
	for st in seq.steps:
		i += 1
		var eq := PackedStringArray()
		for e in st.equipment:
			eq.append("%d x %s (%.1f h)" % [int(e["count"]), TFEquipment.label(String(e["key"])), float(e["hours"])])
		s += _row([i, st.id, st.name, st.phase, "yes" if st.applicable else "no",
			st.not_applicable_reason, " | ".join(st.prerequisites),
			st.start_hours, st.end_hours, st.duration_hours, st.duration_days,
			u.volume(float(st.material.get("bank_m3", 0.0))), st.truckloads,
			st.machine_hours(), st.crew_size, st.crew_hours,
			st.cost.get("equipment", 0.0), st.cost.get("labor", 0.0),
			st.cost.get("trucking", 0.0), st.cost.get("material", 0.0),
			st.cost.get("disposal", 0.0), st.cost.get("other", 0.0),
			st.total_cost(), st.cumulative_cost,
			" | ".join(eq), st.status, " | ".join(st.warnings)])
	return s


static func equipment_csv(p: TFProject, an: TFAnalysis, seq: TFSequence) -> String:
	var a := p.assumptions
	var s := BOM + _meta(p, an, "Equipment plan")
	s += _row(["Equipment class", "Category", "Peak units", "Machine hours",
		"Indicative cost (%s)" % a.currency, "Why it was selected", "Production basis", "Used in steps"])
	for e in TFEquipment.plan_from_steps(seq.steps):
		var rate := a.trucking_rate_per_hour if String(e["category"]) == "hauling" else a.equipment_rate_per_hour
		s += _row([e["label"], e["category"], e["peak_count"], e["machine_hours"],
			float(e["machine_hours"]) * rate, e["reason"],
			" | ".join(e["production_basis"]), " | ".join(e["steps"])])
	return s


static func write(path: String, text: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "Cannot write %s (%s)." % [path, error_string(FileAccess.get_open_error())]}
	f.store_string(text)
	f.close()
	return {"ok": true, "path": path, "bytes": text.length()}
