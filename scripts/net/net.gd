extends Node
## Online play (proof of concept). See docs/ONLINE_MULTIPLAYER_PLAN.md.
##
## The same autoload runs on both sides of the connection, so every message
## below exists on both (Godot calls the matching method on the other side):
##   c_*  phone -> room server (always checked on the server)
##   s_*  room server -> phone
##
## The room server ("godot --headless -- --server") keeps private rooms with
## short codes (NetRoom). It runs every round itself and is the referee.
## Phones move their own creature right away (so controls feel instant),
## send it 20 times a second, and show everything else as the server says.
## Local play never touches this node.
##
## Privacy: no names, accounts, chat or location. A phone sends a room code,
## its creature's look, its creature's position and button presses. Phones
## can't send anything to each other (server_relay is off).

signal status_changed(status: Status)
signal room_changed(info: Dictionary)
signal error_raised(text: String)
## The server put our creature back (it did not accept a move).
signal corrected(position: Vector3)

enum Status { OFFLINE, CONNECTING, CONNECTED, IN_ROOM, RECONNECTING }

const DEFAULT_PORT := NetProtocol.DEFAULT_PORT

var is_server := false

# ---------------------------------------------------------------- phone state
var status: Status = Status.OFFLINE
var server_address := "127.0.0.1"
var server_port := DEFAULT_PORT
var room_code := ""
var room_info: Dictionary = {}
var last_error := ""
var rtt := 0.0
## Tests / demos: the phone's own creature is steered by the CPU brain.
var autopilot := false

var _token := ""
## What to do once connected: {"do": "create"|"join"|"rejoin", ...}
var _want: Dictionary = {}
var _clock_offset := 0.0       # server time - local time
var _have_clock := false
var _ping_samples: Array = []  # [rtt, offset]
var _ping_timer := 0.0
var _pending_match: Dictionary = {}
var _match: MatchController = null
var _snapshots: Array = []     # [{t, clock, time_left, states}], oldest first
var _clock_base := 0.0         # round clock - server time
var _have_clock_base := false
var _seq := 0
var _send_accum := 0.0
var _reconnect_until := 0.0
var _reconnect_timer := 0.0
var _phase_info: Array = []     # last s_phase before the match was attached

# ---------------------------------------------------------------- server state
var _rooms: Dictionary = {}     # code -> NetRoom
var _peer_room: Dictionary = {} # peer id -> code
var _join_tries: Dictionary = {}  # peer id -> Array of times
var _housekeeping := 0.0
var _live_peers: Dictionary = {}  # peer id -> true while connected
var max_rooms := 200
var round_time_override := 0.0
## Tests: the server quits cleanly once this file exists.
var stop_file := ""
var _log_file: FileAccess = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var mp := multiplayer as SceneMultiplayer
	if mp:
		mp.peer_connected.connect(_on_peer_connected)
		mp.peer_disconnected.connect(_on_peer_disconnected)
		mp.connected_to_server.connect(_on_connected)
		mp.connection_failed.connect(_on_connection_failed)
		mp.server_disconnected.connect(_on_server_disconnected)
		mp.peer_authenticating.connect(_on_peer_authenticating)
		mp.peer_authentication_failed.connect(_on_auth_failed)


func log_line(text: String) -> void:
	var line := "[%s] %s" % [Time.get_datetime_string_from_system(), text]
	print(line)
	if _log_file:
		_log_file.store_line(line)
		_log_file.flush()


# ================================================================ room server

## Starts the room server (headless). Returns OK or an error.
func start_server(port: int = DEFAULT_PORT, p_max_rooms: int = 200) -> Error:
	is_server = true
	max_rooms = p_max_rooms
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, mini(p_max_rooms * NetProtocol.MAX_SEATS, 1024))
	if err != OK:
		log_line("Could not open UDP port %d (%s)." % [port, error_string(err)])
		return err
	_configure_multiplayer(peer)
	log_line("The Chaos Switch room server %s (protocol %d) listening on UDP port %d." % [
			ProjectSettings.get_setting("application/config/version", "?"), NetProtocol.VERSION, port])
	return OK


func _configure_multiplayer(peer: ENetMultiplayerPeer) -> void:
	var mp := multiplayer as SceneMultiplayer
	mp.server_relay = false            # phones never talk to each other
	mp.allow_object_decoding = false   # plain values only
	mp.auth_timeout = 5.0
	mp.auth_callback = _on_auth_data
	mp.multiplayer_peer = peer


func _on_peer_connected(id: int) -> void:
	if not is_server:
		return
	_live_peers[id] = true
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet:
		var host_peer := enet.get_peer(id)
		if host_peer:
			# Notice dead connections within a few seconds.
			host_peer.set_timeout(32, 3000, 8000)
	log_line("peer %d connected (%d online)" % [id, multiplayer.get_peers().size()])


func _on_peer_disconnected(id: int) -> void:
	if not is_server:
		return
	_live_peers.erase(id)
	_join_tries.erase(id)
	var room := _room_of(id)
	_peer_room.erase(id)
	if room:
		room.member_disconnected(id)
	log_line("peer %d disconnected" % id)


## Room server: sends [param method] to one phone, if it is still really
## connected (a phone that is just dropping out is skipped quietly).
func send(peer: int, method: StringName, args: Array = []) -> void:
	if not _live_peers.has(peer):
		return
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet:
		var pp := enet.get_peer(peer)
		if pp == null or pp.get_state() != ENetPacketPeer.STATE_CONNECTED:
			return
	callv(&"rpc_id", [peer, method] + args)


func _room_of(peer: int) -> NetRoom:
	var code: String = _peer_room.get(peer, "")
	if code == "":
		return null
	return _rooms.get(code)


func _process(delta: float) -> void:
	if is_server:
		_housekeeping += delta
		if _housekeeping >= 1.0:
			_housekeeping = 0.0
			if stop_file != "" and FileAccess.file_exists(stop_file):
				log_line("stop file found: shutting down")
				get_tree().quit(0)
				return
			var now := NetProtocol.now()
			for code in _rooms.keys():
				var room: NetRoom = _rooms[code]
				if not room.check_timeouts(now):
					_close_room(code)
		return
	_client_process(delta)


func _close_room(code: String) -> void:
	var room: NetRoom = _rooms.get(code)
	if room == null:
		return
	for peer in _peer_room.keys():
		if _peer_room[peer] == code:
			_peer_room.erase(peer)
	_rooms.erase(code)
	room.close()
	log_line("room %s closed (%d rooms open)" % [code, _rooms.size()])


func _join_allowed(peer: int) -> bool:
	var now := NetProtocol.now()
	var tries: Array = _join_tries.get(peer, [])
	while not tries.is_empty() and now - float(tries[0]) > 20.0:
		tries.remove_at(0)
	tries.append(now)
	_join_tries[peer] = tries
	return tries.size() <= 6


func _sender() -> int:
	return multiplayer.get_remote_sender_id()


func _leave_current_room(peer: int) -> void:
	var room := _room_of(peer)
	if room:
		_peer_room.erase(peer)
		room.member_left(peer)
		if room.seat_count() == 0:
			_close_room(room.code)


func _send_joined(peer: int, room: NetRoom, seat: int) -> void:
	_peer_room[peer] = room.code
	send(peer, &"s_joined", [room.code, (room.seats[seat] as NetRoom.Seat).token])
	room.broadcast_room()


# ---------------------------------------------------------------- phone -> server

@rpc("any_peer", "call_remote", "reliable")
func c_create_room(look: Dictionary) -> void:
	if not is_server:
		return
	var peer := _sender()
	if not _join_allowed(peer):
		send(peer, &"s_error", ["too_many_tries"])
		return
	if _rooms.size() >= max_rooms:
		send(peer, &"s_error", ["server_full"])
		return
	_leave_current_room(peer)
	var code := NetProtocol.make_code()
	while _rooms.has(code):
		code = NetProtocol.make_code()
	var room := NetRoom.new(self, code)
	room.round_time_override = round_time_override
	_rooms[code] = room
	add_child(room)
	var seat := room.add_member(peer, NetProtocol.clean_look(look))
	log_line("room %s created by peer %d (%d rooms open)" % [code, peer, _rooms.size()])
	_send_joined(peer, room, seat)


@rpc("any_peer", "call_remote", "reliable")
func c_join_room(code: String, look: Dictionary) -> void:
	if not is_server:
		return
	var peer := _sender()
	if not _join_allowed(peer):
		send(peer, &"s_error", ["too_many_tries"])
		return
	code = NetProtocol.normalize_code(code)
	if not NetProtocol.is_valid_code(code):
		send(peer, &"s_error", ["bad_code"])
		return
	var room: NetRoom = _rooms.get(code)
	if room == null:
		send(peer, &"s_error", ["room_not_found"])
		return
	if _room_of(peer) == room:
		_send_joined(peer, room, room.seat_of_peer(peer))
		return
	if room.is_full():
		send(peer, &"s_error", ["room_full"])
		return
	_leave_current_room(peer)
	var seat := room.add_member(peer, NetProtocol.clean_look(look))
	log_line("peer %d joined room %s" % [peer, code])
	_send_joined(peer, room, seat)


@rpc("any_peer", "call_remote", "reliable")
func c_rejoin_room(code: String, token: String) -> void:
	if not is_server:
		return
	var peer := _sender()
	if not _join_allowed(peer):
		send(peer, &"s_error", ["too_many_tries"])
		return
	code = NetProtocol.normalize_code(code)
	var room: NetRoom = _rooms.get(code) if NetProtocol.is_valid_code(code) else null
	if room == null or not NetProtocol.is_valid_token(token):
		send(peer, &"s_error", ["rejoin_failed"])
		return
	var seat := room.rejoin(peer, token)
	if seat < 0:
		send(peer, &"s_error", ["rejoin_failed"])
		return
	log_line("peer %d rejoined room %s" % [peer, code])
	_send_joined(peer, room, seat)
	if room.in_round(seat):
		room.send_match_start(seat)


@rpc("any_peer", "call_remote", "reliable")
func c_leave_room() -> void:
	if is_server:
		_leave_current_room(_sender())


@rpc("any_peer", "call_remote", "reliable")
func c_set_look(look: Dictionary) -> void:
	var room := _room_of(_sender()) if is_server else null
	if room:
		room.set_look(_sender(), NetProtocol.clean_look(look))


@rpc("any_peer", "call_remote", "reliable")
func c_room_options(mode_id: String, cpus: bool) -> void:
	var peer := _sender()
	var room := _room_of(peer) if is_server else null
	if room == null:
		return
	if not room.is_host(peer):
		send(peer, &"s_error", ["not_host"])
		return
	room.set_options(mode_id, cpus)


@rpc("any_peer", "call_remote", "reliable")
func c_start_round() -> void:
	var peer := _sender()
	var room := _room_of(peer) if is_server else null
	if room == null:
		return
	if not room.is_host(peer):
		send(peer, &"s_error", ["not_host"])
		return
	if not room.start_round():
		send(peer, &"s_error", ["cant_start"])


@rpc("any_peer", "call_remote", "reliable")
func c_loaded() -> void:
	var room := _room_of(_sender()) if is_server else null
	if room:
		room.member_loaded(_sender())


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func c_state(seq: int, data: PackedFloat32Array) -> void:
	var room := _room_of(_sender()) if is_server else null
	if room:
		room.on_state(_sender(), seq, data)


@rpc("any_peer", "call_remote", "reliable")
func c_event(kind: int, value: Vector3, pos: Vector3) -> void:
	var room := _room_of(_sender()) if is_server else null
	if room:
		room.on_event(_sender(), kind, value, pos)


@rpc("any_peer", "call_remote", "reliable")
func c_interact() -> void:
	var room := _room_of(_sender()) if is_server else null
	if room:
		room.on_interact(_sender())


@rpc("any_peer", "call_remote", "unreliable")
func c_ping(client_time: float) -> void:
	if is_server:
		send(_sender(), &"s_pong", [client_time, NetProtocol.now()])


# ---------------------------------------------------------------- version check

## Both sides send a small hello; the server only lets matching versions in.
func _on_peer_authenticating(id: int) -> void:
	var mp := multiplayer as SceneMultiplayer
	if is_server:
		return
	mp.send_auth(id, var_to_bytes({"v": NetProtocol.VERSION}))


func _on_auth_data(id: int, data: PackedByteArray) -> void:
	var mp := multiplayer as SceneMultiplayer
	if data.size() > 256:
		mp.disconnect_peer(id)
		return
	var msg = bytes_to_var(data)
	if is_server:
		if typeof(msg) == TYPE_DICTIONARY and int(msg.get("v", -1)) == NetProtocol.VERSION:
			mp.send_auth(id, var_to_bytes({"ok": true}))
			mp.complete_auth(id)
		else:
			mp.send_auth(id, var_to_bytes({"ok": false}))
			# Give the reply a moment to leave before closing.
			get_tree().create_timer(0.3).timeout.connect(func() -> void: mp.disconnect_peer(id))
	else:
		if typeof(msg) == TYPE_DICTIONARY and bool(msg.get("ok", false)):
			mp.complete_auth(id)
		else:
			_fail("update_needed")


func _on_auth_failed(_id: int) -> void:
	if not is_server and last_error == "":
		_fail("connect_failed")


# ================================================================ phone

## Connects to the room server and then creates / joins a room.
func create_room() -> void:
	_start(Status.CONNECTING, {"do": "create"})


func join_room(code: String) -> void:
	_start(Status.CONNECTING, {"do": "join", "code": NetProtocol.normalize_code(code)})


## Takes a seat back with its secret (tests; phones do this by themselves
## after a dropped connection).
func rejoin_room(code: String, token: String) -> void:
	_start(Status.CONNECTING, {"do": "rejoin"})
	room_code = NetProtocol.normalize_code(code)
	_token = token


## The secret for this phone's seat (kept only in memory).
func seat_token() -> String:
	return _token


func leave_room() -> void:
	if status == Status.IN_ROOM and multiplayer.multiplayer_peer \
			and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		rpc_id(1, &"c_leave_room")
	_disconnect()
	room_code = ""
	_token = ""
	room_info = {}
	_set_status(Status.OFFLINE)


func set_room_options(mode_id: String, cpus: bool) -> void:
	if status == Status.IN_ROOM:
		rpc_id(1, &"c_room_options", mode_id, cpus)


func start_round() -> void:
	if status == Status.IN_ROOM:
		rpc_id(1, &"c_start_round")


func send_look() -> void:
	if status == Status.IN_ROOM:
		rpc_id(1, &"c_set_look", my_look())


func my_look() -> Dictionary:
	var prof: Dictionary = GameState.profile
	return {"character": String(prof.get("character", "bloop")), "hat": String(prof.get("hat", "none")),
			"paint": String(prof.get("paint", "classic"))}


func is_host() -> bool:
	return bool(room_info.get("host", false))


func _start(new_status: Status, want: Dictionary) -> void:
	_disconnect()
	last_error = ""
	_want = want
	var parsed := parse_address(String(GameState.get_setting("online_server", "127.0.0.1")))
	server_address = parsed.host
	server_port = parsed.port
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(server_address, server_port)
	if err != OK:
		_fail("connect_failed")
		return
	_configure_multiplayer(peer)
	_set_status(new_status)


## "192.168.1.20" or "example.org:7777" -> {host, port}.
static func parse_address(text: String) -> Dictionary:
	var t := text.strip_edges()
	var port := DEFAULT_PORT
	var colon := t.rfind(":")
	if colon > 0 and t.count(":") == 1:
		var p := t.substr(colon + 1)
		if p.is_valid_int():
			port = clampi(int(p), 1, 65535)
		t = t.substr(0, colon)
	if t == "":
		t = "127.0.0.1"
	return {"host": t, "port": port}


func _disconnect() -> void:
	if is_server:
		return
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_have_clock = false
	_ping_samples.clear()


func _set_status(s: Status) -> void:
	status = s
	status_changed.emit(s)


func _fail(code: String) -> void:
	last_error = code
	var was_in_room := status == Status.IN_ROOM or status == Status.RECONNECTING
	_disconnect()
	_set_status(Status.OFFLINE)
	if code == "rejoin_failed" or was_in_room:
		room_code = ""
		_token = ""
		room_info = {}
	error_raised.emit(NetProtocol.error_text(code))


func _on_connected() -> void:
	if is_server:
		return
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet and enet.get_peer(1):
		enet.get_peer(1).set_timeout(32, 3000, 8000)
	_set_status(Status.CONNECTED)
	_ping_timer = 0.0
	for i in 3:
		_send_ping()
	match String(_want.get("do", "")):
		"create":
			rpc_id(1, &"c_create_room", my_look())
		"join":
			rpc_id(1, &"c_join_room", String(_want.code), my_look())
		"rejoin":
			rpc_id(1, &"c_rejoin_room", room_code, _token)


func _on_connection_failed() -> void:
	if is_server:
		return
	if status == Status.RECONNECTING:
		_disconnect()  # try again shortly (see _client_process)
		return
	_fail("connect_failed")


func _on_server_disconnected() -> void:
	if is_server:
		return
	if status == Status.IN_ROOM and room_code != "" and _token != "":
		# Try to get the seat back for a while (phone asleep, Wi-Fi hiccup...).
		_disconnect()
		_reconnect_until = NetProtocol.now() + NetProtocol.RECONNECT_GRACE - 5.0
		_reconnect_timer = 0.5
		_set_status(Status.RECONNECTING)
		if _match:
			_match.show_message("Connection lost. Reconnecting...", Color("ffd23f"), 3.0)
		return
	if status != Status.OFFLINE:
		_fail("lost_connection")


func _client_process(delta: float) -> void:
	match status:
		Status.RECONNECTING:
			if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
				_reconnect_timer -= delta
				if NetProtocol.now() > _reconnect_until:
					_fail("lost_connection")
				elif _reconnect_timer <= 0.0:
					_reconnect_timer = 2.0
					var want := {"do": "rejoin"}
					var code := room_code
					var token := _token
					_start(Status.RECONNECTING, want)
					room_code = code
					_token = token
		Status.CONNECTED, Status.IN_ROOM:
			_ping_timer -= delta
			if _ping_timer <= 0.0:
				_ping_timer = 2.0
				_send_ping()


func _send_ping() -> void:
	rpc_id(1, &"c_ping", NetProtocol.now())


## Server time estimate on this phone.
func server_now() -> float:
	return NetProtocol.now() + _clock_offset


# ---------------------------------------------------------------- server -> phone

@rpc("authority", "call_remote", "unreliable")
func s_pong(client_time: float, server_time: float) -> void:
	var now := NetProtocol.now()
	var sample_rtt := now - client_time
	if sample_rtt < 0.0 or sample_rtt > 5.0:
		return
	var offset := server_time + sample_rtt * 0.5 - now
	_ping_samples.append([sample_rtt, offset])
	if _ping_samples.size() > 8:
		_ping_samples.remove_at(0)
	# Trust the quickest round trip most (least delay noise).
	var best: Array = _ping_samples[0]
	for s in _ping_samples:
		if float(s[0]) < float(best[0]):
			best = s
	rtt = float(best[0])
	if not _have_clock or absf(float(best[1]) - _clock_offset) > 0.25:
		_clock_offset = float(best[1])
	else:
		_clock_offset = lerpf(_clock_offset, float(best[1]), 0.2)
	_have_clock = true


@rpc("authority", "call_remote", "reliable")
func s_error(code: String) -> void:
	if code in ["rejoin_failed", "update_needed", "server_full"] or status != Status.IN_ROOM:
		_fail(code)
	else:
		last_error = code
		error_raised.emit(NetProtocol.error_text(code))


@rpc("authority", "call_remote", "reliable")
func s_joined(code: String, token: String) -> void:
	room_code = code
	_token = token
	_set_status(Status.IN_ROOM)


@rpc("authority", "call_remote", "reliable")
func s_room(info: Dictionary) -> void:
	room_info = info
	room_changed.emit(info)


## The host started a round (or we came back into one): load the arena.
@rpc("authority", "call_remote", "reliable")
func s_match_start(info: Dictionary, player_index: int) -> void:
	var setup := _setup_from_info(info, player_index)
	if setup == null:
		return
	if _match and _match.setup.seed == setup.seed and _match.setup.mode_id == setup.mode_id \
			and _match.local_player_index == player_index:
		# Back after a dropped connection, still in the same round: no reload,
		# the server just sends the whole picture again (s_catchup).
		_snapshots.clear()
		rpc_id(1, &"c_loaded")
		return
	_pending_match = {"setup": setup, "index": player_index}
	_snapshots.clear()
	_have_clock_base = false
	_phase_info.clear()
	GameState.current_setup = setup
	InputSetup.configure_local_players(1)
	Router.go(&"match")


func _setup_from_info(info: Dictionary, my_index: int) -> MatchSetup:
	var slots = info.get("slots")
	if typeof(slots) != TYPE_ARRAY or (slots as Array).is_empty() or (slots as Array).size() > NetProtocol.MAX_SEATS:
		return null
	if my_index < 0 or my_index >= (slots as Array).size() or not NetProtocol.is_online_mode(String(info.get("mode", ""))):
		return null
	var setup := MatchSetup.new()
	setup.mode_id = StringName(String(info.mode))
	setup.seed = int(info.get("seed", 1))
	setup.round_time = clampf(float(info.get("time", 0.0)), 0.0, 600.0)
	setup.chaos_enabled = bool(info.get("chaos", true))
	setup.team_carry = bool(info.get("team_carry", true))
	setup.online = true
	for i in (slots as Array).size():
		var d = slots[i]
		var look := NetProtocol.clean_look(d.get("look") if typeof(d) == TYPE_DICTIONARY else null)
		var slot := MatchSetup.Slot.new()
		slot.character_id = StringName(look.character)
		slot.hat_id = StringName(look.hat)
		slot.paint_id = StringName(look.paint)
		if i == my_index:
			slot.kind = MatchSetup.Kind.HUMAN
			slot.local_index = 1
			slot.autopilot = autopilot
		else:
			slot.kind = MatchSetup.Kind.REMOTE
			slot.remote_cpu = typeof(d) == TYPE_DICTIONARY and bool(d.get("cpu", false))
		setup.slots.append(slot)
	return setup


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func s_snapshot(server_time: float, clock: float, time_left: float, states: PackedFloat32Array,
		mode_state: Dictionary) -> void:
	if _match == null or states.size() != _match.players.size() * NetProtocol.PLAYER_FLOATS:
		return
	if not NetProtocol.all_finite(states):
		return
	var base := clock - server_time
	if not _have_clock_base or absf(base - _clock_base) > 0.3:
		_clock_base = base
	else:
		_clock_base = lerpf(_clock_base, base, 0.1)
	_have_clock_base = true
	_snapshots.append({"t": server_time, "time_left": time_left, "states": states})
	while _snapshots.size() > 12:
		_snapshots.remove_at(0)
	if not mode_state.is_empty():
		_match.mode.apply_net_state(mode_state)


@rpc("authority", "call_remote", "reliable")
func s_phase(phase: int, started_at: float, success: bool) -> void:
	if _match == null:
		_phase_info = [phase, started_at, success]
		return
	_match.net_set_phase(clampi(phase, 0, MatchController.Phase.RESULTS) as MatchController.Phase, started_at, success)


@rpc("authority", "call_remote", "reliable")
func s_catchup(data: Dictionary) -> void:
	if _match == null:
		return
	var m := _match
	if data.get("clock") is float and data.get("server_time") is float:
		_clock_base = float(data.clock) - float(data.server_time)
		_have_clock_base = true
		m.clock = maxf(m.clock, server_now() + _clock_base)
	if data.get("scores") is Dictionary:
		m.score.import_data(data.scores)
	m.time_left = maxf(0.0, float(data.get("time_left", m.time_left)))
	m.net_set_phase(clampi(int(data.get("phase", 0)), 0, MatchController.Phase.RESULTS) as MatchController.Phase,
			float(data.get("started", 0.0)), bool(data.get("success", false)))
	if data.get("mode") is Dictionary:
		m.mode.apply_net_state(data.mode)
	for entry in data.get("chaos_active", []):
		if entry is Array and (entry as Array).size() == 2:
			m.chaos.apply_remote(StringName(str(entry[0])), "start", float(entry[1]))
	var pending = data.get("chaos_pending", [])
	if pending is Array and (pending as Array).size() == 2:
		m.chaos.apply_remote(StringName(str(pending[0])), "announce", float(pending[1]))
	var you = data.get("you")
	var me := _local_player()
	if you is Dictionary and me:
		if you.get("pos") is Vector3:
			me.teleport(you.pos)
		if you.get("respawn") is Vector3:
			me.respawn_position = you.respawn
		me.controls_enabled = bool(you.get("controls", me.controls_enabled))
		if you.get("personal") is Dictionary:
			me.personal.set_all(you.personal)


@rpc("authority", "call_remote", "reliable")
func s_chaos(id: String, phase: String, value: float) -> void:
	if _match and phase in ["announce", "start", "end"]:
		_match.chaos.apply_remote(StringName(id), phase, clampf(value, 0.0, 120.0))


@rpc("authority", "call_remote", "reliable")
func s_scored(player_index: int, category: String, points: int, reason: String, world_pos: Vector3) -> void:
	if _match:
		_match.net_apply_scored(player_index, StringName(category), points, reason, world_pos)


@rpc("authority", "call_remote", "reliable")
func s_message(text: String, color: Color, seconds: float) -> void:
	if _match:
		_match.show_message(text, color, clampf(seconds, 0.5, 6.0))


@rpc("authority", "call_remote", "reliable")
func s_fx(kind: String, args: Array) -> void:
	if _match:
		_match.net_apply_fx(StringName(kind), args)


@rpc("authority", "call_remote", "reliable")
func s_mode_event(event_name: String, args: Array) -> void:
	if _match:
		_match.mode.apply_net_event(StringName(event_name), args)


@rpc("authority", "call_remote", "reliable")
func s_results(score_data: Dictionary, awards: Array) -> void:
	if _match:
		_match.net_set_results(score_data, awards)


## A command for one creature (our own: knock, respawn...; anyone: react...).
@rpc("authority", "call_remote", "reliable")
func s_player_cmd(player_index: int, command: String, args: Array) -> void:
	if _match == null or player_index < 0 or player_index >= _match.players.size():
		return
	var p := _match.players[player_index]
	var mine := p.is_simulated()
	match command:
		"celebrate":
			p.celebrate()
		"react":
			if args.size() == 1:
				p.react(StringName(str(args[0])))
		"controls":
			if mine and args.size() == 1:
				p.controls_enabled = bool(args[0])
				if not p.controls_enabled and p.input:
					p.input.reset()
		"respawn_point":
			if mine and args.size() == 1 and args[0] is Vector3:
				p.respawn_position = args[0]
		"knock":
			if mine and args.size() == 3 and args[0] is Vector3:
				p.knock(args[0], clampf(float(args[1]), 0.0, 20.0), clampf(float(args[2]), 0.0, 20.0))
		"launch":
			if mine and args.size() == 1:
				p.launch(clampf(float(args[0]), 0.0, 30.0))
		"respawn_now":
			if mine:
				p.respawn_now()
		"teleport":
			if mine and args.size() == 2 and args[0] is Vector3 and args[1] is Vector3:
				p.teleport(args[0], args[1])
		"personal":
			if mine and args.size() == 1 and args[0] is Dictionary:
				p.personal.set_all(args[0])


## Someone else's creature jumped, landed, fell... (from their phone, via the server).
@rpc("authority", "call_remote", "reliable")
func s_player_event(player_index: int, kind: int, value: Vector3) -> void:
	if _match == null or player_index < 0 or player_index >= _match.players.size():
		return
	var p := _match.players[player_index]
	if not p.is_simulated():
		p.net_emit(kind, value)


## The server didn't accept where our creature went: put it back.
@rpc("authority", "call_remote", "reliable")
func s_correct(pos: Vector3) -> void:
	var me := _local_player()
	if me and pos.is_finite():
		me.teleport(pos)
		corrected.emit(pos)


# ---------------------------------------------------------------- phone match hooks (MatchController)

func has_pending_client_match() -> bool:
	return not _pending_match.is_empty()


func attach_client_match(m: MatchController) -> void:
	m.net_role = MatchController.NetRole.CLIENT
	m.setup = _pending_match.setup
	m.local_player_index = int(_pending_match.index)
	_pending_match = {}
	_match = m


## The arena is loaded and the players exist: report events and say "ready".
func client_match_loaded(m: MatchController) -> void:
	if m != _match:
		return
	var me := _local_player()
	if me:
		me.jumped.connect(func() -> void: _send_event(PlayerCharacter.NET_JUMPED))
		me.landed.connect(func(impact: float) -> void:
			_send_event(PlayerCharacter.NET_LANDED, Vector3(0, impact, 0)))
		me.bounced.connect(func(s: float) -> void: _send_event(PlayerCharacter.NET_BOUNCED, Vector3(0, s, 0)))
		me.knocked.connect(func(dir: Vector3) -> void: _send_event(PlayerCharacter.NET_KNOCKED, dir))
		me.fell_out.connect(func() -> void: _send_event(PlayerCharacter.NET_FELL))
		me.respawned.connect(func() -> void: _send_event(PlayerCharacter.NET_RESPAWNED))
	if not _phase_info.is_empty():
		s_phase(int(_phase_info[0]), float(_phase_info[1]), bool(_phase_info[2]))
		_phase_info.clear()
	if status == Status.IN_ROOM:
		rpc_id(1, &"c_loaded")


func detach_client_match(m: MatchController) -> void:
	if m == _match:
		_match = null
		_snapshots.clear()


func _local_player() -> PlayerCharacter:
	if _match == null or _match.local_player_index < 0 or _match.local_player_index >= _match.players.size():
		return null
	return _match.players[_match.local_player_index]


func _send_event(kind: int, value: Vector3 = Vector3.ZERO) -> void:
	var me := _local_player()
	if me and status == Status.IN_ROOM:
		rpc_id(1, &"c_event", kind, value, me.global_position)


func client_send_interact() -> void:
	if status == Status.IN_ROOM:
		rpc_id(1, &"c_interact")


## The round clock on this phone: the server's clock, moving smoothly.
func client_round_clock(previous: float, delta: float) -> float:
	if not _have_clock_base:
		return previous
	var target := server_now() + _clock_base
	var expected := previous + delta
	var error := target - expected
	if absf(error) > 0.5:
		return target  # way off (just joined): jump
	# Nudge gently so obstacles never stutter.
	return expected + clampf(error, -delta * 0.5, delta * 0.5)


## Seconds left in the round on this phone.
func client_time_left(previous: float, delta: float) -> float:
	if _snapshots.is_empty():
		return maxf(0.0, previous - delta)
	var last: Dictionary = _snapshots[-1]
	var target := maxf(0.0, float(last.time_left) - (server_now() - float(last.t)))
	var expected := maxf(0.0, previous - delta)
	if absf(target - expected) > 1.0:
		return target
	return lerpf(expected, target, 0.1)


func _physics_process(delta: float) -> void:
	if is_server or _match == null or status != Status.IN_ROOM:
		return
	_place_puppets()
	_send_accum += delta
	var step := 1.0 / NetProtocol.SEND_RATE
	if _send_accum >= step:
		_send_accum = fmod(_send_accum, step)
		var me := _local_player()
		if me and _match.phase != MatchController.Phase.LOADING:
			_seq += 1
			rpc_id(1, &"c_state", _seq, NetProtocol.pack_player(me))


## Shows other creatures where the server saw them a moment ago, blending
## between the two snapshots around that time.
func _place_puppets() -> void:
	if _snapshots.size() == 0:
		return
	var render_t := server_now() - NetProtocol.INTERP_DELAY
	var a: Dictionary = _snapshots[0]
	var b: Dictionary = _snapshots[0]
	for i in _snapshots.size():
		if float(_snapshots[i].t) <= render_t:
			a = _snapshots[i]
			b = _snapshots[mini(i + 1, _snapshots.size() - 1)]
	var span := float(b.t) - float(a.t)
	var w := clampf((render_t - float(a.t)) / span, 0.0, 1.0) if span > 0.0001 else 1.0
	var sa: PackedFloat32Array = a.states
	var sb: PackedFloat32Array = b.states
	var n := NetProtocol.PLAYER_FLOATS
	for p in _match.players:
		if p.is_simulated():
			continue
		var o := p.player_index * n
		var flags_a := int(sa[o + 8])
		var flags_b := int(sb[o + 8])
		var pa := Vector3(sa[o], sa[o + 1], sa[o + 2])
		var pb := Vector3(sb[o], sb[o + 1], sb[o + 2])
		var jump := pa.distance_to(pb) > 4.0 or (flags_a & 2) != (flags_b & 2)
		var pos := pb if jump else pa.lerp(pb, w)
		var vel := Vector3(sb[o + 3], sb[o + 4], sb[o + 5])
		var yaw := lerp_angle(sa[o + 6], sb[o + 6], w)
		var size := lerpf(sa[o + 7], sb[o + 7], w)
		var teleported := pos.distance_to(p.global_position) > 4.0
		p.net_apply_state(pos, vel, yaw, size, flags_b)
		if teleported:
			p.reset_physics_interpolation()
		var away := (flags_b & 4) != 0
		if away != p.is_away():
			p.net_set_away(away)
