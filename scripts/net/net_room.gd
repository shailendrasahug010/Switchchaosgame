class_name NetRoom
extends Node
## One private room on the online room server (see Net and
## docs/ONLINE_MULTIPLAYER_PLAN.md).
##
## A room has up to four seats. The first player is the host: they pick the
## game and start rounds. A round runs the normal MatchController in its
## SERVER role inside a SubViewport with its own physics world, so many rooms
## can play at once in one server program without touching each other.
##
## The server is the referee: it runs the rules, the timer and the Chaos
## Switch. Phones send where their creature is; every update is checked
## (speed, bounds, respawn spots) before it can move the server's copy, and
## points only ever come from the rules running here.

enum State { LOBBY, LOADING, PLAYING }

const MATCH_SCENE := preload("res://scenes/match/match.tscn")


class Seat:
	extends RefCounted
	## Network peer id, 0 while disconnected.
	var peer: int = 0
	## Secret for taking the seat back after a dropped connection.
	var token: String = ""
	var look: Dictionary = {}
	## When the connection dropped (-1 = connected).
	var away_since: float = -1.0
	## Left on purpose (only kept until the round ends).
	var gone: bool = false
	var loaded: bool = false
	# Movement checks
	var last_seq: int = -1
	var last_time: float = 0.0
	var last_pos: Vector3 = Vector3.ZERO
	var have_pos: bool = false
	var strikes: int = 0
	var last_correction: float = -10.0
	# Rate limits
	var interact_times: Array[float] = []
	var event_times: Array[float] = []


var net: Node
var code: String = ""
var seats: Array = [null, null, null, null]
var host_seat: int = 0
var mode_id: String = "bounce_race"
var fill_cpus: bool = true
var state: State = State.LOBBY
var match_ctl: MatchController = null
var viewport: SubViewport = null
var created_at: float = 0.0
var last_activity: float = 0.0
var empty_since: float = -1.0
var rounds_played: int = 0
## Tests: shorter rounds (0 = the mode's own length).
var round_time_override: float = 0.0
## Match player index -> seat (-1 for CPU buddies), for the current round.
var _seat_of_player: Array[int] = []
var _load_started: float = 0.0
var _send_accum: float = 0.0
var _mode_accum: float = 0.0
var _old_viewports: Array[Dictionary] = []


func _init(p_net: Node, p_code: String) -> void:
	net = p_net
	code = p_code
	name = "Room_" + p_code
	created_at = NetProtocol.now()
	last_activity = created_at


# ---------------------------------------------------------------- seats

func seat_count() -> int:
	var n := 0
	for s in seats:
		if s != null:
			n += 1
	return n


func connected_count() -> int:
	var n := 0
	for s in seats:
		if s != null and (s as Seat).peer != 0:
			n += 1
	return n


func is_full() -> bool:
	return seat_count() >= NetProtocol.MAX_SEATS


func seat_of_peer(peer: int) -> int:
	for i in seats.size():
		if seats[i] != null and (seats[i] as Seat).peer == peer:
			return i
	return -1


## Adds [param peer] to the first free seat. Returns the seat or -1.
func add_member(peer: int, look: Dictionary) -> int:
	for i in seats.size():
		if seats[i] == null:
			var s := Seat.new()
			s.peer = peer
			s.token = NetProtocol.make_token()
			s.look = look
			seats[i] = s
			if seat_count() == 1 or seats[host_seat] == null:
				host_seat = i
			last_activity = NetProtocol.now()
			empty_since = -1.0
			return i
	return -1


## Gives a seat back to a phone that knows its secret. Returns the seat or -1.
func rejoin(peer: int, token: String) -> int:
	for i in seats.size():
		var s: Seat = seats[i]
		if s != null and not s.gone and s.token == token:
			s.peer = peer
			s.away_since = -1.0
			s.loaded = false
			s.have_pos = false
			s.last_seq = -1
			empty_since = -1.0
			last_activity = NetProtocol.now()
			var p := _player_for_seat(i)
			if p:
				p.net_set_away(false)
				_broadcast_message("%s is back!" % p.display_name, Color("7dffb0"))
			return i
	return -1


## The connection dropped: keep the seat for a while.
func member_disconnected(peer: int) -> void:
	var i := seat_of_peer(peer)
	if i < 0:
		return
	var s: Seat = seats[i]
	s.peer = 0
	s.away_since = NetProtocol.now()
	var p := _player_for_seat(i)
	if p:
		p.net_set_away(true)
		if match_ctl and match_ctl.mode:
			match_ctl.mode.on_player_away(p)
		_broadcast_message("%s lost the connection..." % p.display_name, Color("ffd23f"))
	_pass_host_if_needed()
	broadcast_room()


## Left on purpose.
func member_left(peer: int) -> void:
	var i := seat_of_peer(peer)
	if i < 0:
		return
	var p := _player_for_seat(i)
	if p and state != State.LOBBY:
		# Keep the creature until the round ends, as an empty seat.
		var s: Seat = seats[i]
		s.peer = 0
		s.gone = true
		s.away_since = NetProtocol.now()
		p.net_set_away(true)
		if match_ctl and match_ctl.mode:
			match_ctl.mode.on_player_away(p)
		_broadcast_message("%s left the room." % p.display_name, Color("ffd23f"))
	else:
		seats[i] = null
	_pass_host_if_needed()
	broadcast_room()


func _pass_host_if_needed() -> void:
	var host: Seat = seats[host_seat]
	if host != null and host.peer != 0:
		return
	for i in seats.size():
		if seats[i] != null and (seats[i] as Seat).peer != 0:
			host_seat = i
			return


func is_host(peer: int) -> bool:
	return seat_of_peer(peer) == host_seat


# ---------------------------------------------------------------- lobby

## What one phone shows on the room screen.
func info_for(seat_index: int) -> Dictionary:
	var list := []
	var order := 0
	for i in seats.size():
		var s: Seat = seats[i]
		if s == null or s.gone:
			continue
		list.append({
			"label": "P%d" % (order + 1), "color": order, "look": s.look,
			"connected": s.peer != 0, "host": i == host_seat, "you": i == seat_index,
		})
		order += 1
	return {
		"code": code, "players": list, "mode": mode_id, "cpus": fill_cpus,
		"state": ["lobby", "loading", "playing"][state], "host": seat_index == host_seat,
	}


func broadcast_room() -> void:
	for i in seats.size():
		var s: Seat = seats[i]
		if s != null and s.peer != 0:
			net.send(s.peer, &"s_room", [info_for(i)])


func set_options(p_mode: String, p_cpus: bool) -> void:
	if NetProtocol.is_online_mode(p_mode):
		mode_id = p_mode
	fill_cpus = p_cpus
	last_activity = NetProtocol.now()
	broadcast_room()


func set_look(peer: int, look: Dictionary) -> void:
	var i := seat_of_peer(peer)
	if i >= 0 and state == State.LOBBY:
		(seats[i] as Seat).look = look
		broadcast_room()


# ---------------------------------------------------------------- rounds

func can_start() -> bool:
	return state == State.LOBBY and connected_count() >= 1


## Builds the round and asks every phone to load the arena.
func start_round() -> bool:
	if not can_start():
		return false
	# Seats of people who left for good are freed now.
	for i in seats.size():
		var s: Seat = seats[i]
		if s != null and (s.gone or (s.peer == 0 and NetProtocol.now() - s.away_since > NetProtocol.RECONNECT_GRACE)):
			seats[i] = null
	_free_match(true)
	var setup := MatchSetup.new()
	setup.mode_id = StringName(mode_id)
	setup.online = true
	setup.no_progress = true
	setup.seed = (randi() % 2000000000) + 1
	setup.round_time = round_time_override
	_seat_of_player.clear()
	var used: Array[StringName] = []
	for i in seats.size():
		var s: Seat = seats[i]
		if s == null:
			continue
		var slot := MatchSetup.Slot.new()
		slot.kind = MatchSetup.Kind.REMOTE
		slot.character_id = StringName(s.look.character)
		slot.hat_id = StringName(s.look.hat)
		slot.paint_id = StringName(s.look.paint)
		setup.slots.append(slot)
		_seat_of_player.append(i)
		used.append(slot.character_id)
		s.loaded = false
		s.have_pos = false
		s.last_seq = -1
		s.strikes = 0
	if fill_cpus:
		while setup.slots.size() < NetProtocol.MAX_SEATS:
			var slot := MatchSetup.Slot.new()
			slot.kind = MatchSetup.Kind.CPU
			slot.character_id = MatchSetup._next_free_character(used)
			used.append(slot.character_id)
			setup.slots.append(slot)
			_seat_of_player.append(-1)
	viewport = SubViewport.new()
	viewport.name = "Round%d" % (rounds_played + 1)
	viewport.own_world_3d = true
	viewport.size = Vector2i(2, 2)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.audio_listener_enable_3d = false
	add_child(viewport)
	match_ctl = MATCH_SCENE.instantiate() as MatchController
	match_ctl.net_role = MatchController.NetRole.SERVER
	match_ctl.net_room = self
	match_ctl.setup = setup
	viewport.add_child(match_ctl)
	state = State.LOADING
	_load_started = NetProtocol.now()
	_send_accum = 0.0
	_mode_accum = 0.0
	rounds_played += 1
	last_activity = _load_started
	var setup_info := _setup_info(setup)
	for pi in _seat_of_player.size():
		var si := _seat_of_player[pi]
		if si >= 0 and seats[si] != null and (seats[si] as Seat).peer != 0:
			net.send((seats[si] as Seat).peer, &"s_match_start", [setup_info, pi])
	broadcast_room()
	net.log_line("room %s: round %d (%s, %d players)" % [code, rounds_played, mode_id, setup.slots.size()])
	return true


func _setup_info(setup: MatchSetup) -> Dictionary:
	var slots := []
	for s in setup.slots:
		slots.append({"cpu": s.kind == MatchSetup.Kind.CPU,
				"look": {"character": String(s.character_id), "hat": String(s.hat_id), "paint": String(s.paint_id)}})
	return {"mode": String(setup.mode_id), "seed": setup.seed, "time": setup.round_time,
			"chaos": setup.chaos_enabled, "team_carry": setup.team_carry, "slots": slots}


## Asks a phone that (re)joined during a round to load it.
func send_match_start(seat_index: int) -> void:
	if match_ctl == null or state == State.LOBBY:
		return
	var pi := _seat_of_player.find(seat_index)
	var s: Seat = seats[seat_index]
	if pi < 0 or s == null or s.peer == 0:
		return
	s.loaded = false
	net.send(s.peer, &"s_match_start", [_setup_info(match_ctl.setup), pi])


## True when [param seat_index] has a creature in the current round.
func in_round(seat_index: int) -> bool:
	return match_ctl != null and state != State.LOBBY and _seat_of_player.has(seat_index)


## A phone finished loading the arena.
func member_loaded(peer: int) -> void:
	var i := seat_of_peer(peer)
	if i < 0 or match_ctl == null:
		return
	var s: Seat = seats[i]
	s.loaded = true
	if state == State.PLAYING:
		_send_catchup(i)


## Everything a phone that loads late (or comes back) needs to join in.
func _send_catchup(seat_index: int) -> void:
	var s: Seat = seats[seat_index]
	var p := _player_for_seat(seat_index)
	if s == null or s.peer == 0 or p == null:
		return
	var m := match_ctl
	var active := []
	for entry in m.chaos.get_active_entries():
		active.append([String((entry.event as ChaosEvent).id), float(entry.left)])
	var pending := []
	if m.chaos.get_pending_event():
		pending = [String(m.chaos.get_pending_event().id), m.chaos.get_pending_time_left()]
	var data := {
		"phase": int(m.phase), "started": m._phase_started_at, "success": m.success,
		"clock": m.clock, "server_time": NetProtocol.now(), "time_left": m.time_left,
		"scores": m.score.export_data(), "chaos_active": active, "chaos_pending": pending,
		"mode": m.mode.get_net_state(),
		"you": {"pos": p.global_position, "respawn": p.respawn_position, "controls": p.controls_enabled,
				"personal": p.personal.to_dict(), "respawning": p.is_respawning},
	}
	s.last_pos = p.global_position
	s.have_pos = true
	s.last_time = NetProtocol.now()
	net.send(s.peer, &"s_catchup", [data])


func _all_loaded() -> bool:
	for si in _seat_of_player:
		if si < 0:
			continue
		var s: Seat = seats[si]
		if s != null and s.peer != 0 and not s.loaded:
			return false
	return true


func _player_for_seat(seat_index: int) -> PlayerCharacter:
	if match_ctl == null or not is_instance_valid(match_ctl):
		return null
	var pi := _seat_of_player.find(seat_index)
	if pi < 0 or pi >= match_ctl.players.size():
		return null
	return match_ctl.players[pi]


func _seat_for_player(player_index: int) -> int:
	if player_index < 0 or player_index >= _seat_of_player.size():
		return -1
	return _seat_of_player[player_index]


func _free_match(now: bool = false) -> void:
	if viewport:
		if now:
			viewport.queue_free()
		else:
			# Let the last messages go out first.
			_old_viewports.append({"vp": viewport, "at": NetProtocol.now() + 3.0})
	viewport = null
	match_ctl = null


# ---------------------------------------------------------------- every tick

func _physics_process(delta: float) -> void:
	var now := NetProtocol.now()
	for i in range(_old_viewports.size() - 1, -1, -1):
		if now >= float(_old_viewports[i].at):
			(_old_viewports[i].vp as Node).queue_free()
			_old_viewports.remove_at(i)
	match state:
		State.LOADING:
			if match_ctl and (_all_loaded() or now - _load_started > NetProtocol.LOAD_TIMEOUT):
				# Late loaders get the whole picture when they arrive (member_loaded).
				state = State.PLAYING
				match_ctl.begin()
				broadcast_room()
		State.PLAYING:
			_send_accum += delta
			var step := 1.0 / NetProtocol.SEND_RATE
			if _send_accum >= step:
				_send_accum = fmod(_send_accum, step)
				_mode_accum += step
				var with_mode := _mode_accum >= 1.0 / NetProtocol.MODE_STATE_RATE - 0.001
				if with_mode:
					_mode_accum = 0.0
				_send_snapshots(with_mode)


func _send_snapshots(with_mode: bool) -> void:
	if match_ctl == null:
		return
	var states := PackedFloat32Array()
	for p in match_ctl.players:
		var packed := NetProtocol.pack_player(p)
		var si := _seat_for_player(p.player_index)
		if si >= 0 and seats[si] != null and (seats[si] as Seat).peer == 0:
			packed[8] = float(int(packed[8]) | 4)  # away
		states.append_array(packed)
	var mode_state: Dictionary = match_ctl.mode.get_net_state() if with_mode else {}
	var now := NetProtocol.now()
	for s in seats:
		if s != null and (s as Seat).peer != 0 and (s as Seat).loaded:
			net.send((s as Seat).peer, &"s_snapshot", [now, match_ctl.clock, match_ctl.time_left, states, mode_state])


## Housekeeping (once a second, from Net). Returns false when the room should close.
func check_timeouts(now: float) -> bool:
	if connected_count() == 0:
		if empty_since < 0.0:
			empty_since = now
		if now - empty_since > NetProtocol.EMPTY_ROOM_TIMEOUT or seat_count() == 0:
			return false
	else:
		empty_since = -1.0
	if state == State.LOBBY:
		if now - last_activity > NetProtocol.IDLE_ROOM_TIMEOUT:
			return false
		var changed := false
		for i in seats.size():
			var s: Seat = seats[i]
			if s != null and s.peer == 0 and (s.gone or now - s.away_since > NetProtocol.RECONNECT_GRACE):
				seats[i] = null
				changed = true
		if changed:
			_pass_host_if_needed()
			broadcast_room()
	return seat_count() > 0


func close() -> void:
	for s in seats:
		if s != null and (s as Seat).peer != 0:
			net.send((s as Seat).peer, &"s_error", ["rejoin_failed"])
	_free_match(true)
	for d in _old_viewports:
		(d.vp as Node).queue_free()
	_old_viewports.clear()
	queue_free()


# ---------------------------------------------------------------- phones -> server (checked)

## A phone's update for its creature: [x y z vx vy vz yaw size flags].
func on_state(peer: int, seq: int, data: PackedFloat32Array) -> void:
	var si := seat_of_peer(peer)
	var p := _player_for_seat(si)
	if p == null or state != State.PLAYING:
		return
	var s: Seat = seats[si]
	if seq <= s.last_seq:
		return  # old or repeated packet
	s.last_seq = seq
	if data.size() != NetProtocol.PLAYER_FLOATS or not NetProtocol.all_finite(data):
		return
	if p.is_respawning:
		return  # wait for the "respawned" event
	var pos := Vector3(data[0], data[1], data[2])
	var vel := Vector3(data[3], data[4], data[5]).limit_length(45.0)
	var now := NetProtocol.now()
	if not _in_bounds(pos):
		_correct(si, p, p.global_position)
		return
	if s.have_pos:
		var dt := clampf(now - s.last_time, 1.0 / 60.0, 0.6)
		var horizontal := Vector2(pos.x - s.last_pos.x, pos.z - s.last_pos.z).length()
		var vertical := absf(pos.y - s.last_pos.y)
		# Generous: bounce pads, bonks and moving platforms all add speed.
		var max_h := (p.max_speed * maxf(1.0, p.stat(&"speed")) * 1.6 + 14.0) * dt + 1.0
		var max_v := 40.0 * dt + 1.5
		if horizontal > max_h or vertical > max_v:
			s.strikes += 1
			_correct(si, p, s.last_pos)
			return
	p.net_apply_state(pos, vel, data[6], data[7], int(data[8]))
	s.last_pos = pos
	s.last_time = now
	s.have_pos = true


func _in_bounds(pos: Vector3) -> bool:
	var b: AABB = match_ctl.mode.camera_bounds
	if b.size == Vector3.ZERO:
		return pos.length() < 500.0
	var grown := b.grow(25.0)
	grown.position.y = minf(grown.position.y, match_ctl.mode.kill_height - 10.0)
	grown.end.y = maxf(grown.end.y, 60.0)
	return grown.has_point(pos)


## Sends the phone's creature back to a place the server accepts.
func _correct(seat_index: int, p: PlayerCharacter, to: Vector3) -> void:
	var s: Seat = seats[seat_index]
	var now := NetProtocol.now()
	if now - s.last_correction < 0.25:
		return
	s.last_correction = now
	s.last_pos = to
	s.last_time = now
	s.have_pos = true
	p.global_position = to
	net.send(s.peer, &"s_correct", [to])


## Something that happened to a phone's creature (jumped, fell, respawned...).
func on_event(peer: int, kind: int, value: Vector3, pos: Vector3) -> void:
	var si := seat_of_peer(peer)
	var p := _player_for_seat(si)
	if p == null or state != State.PLAYING or not value.is_finite() or not pos.is_finite():
		return
	var s: Seat = seats[si]
	if not _rate_ok(s.event_times, 30):
		return
	match kind:
		PlayerCharacter.NET_JUMPED:
			p.net_emit(kind)
		PlayerCharacter.NET_BOUNCED:
			p.net_emit(kind, Vector3(0, clampf(value.y, 0.0, 30.0), 0))
		PlayerCharacter.NET_LANDED:
			var impact := clampf(value.y, 0.0, 45.0)
			if s.have_pos and pos.distance_to(s.last_pos) < 3.0 and _in_bounds(pos):
				p.global_position = pos
			# A landing is a moment of falling speed (stomping buttons checks it).
			p.velocity.y = -impact
			p.net_emit(kind, Vector3(0, impact, 0))
		PlayerCharacter.NET_KNOCKED:
			var dir := Vector3(value.x, 0, value.z)
			p.net_emit(kind, dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD)
		PlayerCharacter.NET_FELL:
			p.net_emit(kind)
		PlayerCharacter.NET_RESPAWNED:
			var at := pos
			if at.distance_to(p.respawn_position) > 4.0:
				at = p.respawn_position
				net.send(s.peer, &"s_correct", [at])
			p.global_position = at
			p.velocity = Vector3.ZERO
			p.reset_physics_interpolation()
			s.last_pos = at
			s.last_time = NetProtocol.now()
			s.have_pos = true
			p.net_emit(kind)
		_:
			return
	# Everyone else's copy shows it too.
	for i in seats.size():
		if i != si and seats[i] != null and (seats[i] as Seat).peer != 0 and (seats[i] as Seat).loaded:
			net.send((seats[i] as Seat).peer, &"s_player_event", [p.player_index, kind, value])


## The phone pressed its action button: the server checks reach and does it.
func on_interact(peer: int) -> void:
	var si := seat_of_peer(peer)
	var p := _player_for_seat(si)
	if p == null or not match_ctl.is_playing() or p.is_respawning or not p.controls_enabled:
		return
	if not _rate_ok((seats[si] as Seat).interact_times, 8):
		return
	match_ctl.mode.handle_interact(p)


## At most [param per_second] calls in the last second.
func _rate_ok(times: Array[float], per_second: int) -> bool:
	var now := NetProtocol.now()
	while not times.is_empty() and now - times[0] > 1.0:
		times.remove_at(0)
	if times.size() >= per_second:
		return false
	times.append(now)
	return true


# ---------------------------------------------------------------- server -> phones (called by the match)

const _OWNER_COMMANDS: Array[StringName] = [&"controls", &"respawn_point", &"knock", &"launch",
		&"respawn_now", &"teleport", &"personal"]


func player_command(player: PlayerCharacter, command: StringName, args: Array, m: MatchController) -> void:
	if m != match_ctl:
		return
	var idx := player.player_index
	if _OWNER_COMMANDS.has(command):
		var si := _seat_for_player(idx)
		if si < 0 or seats[si] == null or (seats[si] as Seat).peer == 0:
			return
		var s: Seat = seats[si]
		if command == &"teleport" and args.size() > 0 and args[0] is Vector3:
			s.last_pos = args[0]
			s.last_time = NetProtocol.now()
		if s.loaded:
			net.send(s.peer, &"s_player_cmd", [idx, String(command), args])
	else:
		_broadcast(&"s_player_cmd", [idx, String(command), args])


func match_chaos(m: MatchController, id: StringName, phase: String, value: float) -> void:
	if m == match_ctl:
		_broadcast(&"s_chaos", [String(id), phase, value])


func match_phase(m: MatchController, phase: int, clock: float, success: bool) -> void:
	if m != match_ctl:
		return
	_broadcast(&"s_phase", [phase, clock, success])
	if phase == MatchController.Phase.RESULTS:
		# The phones show the results; the room is ready for the next round.
		state = State.LOBBY
		last_activity = NetProtocol.now()
		_free_match(false)
		broadcast_room()


func match_scored(m: MatchController, player_index: int, category: StringName, points: int, reason: String,
		world_pos: Vector3) -> void:
	if m == match_ctl:
		_broadcast(&"s_scored", [player_index, String(category), points, reason, world_pos])


func match_message(m: MatchController, text: String, color: Color, seconds: float) -> void:
	if m == match_ctl:
		_broadcast(&"s_message", [text, color, seconds])


func match_fx(m: MatchController, kind: StringName, args: Array) -> void:
	if m == match_ctl:
		_broadcast(&"s_fx", [String(kind), args])


func match_mode_event(m: MatchController, event_name: StringName, args: Array) -> void:
	if m == match_ctl:
		_broadcast(&"s_mode_event", [String(event_name), args])


func match_results(m: MatchController, result: Dictionary) -> void:
	if m != match_ctl:
		return
	_broadcast(&"s_results", [m.score.export_data(), result.get("awards", [])])
	var totals := []
	for p in m.players:
		totals.append(m.score.total(p.player_index))
	net.log_line("room %s: round %d over (%s) points %s" % [code, rounds_played,
			"success" if result.get("success", false) else "time up", str(totals)])


func _broadcast(method: StringName, args: Array) -> void:
	for s in seats:
		if s != null and (s as Seat).peer != 0 and (s as Seat).loaded:
			net.send((s as Seat).peer, method, args)


func _broadcast_message(text: String, color: Color) -> void:
	if match_ctl and state != State.LOBBY:
		match_ctl.show_message(text, color, 2.4)
