extends SceneTree
## Visual check of the online lobby (scenes/menus/online_lobby.tscn) in each
## of its views, using made-up room data so no server is needed. Saves one
## screenshot per view. Needs a display (Xvfb on Linux).
##
##   godot --path . --rendering-driver opengl3 --resolution 1280x720 -s tools/lobby_gallery.gd -- \
##       --out-dir=/tmp/lobby
##
## Images: <out-dir>/lobby_01_locked.png ... lobby_08_server_address.png
## (the real connection flow is covered by tools/net_sync_test.gd -- --only=lobby).

const SETTLE := 24   # frames between switching a view and taking its picture

var _out_dir := "user://lobby_gallery"
var _frame := 0
## Untyped on purpose: a -s script cannot compile against classes that use
## autoload names, so the lobby and autoloads are only touched at runtime.
var _lobby = null
var _net = null
var _gs = null
var _steps: Array = []   # [name, callable]
var _step := -1
var _next_at := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var parts := a.trim_prefix("--").split("=", true, 1)
		if parts[0] == "out-dir" and parts.size() > 1:
			_out_dir = parts[1]
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_gs = root.get_node("GameState")
	_gs.persist_enabled = false
	_net = root.get_node("Net")
	_steps = [
		["01_locked", func() -> void:
			# (GameState loads its defaults after _initialize, so set them here.)
			_gs.reset_to_defaults()
			_gs.settings.online_allowed = false
			_gs.settings.online_server = "192.168.1.20"
			_lobby._refresh()],
		["02_start", func() -> void:
			_gs.settings.online_allowed = true
			_lobby._refresh()],
		["03_code_entry", func() -> void:
			_lobby._show_code_entry()
			for ch in "BC7":
				_lobby._type(ch)],
		["04_connecting", func() -> void:
			_net.status = _net.Status.CONNECTING
			_lobby._refresh()],
		["05_room_host", func() -> void:
			_net.room_info = _room(true, 2, "lobby", "button_mayhem", true)
			_net.status = _net.Status.IN_ROOM
			_lobby._refresh()],
		["06_room_guest_round_on", func() -> void:
			_net.room_info = _room(false, 4, "playing", "cake_dash", false)
			_lobby._show_room()],
		["07_error", func() -> void:
			_net.status = _net.Status.OFFLINE
			_net.room_info = {}
			_lobby._show_start()
			_lobby._show_error(load("res://scripts/net/net_protocol.gd").error_text("room_not_found"))],
		["08_server_address", func() -> void:
			_lobby._toast.visible = false
			_lobby._edit_server_address()],
	]
	change_scene_to_file("res://scenes/menus/online_lobby.tscn")


func _room(host: bool, people: int, state: String, mode: String, cpus: bool) -> Dictionary:
	var looks := [
		{"character": "bloop", "hat": "party", "paint": "classic"},
		{"character": "jelly", "hat": "none", "paint": "classic"},
		{"character": "mossy", "hat": "none", "paint": "classic"},
		{"character": "sunny", "hat": "none", "paint": "classic"},
	]
	var players := []
	var me := 0 if host else 1
	for i in people:
		# P3 shows the "reconnecting..." state when there are 3+ people.
		players.append({"label": "P%d" % (i + 1), "color": i, "look": looks[i], "connected": i != 2,
				"host": i == 0, "you": i == me})
	return {"code": "K7QXM", "players": players, "mode": mode, "cpus": cpus, "state": state, "host": host}


func _process(_delta: float) -> bool:
	_frame += 1
	# Pretend states only: Net must never try to talk to a server. (Turned off
	# here, after its _ready, which would switch processing back on.)
	_net.set_process(false)
	_net.set_physics_process(false)
	if _lobby == null:
		if current_scene != null and current_scene.has_method("_show_room"):
			_lobby = current_scene
			_next_at = _frame + 2
		return false
	if _frame < _next_at:
		return false
	if _step >= 0:
		var path := _out_dir.path_join("lobby_%s.png" % _steps[_step][0])
		root.get_texture().get_image().save_png(path)
		print("saved ", path)
	_step += 1
	if _step >= _steps.size():
		quit()
		return true
	(_steps[_step][1] as Callable).call()
	_next_at = _frame + SETTLE
	return false
