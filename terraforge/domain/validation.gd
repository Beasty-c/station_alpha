class_name TFValidation
extends RefCounted

## Actionable validation. Warnings never block conceptual exploration - the
## user is allowed to build a physically silly landform - but the app has to
## say plainly what is wrong and what it means for the numbers.

const ERROR := "error"
const WARNING := "warning"
const INFO := "info"

const SEVERITY_RANK := {"error": 0, "warning": 1, "info": 2}


static func _issue(sev: String, code: String, message: String,
		action: String = "", field: String = "") -> Dictionary:
	return {"severity": sev, "code": code, "message": message,
		"action": action, "field": field}


## Assumption-only checks. Cheap enough to run on every keystroke.
static func check_assumptions(a: TFAssumptions) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if a.truck_capacity_loose_m3 <= 0.0:
		out.append(_issue(ERROR, "truck_capacity",
			"Truck capacity is %.2f m3. A load count cannot be produced from a non-positive capacity." % a.truck_capacity_loose_m3,
			"Enter a positive truck capacity. Hauling steps stay marked not applicable until you do.",
			"truck_capacity_loose_m3"))
	if a.shrinkage >= 0.95:
		out.append(_issue(ERROR, "shrinkage_extreme",
			"Shrinkage of %.2f means compacted fill would need at least %.0fx its own volume in bank material." % [a.shrinkage, a.bank_per_compacted()],
			"Typical shrinkage is 0.05 to 0.25. Values at or above 0.95 are not physically meaningful.",
			"shrinkage"))
	elif a.shrinkage > 0.4 or a.shrinkage < -0.25:
		out.append(_issue(WARNING, "shrinkage_unusual",
			"Shrinkage of %.2f is outside the usual -0.15 to 0.30 range for soils." % a.shrinkage,
			"Confirm the value against a geotechnical report before relying on the quantities.",
			"shrinkage"))
	if a.swell <= -0.9:
		out.append(_issue(ERROR, "swell_invalid",
			"Swell of %.2f would make loose volume zero or negative." % a.swell,
			"Swell is normally 0.10 to 0.45.", "swell"))
	elif a.swell > 0.8 or a.swell < 0.0:
		out.append(_issue(WARNING, "swell_unusual",
			"Swell of %.2f is outside the usual 0.10 to 0.45 range." % a.swell,
			"Confirm against material test data.", "swell"))
	if a.shrinkage < 0.0 and a.swell < 0.0:
		out.append(_issue(WARNING, "factors_inconsistent",
			"Shrinkage and swell are both negative, which is internally inconsistent: material cannot both compact more loosely and haul more densely.",
			"Set swell positive, or set shrinkage positive, to match a real material.", "swell"))
	if a.workday_hours <= 0.0:
		out.append(_issue(ERROR, "workday",
			"Workday length must be greater than zero.",
			"Set a workday between 1 and 24 hours.", "workday_hours"))
	if a.efficiency_factor <= 0.0 or a.efficiency_factor > 1.0:
		out.append(_issue(WARNING, "efficiency",
			"Job efficiency of %.2f is outside 0 to 1." % a.efficiency_factor,
			"Typical values are 0.65 to 0.85.", "efficiency_factor"))
	if a.cost_low_factor > 1.0 or a.cost_high_factor < 1.0 or a.cost_low_factor > a.cost_high_factor:
		out.append(_issue(WARNING, "cost_band",
			"The estimate band is inverted: low factor %.2f, high factor %.2f." % [a.cost_low_factor, a.cost_high_factor],
			"Low should be at or below 1.0 and high at or above 1.0.", "cost_low_factor"))

	var missing := PackedStringArray()
	for k in ["labor_rate_per_hour", "equipment_rate_per_hour", "trucking_rate_per_hour"]:
		if float(a.get(k)) <= 0.0:
			missing.append(String(TFAssumptions.SPEC[k]["label"]))
	if missing.size() > 0:
		out.append(_issue(WARNING, "missing_rates",
			"These cost assumptions are zero: %s. The estimate will understate the work." % ", ".join(missing),
			"Enter your own rates. TerraForge ships illustrative placeholders only.", "labor_rate_per_hour"))

	for k in ["excavator_bcm_per_hour", "dozer_bcm_per_hour", "compactor_ccm_per_hour",
			"grader_m2_per_hour", "stripping_m2_per_hour", "clearing_m2_per_hour",
			"loader_bcm_per_hour"]:
		if float(a.get(k)) <= 0.0:
			out.append(_issue(ERROR, "production_rate",
				"%s is %.1f. A non-positive production rate cannot produce a duration." % [TFAssumptions.SPEC[k]["label"], float(a.get(k))],
				"Enter a positive production rate.", k))
	return out


## Design + analysis checks.
static func check_design(project: TFProject, an: TFAnalysis) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if project.existing == null or project.proposed == null:
		out.append(_issue(ERROR, "no_terrain", "No terrain surface exists.",
			"Create a new project to generate a flat existing surface."))
		return out
	if project.settings.site_cols < 2 or project.settings.site_rows < 2 or project.settings.site_spacing_m <= 0.0:
		out.append(_issue(ERROR, "site_dims",
			"Site dimensions are invalid (%d x %d nodes at %.3f m)." % [project.settings.site_cols, project.settings.site_rows, project.settings.site_spacing_m],
			"Create a new project with a valid grid."))

	# The road is checked from the project, not only from the analysis: an
	# alignment that is invalid produces no metrics at all, so relying on the
	# analysis alone would let a zero width or a single control point through
	# in silence.
	if project.road != null and not project.road.is_valid():
		if project.road.width_m <= 0.0:
			out.append(_issue(ERROR, "road_width",
				"Road width is %.2f m. A corridor cannot be built from a non-positive width." % project.road.width_m,
				"Enter a positive width in the road properties.", "width_m"))
		if project.road.point_count() < 2:
			out.append(_issue(ERROR, "road_points",
				"The road alignment has %d control point(s); at least two are needed." % project.road.point_count(),
				"Add another control point, or remove the alignment.", "control_points"))

	if an != null:
		if an.max_slope_ratio > 1.0:
			out.append(_issue(WARNING, "slope_extreme",
				"Maximum proposed slope is %.0f%% (%s), steeper than 1:1." % [an.max_slope_ratio * 100.0, TFUnits.ratio_to_hv(an.max_slope_ratio)],
				"Slopes this steep will not stand in most soils. Flatten the design or accept it as a concept only."))
		elif an.max_slope_ratio > 0.5:
			out.append(_issue(WARNING, "slope_steep",
				"Maximum proposed slope is %.0f%% (%s)." % [an.max_slope_ratio * 100.0, TFUnits.ratio_to_hv(an.max_slope_ratio)],
				"Many soils require 2:1 or flatter without engineered stabilisation."))
		if an.disturbed_area_m2 <= 0.0:
			out.append(_issue(INFO, "no_change",
				"The proposed surface still matches existing ground everywhere.",
				"Sculpt the terrain, or use Generate sample site, to produce quantities."))
		if not an.road.is_empty():
			var mg := float(an.road.get("max_grade", 0.0))
			var lim := float(an.road.get("max_grade_limit", 0.1))
			if not bool(an.road.get("grade_limit_met", true)):
				out.append(_issue(WARNING, "road_grade",
					"Road grade reaches %.1f%%, above the %.1f%% limit set for this alignment." % [mg * 100.0, lim * 100.0],
					"Raise the maximum grade, lengthen the alignment, or lower the summit."))
			if mg > 0.20:
				out.append(_issue(WARNING, "road_grade_extreme",
					"Road grade of %.1f%% exceeds what most haul and service vehicles can climb loaded." % (mg * 100.0),
					"Public roads are commonly limited to 8 to 12%%. Consider a longer alignment."))
			if lim > 0.30:
				out.append(_issue(WARNING, "road_limit_extreme",
					"The alignment's maximum grade limit is set to %.0f%%, which is not a buildable road standard." % (lim * 100.0),
					"Set a limit appropriate to the vehicle type, typically 8 to 15%%."))
			if float(an.road.get("length_m", 0.0)) <= 0.0:
				out.append(_issue(WARNING, "road_length",
					"The road alignment has no length.",
					"Add at least two control points that are not coincident."))
			if float(an.road.get("width_m", 0.0)) <= 0.0:
				out.append(_issue(ERROR, "road_width",
					"Road width must be greater than zero.",
					"Set a positive width in the road properties."))
		if not an.tower.is_empty():
			if float(an.tower.get("foundation_depth_m", 0.0)) <= 0.0:
				out.append(_issue(WARNING, "foundation_depth",
					"Foundation depth is not positive, so the excavation quantity is zero.",
					"Set a positive placeholder depth, or accept a zero foundation take-off."))
			if float(an.tower.get("height_m", 0.0)) <= 0.0:
				out.append(_issue(WARNING, "tower_height",
					"Tower height is not positive.", "Set a positive height."))
	return out


## Things the app must always say, regardless of the design.
static func professional_scope_notes() -> Array[Dictionary]:
	return [
		_issue(INFO, "scope_geotech", "Slope stability, soil bearing capacity, settlement and groundwater are NOT analysed.", "Engage a geotechnical engineer before any design decision."),
		_issue(INFO, "scope_hydro", "Drainage, hydrology and hydraulics are NOT analysed. Drainage appears as a cost allowance only.", "Engage a civil engineer for drainage design."),
		_issue(INFO, "scope_boundary", "Property boundaries, easements and setbacks are NOT represented.", "A licensed land surveyor must establish boundaries."),
		_issue(INFO, "scope_permit", "No permit, environmental or code compliance check is performed.", "Confirm requirements with the authority having jurisdiction."),
		_issue(INFO, "scope_survey", "The existing surface is a synthetic flat datum, not survey data.", "Import a real survey surface before relying on quantities."),
	]


static func all(project: TFProject, an: TFAnalysis) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(check_assumptions(project.assumptions))
	out.append_array(check_design(project, an))
	out.sort_custom(func(x, y):
		return int(SEVERITY_RANK.get(x["severity"], 3)) < int(SEVERITY_RANK.get(y["severity"], 3)))
	return out


static func count_by_severity(issues: Array) -> Dictionary:
	var c := {"error": 0, "warning": 0, "info": 0}
	for i in issues:
		var s := String(i.get("severity", "info"))
		c[s] = int(c.get(s, 0)) + 1
	return c
