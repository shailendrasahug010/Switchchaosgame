extends Node
## Headless test runner (scene: res://tests/test_runner.tscn).
##
##   godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn
##   godot --headless --path . --fixed-fps 60 res://tests/test_runner.tscn -- chaos   (only files containing "chaos")
##
## --fixed-fps 60 runs the simulation faster than real time while keeping the
## exact 60 Hz physics steps the game uses. Any engine or script error raised
## while a test runs makes that test fail. Exit code 0 = all passed.

var _passed := 0
var _failed := 0
var _report: PackedStringArray = []
var _catcher := ErrorCatcher.new()


class ErrorCatcher:
	extends Logger
	var _mutex := Mutex.new()
	var messages: PackedStringArray = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		var text := "%s (%s:%d in %s)" % [rationale if rationale != "" else code, file.get_file(), line, function]
		_mutex.lock()
		messages.append(text)
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func take() -> PackedStringArray:
		_mutex.lock()
		var out := messages.duplicate()
		messages.clear()
		_mutex.unlock()
		return out


func _ready() -> void:
	OS.add_logger(_catcher)
	# Tests change scenes; make sure that never frees the runner itself.
	get_tree().current_scene = null
	_run.call_deferred()


func _run() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs:
		gs.persist_enabled = false
		gs.reset_to_defaults()
		gs.settings.debug_tools = true
	var filters := OS.get_cmdline_user_args()
	var files := PackedStringArray()
	var dir := DirAccess.open("res://tests")
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd":
			var wanted := filters.is_empty()
			for x in filters:
				if f.contains(x):
					wanted = true
			if wanted:
				files.append("res://tests/" + f)
	files.sort()
	var start := Time.get_ticks_msec()
	_catcher.take()
	for path in files:
		await _run_file(path)
	var secs := (Time.get_ticks_msec() - start) / 1000.0
	print("")
	print("==================== TEST SUMMARY ====================")
	for line in _report:
		print(line)
	print("------------------------------------------------------")
	print("%d passed, %d failed (%.1fs)" % [_passed, _failed, secs])
	OS.remove_logger(_catcher)
	get_tree().quit(0 if _failed == 0 else 1)


func _run_file(path: String) -> void:
	var script := load(path) as GDScript
	if script == null:
		_failed += 1
		_report.append("FAIL  %s (could not load)" % path)
		return
	for m in script.get_script_method_list():
		var name: String = m.name
		if not name.begins_with("test_"):
			continue
		var t: TestCase = script.new()
		t.tree = get_tree()
		print("--- %s :: %s" % [path.get_file(), name])
		_catcher.take()
		await t.before_each()
		await t.call(name)
		await t.after_each()
		for e in _catcher.take():
			t.failures.append("engine/script error: " + e)
		for n in t.notes:
			print("      note: ", n)
		if t.failures.is_empty():
			_passed += 1
			_report.append("PASS  %s :: %s" % [path.get_file(), name])
		else:
			_failed += 1
			_report.append("FAIL  %s :: %s" % [path.get_file(), name])
			for f in t.failures:
				_report.append("        - " + f)
				print("      FAILED: ", f)
