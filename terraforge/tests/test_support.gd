class_name TFTest
extends RefCounted

## Minimal deterministic assertion harness for headless domain tests.

var suite: String = ""
var passed: int = 0
var failed: int = 0
var failures: Array[String] = []
var log_lines: Array[String] = []


func _init(p_suite: String = "") -> void:
	suite = p_suite


func ok(cond: bool, what: String) -> void:
	if cond:
		passed += 1
		log_lines.append("    PASS  %s" % what)
	else:
		failed += 1
		failures.append("%s :: %s" % [suite, what])
		log_lines.append("    FAIL  %s" % what)


func eq_int(a: int, b: int, what: String) -> void:
	ok(a == b, "%s (got %d, want %d)" % [what, a, b])


func eq_str(a: String, b: String, what: String) -> void:
	ok(a == b, "%s (got '%s', want '%s')" % [what, a, b])


func near(a: float, b: float, tol: float, what: String) -> void:
	var d := absf(a - b)
	ok(d <= tol, "%s (got %.6f, want %.6f +/- %.6f, delta %.6f)" % [what, a, b, tol, d])


## Relative tolerance in percent of the expected magnitude.
func near_pct(a: float, b: float, pct: float, what: String) -> void:
	var tol: float = absf(b) * pct * 0.01
	if tol < 1.0e-9:
		tol = 1.0e-9
	near(a, b, tol, "%s [<= %.3f%%]" % [what, pct])


func greater(a: float, b: float, what: String) -> void:
	ok(a > b, "%s (got %.6f, want > %.6f)" % [what, a, b])


func between(a: float, lo: float, hi: float, what: String) -> void:
	ok(a >= lo and a <= hi, "%s (got %.6f, want in [%.6f, %.6f])" % [what, a, lo, hi])
