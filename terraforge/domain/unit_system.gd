class_name TFUnitSystem
extends RefCounted

## The *display* unit system for a project. The authoritative model is always
## metric (see TFUnits); this object only decides how numbers are presented and
## how user-typed numbers are converted on the way in.

var length_unit: String = "m"      # "m" | "ft" | "us_ft"
var volume_unit: String = "m3"     # "m3" | "yd3"


func _init(length: String = "m", volume: String = "m3") -> void:
	set_length_unit(length)
	set_volume_unit(volume)


func set_length_unit(u: String) -> void:
	if TFUnits.is_length_unit(u):
		length_unit = u


func set_volume_unit(u: String) -> void:
	if TFUnits.is_volume_unit(u):
		volume_unit = u


func duplicate_system() -> TFUnitSystem:
	return TFUnitSystem.new(length_unit, volume_unit)


## Convenience preset: switching the length unit to feet also switches volume
## to cubic yards, which is what an earthworks user expects, but the pairing is
## explicit and always visible in the UI.
static func preset(name: String) -> TFUnitSystem:
	match name:
		"metric": return TFUnitSystem.new("m", "m3")
		"imperial": return TFUnitSystem.new("ft", "yd3")
		"us_survey": return TFUnitSystem.new("us_ft", "yd3")
	return TFUnitSystem.new("m", "m3")


func preset_name() -> String:
	if length_unit == "m" and volume_unit == "m3":
		return "metric"
	if length_unit == "ft" and volume_unit == "yd3":
		return "imperial"
	if length_unit == "us_ft" and volume_unit == "yd3":
		return "us_survey"
	return "custom"


# --- Labels ------------------------------------------------------------------
func length_label() -> String:
	return TFUnits.LENGTH_LABEL[length_unit]


func area_label() -> String:
	return TFUnits.AREA_LABEL[length_unit]


func volume_label() -> String:
	return TFUnits.VOLUME_LABEL[volume_unit]


# --- Conversions out of the model -------------------------------------------
func length(metres: float) -> float:
	return TFUnits.length_from_m(metres, length_unit)


func area(m2: float) -> float:
	return TFUnits.area_from_m2(m2, length_unit)


func volume(m3: float) -> float:
	return TFUnits.volume_from_m3(m3, volume_unit)


# --- Conversions into the model ---------------------------------------------
func length_in(display_value: float) -> float:
	return TFUnits.length_to_m(display_value, length_unit)


func volume_in(display_value: float) -> float:
	return TFUnits.volume_to_m3(display_value, volume_unit)


# --- Formatted output (always carries the unit) ------------------------------
func fmt_length(metres: float, decimals: int = 2) -> String:
	return "%s %s" % [TFUnits.fmt(length(metres), decimals), length_label()]


func fmt_area(m2: float, decimals: int = 0) -> String:
	return "%s %s" % [TFUnits.fmt(area(m2), decimals), area_label()]


func fmt_volume(m3: float, decimals: int = 0) -> String:
	return "%s %s" % [TFUnits.fmt(volume(m3), decimals), volume_label()]


func to_dict() -> Dictionary:
	return {"length_unit": length_unit, "volume_unit": volume_unit}


static func from_dict(d: Dictionary) -> TFUnitSystem:
	return TFUnitSystem.new(
		String(d.get("length_unit", "m")),
		String(d.get("volume_unit", "m3")))
