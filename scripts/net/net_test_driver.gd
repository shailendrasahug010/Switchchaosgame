extends Node
## Development tool: a phone that plays an online round on its own, for the
## multi-client sync test (tools/net_sync_test.gd). Started by Boot with
## --net-test=create|join|rejoin. Writes JSON lines to --net-log=FILE.
##
##   create  makes a room, writes its code to --code-file, starts the round
##           once --players people are in (with --mode, CPU buddies off)
##   join    reads the code from --code-file and joins
##   rejoin  reads code and seat secret from --seat-file and takes the seat back
##   ui-create / ui-join
##           the same as create / join, but through the real Online screen:
##           the phone taps "Make a room" (or "Join with a code" and the code's
##           letter keys), the host taps the game and CPU-buddy buttons and
##           START!, and after the results everyone taps "Back to the room".
##           --rounds=N plays N rounds; --mode=a,b picks a game per round.
##           A button that is hidden, disabled or off the screen is never
##           tapped (logged as "offscreen"), so a broken layout fails the test.
##   --look=jelly  play as that creature (so other phones can check it)
##   --screen=WxH  screen size to act like in UI modes (headless only)
##
## Every phone's creature is steered by the CPU brain (Net.autopilot).
## --cheat=teleport makes this phone try to jump its creature far ahead every
## few seconds (the server must refuse it).

var args: Dictionary = {}
var _log: FileAccess
var _started := false
var _seen_match: Object = null
var _pos_timer := 0.0
var _quit_at := -1.0
var _join_sent := false
var _wait := 0.0
var _cheat_timer := 4.0
# UI modes (ui-create / ui-join)
var _ui_step := ""
var _ui_wait := 0.0
var _ui_logged: Dictionary = {}
var _rounds_wanted := 1
var _rounds_done := 0
var _modes: PackedStringArray = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.persist_enabled = false
	GameState.settings.online_allowed = true
	GameState.settings.online_server = String(args.get("online-server", "127.0.0.1:%d" % Net.DEFAULT_PORT))
	GameState.settings.show_tips = false
	Net.autopilot = true
	var path := String(args.get("net-log", "user://net_test.log"))
	_log = FileAccess.open(path, FileAccess.WRITE)
	Net.status_changed.connect(func(st: int) -> void: _write({"ev": "status", "status": st}))
	Net.room_changed.connect(_on_room)
	Net.error_raised.connect(func(text: String) -> void: _write({"ev": "error", "text": text, "code": Net.last_error}))
	Net.corrected.connect(func(pos: Vector3) -> void: _write({"ev": "corrected", "pos": [pos.x, pos.y, pos.z]}))
	if args.has("look"):
		GameState.profile.character = StringName(String(args.look))
	_rounds_wanted = maxi(1, int(args.get("rounds", "1")))
	_modes = String(args.get("mode", "bounce_race")).split(",")
	match String(args.get("net-test", "")):
		"create":
			Net.create_room()
		"ui-create", "ui-join":
			_ui_step = "open"
		"rejoin":
			var seat := _read_json(String(args.get("seat-file", "")))
			Net.rejoin_room(String(seat.get("code", "")), String(seat.get("token", "")))
			_write({"ev": "rejoining", "code": seat.get("code", "")})


func _write(d: Dictionary) -> void:
	d["st"] = Net.server_now()
	d["lt"] = NetProtocol.now()
	if _log:
		_log.store_line(JSON.stringify(d))
		_log.flush()


func _read_json(path: String) -> Dictionary:
	if path == "" or not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _on_room(info: Dictionary) -> void:
	var players: Array = info.get("players", [])
	_write({"ev": "room", "code": info.get("code", ""), "players": players.size(), "state": info.get("state", ""),
			"host": info.get("host", false)})
	# Remember the seat (for the rejoin test).
	if args.has("seat-file") and Net.seat_token() != "":
		var f := FileAccess.open(String(args["seat-file"]), FileAccess.WRITE)
		f.store_string(JSON.stringify({"code": Net.room_code, "token": Net.seat_token()}))
		f.close()
	if String(args.get("net-test", "")) == "create":
		if args.has("code-file"):
			var f := FileAccess.open(String(args["code-file"]), FileAccess.WRITE)
			f.store_string(Net.room_code)
			f.close()
		if not _started and players.size() >= int(args.get("players", "2")) and info.get("state", "") == "lobby":
			_started = true
			Net.set_room_options(String(args.get("mode", "bounce_race")), args.has("cpus"))
			# Options first, then start (same reliable channel: in order).
			Net.start_round()
			_write({"ev": "start_requested"})


func _process(delta: float) -> void:
	if _quit_at > 0.0 and NetProtocol.now() >= _quit_at:
		_write({"ev": "quit"})
		Net.leave_room()
		get_tree().quit(0)
		return
	if _ui_step != "":
		_ui_process(delta)
	if String(args.get("net-test", "")) == "join" and not _join_sent:
		_wait -= delta
		if _wait <= 0.0:
			_wait = 0.5
			var path := String(args.get("code-file", ""))
			if FileAccess.file_exists(path):
				var code := FileAccess.get_file_as_string(path).strip_edges()
				if NetProtocol.is_valid_code(code):
					_join_sent = true
					Net.join_room(code)
					_write({"ev": "joining", "code": code})
	var m = Net._match
	if m != _seen_match and m != null:
		_seen_match = m
		_hook_match(m)
	if m != null and is_instance_valid(m):
		if args.get("cheat", "") == "teleport" and m.is_playing():
			_cheat_timer -= delta
			if _cheat_timer <= 0.0:
				_cheat_timer = 3.0
				var me: PlayerCharacter = m.players[m.local_player_index]
				var to := me.global_position + Vector3(0, 0, -30)
				_write({"ev": "cheat", "from": [me.global_position.x, me.global_position.y, me.global_position.z],
						"to": [to.x, to.y, to.z]})
				me.global_position = to
		_pos_timer -= delta
		if _pos_timer <= 0.0:
			_pos_timer = 0.1
			var pos := []
			for p in m.players:
				pos.append([p.global_position.x, p.global_position.y, p.global_position.z, p.is_simulated()])
			_write({"ev": "pos", "clock": m.clock, "phase": m.phase, "time_left": m.time_left, "pos": pos,
					"rtt": Net.rtt})


## Packed arrays -> plain arrays, for JSON.
func _plain(v: Variant) -> Variant:
	match typeof(v):
		TYPE_DICTIONARY:
			var out := {}
			for k in v:
				out[str(k)] = _plain(v[k])
			return out
		TYPE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_STRING_ARRAY:
			var out := []
			for x in v:
				out.append(_plain(x))
			return out
		TYPE_FLOAT:
			return snappedf(v, 0.01)
	return v


func _hook_match(m: MatchController) -> void:
	var chars := []
	for pl in m.players:
		chars.append(String(pl.character_id))
	_write({"ev": "match", "mode": String(m.setup.mode_id), "index": m.local_player_index,
			"players": m.players.size(), "seed": m.setup.seed, "phase_now": m.phase, "chars": chars})
	if _ui_step != "":
		_ui_step = "playing"
	m.phase_changed.connect(func(p: int) -> void:
		_write({"ev": "phase", "phase": p, "clock": m.clock, "success": m.success})
		if p == MatchController.Phase.RESULTS:
			var totals := []
			for pl in m.players:
				totals.append(m.score.total(pl.player_index))
			var awards := []
			for a in m.result.get("awards", []):
				awards.append(a.get("title", ""))
			_write({"ev": "results", "totals": totals, "success": m.success, "awards": awards,
					"headline": m.result.get("headline", ""), "mode_state": _plain(m.mode.get_net_state())})
			_rounds_done += 1
			if _ui_step != "" and _rounds_done < _rounds_wanted:
				_ui_step = "back_to_room"
				_ui_wait = 1.0
			else:
				_quit_at = NetProtocol.now() + float(args.get("linger", "1.5")))
	m.chaos.event_announced.connect(func(ev: ChaosEvent, lead: float) -> void:
		_write({"ev": "chaos", "id": String(ev.id), "what": "announce", "clock": m.clock, "lead": lead}))
	m.chaos.event_started.connect(func(ev: ChaosEvent) -> void:
		_write({"ev": "chaos", "id": String(ev.id), "what": "start", "clock": m.clock}))
	m.chaos.event_ended.connect(func(ev: ChaosEvent) -> void:
		_write({"ev": "chaos", "id": String(ev.id), "what": "end", "clock": m.clock}))
	m.score.scored.connect(func(i: int, cat: StringName, pts: int, reason: String) -> void:
		_write({"ev": "scored", "player": i, "cat": String(cat), "pts": pts, "reason": reason, "clock": m.clock}))


# ---------------------------------------------------------------- UI modes

func _ui_process(delta: float) -> void:
	_ui_wait -= delta
	if _ui_wait > 0.0:
		return
	_ui_wait = 0.25
	var creating := String(args.get("net-test", "")) == "ui-create"
	var lobby := _lobby()
	match _ui_step:
		"open":
			if DisplayServer.get_name() == "headless" and get_tree().root.size.x < 200:
				# No real window here: act like a phone screen (default 16:9;
				# --screen=2400x1080 for a 20:9 phone) so "on the screen" means
				# what it would on a device.
				var dims := String(args.get("screen", "1280x720")).split("x")
				if dims.size() == 2:
					get_tree().root.size = Vector2i(int(dims[0]), int(dims[1]))
				_ui_wait = 0.2
				return
			var vp := get_tree().root.get_visible_rect()
			_write({"ev": "ui", "what": "screen", "size": [vp.size.x, vp.size.y]})
			Router.go(&"online", false)
			_ui_step = "start_view"
		"start_view":
			if lobby and lobby.get("_view") == "start":
				if _tap(lobby, "MakeRoom" if creating else "JoinWithCode"):
					_write({"ev": "ui", "what": "pressed_make" if creating else "pressed_join_with_code"})
					_ui_step = "wait_room" if creating else "type_code"
		"wait_room":
			if lobby and lobby.get("_view") == "room":
				var label := lobby.find_child("RoomCode", true, false) as Label
				if label and NetProtocol.is_valid_code(label.text):
					_write({"ev": "ui", "what": "room_code_shown", "code": label.text, "matches_net": label.text == Net.room_code})
					if args.has("code-file"):
						var f := FileAccess.open(String(args["code-file"]), FileAccess.WRITE)
						f.store_string(label.text)
						f.close()
					_ui_step = "host_setup"
		"host_setup":
			# Wait for friends, pick this round's game and CPU buddies, START.
			var info := Net.room_info
			if lobby == null or lobby.get("_view") != "room" or String(info.get("state", "")) != "lobby":
				return
			if (info.get("players", []) as Array).size() < int(args.get("players", "2")):
				return
			var want := _modes[mini(_rounds_done, _modes.size() - 1)]
			if String(info.get("mode", "")) != want:
				_tap(lobby, "Mode_" + want)
				_ui_wait = 0.6  # the room screen changes once the server agrees
				return
			if bool(info.get("cpus", true)) != args.has("cpus"):
				_tap(lobby, "CpuToggle")
				_ui_wait = 0.6
				return
			if _tap(lobby, "StartButton"):
				_write({"ev": "ui", "what": "pressed_start", "round": _rounds_done + 1, "mode": want})
				_ui_step = "playing"
		"type_code":
			if lobby == null or lobby.get("_view") != "code":
				return
			var path := String(args.get("code-file", ""))
			if not FileAccess.file_exists(path):
				return
			var code := FileAccess.get_file_as_string(path).strip_edges()
			if not NetProtocol.is_valid_code(code):
				return
			var join_btn := lobby.find_child("JoinButton", true, false) as Button
			if join_btn == null:
				return
			var was_disabled := join_btn.disabled
			for ch in code:
				if not _tap(lobby, "Key_" + ch):
					return
			_write({"ev": "ui", "what": "typed_code", "code": code, "join_was_disabled": was_disabled,
					"join_enabled": not join_btn.disabled})
			if _tap_button(join_btn):
				_ui_step = "wait_room_join"
		"wait_room_join":
			if lobby and lobby.get("_view") == "room":
				var label := lobby.find_child("RoomCode", true, false) as Label
				_write({"ev": "ui", "what": "in_room", "code": label.text if label else "",
						"players": (Net.room_info.get("players", []) as Array).size(), "host": Net.is_host()})
				_ui_step = "playing"
		"playing":
			pass  # the round runs; its results move us on (see _hook_match)
		"back_to_room":
			var b := _button_with_text(get_tree().current_scene, "Back to the room")
			if b and _tap_button(b):
				_write({"ev": "ui", "what": "pressed_back_to_room"})
				_ui_step = "back_in_room"
		"back_in_room":
			if lobby and lobby.get("_view") == "room":
				_write({"ev": "ui", "what": "back_in_room", "state": String(Net.room_info.get("state", "")),
						"players": (Net.room_info.get("players", []) as Array).size()})
				# The host gives friends a moment to come back too.
				_ui_step = "host_setup" if creating else "playing"
				_ui_wait = 3.0 if creating else 0.25


func _lobby() -> Node:
	var s := get_tree().current_scene
	if s and s.scene_file_path == "res://scenes/menus/online_lobby.tscn" and s.is_node_ready():
		return s
	return null


func _tap(root: Node, node_name: String) -> bool:
	var b := root.find_child(node_name, true, false) as Button
	return b != null and _tap_button(b)


## Presses a button the way a finger could: only if it is shown, enabled and
## completely on the screen.
func _tap_button(b: Button) -> bool:
	if not b.is_visible_in_tree() or b.disabled:
		return false
	var screen := b.get_viewport().get_visible_rect()
	var rect := b.get_global_rect()
	if not screen.encloses(rect):
		if not _ui_logged.has(b.name):
			_ui_logged[b.name] = true
			_write({"ev": "offscreen", "button": String(b.name), "rect": [rect.position.x, rect.position.y,
					rect.size.x, rect.size.y], "screen": [screen.size.x, screen.size.y]})
		return false
	b.pressed.emit()
	return true


func _button_with_text(root: Node, text: String) -> Button:
	if root == null:
		return null
	for n in root.find_children("*", "Button", true, false):
		var b := n as Button
		var l := b.find_child("Text", true, false) as Label
		if (l.text if l else b.text) == text:
			return b
	return null
