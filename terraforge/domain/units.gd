class_name TFUnits
extends RefCounted

## Canonical unit handling for TerraForge.
##
## The domain stores every length in METRES and every volume in CUBIC METRES.
## Nothing else is ever stored. Display conversion happens at the boundary
## through TFUnitSystem so feet / US survey feet / cubic yards can never be
## silently mixed into the authoritative model.

# --- Exact definitions -------------------------------------------------------
const M_PER_FT: float = 0.3048                       # international foot (exact)
const M_PER_US_FT: float = 1200.0 / 3937.0           # US survey foot (exact)
const M3_PER_YD3: float = 0.764554857984             # 0.9144^3 (exact)
const M2_PER_FT2: float = M_PER_FT * M_PER_FT
const M2_PER_ACRE: float = 4046.8564224              # exact (int. ft based)
const M2_PER_HECTARE: float = 10000.0

const LENGTH_UNITS: PackedStringArray = ["m", "ft", "us_ft"]
const VOLUME_UNITS: PackedStringArray = ["m3", "yd3"]

const LENGTH_LABEL := {"m": "m", "ft": "ft", "us_ft": "US ft"}
const VOLUME_LABEL := {"m3": "m3", "yd3": "CY"}
const AREA_LABEL := {"m": "m2", "ft": "ft2", "us_ft": "US ft2"}


static func is_length_unit(u: String) -> bool:
	return LENGTH_UNITS.has(u)


static func is_volume_unit(u: String) -> bool:
	return VOLUME_UNITS.has(u)


## Metres per one unit of `u`.
static func metres_per_length(u: String) -> float:
	match u:
		"m": return 1.0
		"ft": return M_PER_FT
		"us_ft": return M_PER_US_FT
	push_error("TFUnits: unknown length unit '%s'" % u)
	return 1.0


## Cubic metres per one unit of `u`.
static func cubic_metres_per_volume(u: String) -> float:
	match u:
		"m3": return 1.0
		"yd3": return M3_PER_YD3
	push_error("TFUnits: unknown volume unit '%s'" % u)
	return 1.0


static func length_to_m(value: float, from_unit: String) -> float:
	return value * metres_per_length(from_unit)


static func length_from_m(metres: float, to_unit: String) -> float:
	return metres / metres_per_length(to_unit)


static func area_to_m2(value: float, from_length_unit: String) -> float:
	var f := metres_per_length(from_length_unit)
	return value * f * f


static func area_from_m2(m2: float, to_length_unit: String) -> float:
	var f := metres_per_length(to_length_unit)
	return m2 / (f * f)


static func volume_to_m3(value: float, from_unit: String) -> float:
	return value * cubic_metres_per_volume(from_unit)


static func volume_from_m3(m3: float, to_unit: String) -> float:
	return m3 / cubic_metres_per_volume(to_unit)


static func acres_from_m2(m2: float) -> float:
	return m2 / M2_PER_ACRE


static func hectares_from_m2(m2: float) -> float:
	return m2 / M2_PER_HECTARE


## Slope expressed as a percentage from a rise/run ratio.
static func ratio_to_percent(ratio: float) -> float:
	return ratio * 100.0


## Slope expressed as "H:V" run-per-rise, the usual earthworks convention.
static func ratio_to_hv(ratio: float) -> String:
	if absf(ratio) < 1.0e-9:
		return "flat"
	return "%.1f:1 (H:V)" % (1.0 / absf(ratio))


static func degrees_from_ratio(ratio: float) -> float:
	return rad_to_deg(atan(ratio))


## Human formatting helper - never used as a calculation input.
static func fmt(value: float, decimals: int = 2) -> String:
	if not is_finite(value):
		return "n/a"
	var s := String.num(value, decimals)
	# thousands separators for readability in dense engineering tables
	var parts := s.split(".")
	var whole := parts[0]
	var neg := whole.begins_with("-")
	if neg:
		whole = whole.substr(1)
	var out := ""
	var count := 0
	for i in range(whole.length() - 1, -1, -1):
		out = whole[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	if neg:
		out = "-" + out
	if parts.size() > 1:
		out += "." + parts[1]
	return out
