class_name TFPlayback
extends RefCounted

## Timeline state for 4D construction playback.
##
## Position is stored in SCHEDULE HOURS, not frames. `advance()` is given a
## real-time delta and a speed in schedule-hours per second, so the surface and
## the quantity read-out at a given timeline position are identical whether the
## app runs at 15 fps or 240 fps, or whether the user scrubs there directly.

signal changed()
signal step_entered(index: int)
signal finished()

const SPEEDS := [0.25, 0.5, 1.0, 2.0, 4.0, 8.0]
const BASE_HOURS_PER_SECOND := 24.0   # 1 real second = 1 modelled day at 1x

var sequence: TFSequence = null
var position_hours: float = 0.0
var playing: bool = false
var speed_index: int = 2
var loop: bool = false
var reduced_motion: bool = false

var _last_step_index: int = -1


func set_sequence(q: TFSequence) -> void:
	sequence = q
	position_hours = 0.0
	playing = false
	_last_step_index = -1
	changed.emit()


func has_sequence() -> bool:
	return sequence != null and not sequence.applicable_steps().is_empty()


func total_hours() -> float:
	return sequence.total_duration_hours if sequence != null else 0.0


func speed() -> float:
	return SPEEDS[clampi(speed_index, 0, SPEEDS.size() - 1)]


func set_speed_index(i: int) -> void:
	speed_index = clampi(i, 0, SPEEDS.size() - 1)
	changed.emit()


func play() -> void:
	if not has_sequence():
		return
	if position_hours >= total_hours() - 1e-6:
		position_hours = 0.0
	playing = true
	changed.emit()


func pause() -> void:
	playing = false
	changed.emit()


func toggle() -> void:
	if playing:
		pause()
	else:
		play()


func stop() -> void:
	playing = false
	position_hours = 0.0
	_emit_step()
	changed.emit()


func seek_hours(h: float) -> void:
	position_hours = clampf(h, 0.0, total_hours())
	_emit_step()
	changed.emit()


func seek_fraction(f: float) -> void:
	seek_hours(clampf(f, 0.0, 1.0) * total_hours())


func fraction() -> float:
	var t := total_hours()
	return 0.0 if t <= 0.0 else clampf(position_hours / t, 0.0, 1.0)


func goto_step(index: int, at_end: bool = false) -> void:
	if not has_sequence():
		return
	var applicable := sequence.applicable_steps()
	var i := clampi(index, 0, applicable.size() - 1)
	var s := applicable[i]
	# Land just inside the step so `locate()` reports this step, not the one
	# that ends where it starts.
	position_hours = s.end_hours if at_end else minf(s.start_hours + 1e-4, s.end_hours)
	_emit_step()
	changed.emit()


func current_index() -> int:
	if not has_sequence():
		return -1
	return int(sequence.locate(position_hours).get("index", -1))


func current_step() -> TFStep:
	if not has_sequence():
		return null
	return sequence.locate(position_hours).get("step")


func next_step() -> void:
	goto_step(current_index() + 1)


func prev_step() -> void:
	var loc := sequence.locate(position_hours) if has_sequence() else {}
	var i := int(loc.get("index", 0))
	# If we are partway into a step, the first press returns to its start.
	if float(loc.get("t", 0.0)) > 0.02:
		goto_step(i)
	else:
		goto_step(i - 1)


## Advance the timeline. `delta` is real seconds.
func advance(delta: float) -> void:
	if not playing or not has_sequence():
		return
	var scale := 0.0 if reduced_motion else 1.0
	if reduced_motion:
		# Reduced motion: still advance, but in discrete step jumps rather than
		# continuous sliding, so nothing animates smoothly across the screen.
		position_hours += delta * BASE_HOURS_PER_SECOND * speed()
		var applicable := sequence.applicable_steps()
		for s in applicable:
			if position_hours < s.end_hours:
				position_hours = s.start_hours + 1e-4
				break
	else:
		position_hours += delta * BASE_HOURS_PER_SECOND * speed() * scale
	if position_hours >= total_hours():
		if loop:
			position_hours = 0.0
		else:
			position_hours = total_hours()
			playing = false
			finished.emit()
	_emit_step()
	changed.emit()


func state() -> Dictionary:
	if sequence == null:
		return TFStep.ZERO_STATE.duplicate()
	return sequence.state_at_hours(position_hours)


func cumulative() -> Dictionary:
	if sequence == null:
		return {"cost": 0.0, "bank_m3": 0.0, "truckloads": 0, "hours": 0.0, "step_name": "-"}
	return sequence.cumulative_at_hours(position_hours)


func _emit_step() -> void:
	var i := current_index()
	if i != _last_step_index:
		_last_step_index = i
		step_entered.emit(i)
