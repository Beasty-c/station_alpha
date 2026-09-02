extends SceneTree

## Headless domain test runner.
##   godot --headless --path terraforge --script res://tests/run_tests.gd
## Exit code 0 = all passed, 1 = at least one failure.

const SUITES := [
	["Units", "res://tests/test_units.gd"],
	["Heightfield", "res://tests/test_heightfield.gd"],
	["Earthworks", "res://tests/test_earthworks.gd"],
	["Estimating", "res://tests/test_estimate.gd"],
	["Operations", "res://tests/test_operations.gd"],
	["Features", "res://tests/test_features.gd"],
	["Construction", "res://tests/test_construction.gd"],
	["Persistence", "res://tests/test_persistence.gd"],
	["Validation", "res://tests/test_validation.gd"],
]


func _initialize() -> void:
	var verbose := false
	for arg in OS.get_cmdline_user_args():
		if arg == "-v" or arg == "--verbose":
			verbose = true

	print("")
	print("TerraForge domain tests - Godot ", Engine.get_version_info()["string"])
	print("calculation engine ", TFAnalysis.CALC_ENGINE_VERSION,
		"  |  project schema ", TFSchema.SCHEMA_VERSION)
	print("=".repeat(74))

	var total_pass := 0
	var total_fail := 0
	var all_failures: Array[String] = []
	var t0 := Time.get_ticks_msec()

	for entry in SUITES:
		var suite_name: String = entry[0]
		var path: String = entry[1]
		var script: Script = load(path)
		if script == null:
			print("  !! could not load suite %s (%s)" % [suite_name, path])
			total_fail += 1
			all_failures.append("%s :: suite failed to load" % suite_name)
			continue
		var t := TFTest.new(suite_name)
		var st := Time.get_ticks_msec()
		script.run(t)
		var dt := Time.get_ticks_msec() - st
		total_pass += t.passed
		total_fail += t.failed
		all_failures.append_array(t.failures)
		var mark := "ok  " if t.failed == 0 else "FAIL"
		print("  %s %-14s %3d passed  %3d failed   (%d ms)" % [mark, suite_name, t.passed, t.failed, dt])
		if verbose or t.failed > 0:
			for line in t.log_lines:
				if verbose or line.begins_with("    FAIL"):
					print(line)

	print("=".repeat(74))
	print("  %d passed, %d failed in %d ms" % [total_pass, total_fail, Time.get_ticks_msec() - t0])
	if total_fail > 0:
		print("")
		print("  Failures:")
		for f in all_failures:
			print("    - ", f)
	print("")
	quit(1 if total_fail > 0 else 0)
