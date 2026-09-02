class_name TFSequenceGenerator
extends RefCounted

## Turns an earthworks analysis into an ordered, costed, schedulable
## construction sequence. Pure function of (analysis, assumptions, features).
##
## Every duration and cost line records the formula it came from in
## `step.basis`, so changing a production rate or a price can be traced to the
## number it moved.

const PHASES := ["Layout", "Site preparation", "Earthworks", "Hauling",
	"Road", "Structures", "Finishing", "Closeout"]


static func generate(an: TFAnalysis, a: TFAssumptions,
		road: TFRoad = null, tower: TFTower = null) -> TFSequence:
	var q := TFSequence.new()
	q.generated_unix = int(Time.get_unix_time_from_system())
	q.status = "simulated"
	q.confidence = an.confidence

	var eff: float = clampf(a.efficiency_factor, 0.05, 1.0)
	var area: float = maxf(0.0, an.disturbed_area_m2)
	var has_road := road != null and road.is_valid() and not an.road.is_empty()
	var has_tower := tower != null and not an.tower.is_empty()
	var road_len: float = float(an.road.get("length_m", 0.0)) if has_road else 0.0
	var road_area: float = float(an.road.get("corridor_area_m2", 0.0)) if has_road else 0.0
	var pad_area: float = float(an.tower.get("pad_area_m2", 0.0)) if has_tower else 0.0
	var perimeter: float = 4.0 * sqrt(maxf(area, 1.0))
	var topsoil_bank: float = area * maxf(0.0, a.topsoil_depth_m)

	var channels := {}    # step id -> {channel: weight}
	var steps: Array[TFStep] = []

	# ---------------------------------------------------------------- Layout
	var s := _mk("survey_stakeout", "Survey control and proposed stakeout", "Layout",
		"Set project control and mark PROPOSED stakeout locations for the design surface, road centreline and structure pad. These are simulated stake positions produced from the design model. No field survey has been performed.", [])
	s.zone = {"type": "site"}
	s.crew_size = 2
	s.crew_hours = 2.0 * (4.0 + area / 9000.0 + road_len / 350.0)
	s.duration_hours = s.crew_hours / 2.0
	s.equipment = [_eq("survey_crew", 1, s.duration_hours, "Layout rate: 4 h mobilisation + area/9000 m2/h + centreline/350 m/h")]
	s.visual = {"stakes": true, "highlight": "site"}
	s.warnings.append("Stake positions are proposed design output, not field-verified survey marks.")
	s.basis.append("crew_hours = 2 crew x (4 h + %.0f m2 / 9000 + %.0f m / 350)" % [area, road_len])
	_cost(s, a)
	steps.append(s)
	channels[s.id] = {}

	# ------------------------------------------------------ Site preparation
	s = _mk("clearing_grubbing", "Clearing and grubbing", "Site preparation",
		"Remove vegetation and root mat over the disturbed footprint so topsoil can be stripped cleanly.", ["survey_stakeout"])
	s.zone = {"type": "site"}
	s.applicable = area > 1.0
	s.not_applicable_reason = "No measurable disturbed area in the current design."
	s.duration_hours = (area / maxf(1.0, a.clearing_m2_per_hour)) / eff
	s.equipment = [
		_eq("dozer_d6", 1, s.duration_hours, "Clearing production %.0f m2/h at %.0f%% efficiency" % [a.clearing_m2_per_hour, eff * 100.0]),
		_eq("excavator_20t", 1, s.duration_hours * 0.6, "Grubbing support, 60%% of clearing hours"),
	]
	s.crew_size = 2
	s.crew_hours = s.duration_hours * 2.0
	s.visual = {"machines": [{"key": "dozer_d6", "count": 1, "motion": "area"}], "highlight": "site"}
	s.basis.append("duration = %.0f m2 / %.0f m2/h / %.2f eff" % [area, a.clearing_m2_per_hour, eff])
	_cost(s, a)
	steps.append(s)
	channels[s.id] = {}

	s = _mk("topsoil_strip", "Topsoil stripping and stockpiling", "Site preparation",
		"Strip %.2f m of topsoil across the disturbed area and stockpile it on site for reuse during finishing." % a.topsoil_depth_m, ["clearing_grubbing"])
	s.zone = {"type": "site"}
	s.applicable = topsoil_bank > 0.5
	s.not_applicable_reason = "Topsoil depth assumption is zero, or nothing is disturbed."
	var strip_hours: float = maxf(area / maxf(1.0, a.stripping_m2_per_hour), topsoil_bank / maxf(1.0, a.dozer_bcm_per_hour)) / eff
	s.duration_hours = strip_hours
	s.material = {"bank_m3": topsoil_bank, "loose_m3": topsoil_bank * a.loose_per_bank(), "compacted_m3": 0.0, "direction": "onsite"}
	s.equipment = [
		_eq("dozer_d6", 1, strip_hours, "Stripping production %.0f m2/h" % a.stripping_m2_per_hour),
		_eq("excavator_20t", 1, strip_hours * 0.5, "Stockpile shaping"),
	]
	s.crew_size = 2
	s.crew_hours = strip_hours * 2.0
	s.visual = {"machines": [{"key": "dozer_d6", "count": 2, "motion": "area"}], "stockpile": true, "highlight": "site"}
	s.basis.append("topsoil bank = %.0f m2 x %.2f m = %.0f m3" % [area, a.topsoil_depth_m, topsoil_bank])
	s.basis.append("duration = max(area/%.0f, volume/%.0f) / %.2f eff" % [a.stripping_m2_per_hour, a.dozer_bcm_per_hour, eff])
	_cost(s, a)
	steps.append(s)
	channels[s.id] = {"strip": 1.0}

	s = _mk("temporary_access", "Temporary haul access", "Site preparation",
		"Form a temporary running surface so trucks and plant can reach the working areas before the permanent road is built.", ["topsoil_strip"])
	s.zone = {"type": "corridor"} if has_road else {"type": "site"}
	s.applicable = an.total_haul_loose_m3 > 1.0
	s.not_applicable_reason = "No material movement is required, so no temporary haul access is needed."
	var access_len: float = maxf(road_len * 0.6, 120.0)
	s.duration_hours = (access_len * 5.0 / maxf(1.0, a.grader_m2_per_hour)) / eff + 4.0
	s.equipment = [
		_eq("dozer_d6", 1, s.duration_hours, "Temporary access forming, 5 m wide running surface"),
		_eq("motor_grader", 1, s.duration_hours * 0.5, "Shape and crown the temporary surface"),
		_eq("smooth_drum_roller", 1, s.duration_hours * 0.4, "Seal the temporary surface"),
	]
	s.crew_size = 3
	s.crew_hours = s.duration_hours * 3.0
	s.visual = {"temp_access": true, "highlight": "corridor" if has_road else "site"}
	s.basis.append("duration = %.0f m x 5 m / %.0f m2/h / %.2f eff + 4 h" % [access_len, a.grader_m2_per_hour, eff])
	_cost(s, a)
	steps.append(s)
	channels[s.id] = {}

	s = _mk("erosion_control", "Erosion and sediment controls", "Site preparation",
		"Install perimeter sediment controls and inlet protection before earthmoving. Sizing and permitting are a professional design task; this is a linear allowance only.", ["topsoil_strip"])
	s.zone = {"type": "site"}
	s.applicable = area > 1.0
	s.not_applicable_reason = "Nothing is disturbed, so no perimeter controls are modelled."
	s.duration_hours = (perimeter / 110.0) / eff + 2.0
	s.equipment = [
		_eq("skid_steer", 1, s.duration_hours, "Silt fence and inlet protection installation at 110 m/h"),
	]
	s.crew_size = 3
	s.crew_hours = s.duration_hours * 3.0
	s.cost["other"] = perimeter * a.erosion_control_per_m
	s.visual = {"erosion_fence": true, "highlight": "site"}
	s.warnings.append("Erosion and sediment control design, permitting and inspection require a qualified professional.")
	s.basis.append("perimeter = 4 x sqrt(%.0f m2) = %.0f m; material = %.0f m x %.2f/m" % [area, perimeter, perimeter, a.erosion_control_per_m])
	_cost(s, a)
	steps.append(s)
	channels[s.id] = {}

	# ------------------------------------------------------------ Earthworks
	s = _mk("subgrade_prep", "Subgrade preparation and proof rolling", "Earthworks",
		"Scarify, moisture condition and proof roll the exposed subgrade before fill placement.", ["topsoil_strip"])
	s.zone = {"type": "site"}
	s.applicable = area > 1.0
	s.not_applicable_reason = "No exposed subgrade in the current design."
	s.duration_hours = (area / maxf(1.0, a.grader_m2_per_hour * 0.8)) / eff
	s.equipment = [
		_eq("motor_grader", 1, s.duration_hours, "Scarify and shape at 80%% of grader production"),
		_eq("sheepsfoot_compactor", 1, s.duration_hours, "Proof rolling the exposed subgrade"),
		_eq("water_truck", 1, s.duration_hours * 0.7, "Moisture conditioning and dust control"),
	]
	s.crew_size = 3
	s.crew_hours = s.duration_hours * 3.0
	s.visual = {"machines": [{"key": "sheepsfoot_compactor", "count": 1, "motion": "area"}], "highlight": "site"}
	s.warnings.append("Subgrade acceptance requires field density testing by a qualified testing agency. No test has been performed.")
	_cost(s, a)
	steps.append(s)
	channels[s.id] = {}

	s = _mk("mass_excavation", "Mass excavation (cut)", "Earthworks",
		"Excavate the design cut areas down to the mass-grading surface.", ["subgrade_prep"])
	s.zone = {"type": "site"}
	s.applicable = an.cut_bank_m3 > 0.5
	s.not_applicable_reason = "The design has no cut: the proposed surface is at or above existing ground everywhere."
	s.duration_hours = (an.cut_bank_m3 / maxf(1.0, a.excavator_bcm_per_hour)) / eff
	s.material = {"bank_m3": an.cut_bank_m3, "loose_m3": an.cut_bank_m3 * a.loose_per_bank(), "compacted_m3": 0.0, "direction": "cut"}
	s.equipment = [
		_eq("excavator_20t", 1, s.duration_hours, "Excavator production %.0f bank m3/h at %.0f%% efficiency" % [a.excavator_bcm_per_hour, eff * 100.0]),
		_eq("dozer_d6", 1, s.duration_hours * 0.5, "Push and feed the excavator"),
	]
	s.crew_size = 3
	s.crew_hours = s.duration_hours * 3.0
	s.visual = {"machines": [{"key": "excavator_20t", "count": 1, "motion": "cut"}], "highlight": "site"}
	s.basis.append("duration = %.0f bank m3 / %.0f m3/h / %.2f eff" % [an.cut_bank_m3, a.excavator_bcm_per_hour, eff])
	_cost(s, a)
	steps.append(s)
	channels[s.id] = {"cut": 1.0}

	# --------------------------------------------------------------- Hauling
	var fleet_onsite := _fleet_size(a, a.onsite_cycle_minutes)
	s = _mk("onsite_haul", "Cut-to-fill haul on site", "Hauling",
		"Move suitable excavated material from the cut areas to the fill areas.", ["mass_excavation"])
	s.zone = {"type": "site"}
	s.applicable = an.onsite_reuse_bank_m3 > 0.5 and a.truck_capacity_loose_m3 > 0.0
	s.not_applicable_reason = ("Truck capacity is not positive, so no haul cycle can be modelled."
		if a.truck_capacity_loose_m3 <= 0.0 else "No excavated material can be reused in fill.")
	s.truckloads = an.onsite_truckloads
	var onsite_truck_hours: float = float(an.onsite_truckloads) * a.onsite_cycle_minutes / 60.0
	s.duration_hours = onsite_truck_hours / float(fleet_onsite) if fleet_onsite > 0 else 0.0
	s.material = {"bank_m3": an.onsite_reuse_bank_m3, "loose_m3": an.onsite_haul_loose_m3, "compacted_m3": 0.0, "direction": "onsite"}
	s.equipment = [
		_eq("haul_truck", fleet_onsite, onsite_truck_hours, "%d loads x %.0f min cycle / %d trucks" % [an.onsite_truckloads, a.onsite_cycle_minutes, fleet_onsite]),
		_eq("wheel_loader", 1, s.duration_hours, "Loading at %.0f bank m3/h" % a.loader_bcm_per_hour),
	]
	s.crew_size = fleet_onsite + 1
	s.crew_hours = s.duration_hours * float(fleet_onsite + 1)
	s.cost["trucking"] = onsite_truck_hours * a.trucking_rate_per_hour
	s.visual = {"trucks": fleet_onsite, "truck_route": "onsite", "highlight": "site"}
	s.basis.append("loads = ceil(%.0f loose m3 / %.2f m3) = %d" % [an.onsite_haul_loose_m3, a.truck_capacity_loose_m3, an.onsite_truckloads])
	s.basis.append("truck hours = %d x %.0f min / 60 = %.1f h, shared over %d trucks" % [an.onsite_truckloads, a.onsite_cycle_minutes, onsite_truck_hours, fleet_onsite])
	_cost(s, a)
	steps.append(s)
	channels[s.id] = {"fill": 0.35}

	var fleet_import := _fleet_size(a, a.truck_cycle_minutes)
	s = _mk("import_delivery", "Imported fill delivery", "Hauling",
		"Import borrow material to make up the fill shortfall.", ["onsite_haul"])
	s.zone = {"type": "site"}
	s.applicable = an.import_bank_m3 > 0.5 and a.truck_capacity_loose_m3 > 0.0
	s.not_applicable_reason = ("Truck capacity is not positive, so no delivery cycle can be modelled."
		if a.truck_capacity_loose_m3 <= 0.0 else "The site balances or has surplus material; no import is required.")
	s.truckloads = an.import_truckloads
	var import_truck_hours: float = float(an.import_truckloads) * a.truck_cycle_minutes / 60.0
	s.duration_hours = import_truck_hours / float(fleet_import) if fleet_import > 0 else 0.0
	s.material = {"bank_m3": an.import_bank_m3, "loose_m3": an.import_loose_m3, "compacted_m3": 0.0, "direction": "import"}
	s.equipment = [
		_eq("highway_dump", fleet_import, import_truck_hours, "%d loads x %.0f min cycle over %.1f km one way" % [an.import_truckloads, a.truck_cycle_minutes, a.haul_distance_one_way_m / 1000.0]),
		_eq("wheel_loader", 1, s.duration_hours, "Receiving and spotting at the fill area"),
	]
	s.crew_size = 2
	s.crew_hours = s.duration_hours * 2.0
	s.cost["trucking"] = import_truck_hours * a.trucking_rate_per_hour
	s.cost["material"] = an.import_loose_m3 * a.import_material_price_per_m3
	s.visual = {"trucks": fleet_import, "truck_route": "import", "stockpile": true, "highlight": "site"}
	s.basis.append("import material = %.0f loose m3 x %.2f/m3" % [an.import_loose_m3, a.import_material_price_per_m3])
	_cost(s, a)
	steps.append(s)
	channels[s.id] = {"fill": 0.25}

	s = _mk("export_disposal", "Surplus export and disposal", "Hauling",
		"Haul surplus and unsuitable material off site for disposal.", ["mass_excavation"])
	s.zone = {"type": "site"}
	s.applicable = an.export_bank_m3 > 0.5 and a.truck_capacity_loose_m3 > 0.0
	s.not_applicable_reason = ("Truck capacity is not positive, so no disposal cycle can be modelled."
		if a.truck_capacity_loose_m3 <= 0.0 else "No surplus material: the design does not generate export.")
	s.truckloads = an.export_truckloads
	var export_truck_hours: float = float(an.export_truckloads) * a.truck_cycle_minutes / 60.0
	s.duration_hours = export_truck_hours / float(fleet_import) if fleet_import > 0 else 0.0
	s.material = {"bank_m3": an.export_bank_m3, "loose_m3": an.export_loose_m3, "compacted_m3": 0.0, "direction": "export"}
	s.equipment = [
		_eq("highway_dump", fleet_import, export_truck_hours, "%d loads x %.0f min cycle" % [an.export_truckloads, a.truck_cycle_minutes]),
		_eq("wheel_loader", 1, s.duration_hours, "Loading out the surplus stockpile"),
	]
	s.crew_size = 2
	s.crew_hours = s.duration_hours * 2.0
	s.cost["trucking"] = export_truck_hours * a.trucking_rate_per_hour
	s.cost["disposal"] = an.export_loose_m3 * a.disposal_price_per_m3
	s.visual = {"trucks": fleet_import, "truck_route": "export", "highlight": "site"}
	s.basis.append("disposal = %.0f loose m3 x %.2f/m3" % [an.export_loose_m3, a.disposal_price_per_m3])
	_cost(s, a)
	steps.append(s)
	channels[s.id] = {}

	# ------------------------------------------------------- Fill and compact
	var lifts: int = maxi(1, int(ceil(maxf(an.max_fill_depth_m, 0.01) / maxf(0.05, a.lift_thickness_m))))
	s = _mk("fill_placement", "Structural fill placement in lifts", "Earthworks",
		"Spread fill in %.2f m compacted lifts across the fill areas (%d lifts at the deepest point)." % [a.lift_thickness_m, lifts], ["onsite_haul"])
	s.zone = {"type": "site"}
	s.applicable = an.fill_bank_required_m3 > 0.5
	s.not_applicable_reason = "The design has no fill: the proposed surface is at or below existing ground everywhere."
	s.duration_hours = (an.fill_bank_required_m3 / maxf(1.0, a.dozer_bcm_per_hour)) / eff
	s.material = {"bank_m3": an.fill_bank_required_m3, "loose_m3": an.fill_bank_required_m3 * a.loose_per_bank(), "compacted_m3": an.fill_compacted_m3, "direction": "fill"}
	s.equipment = [
		_eq("dozer_d6", 2, s.duration_hours * 2.0, "Spreading at %.0f bank m3/h per dozer" % a.dozer_bcm_per_hour),
		_eq("water_truck", 1, s.duration_hours * 0.6, "Moisture conditioning to near optimum"),
	]
	s.crew_size = 4
	s.crew_hours = s.duration_hours * 4.0
	s.visual = {"machines": [{"key": "dozer_d6", "count": 2, "motion": "fill"}], "highlight": "site"}
	s.basis.append("bank required = %.0f compacted m3 / (1 - %.3f) = %.0f m3" % [an.fill_compacted_m3, a.shrinkage, an.fill_bank_required_m3])
	s.basis.append("duration = %.0f bank m3 / %.0f m3/h / %.2f eff" % [an.fill_bank_required_m3, a.dozer_bcm_per_hour, eff])
	_cost(s, a)
	steps.append(s)
	channels[s.id] = {"fill": 0.3}

	s = _mk("compaction", "Lift compaction and density control", "Earthworks",
		"Compact each lift to the specified density. Acceptance requires field density testing by a qualified agency; none has been performed.", ["fill_placement"])
	s.zone = {"type": "site"}
	s.applicable = an.fill_compacted_m3 > 0.5
	s.not_applicable_reason = "No fill is placed, so no lift compaction is required."
	s.duration_hours = (an.fill_compacted_m3 / maxf(1.0, a.compactor_ccm_per_hour)) / eff
	s.equipment = [
		_eq("sheepsfoot_compactor", 1, s.duration_hours, "Compaction production %.0f compacted m3/h" % a.compactor_ccm_per_hour),
		_eq("water_truck", 1, s.duration_hours * 0.5, "Moisture conditioning"),
	]
	s.crew_size = 2
	s.crew_hours = s.duration_hours * 2.0
	s.cost["other"] = a.testing_allowance
	s.visual = {"machines": [{"key": "sheepsfoot_compactor", "count": 2, "motion": "fill"}], "highlight": "site"}
	s.warnings.append("Compaction acceptance, moisture-density relationships and lift thickness must be set by a geotechnical professional.")
	s.basis.append("duration = %.0f compacted m3 / %.0f m3/h / %.2f eff" % [an.fill_compacted_m3, a.compactor_ccm_per_hour, eff])
	s.basis.append("testing allowance = %.2f (lump sum assumption)" % a.testing_allowance)
	_cost(s, a)
	steps.append(s)
	channels[s.id] = {"fill": 0.10}

	# --------------------------------------------------------------- Road
	s = _mk("road_formation", "Road formation and surfacing", "Road",
		"Form the %.1f m wide running surface to the design profile and place %.2f m of surfacing." % [road.width_m if has_road else 0.0, road.surface_thickness_m if has_road else 0.0], ["compaction"])
	s.zone = {"type": "corridor"}
	s.applicable = has_road and road_area > 0.5
	s.not_applicable_reason = "No road alignment exists in this design."
	if s.applicable:
		s.duration_hours = (road_area / maxf(1.0, a.grader_m2_per_hour * 0.5)) / eff
		var surfacing: float = float(an.road.get("surfacing_volume_m3", 0.0))
		s.material = {"bank_m3": surfacing, "loose_m3": surfacing * a.loose_per_bank(), "compacted_m3": surfacing, "direction": "import"}
		s.equipment = [
			_eq("motor_grader", 1, s.duration_hours, "Line and grade at 50%% of open-area grader production"),
			_eq("smooth_drum_roller", 1, s.duration_hours * 0.8, "Surface compaction"),
			_eq("water_truck", 1, s.duration_hours * 0.4, "Moisture conditioning"),
		]
		s.crew_size = 4
		s.crew_hours = s.duration_hours * 4.0
		s.cost["material"] = surfacing * a.import_material_price_per_m3
		s.basis.append("surfacing = %.0f m2 corridor x %.2f m = %.0f m3" % [road_area, road.surface_thickness_m, surfacing])
		if not bool(an.road.get("grade_limit_met", true)):
			s.warnings.append("The alignment exceeds its own maximum grade limit; the profile needs redesign before this step is realistic.")
	s.visual = {"machines": [{"key": "motor_grader", "count": 1, "motion": "corridor"}], "highlight": "corridor"}
	_cost(s, a)
	steps.append(s)
	channels[s.id] = {"form": 0.7}

	s = _mk("summit_pad", "Structure pad construction", "Road",
		"Cut and compact the level pad the structure sits on.", ["road_formation"])
	s.zone = {"type": "pad"}
	s.applicable = has_tower and pad_area > 0.5
	s.not_applicable_reason = "No structure pad exists in this design."
	if s.applicable:
		s.duration_hours = (pad_area / maxf(1.0, a.grader_m2_per_hour * 0.4)) / eff + 2.0
		s.equipment = [
			_eq("motor_grader", 1, s.duration_hours, "Pad forming to tolerance"),
			_eq("smooth_drum_roller", 1, s.duration_hours * 0.8, "Pad compaction"),
		]
		s.crew_size = 3
		s.crew_hours = s.duration_hours * 3.0
	s.visual = {"machines": [{"key": "smooth_drum_roller", "count": 1, "motion": "pad"}], "highlight": "pad"}
	_cost(s, a)
	steps.append(s)
	channels[s.id] = {"form": 0.3}

	# ---------------------------------------------------------- Structures
	s = _mk("tower_foundation", "Tower foundation (placeholder quantity)", "Structures",
		"Excavate and place the foundation. The footing size here is a VOLUME PLACEHOLDER for take-off only - it is not a structural or geotechnical foundation design.", ["summit_pad"])
	s.zone = {"type": "pad"}
	s.applicable = has_tower
	s.not_applicable_reason = "No structure is placed in this design."
	if s.applicable:
		var exc: float = float(an.tower.get("excavation_volume_m3", 0.0))
		var conc: float = float(an.tower.get("concrete_volume_m3", 0.0))
		s.duration_hours = exc / maxf(1.0, a.excavator_bcm_per_hour) / eff + conc / 12.0 + 8.0
		s.material = {"bank_m3": exc, "loose_m3": exc * a.loose_per_bank(), "compacted_m3": conc, "direction": "cut"}
		s.equipment = [
			_eq("excavator_20t", 1, exc / maxf(1.0, a.excavator_bcm_per_hour) / eff, "Foundation excavation"),
			_eq("concrete_truck", maxi(1, int(ceil(conc / 8.0))), conc / 12.0, "%.0f m3 concrete at 8 m3 per truck" % conc),
		]
		s.crew_size = 5
		s.crew_hours = s.duration_hours * 5.0
		s.cost["material"] = conc * a.concrete_price_per_m3
		s.basis.append("concrete placeholder = %.0f m3 x %.2f/m3" % [conc, a.concrete_price_per_m3])
		s.warnings.append("Foundation sizing, bearing capacity and settlement require a licensed structural and geotechnical engineer.")
	s.visual = {"tower_stage": "foundation", "highlight": "pad"}
	_cost(s, a)
	steps.append(s)
	channels[s.id] = {"tower": 0.3}

	s = _mk("tower_erection", "Tower erection", "Structures",
		"Erect the %.0f m tower in sections." % (tower.height_m if has_tower else 0.0), ["tower_foundation"])
	s.zone = {"type": "pad"}
	s.applicable = has_tower
	s.not_applicable_reason = "No structure is placed in this design."
	if s.applicable:
		s.duration_hours = maxf(8.0, tower.height_m * 0.9) / eff
		s.equipment = [
			_eq("mobile_crane", 1, s.duration_hours, "0.9 crane-hours per metre of tower height"),
		]
		s.crew_size = 5
		s.crew_hours = s.duration_hours * 5.0
		s.warnings.append("Tower design, connections, wind loading and erection engineering are outside TerraForge. This is a massing placeholder.")
	s.visual = {"tower_stage": "erection", "highlight": "pad"}
	_cost(s, a)
	steps.append(s)
	channels[s.id] = {"tower": 0.7}

	# ------------------------------------------------------------- Finishing
	s = _mk("drainage", "Drainage structures (allowance)", "Finishing",
		"Placeholder allowance for culverts, ditches and outlets. TerraForge does NOT perform hydrologic or hydraulic design; sizing is a professional task.", ["road_formation"])
	s.zone = {"type": "corridor"} if has_road else {"type": "site"}
	s.applicable = area > 1.0
	s.not_applicable_reason = "Nothing is disturbed, so no drainage allowance is modelled."
	s.duration_hours = maxf(6.0, road_len / 220.0)
	s.equipment = [_eq("excavator_20t", 1, s.duration_hours, "Ditch and culvert allowance at 220 m of alignment per hour")]
	s.crew_size = 3
	s.crew_hours = s.duration_hours * 3.0
	s.visual = {"highlight": "corridor" if has_road else "site"}
	s.warnings.append("Placeholder only. Hydrology, hydraulics, culvert sizing and outlet protection require professional design.")
	_cost(s, a)
	steps.append(s)
	channels[s.id] = {}

	s = _mk("fine_grading", "Fine grading to design surface", "Finishing",
		"Trim the site and road surfaces to the design elevations and cross-falls.", ["compaction"])
	s.zone = {"type": "site"}
	s.applicable = area > 1.0
	s.not_applicable_reason = "Nothing is disturbed, so there is no surface to trim."
	s.duration_hours = (area / maxf(1.0, a.grader_m2_per_hour)) / eff
	s.equipment = [
		_eq("motor_grader", 1, s.duration_hours, "Fine grading at %.0f m2/h" % a.grader_m2_per_hour),
		_eq("smooth_drum_roller", 1, s.duration_hours * 0.5, "Surface sealing"),
	]
	s.crew_size = 3
	s.crew_hours = s.duration_hours * 3.0
	s.visual = {"machines": [{"key": "motor_grader", "count": 1, "motion": "area"}], "highlight": "site"}
	_cost(s, a)
	steps.append(s)
	channels[s.id] = {}

	s = _mk("topsoil_replacement", "Topsoil respread", "Finishing",
		"Respread the stockpiled topsoil over the disturbed areas outside the road and pad.", ["fine_grading"])
	s.zone = {"type": "site"}
	s.applicable = topsoil_bank > 0.5
	s.not_applicable_reason = "No topsoil was stripped, so none is respread."
	s.duration_hours = (topsoil_bank / maxf(1.0, a.dozer_bcm_per_hour * 0.8)) / eff
	s.material = {"bank_m3": topsoil_bank, "loose_m3": topsoil_bank * a.loose_per_bank(), "compacted_m3": 0.0, "direction": "onsite"}
	s.equipment = [
		_eq("dozer_d6", 1, s.duration_hours, "Respread at 80%% of dozer production"),
		_eq("wheel_loader", 1, s.duration_hours * 0.6, "Reclaiming the topsoil stockpile"),
	]
	s.crew_size = 3
	s.crew_hours = s.duration_hours * 3.0
	s.visual = {"machines": [{"key": "dozer_d6", "count": 1, "motion": "area"}], "highlight": "site"}
	_cost(s, a)
	steps.append(s)
	channels[s.id] = {}

	s = _mk("stabilization", "Permanent surface stabilisation", "Finishing",
		"Seed, mulch and establish permanent cover on all disturbed surfaces.", ["topsoil_replacement"])
	s.zone = {"type": "site"}
	s.applicable = area > 1.0
	s.not_applicable_reason = "Nothing is disturbed, so no stabilisation is modelled."
	s.duration_hours = (area / 4500.0) / eff + 2.0
	s.equipment = [_eq("hydroseeder", 1, s.duration_hours, "Hydroseeding at 4500 m2/h")]
	s.crew_size = 2
	s.crew_hours = s.duration_hours * 2.0
	s.visual = {"stabilised": true, "highlight": "site"}
	_cost(s, a)
	steps.append(s)
	channels[s.id] = {}

	# --------------------------------------------------------------- Closeout
	s = _mk("final_inspection", "Planned final walkthrough and as-built survey", "Closeout",
		"PLANNED activity only. TerraForge has not performed, scheduled or certified any inspection, test or survey. A licensed surveyor must produce the as-built record and the responsible engineer must accept the work.", ["stabilization"])
	s.zone = {"type": "site"}
	s.crew_size = 2
	s.crew_hours = 12.0
	s.duration_hours = 6.0
	s.equipment = [_eq("survey_crew", 1, 6.0, "As-built pickup allowance")]
	s.visual = {"stakes": true, "highlight": "site"}
	s.warnings.append("No inspection, test, approval, certification or permit is represented anywhere in this project.")
	_cost(s, a)
	steps.append(s)
	channels[s.id] = {}

	# Mobilisation is a project-level cost; attach it to the first step so it
	# appears exactly once in the roll-up and in the timeline.
	steps[0].cost["other"] = float(steps[0].cost.get("other", 0.0)) + a.mobilization_cost
	steps[0].basis.append("mobilisation = %.2f (lump sum assumption)" % a.mobilization_cost)
	steps[0].recompute_total()

	_assign_states(steps, channels)
	q.steps = steps
	q.warnings = _sequence_warnings(an, a, has_road, has_tower)
	q.finalize(a, a.cost_low_factor, a.cost_high_factor)
	return q


# --- helpers -----------------------------------------------------------------
static func _mk(id: String, name: String, phase: String, desc: String, prereq: Array) -> TFStep:
	var s := TFStep.new()
	s.id = id
	s.name = name
	s.phase = phase
	s.description = desc
	var pr := PackedStringArray()
	for p in prereq:
		pr.append(String(p))
	s.prerequisites = pr
	s.status = "simulated"
	return s


static func _eq(key: String, count: int, hours: float, basis: String) -> Dictionary:
	return {"key": key, "count": maxi(1, count), "hours": maxf(0.0, hours), "basis": basis}


static func _cost(s: TFStep, a: TFAssumptions) -> void:
	if not s.applicable:
		s.duration_hours = 0.0
		s.duration_days = 0.0
		s.crew_hours = 0.0
		s.equipment = []
		s.truckloads = 0
		s.material = {"bank_m3": 0.0, "loose_m3": 0.0, "compacted_m3": 0.0, "direction": "none"}
		s.cost = {"equipment": 0.0, "labor": 0.0, "trucking": 0.0, "material": 0.0,
			"disposal": 0.0, "other": 0.0, "total": 0.0}
		return
	s.duration_hours = maxf(0.0, s.duration_hours)
	s.duration_days = s.duration_hours / maxf(0.5, a.workday_hours)
	var eq_hours := 0.0
	for e in s.equipment:
		# Trucking equipment is billed through the trucking rate, not the
		# generic equipment rate, so it is never double counted.
		if TFEquipment.category(String(e["key"])) == "hauling":
			continue
		eq_hours += float(e.get("hours", 0.0))
	s.cost["equipment"] = eq_hours * a.equipment_rate_per_hour
	s.cost["labor"] = s.crew_hours * a.labor_rate_per_hour
	s.recompute_total()


## Trucks needed to keep the loading unit busy over one cycle.
static func _fleet_size(a: TFAssumptions, cycle_minutes: float) -> int:
	if a.truck_capacity_loose_m3 <= 0.0:
		return 0
	var loose_per_hour: float = maxf(1.0, a.loader_bcm_per_hour) * a.loose_per_bank()
	var load_minutes: float = 60.0 * a.truck_capacity_loose_m3 / loose_per_hour
	if load_minutes <= 0.0:
		return 1
	return clampi(int(ceil(maxf(1.0, cycle_minutes) / load_minutes)), 1, 12)


## Distribute each terrain-progress channel across the applicable steps that
## carry it, so omitted steps never leave the surface half-built.
static func _assign_states(steps: Array[TFStep], channels: Dictionary) -> void:
	var totals := {}
	for s in steps:
		if not s.applicable:
			continue
		for ch in channels.get(s.id, {}).keys():
			totals[ch] = float(totals.get(ch, 0.0)) + float(channels[s.id][ch])
	var running := {}
	var current := TFStep.ZERO_STATE.duplicate()
	for s in steps:
		s.state_from = current.duplicate()
		if s.applicable:
			for ch in channels.get(s.id, {}).keys():
				var total := float(totals.get(ch, 0.0))
				if total <= 0.0:
					continue
				running[ch] = float(running.get(ch, 0.0)) + float(channels[s.id][ch])
				current[ch] = clampf(float(running[ch]) / total, 0.0, 1.0)
		s.state_to = current.duplicate()


static func _sequence_warnings(an: TFAnalysis, a: TFAssumptions,
		has_road: bool, has_tower: bool) -> PackedStringArray:
	var w := PackedStringArray()
	w.append("This sequence is a modelled concept, not a construction schedule. Sequencing, means and methods are the contractor's responsibility.")
	if a.truck_capacity_loose_m3 <= 0.0:
		w.append("Truck capacity is not positive: all hauling steps are marked not applicable and no truckloads are reported.")
	if not has_road:
		w.append("No road alignment: road formation and its drainage are omitted from the sequence.")
	if not has_tower:
		w.append("No structure: pad, foundation and erection steps are omitted from the sequence.")
	if an.cut_bank_m3 <= 0.5 and an.fill_compacted_m3 <= 0.5:
		w.append("The proposed surface matches existing ground; there is no earthwork to sequence.")
	return w
