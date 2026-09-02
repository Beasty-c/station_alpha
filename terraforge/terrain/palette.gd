class_name TFPalette
extends RefCounted

## The application's colour system, in one place.
##
## Industrial and field-ready: dark graphite and slate surfaces, high-contrast
## terrain, survey orange for the active tool, construction yellow for
## warnings, cut/fill blue and red, restrained green for completion.
##
## Every colour-coded state in the UI is paired with a text label or a shape
## cue, so colour is never the only carrier of meaning.

# --- Workspace surfaces ------------------------------------------------------
const BG_DEEP := Color("#14171b")
const BG_PANEL := Color("#1b1f24")
const BG_PANEL_ALT := Color("#22272e")
const BG_INPUT := Color("#0f1216")
const BG_HOVER := Color("#2b323a")
const BORDER := Color("#333b45")
const BORDER_STRONG := Color("#48525e")

# --- Text --------------------------------------------------------------------
const TEXT := Color("#e6ebf0")
const TEXT_DIM := Color("#9aa5b1")
const TEXT_FAINT := Color("#6b7683")

# --- Brand / state -----------------------------------------------------------
const SURVEY_ORANGE := Color("#ff8b2b")     # active tool, selection, focus
const CONSTRUCTION_YELLOW := Color("#ffc53d")  # warnings
const ALERT_RED := Color("#ff6b6b")         # errors
const VERIFIED_GREEN := Color("#5fbf7a")    # completed work
const INFO_BLUE := Color("#6ba8e6")

# --- Cut / fill --------------------------------------------------------------
const CUT_BLUE := Color("#3d8bd4")          # material removed
const FILL_RED := Color("#d4533d")          # material added
const NO_CHANGE := Color("#8d9299")

# --- Terrain shading ---------------------------------------------------------
const GROUND_LOW := Color("#4a5340")
const GROUND_HIGH := Color("#b9b19a")
const GROUND_EXISTING := Color("#5a6068")
const ROAD_SURFACE := Color("#6e6a63")
const PAD_SURFACE := Color("#8a8781")

# --- Playback states ---------------------------------------------------------
const STATE_PROPOSED := Color("#7f8a96")
const STATE_ACTIVE := Color("#ff8b2b")
const STATE_COMPLETE := Color("#5fbf7a")
const STATE_WARNING := Color("#ffc53d")
const STATE_UNVERIFIED := Color("#a07fd0")

## Text label for each construction state, so the colour is never alone.
const STATE_LABELS := {
	"proposed": "Proposed",
	"active": "Active work",
	"complete": "Completed",
	"warning": "Warning",
	"unverified": "Unverified",
}


static func state_color(key: String) -> Color:
	match key:
		"proposed": return STATE_PROPOSED
		"active": return STATE_ACTIVE
		"complete": return STATE_COMPLETE
		"warning": return STATE_WARNING
		"unverified": return STATE_UNVERIFIED
	return TEXT_DIM


static func severity_color(sev: String) -> Color:
	match sev:
		"error": return ALERT_RED
		"warning": return CONSTRUCTION_YELLOW
		"info": return INFO_BLUE
	return TEXT_DIM


## Severity is also carried as a glyph, for users who cannot rely on hue.
static func severity_glyph(sev: String) -> String:
	match sev:
		"error": return "!"
		"warning": return "▲"
		"info": return "i"
	return "-"


static func severity_label(sev: String) -> String:
	match sev:
		"error": return "ERROR"
		"warning": return "WARNING"
		"info": return "NOTE"
	return sev.to_upper()


## Elevation ramp, low ground to high ground.
static func elevation_color(t: float) -> Color:
	var f: float = clampf(t, 0.0, 1.0)
	if f < 0.5:
		return GROUND_LOW.lerp(Color("#8a8a5e"), f * 2.0)
	return Color("#8a8a5e").lerp(GROUND_HIGH, (f - 0.5) * 2.0)


## Cut/fill ramp. `d` is proposed - existing in metres, `scale` the depth that
## saturates the ramp. Blue is cut (material removed), red is fill (added).
static func cut_fill_color(d: float, scale: float) -> Color:
	var s: float = maxf(0.01, scale)
	if absf(d) < 0.02:
		return NO_CHANGE
	var f: float = clampf(absf(d) / s, 0.0, 1.0)
	# A perceptible step at the daylight line so the boundary reads clearly.
	var base := NO_CHANGE.lerp(CUT_BLUE if d < 0.0 else FILL_RED, 0.25 + 0.75 * f)
	return base


## Slope ramp: green (flat) through yellow to red (unbuildably steep).
## `ratio` is rise/run. 0.5 (2:1) is the usual practical limit.
static func slope_color(ratio: float) -> Color:
	var f: float = clampf(absf(ratio) / 1.0, 0.0, 1.0)
	if f < 0.5:
		return Color("#4f8f5a").lerp(CONSTRUCTION_YELLOW, f * 2.0)
	return CONSTRUCTION_YELLOW.lerp(ALERT_RED, (f - 0.5) * 2.0)
