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
	_check_references()
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


## Paths written in code (screens, arenas, chaos events, the main scene) must
## point at files that exist and load as the right kind of thing. Project
## classes are only touched through load() here, so this script itself never
## depends on autoloads (which a -s run does not have).
func _check_references() -> void:
	var refs := 0
	var router: GDScript = load("res://scripts/autoload/router.gd")
	var screens: Dictionary = router.get_script_constant_map().get("SCENES", {})
	for id in screens:
		refs += 1
		if not ResourceLoader.exists(screens[id]) or not (load(screens[id]) is PackedScene):
			_failures.append("Router screen '%s' -> missing scene %s" % [id, screens[id]])
	var catalog: Dictionary = (load("res://scripts/data/catalog.gd") as GDScript).get_script_constant_map()
	for m: Dictionary in catalog.get("MODES", []):
		refs += 1
		var ps := load(String(m.scene)) as PackedScene
		if ps == null:
			_failures.append("mode '%s' -> missing arena %s" % [m.id, m.scene])
			continue
		var state := ps.get_state()
		var root_script: Variant = null
		var mode_id: Variant = null
		for i in state.get_node_property_count(0):
			match state.get_node_property_name(0, i):
				&"script":
					root_script = state.get_node_property_value(0, i)
				&"mode_id":
					mode_id = state.get_node_property_value(0, i)
		if not _extends(root_script as Script, "res://scripts/modes/game_mode.gd"):
			_failures.append("mode '%s' -> arena root does not use a GameMode script" % m.id)
		elif mode_id != m.id:
			_failures.append("mode '%s' -> arena says mode_id '%s'" % [m.id, mode_id])
	var ids := {}
	for path: String in catalog.get("CHAOS_EVENTS", []):
		refs += 1
		var ev := load(path)
		if ev == null or ev.get("id") == null:
			_failures.append("chaos event missing: " + path)
		elif ids.has(ev.id) or ev.id == &"":
			_failures.append("chaos event id empty or duplicated: %s (%s)" % [ev.id, path])
		else:
			ids[ev.id] = true
	refs += 1
	var main_scene := String(ProjectSettings.get_setting("application/run/main_scene", ""))
	if not ResourceLoader.exists(main_scene):
		_failures.append("main scene missing: " + main_scene)
	print("Checked %d references (screens, arenas, chaos events, main scene)." % refs)


func _extends(script: Script, base_path: String) -> bool:
	var s := script
	while s != null:
		if s.resource_path == base_path:
			return true
		s = s.get_base_script()
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
