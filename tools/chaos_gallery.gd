extends SceneTree
## Visual check of every chaos event inside a real round: forces each event in
## turn and saves a screenshot while it is active (plus one of an
## announcement card). Needs a display (Xvfb on Linux).
##
##   godot --path . --rendering-driver opengl3 --resolution 1280x720 -s tools/chaos_gallery.gd -- \
##       --mode=cake_dash --out-dir=/tmp/gallery
##
## Images: <out-dir>/<mode>_00_announce.png, <mode>_01_<event>.png, ...

const FIRST := 90
const STEP := 150
const SHOT_DELAY := 70

var _mode := "cake_dash"
var _out_dir := "user://gallery"
var _frame := 0
## Untyped on purpose: a -s script cannot compile against classes that use
## autoload names (the match does), so the match is only touched at runtime.
var _match = null
var _ids: Array[StringName] = []
var _captures: Dictionary = {}   # frame -> file name


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var parts := a.trim_prefix("--").split("=", true, 1)
		if parts[0] == "mode":
			_mode = parts[1]
		elif parts[0] == "out-dir":
			_out_dir = parts[1]
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var gs := root.get_node("GameState")
	gs.persist_enabled = false
	var setup = load("res://scripts/match/match_setup.gd").quick(StringName(_mode), 1, 3)
	setup.seed = 3
	setup.no_progress = true
	setup.round_time = 180.0
	setup.slots[0].autopilot = true
	gs.current_setup = setup
	change_scene_to_file("res://scenes/match/match.tscn")


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_match = current_scene
		_match.skip_intro()
		_match.chaos.auto_schedule = false
		for ev in _match.chaos.library:
			_ids.append(ev.id)
		_captures[FIRST + 40] = "%s_00_announce.png" % _mode
		for i in _ids.size():
			_captures[FIRST + STEP * (i + 1) + SHOT_DELAY] = "%s_%02d_%s.png" % [_mode, i + 1, _ids[i]]
	if _match == null:
		return false
	if _frame == FIRST:
		_match.chaos.force_event(&"moon", false, 3.0)
	if _frame == FIRST + 60:
		_match.chaos.end_all_events()
		_match.chaos.stop()
	for i in _ids.size():
		if _frame == FIRST + STEP * (i + 1):
			_match.chaos.end_all_events()
			_match.chaos.force_event(_ids[i], true)
	if _captures.has(_frame):
		var path := _out_dir.path_join(_captures[_frame])
		root.get_texture().get_image().save_png(path)
		print("saved ", path)
	var last := 0
	for f: int in _captures:
		last = maxi(last, f)
	if _frame > last:
		quit()
		return true
	# Software rendering is slow: only draw frames shortly before a capture.
	var next := 1 << 30
	for f: int in _captures:
		if f >= _frame:
			next = mini(next, f)
	RenderingServer.render_loop_enabled = next - _frame <= 2
	return false
