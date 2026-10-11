extends SceneTree
## Static project check: loads every script, scene and resource and reports
## anything that fails (parse errors, missing files, broken references).
##
##   godot --headless --path . -s tools/check_project.gd
##
## Exit code 0 = everything loaded, 1 = problems found (details printed above).

var _failures: PackedStringArray = []


func _initialize() -> void:
	var files := PackedStringArray()
	_collect("res://", files)
	var scripts := 0
	var scenes := 0
	var resources := 0
	for path in files:
		if path.ends_with(".gd"):
			scripts += 1
			var s := load(path) as GDScript
			if s == null or not s.can_instantiate() and not _is_abstract_ok(path):
				_failures.append("script: " + path)
		elif path.ends_with(".tscn"):
			scenes += 1
			var ps := load(path) as PackedScene
			if ps == null:
				_failures.append("scene: " + path)
				continue
			var state := ps.get_state()
			if state == null or state.get_node_count() == 0:
				_failures.append("empty scene: " + path)
		elif path.ends_with(".tres"):
			resources += 1
			if load(path) == null:
				_failures.append("resource: " + path)
	print("Checked %d scripts, %d scenes, %d resources." % [scripts, scenes, resources])
	if _failures.is_empty():
		print("PROJECT CHECK: OK")
		quit(0)
	else:
		for f in _failures:
			printerr("FAILED ", f)
		print("PROJECT CHECK: %d problem(s)" % _failures.size())
		quit(1)


func _is_abstract_ok(_path: String) -> bool:
	return false


func _collect(dir_path: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			if name != "addons":
				_collect(full, out)
		elif name.ends_with(".gd") or name.ends_with(".tscn") or name.ends_with(".tres"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
