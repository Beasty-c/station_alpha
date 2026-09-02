class_name TFAnalysisJob
extends Node

## Runs the earthworks analysis off the main thread.
##
## The analysis is a pure function over cloned surfaces (see
## TFProject.analysis_inputs), so the worker touches no shared state, no scene
## node and no rendering object. Progress and completion are marshalled back
## with call_deferred, and every signal this class emits is emitted on the main
## thread.
##
## Requests are debounced: a brush drag can ask for an analysis on every stroke
## and only the last one inside the quiet window actually runs. A request that
## arrives while a job is in flight cancels that job rather than queueing
## behind it, because its result is already stale.

signal started()
signal progress(fraction: float)
signal finished(analysis: TFAnalysis)
signal cancelled()

const DEBOUNCE_SECONDS := 0.35

var _task_id: int = -1
var _running := false
var _running_gen: int = -1
var _cancel := false
var _generation := 0
var _pending_inputs: Dictionary = {}
var _timer: SceneTreeTimer = null
var _last_progress: float = 0.0


func is_running() -> bool:
	return _running


func last_progress() -> float:
	return _last_progress


## Ask for an analysis after the debounce window. Repeated calls reset it.
func request(inputs: Dictionary) -> void:
	_pending_inputs = inputs
	_generation += 1
	var gen := _generation
	if _running:
		_cancel = true
	_timer = get_tree().create_timer(DEBOUNCE_SECONDS)
	_timer.timeout.connect(func(): _fire(gen))


## Run immediately, skipping the debounce. Used by explicit "Analyze" actions
## where the user is waiting on the result.
func request_now(inputs: Dictionary) -> void:
	_pending_inputs = inputs
	_generation += 1
	if _running:
		_cancel = true
		_await_finish()
	_fire(_generation)


func cancel() -> void:
	if _running:
		_cancel = true


func _fire(gen: int) -> void:
	if gen != _generation:
		return           # superseded by a newer request
	if _pending_inputs.is_empty():
		return
	if _running:
		# The in-flight job was told to cancel; retry on the next frame rather
		# than blocking the main thread waiting for it.
		_cancel = true
		var again := func(): _fire(gen)
		get_tree().create_timer(0.05).timeout.connect(again)
		return
	var inputs := _pending_inputs
	_pending_inputs = {}
	_running = true
	_running_gen = gen
	_cancel = false
	_last_progress = 0.0
	started.emit()
	_task_id = WorkerThreadPool.add_task(func(): _work(inputs, gen), true, "TerraForge analysis")


func _work(inputs: Dictionary, gen: int) -> void:
	var result := TFEarthworks.analyze(
		inputs.get("existing"), inputs.get("proposed"), inputs.get("assumptions"),
		inputs.get("road"), inputs.get("tower"),
		func(f): call_deferred("_on_progress", f, gen),
		func(): return _cancel or gen != _generation)
	call_deferred("_on_done", result, gen)


func _on_progress(f: float, gen: int) -> void:
	if gen != _generation:
		return
	_last_progress = f
	progress.emit(f)


func _on_done(result: TFAnalysis, gen: int) -> void:
	# Only the job that is actually running may clear the running flag. A job
	# that was superseded can land here after its replacement has started, and
	# clearing the flag there would let two analyses run at once.
	if gen == _running_gen:
		_running = false
		_running_gen = -1
		_cancel = false
		if _task_id != -1:
			# The task has already returned; this just releases the handle.
			WorkerThreadPool.wait_for_task_completion(_task_id)
			_task_id = -1
	if gen != _generation or result == null:
		cancelled.emit()
		return
	_last_progress = 1.0
	finished.emit(result)


func _await_finish() -> void:
	if _task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
	_running = false
	_running_gen = -1


func _exit_tree() -> void:
	_cancel = true
	_generation += 1
	_await_finish()
