class_name CakeDashMode
extends GameMode
## Mode A: carry the giant birthday cake to the party table.
##
## Anyone can GRAB the cake. Teammates near the carrier can HELP: every helper
## makes the cake steadier and the carrier faster. Wobble too much (sharp
## turns, big landings, bonks, chaos!) and it tumbles: someone grabs it again
## ("Cake rescue!"). Each tumble blows out one candle. Falling into the goo
## sends the cake back to the last checkpoint. Delivering the cake wins the
## round for everyone; fewer drops and a faster time mean more points.

const GRAB_RADIUS := 2.3
const HELP_RADIUS := 3.0
const HELP_KEEP_RADIUS := 3.8
const MAX_HELPERS := 3

var cake: GiantCake
var finish_zone: FinishZone
var table_spot: Marker3D
var checkpoints: Array[Checkpoint] = []
var delivered := false
var cake_checkpoint_pos: Vector3
var start_z := 0.0
var finish_z := -100.0

var _path: Array[Node3D] = []
var _cake_free_since := 0.0
var _help_accum: Dictionary = {}     # player index -> seconds since last teamwork tick
var _help_total: Dictionary = {}     # player index -> seconds, for the "Team carry!" popups
var _cake_checkpoints: Dictionary = {}
var _best_progress := 0.0
var _carry_source_on: Dictionary = {}  # player index -> true while carrying modifier set


func setup_mode(p_match: MatchController) -> void:
	super(p_match)
	for n in find_children("*", "GiantCake", true, false):
		cake = n as GiantCake
	for n in find_children("*", "FinishZone", true, false):
		finish_zone = n as FinishZone
	table_spot = find_child("TableSpot", true, false) as Marker3D
	for n in find_children("*", "Checkpoint", true, false):
		checkpoints.append(n as Checkpoint)
	checkpoints.sort_custom(func(a: Checkpoint, b: Checkpoint) -> bool: return a.index < b.index)
	for cp in checkpoints:
		cp.reached.connect(_on_checkpoint)
	for n in find_children("*", "StarPickup", true, false):
		(n as StarPickup).touched.connect(_on_star_touched)
	finish_zone.body_arrived.connect(_on_finish_body)
	cake.dropped.connect(_on_cake_dropped)
	cake.fell_in_goo.connect(_on_cake_goo)
	cake_checkpoint_pos = cake.global_position
	start_z = cake.global_position.z
	finish_z = finish_zone.global_position.z
	_path = get_bot_path()


func on_players_spawned(p_players: Array[PlayerCharacter]) -> void:
	super(p_players)
	for p in players:
		p.landed.connect(_on_player_landed.bind(p))
		p.knocked.connect(_on_player_knocked.bind(p))
		p.fell_out.connect(_on_player_fell.bind(p))


func on_round_started() -> void:
	super()
	_cake_free_since = MatchClock.now(self)


# ---------------------------------------------------------------- every tick

func mode_physics_process(delta: float) -> void:
	if delivered:
		return
	if cake.state != GiantCake.State.CARRIED and cake.global_position.y < kill_height:
		_on_cake_goo()
		return
	if cake.state == GiantCake.State.CARRIED:
		_update_carry(delta)
	else:
		_clear_carry_modifiers()
	objective_changed.emit()


func _update_carry(delta: float) -> void:
	var carrier := cake.carrier
	if carrier == null or carrier.is_respawning:
		cake.release(true, MatchClock.now(self))
		return
	# Helpers who wandered off let go automatically.
	for h in cake.helpers.duplicate():
		if h.is_respawning or h.global_position.distance_to(carrier.global_position) > HELP_KEEP_RADIUS:
			cake.remove_helper(h)
	var n := cake.helpers.size()
	var sensitivity := carrier.stat(&"cake_wobble") * pow(0.62, n)
	if cake.update_carried(delta, sensitivity, 1.6 * n):
		cake.release(true, MatchClock.now(self))
		return
	# Heavy cake: slower alone, back to full speed with friends.
	var heavy := 0.76 if (match_node.setup.team_carry and players.size() > 1) else 0.92
	carrier.personal.set_source(&"carry", {&"speed": minf(1.0, heavy + 0.09 * n), &"jump": 0.85})
	_carry_source_on[carrier.player_index] = true
	for p in players:
		if p != carrier and _carry_source_on.has(p.player_index):
			p.personal.remove_source(&"carry")
			_carry_source_on.erase(p.player_index)
	stat(carrier, &"carry_time", delta)
	# Teamwork points while carrying together.
	for h in cake.helpers:
		stat(h, &"help_time", delta)
		var acc: float = _help_accum.get(h.player_index, 0.0) + delta
		if acc >= 1.0:
			acc -= 1.0
			var total: float = _help_total.get(h.player_index, 0.0) + 1.0
			_help_total[h.player_index] = total
			var show := int(total) % 3 == 0
			award(h, ScoreKeeper.TEAMWORK, 10, "Team carry!" if show else "", h.global_position + Vector3(0, 2.4, 0) if show else Vector3.INF)
			award(carrier, ScoreKeeper.TEAMWORK, 4, "", Vector3.INF)
		_help_accum[h.player_index] = acc
	_best_progress = maxf(_best_progress, progress())
	# Walking into the party area with the cake delivers it.
	if finish_zone.overlaps_body(carrier):
		_deliver()


func _clear_carry_modifiers() -> void:
	for idx in _carry_source_on.keys():
		for p in players:
			if p.player_index == idx:
				p.personal.remove_source(&"carry")
	_carry_source_on.clear()


## 0 at the start, 1 at the party table.
func progress() -> float:
	var z := cake.global_position.z
	if cake.state == GiantCake.State.CARRIED and cake.carrier:
		z = cake.carrier.global_position.z
	return clampf((start_z - z) / maxf(start_z - finish_z, 1.0), 0.0, 1.0)


# ---------------------------------------------------------------- interacting

func get_interact_prompt(p: PlayerCharacter) -> String:
	if delivered or p.is_respawning:
		return ""
	match cake.state:
		GiantCake.State.LOOSE:
			if _can_grab(p):
				return "GRAB"
		GiantCake.State.CARRIED:
			if cake.carrier == p:
				return "PUT DOWN"
			if cake.helpers.has(p):
				return "LET GO"
			if p.global_position.distance_to(cake.carrier.global_position) <= HELP_RADIUS:
				if not p.is_cpu and cake.carrier.is_cpu:
					return "TAKE"
				if cake.helpers.size() < MAX_HELPERS:
					return "HELP"
	return ""


func get_interact_icon(p: PlayerCharacter) -> StringName:
	match get_interact_prompt(p):
		"GRAB", "TAKE":
			return &"cake"
		"PUT DOWN":
			return &"down"
		"LET GO":
			return &"cross"
	return &"hand"


func handle_interact(p: PlayerCharacter) -> void:
	match get_interact_prompt(p):
		"GRAB":
			_grab(p)
		"PUT DOWN":
			cake.release(false, MatchClock.now(self))
			_clear_carry_modifiers()
			_cake_free_since = MatchClock.now(self)
			sfx(&"put_down")
		"LET GO":
			cake.remove_helper(p)
		"TAKE":
			var old := cake.carrier
			old.personal.remove_source(&"carry")
			_carry_source_on.erase(old.player_index)
			old.visual.set_carrying(false)
			old.visual.set_struggling(false)
			cake.pick_up(p)
			cake.add_helper(old)
			sfx(&"cake_grab")
		"HELP":
			cake.add_helper(p)
			p.react(&"happy")
			sfx(&"helper")


func _can_grab(p: PlayerCharacter) -> bool:
	var d := cake.global_position - p.global_position
	return Vector2(d.x, d.z).length() <= GRAB_RADIUS and absf(d.y) < 2.2


func _grab(p: PlayerCharacter) -> void:
	var dropped_by := cake.last_carrier_index
	var since_drop := MatchClock.now(self) - cake.last_drop_time
	cake.pick_up(p)
	sfx(&"cake_grab")
	p.react(&"happy")
	if since_drop < 12.0:
		if dropped_by == p.player_index:
			award(p, ScoreKeeper.RECOVERY, 60, "Nice recovery!")
			stat(p, &"recoveries")
		else:
			award(p, ScoreKeeper.TEAMWORK, 75, "Cake rescue!")
			stat(p, &"rescues")
		cake.last_drop_time = -100.0


# ---------------------------------------------------------------- events

func _on_player_landed(impact: float, p: PlayerCharacter) -> void:
	if not is_authority() or cake.state != GiantCake.State.CARRIED or cake.carrier != p or impact < 5.5:
		return
	var steady := pow(0.62, cake.helpers.size())
	cake.jolt(Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)), (impact - 4.0) * 0.16 * steady * p.stat(&"cake_wobble"))


func _on_player_knocked(direction: Vector3, p: PlayerCharacter) -> void:
	if not is_authority():
		return
	if cake.state == GiantCake.State.CARRIED and cake.carrier == p:
		cake.jolt(direction, 2.4 * pow(0.62, cake.helpers.size()))
	elif cake.helpers.has(p):
		cake.remove_helper(p)


func _on_player_fell(p: PlayerCharacter) -> void:
	reset_bot_path(p)
	if not is_authority():
		return
	if cake.state == GiantCake.State.CARRIED and cake.carrier == p:
		cake.release(true, MatchClock.now(self))
	elif cake.helpers.has(p):
		cake.remove_helper(p)


## Online: whoever drops out of the room lets go of the cake.
func on_player_away(p: PlayerCharacter) -> void:
	_on_player_fell(p)


func _on_cake_dropped(by: PlayerCharacter) -> void:
	if not is_authority():
		return
	_clear_carry_modifiers()
	_cake_free_since = MatchClock.now(self)
	sfx(&"cake_drop")
	if by:
		by.react(&"oops")
	match_node.fx.puff(cake.global_position + Vector3(0, 1.4, 0), Color("ffb13b"))
	message("Whoops! The cake tumbled! Grab it!", Color("ffd23f"))
	shake(0.3)


func _on_cake_goo() -> void:
	if delivered or not is_authority():
		return
	if cake.state == GiantCake.State.CARRIED:
		cake.release(true, MatchClock.now(self))
	cake.lose_candle()
	match_node.fx.puff(cake.global_position, Color("ff9ccf"), 1.5)
	cake.reset_cake(cake_checkpoint_pos + Vector3(0, 0.3, 0))
	_cake_free_since = MatchClock.now(self)
	sfx(&"splat")
	message("SPLAT! The cake is back at the checkpoint.", Color("ff9ccf"))


func _on_checkpoint(p: PlayerCharacter, cp: Checkpoint) -> void:
	if not is_authority():
		if p.is_simulated():
			p.respawn_position = cp.get_respawn_point(p.player_index)
		return
	p.respawn_position = cp.get_respawn_point(p.player_index)
	sfx(&"checkpoint")
	var carrying := cake.state == GiantCake.State.CARRIED and (cake.carrier == p)
	if carrying and not _cake_checkpoints.has(cp.index):
		_cake_checkpoints[cp.index] = true
		cake_checkpoint_pos = cp.global_transform * Vector3(0, 0, -2.6)
		award(p, ScoreKeeper.OBJECTIVE, 100, "Checkpoint!")
		for h in cake.helpers:
			award(h, ScoreKeeper.TEAMWORK, 50, "Helper!")
		message("Checkpoint! The cake is safe here.", Color("7dffb0"), 1.6)


func _on_star_touched(p: PlayerCharacter, star: StarPickup) -> void:
	if not is_playing() or not is_authority():
		return
	collect_star(p, star)


func _on_finish_body(body: Node3D) -> void:
	if delivered or not is_playing() or not is_authority():
		return
	if body == cake or (cake.state == GiantCake.State.CARRIED and body == cake.carrier):
		_deliver()


func _deliver() -> void:
	if delivered:
		return
	delivered = true
	var carrier := cake.carrier
	var helper_list := cake.helpers.duplicate()
	_clear_carry_modifiers()
	cake.deliver_to(table_spot.global_position if table_spot else finish_zone.global_position)
	finish_zone.celebrate()
	net_event(&"delivered")
	match_node.fx.confetti(finish_zone.global_position + Vector3(0, 2, 0))
	sfx(&"delivery")
	award_everyone(ScoreKeeper.OBJECTIVE, 400, "Cake delivered!")
	if carrier:
		award(carrier, ScoreKeeper.OBJECTIVE, 150, "Delivery!")
	for h in helper_list:
		award(h, ScoreKeeper.TEAMWORK, 75, "Helper!")
	if cake.candles > 0:
		award_everyone(ScoreKeeper.OBJECTIVE, 50 * cake.candles, "%d candles!" % cake.candles)
	var secs := int(time_left())
	if secs > 0:
		award_everyone(ScoreKeeper.TIME, secs * 4, "Speedy!")
	_best_progress = 1.0
	message("PARTY TIME! The cake made it!", Color("7dffb0"), 3.0)
	finish(true)


func on_time_up() -> void:
	if delivered:
		return
	if cake.state == GiantCake.State.CARRIED:
		cake.release(false, MatchClock.now(self))
	_clear_carry_modifiers()
	var pts := int(300.0 * _best_progress)
	if pts > 0:
		award_everyone(ScoreKeeper.OBJECTIVE, pts, "So close!")


func on_round_ended(p_success: bool) -> void:
	super(p_success)
	_clear_carry_modifiers()


# ---------------------------------------------------------------- online

func get_net_state() -> Dictionary:
	var cps := PackedInt32Array()
	for i: int in _cake_checkpoints:
		cps.append(i)
	return {"cake": cake.get_net_state(), "dl": delivered, "bp": _best_progress, "cc": cps,
			"st": stars_net_state()}


func apply_net_state(state: Dictionary) -> void:
	if typeof(state.get("cake")) == TYPE_DICTIONARY:
		cake.apply_net_state(state.cake, players)
	delivered = bool(state.get("dl", delivered))
	_best_progress = clampf(float(state.get("bp", _best_progress)), 0.0, 1.0)
	apply_stars_net_state(state.get("st"))


func apply_net_event(event_name: StringName, args: Array) -> void:
	if _apply_common_event(event_name, args):
		return
	if event_name == &"delivered":
		finish_zone.celebrate()


func mode_client_process(delta: float) -> void:
	cake.net_process(delta)
	objective_changed.emit()


# ---------------------------------------------------------------- HUD & results

func get_objective_text() -> String:
	if delivered:
		return "PARTY TIME!"
	if cake.state == GiantCake.State.CARRIED:
		return "Carry the cake to the party table!"
	return "Grab the cake!"


func create_objective_widget() -> Control:
	var w := CakeMeter.new()
	w.mode = self
	return w


func get_result_text(p_success: bool) -> Dictionary:
	if p_success:
		return {"headline": "PARTY TIME!",
				"subline": "The cake made it with %d candle%s still lit!" % [cake.candles, "" if cake.candles == 1 else "s"]}
	return {"headline": "Uh-oh, no cake yet!",
			"subline": "The guests ate sandwiches instead. You got %d%% of the way. Try again!" % int(_best_progress * 100.0)}


func get_award_candidates() -> Array[Dictionary]:
	return [
		{"stat": &"carry_time", "title": "Cake Captain", "text": "Carried the cake the longest"},
		{"stat": &"help_time", "title": "Helping Hands", "text": "Helped carry the cake the most"},
		{"stat": &"rescues", "title": "Cake Rescuer", "text": "Saved the cake after a tumble"},
	]


func get_progress_stats(p_success: bool) -> Dictionary:
	var out := {"cakes_delivered": 1 if p_success else 0}
	if p_success:
		out["best_time"] = match_node.elapsed
	return out


# ---------------------------------------------------------------- CPU buddies

func get_camera_targets() -> Array[Dictionary]:
	var out := super()
	out.append({"node": cake, "priority": PartyCamera.Priority.SHOULD, "height": 2.0})
	return out


func get_bot_goal(p: PlayerCharacter) -> Dictionary:
	if delivered or p.is_respawning:
		return {"wait": true}
	if cake.state == GiantCake.State.CARRIED:
		var carrier := cake.carrier
		if carrier == p:
			var g := path_goal(p, _path)
			g["careful"] = true
			return g
		var side := _helper_offset(p, carrier)
		var target := carrier.global_position + side + carrier.velocity * 0.25
		if not cake.helpers.has(p) and cake.helpers.size() < MAX_HELPERS \
				and p.global_position.distance_to(carrier.global_position) < HELP_RADIUS - 0.5:
			return {"position": target, "stop_distance": 0.6, "interact": true, "interact_distance": 3.0}
		return {"position": target, "stop_distance": 0.6}
	# Loose cake: one bot fetches it (after giving humans a head start).
	var free_for := MatchClock.now(self) - _cake_free_since
	var human_close := false
	for h in human_players():
		if h.global_position.distance_to(cake.global_position) < 7.0 and not h.is_respawning:
			human_close = true
	if p == _nearest_bot_to_cake() and (not human_close or free_for > 3.0):
		return {"position": cake.global_position, "stop_distance": 0.9, "interact": true,
				"interact_distance": GRAB_RADIUS - 0.4}
	var ring := Vector3(cos(p.player_index * 1.7), 0, sin(p.player_index * 1.7)) * 2.8
	return {"position": cake.global_position + ring, "stop_distance": 0.8}


func _helper_offset(p: PlayerCharacter, carrier: PlayerCharacter) -> Vector3:
	var fwd := carrier.facing
	var right := fwd.cross(Vector3.UP).normalized()
	var slots: Array[Vector3] = [right * 1.6, -right * 1.6, -fwd * 1.8]
	var i := 0
	for other in players:
		if other == p:
			break
		if other != carrier and not other.is_human:
			i += 1
	return slots[i % slots.size()]


func _nearest_bot_to_cake() -> PlayerCharacter:
	var best: PlayerCharacter = null
	var best_d := INF
	for p in players:
		if p.is_human or p.is_respawning:
			continue
		var d := p.global_position.distance_to(cake.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best
