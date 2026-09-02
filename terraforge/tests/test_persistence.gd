extends RefCounted

## Loaded by path from tests/run_tests.gd, so it deliberately has no
## class_name: test suites should not occupy global names in the product.


static func run(t: TFTest) -> void:
	_round_trip(t)
	_file_round_trip(t)
	_malformed(t)
	_migration(t)
	_status_cannot_be_escalated(t)
	_csv(t)
	_report(t)


static func _site() -> TFProject:
	var p := TFProject.create_default(61, 61, 2.0, 0.0)
	p.generate_sample_site()
	p.change_assumption("truck_capacity_loose_m3", 16.0)
	p.change_setting("project_name", "Ridge Road Test Site")
	return p


static func _round_trip(t: TFTest) -> void:
	var p := _site()
	var an := p.analyze()
	var q := TFSequenceGenerator.generate(an, p.assumptions, p.road, p.tower)
	var d := TFSchema.to_dict(p, an, q)
	t.eq_str(String(d["schema_version"]), TFSchema.SCHEMA_VERSION, "the export carries the schema version")
	t.ok(d.has("calculation_engine"), "the export carries the calculation engine version")
	t.ok(String(d["status"]["disclaimer"]).contains("not for construction"),
		"the export carries the concept disclaimer")

	# Round trip through actual JSON text, not just the dictionary.
	var text := JSON.stringify(d)
	var parsed = JSON.parse_string(text)
	t.ok(parsed is Dictionary, "the export is valid JSON")
	var res := TFSchema.from_dict(parsed)
	t.ok(bool(res["ok"]), "the exported project reloads: %s" % ", ".join(res["errors"]))
	if not bool(res["ok"]):
		return
	var p2: TFProject = res["project"]
	t.eq_str(p2.sculpt.checksum(), p.sculpt.checksum(), "the sculpted surface survives bit-exactly")
	t.eq_str(p2.existing.checksum(), p.existing.checksum(), "the existing surface survives bit-exactly")
	t.eq_str(p2.proposed.checksum(), p.proposed.checksum(), "the derived surface is reproduced exactly")
	t.eq_int(p2.ops.size(), p.ops.size(), "the operation history survives")
	t.eq_int(p2.cursor, p.cursor, "the history cursor survives")
	t.eq_str(p2.settings.project_name, "Ridge Road Test Site", "the project name survives")
	t.near(p2.assumptions.truck_capacity_loose_m3, 16.0, 1e-9, "assumptions survive")
	t.ok(p2.road != null, "the road survives")
	t.ok(p2.tower != null, "the tower survives")
	t.near(p2.road.length_m(), p.road.length_m(), 1e-3, "the road geometry is reproduced")

	# The quantities computed from the reloaded project must match.
	var an2 := p2.analyze()
	t.near_pct(an2.cut_bank_m3, an.cut_bank_m3, 0.001, "cut volume is unchanged after reload")
	t.near_pct(an2.fill_compacted_m3, an.fill_compacted_m3, 0.001, "fill volume is unchanged after reload")
	t.eq_int(an2.total_truckloads, an.total_truckloads, "truckloads are unchanged after reload")

	# And undo still works on the reloaded document.
	t.ok(p2.can_undo(), "the reloaded project can still undo")
	p2.undo()
	t.ok(p2.sculpt != null, "undo on a reloaded project produces a surface")


static func _file_round_trip(t: TFTest) -> void:
	var p := _site()
	var an := p.analyze()
	var q := TFSequenceGenerator.generate(an, p.assumptions, p.road, p.tower)
	var path := "user://test_roundtrip.tfproj.json"
	var w := TFProjectIO.save_project(path, p, an, q)
	t.ok(bool(w["ok"]), "the project saves to disk")
	t.ok(not p.dirty_since_save, "saving clears the dirty flag")
	var r := TFProjectIO.load_project(path)
	t.ok(bool(r["ok"]), "the project loads from disk")
	if bool(r["ok"]):
		var p2: TFProject = r["project"]
		t.eq_str(p2.sculpt.checksum(), p.sculpt.checksum(), "the surface survives the file round trip")
		t.ok(r["sequence"] != null, "the stored construction sequence reloads")
		var q2: TFSequence = r["sequence"]
		t.eq_int(q2.steps.size(), q.steps.size(), "every construction step reloads")
		t.near(q2.cost_expected, q.cost_expected, 0.01, "the stored estimate reloads")
		t.eq_str(p2.file_path, path, "the loaded project remembers its path")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	t.ok(not FileAccess.file_exists(path), "local project files can be removed")


static func _malformed(t: TFTest) -> void:
	var cases := {
		"empty object": {},
		"no schema version": {"settings": {}, "surfaces": {}},
		"unsupported version": {"schema_version": "99.0.0"},
		"missing surfaces": {"schema_version": TFSchema.SCHEMA_VERSION, "surfaces": {}},
		"null surfaces": {"schema_version": TFSchema.SCHEMA_VERSION,
			"surfaces": {"existing": null, "sculpt": null}},
	}
	for name in cases.keys():
		var res := TFSchema.from_dict(cases[name])
		t.ok(not bool(res["ok"]), "'%s' is rejected" % name)
		t.greater(float((res["errors"] as PackedStringArray).size()), 0.0,
			"'%s' produces an explanatory error" % name)

	# Mismatched surfaces.
	var good := TFProject.create_default(21, 21, 2.0, 0.0)
	var d := TFSchema.to_dict(good, good.analyze(), null)
	d["surfaces"]["sculpt"] = TFHeightfield.create_flat(9, 9, 1.0).to_dict()
	var res2 := TFSchema.from_dict(d)
	t.ok(not bool(res2["ok"]), "inconsistent surface grids are rejected")

	# Garbage text on disk.
	var path := "user://test_broken.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{ this is not json ]]")
	f.close()
	var r := TFProjectIO.load_project(path)
	t.ok(not bool(r["ok"]), "invalid JSON on disk is rejected")
	t.greater(float((r["errors"] as PackedStringArray).size()), 0.0, "invalid JSON produces an actionable message")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var missing := TFProjectIO.load_project("user://definitely_not_here.json")
	t.ok(not bool(missing["ok"]), "a missing file is reported, not crashed on")

	# A malformed operation record must be skipped, not fatal.
	var d3 := TFSchema.to_dict(good, null, null)
	(d3["operations"]["items"] as Array).append({"nonsense": true})
	var res3 := TFSchema.from_dict(d3)
	t.ok(bool(res3["ok"]), "a malformed operation record does not break the load")
	t.greater(float((res3["warnings"] as PackedStringArray).size()), 0.0,
		"a malformed operation record produces a warning")


static func _migration(t: TFTest) -> void:
	var p := _site()
	var d := TFSchema.to_dict(p, p.analyze(), null)
	# Rewrite it into the shape schema 1.0.0 used.
	var old := {
		"schema_version": "1.0.0",
		"settings": d["settings"],
		"assumptions": d["assumptions"],
		"terrain": {"existing": d["surfaces"]["existing"], "sculpt": d["surfaces"]["sculpt"],
			"proposed": d["surfaces"]["proposed"]},
		"operations": d["operations"],
	}
	var res := TFSchema.from_dict(old)
	t.ok(bool(res["ok"]), "a schema 1.0.0 file loads: %s" % ", ".join(res["errors"]))
	t.eq_str(String(res["migrated_from"]), "1.0.0", "the loader reports the migration")
	if bool(res["ok"]):
		var p2: TFProject = res["project"]
		t.eq_str(p2.sculpt.checksum(), p.sculpt.checksum(), "the migrated surface is identical")
		t.eq_int(p2.ops.size(), p.ops.size(), "the migrated history is intact")
	t.greater(float((res["warnings"] as PackedStringArray).size()), 0.0, "the migration is announced as a warning")


static func _status_cannot_be_escalated(t: TFTest) -> void:
	var p := TFProject.create_default(21, 21, 2.0, 0.0)
	var d := TFSchema.to_dict(p, null, null)
	d["settings"]["provenance"]["data_status"] = "professionally_certified"
	var res := TFSchema.from_dict(d)
	t.ok(bool(res["ok"]), "the file still loads")
	var p2: TFProject = res["project"]
	t.eq_str(p2.settings.data_status, "simulated",
		"a file claiming professional certification is forced back to 'simulated'")
	d["settings"]["provenance"]["data_status"] = "field_measured"
	var p3: TFProject = TFSchema.from_dict(d)["project"]
	t.eq_str(p3.settings.data_status, "simulated",
		"a file claiming field measurement is forced back to 'simulated'")


static func _csv(t: TFTest) -> void:
	var p := _site()
	var an := p.analyze()
	var q := TFSequenceGenerator.generate(an, p.assumptions, p.road, p.tower)

	var qty := TFCsvExport.quantities_csv(p, an)
	t.ok(qty.contains("CONCEPT SIMULATION - NOT FOR CONSTRUCTION"), "the quantity CSV carries the status banner")
	t.ok(qty.contains("Volume unit"), "the quantity CSV declares its volume unit")
	t.ok(qty.contains("Cut volume (bank, in place)"), "the quantity CSV lists the cut volume")
	t.ok(qty.contains("Total truckloads"), "the quantity CSV lists the truckloads")
	_check_csv_shape(t, qty, "quantities")

	var est := TFCsvExport.estimate_csv(p, an, q)
	t.ok(est.contains("TOTAL"), "the estimate CSV has a total row")
	t.ok(est.contains(TFAssumptions.SOURCE_LABEL), "the estimate CSV labels its rates as illustrative")
	_check_csv_shape(t, est, "estimate")

	var seqcsv := TFCsvExport.sequence_csv(p, an, q)
	t.ok(seqcsv.contains("Duration (h)"), "the sequence CSV carries units in its headers")
	var lines := seqcsv.split("\r\n", false)
	var data_rows := 0
	for l in lines:
		if l.begins_with("1,") or l.begins_with("2,"):
			data_rows += 1
	t.greater(float(data_rows), 1.0, "the sequence CSV has step rows")
	_check_csv_shape(t, seqcsv, "sequence")

	var eq := TFCsvExport.equipment_csv(p, an, q)
	t.ok(eq.contains("Why it was selected"), "the equipment CSV explains each selection")
	_check_csv_shape(t, eq, "equipment")

	# Commas and quotes inside values must not break the row structure.
	p.change_setting("project_name", "Site \"A\", north of the creek")
	var qty2 := TFCsvExport.quantities_csv(p, TFProject.create_default(11, 11, 2.0).analyze())
	t.ok(qty2.contains("\"Site \"\"A\"\", north of the creek\""),
		"commas and quotes inside a value are escaped per RFC 4180")


static func _check_csv_shape(t: TFTest, text: String, name: String) -> void:
	t.ok(text.begins_with(TFCsvExport.BOM), "%s CSV starts with a UTF-8 BOM for spreadsheet readers" % name)
	t.ok(text.contains("\r\n"), "%s CSV uses CRLF line endings" % name)
	# Every line must have balanced quotes.
	var balanced := true
	for line in text.split("\r\n"):
		if line.count("\"") % 2 != 0:
			balanced = false
	t.ok(balanced, "%s CSV has balanced quoting on every line" % name)


static func _report(t: TFTest) -> void:
	var p := _site()
	var an := p.analyze()
	var q := TFSequenceGenerator.generate(an, p.assumptions, p.road, p.tower)
	var sections := TFReport.build_sections(p, an, q)
	t.greater(float(sections.size()), 4.0, "the report has several sections")
	var titles := PackedStringArray()
	for s in sections:
		titles.append(String(s["title"]))
	t.ok(titles.has("Earthwork quantities"), "the report includes the quantities section")
	t.ok(titles.has("Schedule and preliminary estimate"), "the report includes the estimate section")
	t.ok(titles.has("Formulas and calculation basis"), "the report shows its formulas")

	var html := TFReport.html(p, an, q, TFValidation.all(p, an))
	t.ok(html.begins_with("<!DOCTYPE html>"), "the report is a standalone HTML document")
	t.ok(html.contains("@media print"), "the report has a print stylesheet")
	t.ok(html.contains(TFProjectSettings.DISCLAIMER), "the report carries the concept banner")
	t.ok(html.contains("PROPOSED stakeout locations"), "the report explains the stake status")
	t.ok(not html.contains("<script"), "the report contains no scripts")
	t.ok(not html.contains("http://") and not html.contains("https://"),
		"the report references no external resources")
	for banned in ["certified", "sealed", "permitted", "as approved", "construction-ready"]:
		t.ok(not html.to_lower().contains(" is %s" % banned),
			"the report never asserts the design is %s" % banned)
