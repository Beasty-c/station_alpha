class_name TFTestUnits
extends RefCounted


static func run(t: TFTest) -> void:
	_exact_factors(t)
	_round_trips(t)
	_unit_system(t)
	_no_silent_mixing(t)
	_formatting(t)


static func _exact_factors(t: TFTest) -> void:
	t.near(TFUnits.M_PER_FT, 0.3048, 0.0, "international foot is exactly 0.3048 m")
	t.near(TFUnits.M_PER_US_FT, 1200.0 / 3937.0, 1e-15, "US survey foot is exactly 1200/3937 m")
	t.near(TFUnits.M3_PER_YD3, 0.9144 * 0.9144 * 0.9144, 1e-15, "cubic yard is exactly 0.9144^3 m3")
	t.ok(TFUnits.M_PER_FT != TFUnits.M_PER_US_FT, "international and US survey feet are distinct")
	# 1 000 000 ft differs from 1 000 000 US ft by ~2 ft: the classic bust.
	var d := absf(TFUnits.length_to_m(1.0e6, "ft") - TFUnits.length_to_m(1.0e6, "us_ft"))
	t.near(d, 0.609601219, 1e-6, "1e6 ft vs 1e6 US ft differ by 0.61 m")


static func _round_trips(t: TFTest) -> void:
	for u in ["m", "ft", "us_ft"]:
		var v := 1234.5678
		t.near(TFUnits.length_from_m(TFUnits.length_to_m(v, u), u), v, 1e-9, "length round trip in %s" % u)
		t.near(TFUnits.area_from_m2(TFUnits.area_to_m2(v, u), u), v, 1e-9, "area round trip in %s" % u)
	for u in ["m3", "yd3"]:
		var v2 := 98765.4321
		t.near(TFUnits.volume_from_m3(TFUnits.volume_to_m3(v2, u), u), v2, 1e-8, "volume round trip in %s" % u)
	t.near(TFUnits.volume_to_m3(1.0, "yd3"), 0.764554857984, 1e-12, "1 CY in m3")
	t.near(TFUnits.volume_from_m3(1000.0, "yd3"), 1307.9506193, 1e-5, "1000 m3 in CY")
	t.near(TFUnits.area_to_m2(1.0, "ft"), 0.09290304, 1e-12, "1 ft2 in m2")
	t.near(TFUnits.acres_from_m2(4046.8564224), 1.0, 1e-12, "1 acre in m2")


static func _unit_system(t: TFTest) -> void:
	var m := TFUnitSystem.preset("metric")
	t.eq_str(m.length_label(), "m", "metric length label")
	t.eq_str(m.volume_label(), "m3", "metric volume label")
	var imp := TFUnitSystem.preset("imperial")
	t.eq_str(imp.length_label(), "ft", "imperial length label")
	t.eq_str(imp.volume_label(), "CY", "imperial volume label")
	t.near(imp.length(100.0), 328.0839895, 1e-5, "100 m shown in feet")
	t.near(imp.volume(1000.0), 1307.9506193, 1e-5, "1000 m3 shown in CY")
	t.near(imp.length_in(328.0839895), 100.0, 1e-6, "feet typed back into metres")
	var us := TFUnitSystem.preset("us_survey")
	t.eq_str(us.preset_name(), "us_survey", "US survey preset round trips")
	t.ok(absf(us.length(1.0e6) - imp.length(1.0e6)) > 1.0, "US survey and international feet display differently")
	# Every display string carries its unit - nothing is unit-less.
	t.ok(imp.fmt_volume(1000.0).ends_with("CY"), "formatted volume carries its unit")
	t.ok(imp.fmt_length(10.0).ends_with("ft"), "formatted length carries its unit")
	t.ok(imp.fmt_area(10.0).ends_with("ft2"), "formatted area carries its unit")


static func _no_silent_mixing(t: TFTest) -> void:
	var us := TFUnitSystem.new("m", "m3")
	us.set_length_unit("furlong")
	t.eq_str(us.length_unit, "m", "an unknown length unit is rejected, not silently adopted")
	us.set_volume_unit("gallons")
	t.eq_str(us.volume_unit, "m3", "an unknown volume unit is rejected")
	t.ok(TFHeightfield.UNITS == "m", "the canonical heightfield is always metric")
	var d := TFUnitSystem.from_dict({"length_unit": "ft", "volume_unit": "yd3"}).to_dict()
	t.eq_str(String(d["length_unit"]), "ft", "unit system serialises its length unit")
	t.eq_str(String(d["volume_unit"]), "yd3", "unit system serialises its volume unit")


static func _formatting(t: TFTest) -> void:
	t.eq_str(TFUnits.fmt(1234567.891, 2), "1,234,567.89", "thousands separators")
	t.eq_str(TFUnits.fmt(-1234.5, 1), "-1,234.5", "negative formatting")
	t.eq_str(TFUnits.fmt(0.0, 0), "0", "zero formatting")
	t.eq_str(TFUnits.ratio_to_hv(0.5), "2.0:1 (H:V)", "50% slope is 2:1 H:V")
	t.eq_str(TFUnits.ratio_to_hv(0.0), "flat", "zero slope reads flat")
	t.near(TFUnits.degrees_from_ratio(1.0), 45.0, 1e-9, "1:1 slope is 45 degrees")
