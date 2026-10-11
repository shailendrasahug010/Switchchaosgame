extends Node
## Development tool: a phone that plays an online round on its own, for the
## multi-client sync test (tools/net_sync_test.gd). Started by Boot with
## --net-test=create|join|rejoin. Writes JSON lines to --net-log=FILE.
##
##   create  makes a room, writes its code to --code-file, starts the round
##           once --players people are in (with --mode, CPU buddies off)
##   join    reads the code from --code-file and joins
##   rejoin  reads code and seat secret from --seat-file and takes the seat back
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
	match String(args.get("net-test", "")):
		"create":
			Net.create_room()
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
	_write({"ev": "match", "mode": String(m.setup.mode_id), "index": m.local_player_index,
			"players": m.players.size(), "seed": m.setup.seed, "phase_now": m.phase})
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
			_quit_at = NetProtocol.now() + float(args.get("linger", "1.5")))
	m.chaos.event_announced.connect(func(ev: ChaosEvent, lead: float) -> void:
		_write({"ev": "chaos", "id": String(ev.id), "what": "announce", "clock": m.clock, "lead": lead}))
	m.chaos.event_started.connect(func(ev: ChaosEvent) -> void:
		_write({"ev": "chaos", "id": String(ev.id), "what": "start", "clock": m.clock}))
	m.chaos.event_ended.connect(func(ev: ChaosEvent) -> void:
		_write({"ev": "chaos", "id": String(ev.id), "what": "end", "clock": m.clock}))
	m.score.scored.connect(func(i: int, cat: StringName, pts: int, reason: String) -> void:
		_write({"ev": "scored", "player": i, "cat": String(cat), "pts": pts, "reason": reason, "clock": m.clock}))
