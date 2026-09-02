class_name TFReport
extends RefCounted

## Print-friendly preliminary summary.
##
## `build_sections()` returns structured data that the in-app report view and
## the exported HTML both render, so the printed page and the screen can never
## drift apart. The HTML has a print stylesheet and no external resources.

static func build_sections(p: TFProject, an: TFAnalysis, seq: TFSequence) -> Array[Dictionary]:
	var u := p.settings.units
	var a := p.assumptions
	var out: Array[Dictionary] = []

	out.append({"title": "Project", "rows": [
		["Project name", p.settings.project_name],
		["Author", p.settings.author if p.settings.author != "" else "-"],
		["Created", TFProjectSettings.format_time(p.settings.created_unix)],
		["Last modified", TFProjectSettings.format_time(p.settings.modified_unix)],
		["Data status", p.settings.status_label()],
		["Coordinate system", p.settings.coordinate_system_label],
		["Horizontal datum", p.settings.horizontal_datum],
		["Vertical datum", p.settings.vertical_datum],
		["Assumed elevation", u.fmt_length(p.settings.assumed_elevation_m, 2)],
		["Existing surface source", p.settings.existing_surface_source],
		["Units", "%s / %s / %s" % [u.length_label(), u.area_label(), u.volume_label()]],
		["Site grid", "%d x %d nodes at %s spacing" % [p.settings.site_cols, p.settings.site_rows, u.fmt_length(p.settings.site_spacing_m, 2)]],
		["Schema version", TFSchema.SCHEMA_VERSION],
		["Calculation engine", TFAnalysis.CALC_ENGINE_VERSION],
		["Operations in history", str(p.ops.size())],
	]})

	if an == null:
		return out

	out.append({"title": "Earthwork quantities", "rows": [
		["Site area", u.fmt_area(an.site_area_m2)],
		["Disturbed area", u.fmt_area(an.disturbed_area_m2)],
		["Cut (bank, in place)", u.fmt_volume(an.cut_bank_m3)],
		["Fill (compacted, as designed)", u.fmt_volume(an.fill_compacted_m3)],
		["Net (fill - cut)", u.fmt_volume(an.net_geometric_m3)],
		["Fill required (bank)", u.fmt_volume(an.fill_bank_required_m3)],
		["On-site reuse (bank)", u.fmt_volume(an.onsite_reuse_bank_m3)],
		["Import (bank / loose)", "%s / %s" % [u.fmt_volume(an.import_bank_m3), u.fmt_volume(an.import_loose_m3)]],
		["Export (bank / loose)", "%s / %s" % [u.fmt_volume(an.export_bank_m3), u.fmt_volume(an.export_loose_m3)]],
		["Material balance", an.balance_label()],
		["Truck capacity (loose)", u.fmt_volume(an.truck_capacity_loose_m3, 2)],
		["Truckloads (import / export / on-site)", "%d / %d / %d" % [an.import_truckloads, an.export_truckloads, an.onsite_truckloads]],
		["Total truckloads", str(an.total_truckloads)],
		["Maximum cut depth", u.fmt_length(an.max_cut_depth_m)],
		["Maximum fill depth", u.fmt_length(an.max_fill_depth_m)],
		["Maximum proposed slope", "%.1f%% (%s)" % [an.max_slope_ratio * 100.0, TFUnits.ratio_to_hv(an.max_slope_ratio)]],
		["Calculation confidence", an.confidence],
	]})

	if not an.road.is_empty():
		out.append({"title": "Road alignment (proposed)", "rows": [
			["Length", u.fmt_length(float(an.road["length_m"]))],
			["Width", u.fmt_length(float(an.road["width_m"]), 2)],
			["Corridor area", u.fmt_area(float(an.road["corridor_area_m2"]))],
			["Maximum grade", "%.1f%%" % (float(an.road["max_grade"]) * 100.0)],
			["Maximum grade limit", "%.1f%%" % (float(an.road["max_grade_limit"]) * 100.0)],
			["Grade limit met", "yes" if bool(an.road["grade_limit_met"]) else "NO"],
			["Elevation gain", u.fmt_length(float(an.road["elevation_gain_m"]))],
			["Surfacing volume", u.fmt_volume(float(an.road["surfacing_volume_m3"]))],
		]})

	if not an.tower.is_empty():
		out.append({"title": "Structure (proposed placeholder)", "rows": [
			["Pad size", u.fmt_length(float(an.tower["pad_size_m"]), 2)],
			["Pad area", u.fmt_area(float(an.tower["pad_area_m2"]))],
			["Pad elevation", u.fmt_length(float(an.tower["pad_elevation_m"]))],
			["Height", u.fmt_length(float(an.tower["height_m"]), 2)],
			["Foundation excavation (placeholder)", u.fmt_volume(float(an.tower["excavation_volume_m3"]))],
			["Concrete (placeholder)", u.fmt_volume(float(an.tower["concrete_volume_m3"]))],
			["Note", String(an.tower["note"])],
		]})

	if seq != null:
		out.append({"title": "Schedule and preliminary estimate", "rows": [
			["Applicable steps", "%d of %d" % [seq.applicable_steps().size(), seq.steps.size()]],
			["Total duration", "%.1f h  (%.1f workdays of %.1f h, %.1f weeks)" % [seq.total_duration_hours, seq.total_duration_days, seq.workday_hours, seq.total_duration_weeks]],
			["Expected cost", "%s %s" % [a.currency, TFUnits.fmt(seq.cost_expected, 0)]],
			["Low estimate (x%.2f)" % a.cost_low_factor, "%s %s" % [a.currency, TFUnits.fmt(seq.cost_low, 0)]],
			["High estimate (x%.2f)" % a.cost_high_factor, "%s %s" % [a.currency, TFUnits.fmt(seq.cost_high, 0)]],
			["Estimate basis", "Preliminary modelled estimate from user-supplied illustrative rates. Not a quote, bid or supplier pricing."],
			["Estimate date", TFProjectSettings.format_time(seq.generated_unix)],
			["Confidence", seq.confidence],
		]})

	var frows := []
	for f in an.formulas:
		frows.append([String(f["name"]), String(f["expr"])])
	out.append({"title": "Formulas and calculation basis", "rows": frows})

	var crows := []
	for r in an.confidence_reasons:
		crows.append(["", r])
	out.append({"title": "Why the confidence is '%s'" % an.confidence, "rows": crows})

	return out


static func html(p: TFProject, an: TFAnalysis, seq: TFSequence,
		issues: Array = []) -> String:
	var a := p.assumptions
	var u := p.settings.units
	var s := ""
	s += "<!DOCTYPE html>\n<html lang=\"en\"><head><meta charset=\"utf-8\">\n"
	s += "<title>TerraForge preliminary summary - %s</title>\n" % _esc(p.settings.project_name)
	s += "<style>\n"
	s += ":root{color-scheme:light}\n"
	s += "body{font:13px/1.5 -apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;margin:0;padding:28px;color:#15181c;background:#fff;max-width:1000px}\n"
	s += "h1{font-size:22px;margin:0 0 2px}h2{font-size:15px;margin:26px 0 8px;padding-bottom:5px;border-bottom:2px solid #d8dde3;text-transform:uppercase;letter-spacing:.06em}\n"
	s += ".sub{color:#5b656f;margin:0 0 18px}\n"
	s += ".banner{background:#fff4d6;border:1px solid #d8a800;border-left:5px solid #d8a800;padding:10px 14px;margin:0 0 18px;font-weight:600}\n"
	s += ".scope{background:#f3f5f7;border:1px solid #d8dde3;padding:10px 14px;margin:18px 0}\n"
	s += "table{border-collapse:collapse;width:100%;margin:0 0 10px}\n"
	s += "th,td{border:1px solid #d8dde3;padding:5px 9px;text-align:left;vertical-align:top}\n"
	s += "th{background:#eef1f4;font-weight:600}\n"
	s += "td.k{width:34%;color:#4a545e}\n"
	s += "td.num{text-align:right;font-variant-numeric:tabular-nums}\n"
	s += "tr.na td{color:#8a939c;font-style:italic}\n"
	s += ".sev-error{color:#a01414;font-weight:600}.sev-warning{color:#8a5a00;font-weight:600}.sev-info{color:#40515f}\n"
	s += "footer{margin-top:30px;padding-top:12px;border-top:1px solid #d8dde3;color:#5b656f;font-size:11px}\n"
	s += "@media print{body{padding:0;font-size:11px;max-width:none}h2{page-break-after:avoid}table{page-break-inside:auto}tr{page-break-inside:avoid}.banner{border-left-width:4px}}\n"
	s += "</style></head><body>\n"
	s += "<div class=\"banner\">%s</div>\n" % _esc(TFProjectSettings.DISCLAIMER)
	s += "<h1>%s</h1>\n" % _esc(p.settings.project_name)
	s += "<p class=\"sub\">Preliminary earthworks summary &middot; generated %s &middot; TerraForge schema %s &middot; calculation engine %s</p>\n" % [
		_esc(TFProjectSettings.format_time(int(Time.get_unix_time_from_system()))),
		TFSchema.SCHEMA_VERSION, TFAnalysis.CALC_ENGINE_VERSION]

	for sec in build_sections(p, an, seq):
		if (sec["rows"] as Array).is_empty():
			continue
		s += "<h2>%s</h2>\n<table>\n" % _esc(String(sec["title"]))
		for row in sec["rows"]:
			s += "<tr><td class=\"k\">%s</td><td>%s</td></tr>\n" % [_esc(str(row[0])), _esc(str(row[1]))]
		s += "</table>\n"

	if seq != null:
		s += "<h2>Construction sequence</h2>\n<table>\n"
		s += "<tr><th>#</th><th>Step</th><th>Phase</th><th>Duration (h)</th><th>Material (%s bank)</th><th>Loads</th><th>Cost (%s)</th><th>Cumulative (%s)</th></tr>\n" % [
			_esc(u.volume_label()), _esc(a.currency), _esc(a.currency)]
		var i := 0
		for st in seq.steps:
			i += 1
			if not st.applicable:
				s += "<tr class=\"na\"><td>%d</td><td>%s</td><td>%s</td><td colspan=\"5\">Not applicable &mdash; %s</td></tr>\n" % [
					i, _esc(st.name), _esc(st.phase), _esc(st.not_applicable_reason)]
				continue
			s += "<tr><td>%d</td><td>%s</td><td>%s</td><td class=\"num\">%.1f</td><td class=\"num\">%s</td><td class=\"num\">%d</td><td class=\"num\">%s</td><td class=\"num\">%s</td></tr>\n" % [
				i, _esc(st.name), _esc(st.phase), st.duration_hours,
				TFUnits.fmt(u.volume(float(st.material.get("bank_m3", 0.0))), 0),
				st.truckloads, TFUnits.fmt(st.total_cost(), 0), TFUnits.fmt(st.cumulative_cost, 0)]
		s += "</table>\n"

		s += "<h2>Equipment plan</h2>\n<table>\n"
		s += "<tr><th>Equipment class</th><th>Peak units</th><th>Machine hours</th><th>Why it was selected</th></tr>\n"
		for e in TFEquipment.plan_from_steps(seq.steps):
			s += "<tr><td>%s</td><td class=\"num\">%d</td><td class=\"num\">%.1f</td><td>%s</td></tr>\n" % [
				_esc(String(e["label"])), int(e["peak_count"]), float(e["machine_hours"]), _esc(String(e["reason"]))]
		s += "</table>\n"

	if not issues.is_empty():
		s += "<h2>Validation</h2>\n<table>\n<tr><th>Severity</th><th>Message</th><th>What to do</th></tr>\n"
		for it in issues:
			s += "<tr><td class=\"sev-%s\">%s</td><td>%s</td><td>%s</td></tr>\n" % [
				_esc(String(it["severity"])), _esc(String(it["severity"]).to_upper()),
				_esc(String(it["message"])), _esc(String(it.get("action", "")))]
		s += "</table>\n"

	s += "<div class=\"scope\"><strong>Scope and status</strong><br>%s</div>\n" % _esc(TFProjectSettings.LONG_DISCLAIMER)
	s += "<div class=\"scope\"><strong>Stakeout</strong><br>Any stake positions shown or exported are PROPOSED stakeout locations derived from the design model. They have not been set, checked or verified in the field.</div>\n"
	s += "<footer>Generated locally by TerraForge. No project data left this machine. Costs are preliminary modelled values built from user-supplied illustrative rates, not supplier quotes.</footer>\n"
	s += "</body></html>\n"
	return s


static func _esc(t: String) -> String:
	return t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")
