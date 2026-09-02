class_name TFTestOperations
extends RefCounted

## The operation history IS the document. These tests prove that replaying it
## reproduces the surface exactly, that undo/redo is derived from it, and that
## quantities never come from accumulated brush events.


static func run(t: TFTest) -> void:
	_default_project(t)
	_stroke_history(t)
	_undo_redo(t)
	_snapshot_replay(t)
	_redo_tail_discarded(t)
	_parametric_features(t)
	_assumption_ops(t)
	_reset_and_sample(t)


static func _p() -> TFProject:
	return TFProject.create_default(61, 61, 2.0, 0.0)


static func _stroke(p: TFProject, mode: TFBrush.Mode, at: Vector2, r: float, s: float, n: int = 6) -> void:
	var stamps := []
	for i in n:
		stamps.append(TFBrush.make_stamp(at + Vector2(float(i), 0.0), r, s, 0.1))
	p.apply_stroke(mode, stamps)


static func _default_project(t: TFTest) -> void:
	var p := _p()
	t.ok(p.existing != null, "a new project has an existing surface")
	t.ok(p.sculpt != null, "a new project has a sculpt surface")
	t.ok(p.proposed != null, "a new project has a derived proposed surface")
	t.near(p.existing.min_max().x, 0.0, 1e-9, "the new terrain is flat at the assumed datum")
	t.near(p.existing.min_max().y, 0.0, 1e-9, "the new terrain has no high point")
	t.eq_str(p.existing.checksum(), p.proposed.checksum(), "proposed starts identical to existing")
	t.eq_int(p.ops.size(), 1, "a new project has exactly one operation")
	t.eq_str(p.ops[0].type, TFOperation.CREATE_FLAT_TERRAIN, "the first operation creates the flat terrain")
	t.ok(not p.can_undo(), "the terrain-creation operation cannot be undone")
	t.ok(not p.dirty_since_save, "a brand new project is not marked dirty")


static func _stroke_history(t: TFTest) -> void:
	var p := _p()
	_stroke(p, TFBrush.Mode.RAISE, Vector2(0.0, 0.0), 20.0, 4.0)
	t.eq_int(p.ops.size(), 2, "a stroke records exactly one operation")
	t.eq_str(p.ops[1].type, TFOperation.RAISE_TERRAIN, "the stroke is a RaiseTerrain command")
	t.greater(p.sculpt.min_max().y, 0.5, "the stroke actually raised the surface")
	t.ok(p.dirty_since_save, "editing marks the project dirty")

	# The existing surface is immutable: sculpting must never touch it.
	t.near(p.existing.min_max().y, 0.0, 1e-9, "the existing surface is untouched by sculpting")
	t.near(p.existing.min_max().x, 0.0, 1e-9, "the existing surface stays flat")

	# Replaying the same history into a new project must reproduce it exactly.
	var q := TFProject.new()
	q.settings = TFProjectSettings.new()
	q.ops = p.ops.duplicate()
	q.cursor = p.cursor
	q._rebuild()
	t.eq_str(q.sculpt.checksum(), p.sculpt.checksum(), "replaying the history reproduces the surface exactly")


static func _undo_redo(t: TFTest) -> void:
	var p := _p()
	var flat := p.sculpt.checksum()
	_stroke(p, TFBrush.Mode.RAISE, Vector2(-10.0, 0.0), 18.0, 3.0)
	var after1 := p.sculpt.checksum()
	_stroke(p, TFBrush.Mode.LOWER, Vector2(20.0, 10.0), 14.0, 2.0)
	var after2 := p.sculpt.checksum()
	t.ok(after1 != flat and after2 != after1, "each stroke changes the surface")

	t.eq_str(p.undo_label(), "Lower terrain (6 strokes)", "undo names the operation it will remove")
	t.ok(p.undo(), "undo succeeds")
	t.eq_str(p.sculpt.checksum(), after1, "undo restores the previous surface exactly")
	t.ok(p.undo(), "second undo succeeds")
	t.eq_str(p.sculpt.checksum(), flat, "undoing every stroke returns to flat ground")
	t.ok(not p.can_undo(), "undo stops at the terrain-creation operation")

	t.ok(p.redo(), "redo succeeds")
	t.eq_str(p.sculpt.checksum(), after1, "redo restores the first stroke exactly")
	t.ok(p.redo(), "second redo succeeds")
	t.eq_str(p.sculpt.checksum(), after2, "redo restores the second stroke exactly")
	t.ok(not p.can_redo(), "redo stops at the end of history")


static func _snapshot_replay(t: TFTest) -> void:
	# More operations than SNAPSHOT_EVERY, so the snapshot shortcut is used.
	var p := _p()
	var marks := []
	for i in 26:
		_stroke(p, TFBrush.Mode.RAISE, Vector2(float(i) - 12.0, float(i % 7) * 3.0), 10.0, 1.5, 3)
		marks.append(p.sculpt.checksum())
	t.greater(float(p._snapshots.size()), 0.0, "snapshots are taken during a long history")
	for k in range(24, 0, -1):
		p.undo()
	t.eq_str(p.sculpt.checksum(), marks[0], "undoing 24 operations through snapshots is exact")
	for k in range(24):
		p.redo()
	t.eq_str(p.sculpt.checksum(), marks[24], "redoing 24 operations through snapshots is exact")


static func _redo_tail_discarded(t: TFTest) -> void:
	var p := _p()
	_stroke(p, TFBrush.Mode.RAISE, Vector2.ZERO, 15.0, 3.0)
	_stroke(p, TFBrush.Mode.RAISE, Vector2(10.0, 10.0), 15.0, 3.0)
	p.undo()
	t.ok(p.can_redo(), "there is a redo tail after undoing")
	_stroke(p, TFBrush.Mode.LOWER, Vector2(-10.0, -10.0), 12.0, 2.0)
	t.ok(not p.can_redo(), "a new operation discards the redo tail")
	t.eq_int(p.ops.size(), 3, "history length after branching")
	t.eq_str(p.ops[2].type, TFOperation.LOWER_TERRAIN, "the new branch keeps the new operation")


static func _parametric_features(t: TFTest) -> void:
	var p := _p()
	_stroke(p, TFBrush.Mode.RAISE, p.sculpt.center_xz(), 40.0, 12.0, 10)
	var sculpt_sum := p.sculpt.checksum()

	var tw := TFTower.new()
	tw.position_xz = p.sculpt.center_xz()
	tw.pad_size_m = 24.0
	p.set_tower(tw)
	t.ok(p.tower != null, "the tower is placed")
	t.eq_str(p.sculpt.checksum(), sculpt_sum, "placing a feature does not modify the sculpted surface")
	t.ok(p.proposed.checksum() != sculpt_sum, "placing a feature changes the derived proposed surface")

	# The pad must actually be level.
	var c := p.proposed.grid_coords(tw.position_xz)
	var h0 := p.proposed.get_h(int(c.x), int(c.y))
	var h1 := p.proposed.get_h(int(c.x) + 4, int(c.y))
	t.near(h1, h0, 0.02, "the structure pad is level across its width")

	var rd := TFRoad.new()
	rd.set_control_points(PackedVector2Array([Vector2(-100.0, -60.0), Vector2(-20.0, -10.0),
		Vector2(40.0, 20.0), Vector2(100.0, 60.0)]))
	rd.width_m = 8.0
	rd.max_grade = 0.10
	p.set_road(rd)
	t.ok(p.road != null, "the road alignment is added")
	t.eq_str(p.sculpt.checksum(), sculpt_sum, "adding a road does not modify the sculpted surface")

	# Editing the road width must change the derived surface - proof that the
	# feature is parametric rather than baked.
	var before := p.proposed.checksum()
	var wider := TFRoad.from_dict(p.road.to_dict())
	wider.width_m = 16.0
	p.set_road(wider)
	t.ok(p.proposed.checksum() != before, "widening the road re-derives the proposed surface")
	t.near(p.road.width_m, 16.0, 1e-9, "the road width is the edited value")

	p.undo()
	t.near(p.road.width_m, 8.0, 1e-9, "undo restores the previous road width")
	p.remove_road()
	t.ok(p.road == null, "the road can be removed")
	t.eq_str(p.proposed.checksum(), p.sculpt.checksum(),
		"with the road removed and the tower undone the derived surface returns to the sculpt")


static func _assumption_ops(t: TFTest) -> void:
	var p := _p()
	t.near(p.assumptions.truck_capacity_loose_m3, 12.0, 1e-9, "default truck capacity")
	p.change_assumption("truck_capacity_loose_m3", 20.0)
	t.near(p.assumptions.truck_capacity_loose_m3, 20.0, 1e-9, "assumption change applies")
	p.change_assumption("soil_type", "clay")
	t.eq_str(p.assumptions.soil_type, "clay", "soil preset applies")
	t.near(p.assumptions.shrinkage, 0.18, 1e-6, "the soil preset also sets shrinkage")
	p.undo()
	t.eq_str(p.assumptions.soil_type, "common_earth", "undo restores the previous soil type")
	t.near(p.assumptions.truck_capacity_loose_m3, 20.0, 1e-9, "undo keeps the earlier assumption change")
	p.change_setting("length_unit", "ft")
	t.eq_str(p.settings.units.length_unit, "ft", "a project setting change applies")


static func _reset_and_sample(t: TFTest) -> void:
	var p := _p()
	var flat := p.sculpt.checksum()
	_stroke(p, TFBrush.Mode.RAISE, Vector2.ZERO, 30.0, 8.0, 8)
	t.ok(p.sculpt.checksum() != flat, "the site is sculpted")
	p.reset_terrain()
	t.eq_str(p.sculpt.checksum(), flat, "reset returns the sculpt to the existing ground")
	t.ok(p.can_undo(), "reset itself is undoable")
	p.undo()
	t.ok(p.sculpt.checksum() != flat, "undoing the reset brings the hill back")

	# The sample scenario must be deterministic: same seed, same surface.
	var a := _p()
	var b := _p()
	a.generate_sample_site()
	b.generate_sample_site()
	t.eq_str(a.sculpt.checksum(), b.sculpt.checksum(), "the sample site is deterministic")
	t.ok(a.road != null, "the sample site creates a road")
	t.ok(a.tower != null, "the sample site creates a tower")
	t.greater(a.sculpt.min_max().y, 20.0, "the sample site builds a substantial hill")
	t.greater(a.road.length_m(), 200.0, "the sample road spirals a meaningful distance")
	t.ok(a.tower.position_xz.is_equal_approx(a.sculpt.center_xz()), "the sample tower sits at the summit")
	# And it stays editable.
	_stroke(a, TFBrush.Mode.LOWER, a.sculpt.center_xz() + Vector2(30.0, 0.0), 15.0, 3.0)
	t.ok(a.sculpt.checksum() != b.sculpt.checksum(), "the generated sample site can still be edited")
