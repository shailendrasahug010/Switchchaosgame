extends SceneTree
## Visual check of the results screen: plays a few seconds of a 4-player
## round per mode (CPU-steered), ends it, and saves a screenshot of the
## results (plus the online version, whose buttons differ). Needs a display
## (Xvfb on Linux).
##
##   godot --path . --rendering-driver opengl3 --resolution 1280x720 -s tools/results_gallery.gd -- \
##       --out-dir=/tmp/results [--modes=cake_dash,bounce_race]
##
## Images: <out-dir>/results_<mode>.png and results_<mode>_online.png

const PLAY_SECONDS := 8.0    # play before the round is ended
const SETTLE := 1.8          # seconds for the results cards to pop in

var _out_dir := "user://results_gallery"
var _modes: PackedStringArray = ["cake_dash", "button_mayhem", "bounce_race"]
var _index := -1
var _time := 0.0
var _stage := ""
## Untyped on purpose: a -s script cannot compile against classes that use
## autoload names, so the match is only touched at runtime.
var _match = null


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var parts := a.trim_prefix("--").split("=", true, 1)
		if parts.size() < 2:
			continue
		if parts[0] == "out-dir":
			_out_dir = parts[1]
		elif parts[0] == "modes":
			_modes = parts[1].split(",")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_next_mode()


func _next_mode() -> void:
	_index += 1
	if _index >= _modes.size():
		quit()
		return
	var gs := root.get_node("GameState")
	gs.persist_enabled = false
	var setup = load("res://scripts/match/match_setup.gd").quick(StringName(_modes[_index]), 1, 3)
	setup.seed = 11 + _index
	setup.no_progress = true
	setup.slots[0].autopilot = true
	gs.current_setup = setup
	change_scene_to_file("res://scenes/match/match.tscn")
	_match = null
	_time = 0.0
	_stage = "load"


func _process(delta: float) -> bool:
	_time += delta
	match _stage:
		"load":
			if current_scene != null and current_scene.has_method("skip_intro"):
				_match = current_scene
				_match.skip_intro()
				_stage = "play"
				_time = 0.0
		"play":
			if _time >= PLAY_SECONDS:
				_match.request_finish(_index % 2 == 0)
				_stage = "results"
				_time = 0.0
		"results":
			if not _match.results_screen.visible:
				_time = 0.0  # count from when the results appear
			elif _time >= SETTLE:
				_save("results_%s.png" % _modes[_index])
				var r: Dictionary = _match.result.duplicate()
				r["online"] = true
				_match.results_screen.show_results(r)
				_stage = "online"
				_time = 0.0
		"online":
			if _time >= SETTLE:
				_save("results_%s_online.png" % _modes[_index])
				_next_mode()
	# Software rendering is slow: draw only shortly before a capture.
	RenderingServer.render_loop_enabled = _stage in ["results", "online"] and _time >= SETTLE - 0.3
	return false


func _save(file: String) -> void:
	var path := _out_dir.path_join(file)
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
