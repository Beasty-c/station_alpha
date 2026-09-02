class_name TFTestEarthworks
extends RefCounted

## Volume tests against analytically known surfaces.
## Tolerances are explicit and documented next to each case.

const SPACING := 2.0
const N := 121   # 121 nodes => 240 m x 240 m site


static func _flat(elev: float = 0.0) -> TFHeightfield:
	return TFHeightfield.create_flat(N, N, SPACING, elev, Vector2(-120.0, -120.0))


static func run(t: TFTest) -> void:
	_test_constant_raise(t)
	_test_plane_tilt_balances(t)
	_test_wedge_exact(t)
	_test_cone(t)
	_test_pyramid_exact(t)
	_test_mixed_cut_fill_symmetry(t)
	_test_determinism(t)
	_test_grid_mismatch_guard(t)
	_test_disturbed_area(t)
	_test_no_change(t)
	_test_subdivision_convergence(t)


## 1. Uniform lift: fill must equal h * site area EXACTLY (bilinear-exact case).
static func _test_constant_raise(t: TFTest) -> void:
	var ex := _flat(0.0)
	var pr := _flat(2.5)
	var v := TFEarthworks.integrate(ex, pr)
	var expected := 2.5 * ex.total_area()
	t.near_pct(float(v["fill_m3"]), expected, 0.0001, "uniform 2.5 m lift fill volume")
	t.near(float(v["cut_m3"]), 0.0, 1e-6, "uniform lift produces no cut")
	t.near_pct(float(v["net_m3"]), expected, 0.0001, "uniform lift net volume")
	t.eq_int(int(v["refined"]), 0, "uniform lift refines no cells")


## 2. A plane tilted about the site centre must balance: cut == fill, net == 0.
static func _test_plane_tilt_balances(t: TFTest) -> void:
	var ex := _flat(0.0)
	var pr := _flat(0.0)
	for r in pr.rows:
		for c in pr.cols:
			var p := pr.node_position(c, r)
			pr.set_h(c, r, 0.05 * p.x)   # 5% grade through the origin
	var v := TFEarthworks.integrate(ex, pr)
	t.near(float(v["net_m3"]), 0.0, 1.0e-3, "tilted plane nets to zero")
	t.near_pct(float(v["cut_m3"]), float(v["fill_m3"]), 0.05, "tilted plane cut equals fill")
	# Analytic: two triangular prisms, each (1/2)(120)(6)(240) = 86,400 m3
	t.near_pct(float(v["fill_m3"]), 86400.0, 0.5, "tilted plane fill vs analytic prism")


## 3. A linear wedge (ridge) is piecewise-linear on grid lines, so the grid
##    method is exact apart from float32 storage.
static func _test_wedge_exact(t: TFTest) -> void:
	var ex := _flat(0.0)
	var pr := _flat(0.0)
	var height := 20.0
	var half := 100.0   # wedge spans x in [-100, 100]
	for r in pr.rows:
		for c in pr.cols:
			var p := pr.node_position(c, r)
			var h: float = height * maxf(0.0, 1.0 - absf(p.x) / half)
			pr.set_h(c, r, h)
	var v := TFEarthworks.integrate(ex, pr)
	# Cross-section area = half * height = 100 * 20 = 2000 m2, length 240 m.
	var expected := 2000.0 * 240.0
	t.near_pct(float(v["fill_m3"]), expected, 0.01, "linear wedge fill volume")


## 4. Right circular cone: V = (1/3) pi R^2 H. The grid method converges from
##    the inside; 1.5% is the documented tolerance at 2 m spacing / R = 90 m.
static func _test_cone(t: TFTest) -> void:
	var ex := _flat(0.0)
	var pr := _flat(0.0)
	var radius := 90.0
	var height := 30.0
	for r in pr.rows:
		for c in pr.cols:
			var p := pr.node_position(c, r)
			var d := p.length()
			pr.set_h(c, r, height * maxf(0.0, 1.0 - d / radius))
	var v := TFEarthworks.integrate(ex, pr)
	var expected := PI * radius * radius * height / 3.0
	t.near_pct(float(v["fill_m3"]), expected, 1.5, "cone fill volume vs (1/3)pi R^2 H")
	t.near(float(v["cut_m3"]), 0.0, 1e-6, "cone produces no cut")


## 5. Square pyramid: V = (1/3) * base_area * H. Exact for the grid method
##    because every face is planar along grid lines.
static func _test_pyramid_exact(t: TFTest) -> void:
	var ex := _flat(0.0)
	var pr := _flat(0.0)
	var half := 100.0
	var height := 25.0
	for r in pr.rows:
		for c in pr.cols:
			var p := pr.node_position(c, r)
			var cheb: float = maxf(absf(p.x), absf(p.y))
			pr.set_h(c, r, height * maxf(0.0, 1.0 - cheb / half))
	var v := TFEarthworks.integrate(ex, pr)
	var expected := (2.0 * half) * (2.0 * half) * height / 3.0
	t.near_pct(float(v["fill_m3"]), expected, 0.05, "square pyramid fill volume")


## 6. Odd-symmetric surface: cut and fill must match to tight tolerance and the
##    net must vanish. This is the case the sub-cell refinement exists for.
static func _test_mixed_cut_fill_symmetry(t: TFTest) -> void:
	var ex := _flat(0.0)
	var pr := _flat(0.0)
	for r in pr.rows:
		for c in pr.cols:
			var p := pr.node_position(c, r)
			# Two whole periods across the site, phase-shifted so the daylight
			# line falls BETWEEN grid nodes and the refinement path is exercised.
			pr.set_h(c, r, 6.0 * sin(p.x * PI / 60.0 + 0.5))
	var v := TFEarthworks.integrate(ex, pr)
	t.near(float(v["net_m3"]), 0.0, 1.0, "balanced surface nets to zero")
	t.near_pct(float(v["cut_m3"]), float(v["fill_m3"]), 0.05, "balanced surface cut equals fill")
	t.greater(float(v["refined"]), 0.0, "off-node daylight line refines mixed cells")


## 7. Determinism: identical inputs, identical outputs, bit for bit.
static func _test_determinism(t: TFTest) -> void:
	var ex := _flat(0.0)
	var pr := _flat(0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260901
	for r in pr.rows:
		for c in pr.cols:
			pr.set_h(c, r, rng.randf_range(-4.0, 4.0))
	var a := TFEarthworks.integrate(ex, pr)
	var b := TFEarthworks.integrate(ex, pr)
	t.ok(float(a["cut_m3"]) == float(b["cut_m3"]), "repeat run: identical cut")
	t.ok(float(a["fill_m3"]) == float(b["fill_m3"]), "repeat run: identical fill")
	t.ok(float(a["net_m3"]) == float(b["net_m3"]), "repeat run: identical net")

	# The same surface reached through a different path must give the same
	# answer: quantities come from surfaces, never from accumulated events.
	var pr2 := pr.clone()
	var v2 := TFEarthworks.integrate(ex, pr2)
	t.ok(float(a["cut_m3"]) == float(v2["cut_m3"]), "cloned surface: identical cut")
	t.eq_str(pr.checksum(), pr2.checksum(), "cloned surface checksum matches")


## 8. Grids that do not match must refuse to mix rather than return nonsense.
static func _test_grid_mismatch_guard(t: TFTest) -> void:
	var ex := _flat(0.0)
	var pr := TFHeightfield.create_flat(N, N, SPACING * 2.0, 1.0, Vector2(-120.0, -120.0))
	var v := TFEarthworks.integrate(ex, pr)
	t.near(float(v["net_m3"]), 0.0, 1e-9, "mismatched grids return zero, not a mixed-unit answer")
	t.eq_int(int(v["cells"]), 0, "mismatched grids evaluate no cells")


## 9. Raised-node block. A heightfield surface is BILINEAR between nodes, so
##    raising an 11 x 11 node block by 1 m gives a 10 x 10 cell plateau plus a
##    one-cell ramp all the way round. The analytic bilinear answer is
##      plateau 100 cells x 4 m2 x 1.00 m   = 400 m3
##      edges    40 cells x 4 m2 x 0.50 m   =  80 m3
##      corners   4 cells x 4 m2 x 0.25 m   =   4 m3   -> 484 m3
##    and the disturbed footprint is the full 12 x 12 = 144 cells = 576 m2.
##    This test exists to pin that interpretation down: quantities follow the
##    surface definition, not the node count.
static func _test_disturbed_area(t: TFTest) -> void:
	var ex := _flat(0.0)
	var pr := _flat(0.0)
	for r in range(60, 71):
		for c in range(60, 71):
			pr.set_h(c, r, 1.0)
	var v := TFEarthworks.integrate(ex, pr)
	t.near(float(v["disturbed_m2"]), 576.0, 0.001, "disturbed area of a raised 11x11 node block")
	t.near_pct(float(v["fill_m3"]), 484.0, 0.001, "raised block fill volume (plateau + bilinear ramp)")
	t.near(float(v["max_fill_m"]), 1.0, 1e-6, "max fill depth of the raised block")


## 10. No edit at all: every quantity is zero.
static func _test_no_change(t: TFTest) -> void:
	var ex := _flat(0.0)
	var pr := _flat(0.0)
	var v := TFEarthworks.integrate(ex, pr)
	t.near(float(v["cut_m3"]), 0.0, 1e-9, "untouched terrain has no cut")
	t.near(float(v["fill_m3"]), 0.0, 1e-9, "untouched terrain has no fill")
	t.near(float(v["disturbed_m2"]), 0.0, 1e-9, "untouched terrain has no disturbed area")


## 11. Refinement level changes the cut/fill split only within tolerance and
##     never changes the exact net.
static func _test_subdivision_convergence(t: TFTest) -> void:
	var ex := _flat(0.0)
	var pr := _flat(0.0)
	for r in pr.rows:
		for c in pr.cols:
			var p := pr.node_position(c, r)
			pr.set_h(c, r, 5.0 * sin(p.x * PI / 80.0) * cos(p.y * PI / 95.0))
	var v1 := TFEarthworks.integrate(ex, pr, 1)
	var v8 := TFEarthworks.integrate(ex, pr, 8)
	t.near(float(v1["net_m3"]), float(v8["net_m3"]), 1e-3, "net is independent of subdivision")
	t.near_pct(float(v1["fill_m3"]), float(v8["fill_m3"]), 6.0, "fill split converges with subdivision")
	t.greater(float(v8["refined"]), 0.0, "wavy surface refines mixed cells")
