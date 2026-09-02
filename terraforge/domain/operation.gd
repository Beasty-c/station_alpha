class_name TFOperation
extends RefCounted

## A deterministic domain command. The project's state is DERIVED by replaying
## the operation list in order - the same idea as Onshape's feature history,
## without the cloud. Undo/redo simply moves the replay cursor.
##
## Every operation is fully described by `params`, which must be plain JSON
## data so history survives a save/load round trip unchanged.

const CREATE_FLAT_TERRAIN := "CreateFlatTerrain"
const RAISE_TERRAIN := "RaiseTerrain"
const LOWER_TERRAIN := "LowerTerrain"
const SMOOTH_REGION := "SmoothRegion"
const FLATTEN_REGION := "FlattenRegion"
const RESET_TERRAIN := "ResetTerrain"
const GENERATE_SAMPLE_SITE := "GenerateSampleSite"
const ADD_ROAD_ALIGNMENT := "AddRoadAlignment"
const UPDATE_ROAD_ALIGNMENT := "UpdateRoadAlignment"
const REMOVE_ROAD_ALIGNMENT := "RemoveRoadAlignment"
const PLACE_TOWER := "PlaceTower"
const UPDATE_TOWER := "UpdateTower"
const REMOVE_TOWER := "RemoveTower"
const CHANGE_ESTIMATE_ASSUMPTION := "ChangeEstimateAssumption"
const CHANGE_PROJECT_SETTING := "ChangeProjectSetting"

## Operations that change the sculpted surface (used to decide what a replay
## from a terrain snapshot has to redo).
const TERRAIN_OPS := [
	CREATE_FLAT_TERRAIN, RAISE_TERRAIN, LOWER_TERRAIN, SMOOTH_REGION,
	FLATTEN_REGION, RESET_TERRAIN, GENERATE_SAMPLE_SITE,
]

var id: String = ""
var type: String = ""
var params: Dictionary = {}
var created_unix: int = 0
var label: String = ""


static func make(p_type: String, p_params: Dictionary, p_label: String = "") -> TFOperation:
	var op := TFOperation.new()
	op.type = p_type
	op.params = p_params
	op.created_unix = int(Time.get_unix_time_from_system())
	op.label = p_label if p_label != "" else default_label(p_type, p_params)
	op.id = "%s-%d-%d" % [p_type.to_lower(), op.created_unix, randi() % 100000]
	return op


static func default_label(p_type: String, p: Dictionary) -> String:
	match p_type:
		CREATE_FLAT_TERRAIN:
			return "Create flat terrain"
		RAISE_TERRAIN:
			return "Raise terrain (%d strokes)" % int(p.get("stamps", []).size())
		LOWER_TERRAIN:
			return "Lower terrain (%d strokes)" % int(p.get("stamps", []).size())
		SMOOTH_REGION:
			return "Smooth region (%d strokes)" % int(p.get("stamps", []).size())
		FLATTEN_REGION:
			return "Flatten region to %.2f m" % float(p.get("target", 0.0))
		RESET_TERRAIN:
			return "Reset terrain to existing ground"
		GENERATE_SAMPLE_SITE:
			return "Generate sample site (hill, road, tower)"
		ADD_ROAD_ALIGNMENT:
			return "Add road alignment"
		UPDATE_ROAD_ALIGNMENT:
			return "Edit road alignment"
		REMOVE_ROAD_ALIGNMENT:
			return "Remove road alignment"
		PLACE_TOWER:
			return "Place tower"
		UPDATE_TOWER:
			return "Edit tower"
		REMOVE_TOWER:
			return "Remove tower"
		CHANGE_ESTIMATE_ASSUMPTION:
			return "Set %s = %s" % [String(p.get("key", "?")), str(p.get("value", ""))]
		CHANGE_PROJECT_SETTING:
			return "Set %s = %s" % [String(p.get("key", "?")), str(p.get("value", ""))]
	return p_type


func is_terrain_op() -> bool:
	return TERRAIN_OPS.has(type)


func icon_hint() -> String:
	match type:
		CREATE_FLAT_TERRAIN, RESET_TERRAIN: return "grid"
		RAISE_TERRAIN: return "up"
		LOWER_TERRAIN: return "down"
		SMOOTH_REGION: return "wave"
		FLATTEN_REGION: return "flat"
		GENERATE_SAMPLE_SITE: return "star"
		ADD_ROAD_ALIGNMENT, UPDATE_ROAD_ALIGNMENT, REMOVE_ROAD_ALIGNMENT: return "road"
		PLACE_TOWER, UPDATE_TOWER, REMOVE_TOWER: return "tower"
	return "dot"


func to_dict() -> Dictionary:
	return {"id": id, "type": type, "params": params,
		"created_unix": created_unix, "label": label}


static func from_dict(d: Dictionary) -> TFOperation:
	var op := TFOperation.new()
	op.id = String(d.get("id", ""))
	op.type = String(d.get("type", ""))
	op.params = d.get("params", {})
	op.created_unix = int(d.get("created_unix", 0))
	op.label = String(d.get("label", ""))
	if op.label == "":
		op.label = default_label(op.type, op.params)
	return op
