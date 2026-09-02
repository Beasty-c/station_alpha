class_name TFProjectIO
extends RefCounted

## Local file adapters. Everything stays on this machine: TerraForge makes no
## network calls and uploads nothing. Exports are always user initiated.

const EXTENSION := "tfproj.json"


static func default_dir() -> String:
	var dir := "user://projects"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	return dir


static func save_project(path: String, p: TFProject, an: TFAnalysis, seq: TFSequence) -> Dictionary:
	var d := TFSchema.to_dict(p, an, seq)
	var text := JSON.stringify(d, "  ", false)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "Cannot write to %s (%s)." % [path, error_string(FileAccess.get_open_error())]}
	f.store_string(text)
	f.close()
	p.file_path = path
	p.dirty_since_save = false
	return {"ok": true, "path": path, "bytes": text.length()}


static func load_project(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "errors": PackedStringArray(["File not found: %s" % path])}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "errors": PackedStringArray(["Cannot read %s (%s)." % [path, error_string(FileAccess.get_open_error())]])}
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		return {"ok": false, "errors": PackedStringArray([
			"The file is not valid JSON, or its top level is not an object.",
			"Open it in a text editor to check, or pick a different file."])}
	var res := TFSchema.from_dict(parsed)
	if res["ok"]:
		(res["project"] as TFProject).file_path = path
	return res


static func list_projects() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(default_dir())
	if dir == null:
		return out
	for name in dir.get_files():
		if name.ends_with(".json"):
			out.append(default_dir() + "/" + name)
	out.sort()
	return out


static func clear_local_projects() -> int:
	var n := 0
	var dir := DirAccess.open(default_dir())
	if dir == null:
		return 0
	for name in dir.get_files():
		if name.ends_with(".json"):
			if dir.remove(name) == OK:
				n += 1
	return n


static func suggest_filename(p: TFProject) -> String:
	var base := p.settings.project_name.strip_edges().to_lower()
	base = base.replace(" ", "_")
	var clean := ""
	for ch in base:
		if ch.is_valid_identifier() or ch == "_" or (ch >= "0" and ch <= "9"):
			clean += ch
	if clean == "":
		clean = "terraforge_site"
	return "%s.%s" % [clean, EXTENSION]
