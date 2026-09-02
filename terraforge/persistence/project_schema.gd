class_name TFSchema
extends RefCounted

## Versioned interchange schema for TerraForge project files.
##
## This is deliberately NOT a Godot serialized scene or a custom Resource: the
## user's project data has to outlive the engine version it was made with, and
## has to be readable by anything that can read JSON. Godot Resources are used
## only for authored application assets.
##
## Layout (schema 1.1.0)
##   schema_version, app, engine, calculation_engine, exported_unix
##   settings      TFProjectSettings.to_dict()      (units, provenance, datums)
##   assumptions   TFAssumptions.to_dict()          (estimating inputs)
##   surfaces      existing / sculpt / proposed heightfields (base64 float32)
##   features      road, tower
##   operations    full command history + cursor
##   analysis      last computed analysis, or null
##   sequence      last generated construction sequence, or null
##   status        professional-integrity block
##
## `sculpt` is authoritative on load; `proposed` is re-derived from it so a
## hand-edited file can never desynchronise the derived surface from its
## features.

const SCHEMA_VERSION := "1.1.0"
const APP_NAME := "TerraForge"
const SUPPORTED_VERSIONS := ["1.0.0", "1.1.0"]


static func to_dict(p: TFProject, an: TFAnalysis, seq: TFSequence) -> Dictionary:
	var ops := []
	for o in p.ops:
		ops.append(o.to_dict())
	return {
		"schema_version": SCHEMA_VERSION,
		"app": {"name": APP_NAME, "version": ProjectSettings.get_setting("application/config/version", "0.1.0")},
		"engine": {"name": "Godot", "version": Engine.get_version_info()["string"]},
		"calculation_engine": TFAnalysis.CALC_ENGINE_VERSION,
		"sequence_engine": TFSequence.SEQUENCE_VERSION,
		"exported_unix": int(Time.get_unix_time_from_system()),
		"settings": p.settings.to_dict(),
		"assumptions": p.assumptions.to_dict(),
		"surfaces": {
			"existing": p.existing.to_dict() if p.existing != null else null,
			"sculpt": p.sculpt.to_dict() if p.sculpt != null else null,
			"proposed": p.proposed.to_dict() if p.proposed != null else null,
		},
		"features": {
			"road": p.road.to_dict() if p.road != null else null,
			"tower": p.tower.to_dict() if p.tower != null else null,
		},
		"operations": {"cursor": p.cursor, "items": ops},
		"analysis": an.to_dict() if an != null else null,
		"sequence": seq.to_dict() if seq != null else null,
		"status": {
			"data_status": p.settings.data_status,
			"disclaimer": TFProjectSettings.DISCLAIMER,
			"long_disclaimer": TFProjectSettings.LONG_DISCLAIMER,
			"estimate_basis": "Preliminary modelled estimate from user-supplied illustrative rates. Not a quote, bid or supplier pricing.",
			"stakes": "Any stake positions are PROPOSED stakeout locations produced from the design model. They are not field-verified survey marks.",
		},
	}


## Returns {ok: bool, project: TFProject, analysis: TFAnalysis,
##          sequence: TFSequence, errors: PackedStringArray,
##          warnings: PackedStringArray, migrated_from: String}
static func from_dict(raw: Dictionary) -> Dictionary:
	var result := {
		"ok": false, "project": null, "analysis": null, "sequence": null,
		"errors": PackedStringArray(), "warnings": PackedStringArray(),
		"migrated_from": "",
	}
	if raw.is_empty():
		result["errors"].append("The file is empty or is not a JSON object.")
		return result
	var ver := String(raw.get("schema_version", ""))
	if ver == "":
		result["errors"].append("No 'schema_version' field: this is not a TerraForge project file.")
		return result
	if not SUPPORTED_VERSIONS.has(ver):
		result["errors"].append("Schema version '%s' is not supported by this build (supports %s)." % [ver, ", ".join(SUPPORTED_VERSIONS)])
		return result

	var d := raw.duplicate(true)
	if ver == "1.0.0":
		d = _migrate_1_0_0_to_1_1_0(d)
		result["migrated_from"] = "1.0.0"
		result["warnings"].append("Project migrated from schema 1.0.0 to %s." % SCHEMA_VERSION)

	var surfaces: Dictionary = d.get("surfaces", {})
	if surfaces.get("existing") == null or surfaces.get("sculpt") == null:
		result["errors"].append("The file has no existing/sculpt terrain surfaces.")
		return result

	var p := TFProject.new()
	p.settings = TFProjectSettings.from_dict(d.get("settings", {}))
	p.assumptions = TFAssumptions.from_dict(d.get("assumptions", {}))
	p.existing = TFHeightfield.from_dict(surfaces["existing"])
	p.sculpt = TFHeightfield.from_dict(surfaces["sculpt"])
	if not p.existing.same_grid_as(p.sculpt):
		result["errors"].append("The existing and sculpted surfaces are on different grids; the file is inconsistent.")
		return result

	var feats: Dictionary = d.get("features", {})
	if feats.get("road") != null:
		p.road = TFRoad.from_dict(feats["road"])
	if feats.get("tower") != null:
		p.tower = TFTower.from_dict(feats["tower"])

	var ops_block: Dictionary = d.get("operations", {})
	var items: Array = ops_block.get("items", [])
	var ops: Array[TFOperation] = []
	for it in items:
		if it is Dictionary and String(it.get("type", "")) != "":
			ops.append(TFOperation.from_dict(it))
		else:
			result["warnings"].append("Skipped a malformed operation record in the history.")
	p.ops = ops
	p.cursor = clampi(int(ops_block.get("cursor", ops.size())), 0, ops.size())
	if ops.is_empty():
		result["warnings"].append("The file carried no operation history; undo will be unavailable for the loaded state.")
		p.ops = [TFOperation.make(TFOperation.CREATE_FLAT_TERRAIN, {
			"cols": p.existing.cols, "rows": p.existing.rows,
			"spacing": p.existing.spacing,
			"origin": [p.existing.origin.x, p.existing.origin.y],
			"elevation": p.settings.assumed_elevation_m})]
		p.cursor = 1

	# `proposed` is always re-derived - never trusted from the file.
	p.rederive_all()
	p.dirty_since_save = false

	if d.get("analysis") != null:
		result["warnings"].append("Stored analysis was discarded and will be recomputed from the surfaces.")
	if d.get("sequence") != null:
		result["sequence"] = TFSequence.from_dict(d["sequence"])

	result["project"] = p
	result["ok"] = true
	return result


## 1.0.0 kept the surfaces under "terrain" and had no derived "proposed"
## entry; 1.1.0 renames the block and adds the derived surface.
static func _migrate_1_0_0_to_1_1_0(d: Dictionary) -> Dictionary:
	var out := d.duplicate(true)
	if out.has("terrain") and not out.has("surfaces"):
		var t: Dictionary = out["terrain"]
		out["surfaces"] = {
			"existing": t.get("existing"),
			"sculpt": t.get("sculpt", t.get("proposed")),
			"proposed": t.get("proposed"),
		}
		out.erase("terrain")
	if not out.has("features"):
		out["features"] = {"road": null, "tower": null}
	out["schema_version"] = SCHEMA_VERSION
	return out
