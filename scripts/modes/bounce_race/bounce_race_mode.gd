class_name BounceRaceMode
extends GameMode
## Mode C: race through a bouncy obstacle course. First to the finish wins!
##
## Trampolines, a spinning bar, sliding platforms, a bounce-pad climb and a
## bridge with swinging hammers. Falling into the goo just pops you back at
## your last checkpoint, so nobody spends the round waiting. Players pass
## through each other: you can only win by being fast, never by pushing.
##
## Points: finishing place, finishing at all, checkpoints, getting back on
## track after a fall, stars and finishing early. When the first racer
## finishes, everyone else gets a 20 second "hurry up" countdown.

const PLACE_POINTS: Array[int] = [300, 220, 170, 130]
const HURRY_TIME := 20.0
const ALL_PEOPLE_DONE_TIME := 6.0

var start_z := 6.0
var finish_z := -131.0
var finish_zone: FinishZone
var checkpoints: Array[Checkpoint] = []
## Player indices in the order they crossed the finish line.
var finish_order: Array[int] = []

var _path: Array[Node3D] = []
var _best_progress: Dictionary = {}       # player index -> 0..1
var _fell_since_checkpoint: Dictionary = {}
var _finish_times: Dictionary = {}        # player index -> seconds
var _hurry_started := false
var _end_queued_at := -1.0
var _pending_tip := ""
var _pending_tip_at := -1.0


func setup_mode(p_match: MatchController) -> void:
	super(p_match)
	for n in find_children("*", "FinishZone", true, false):
		finish_zone = n as FinishZone
	for n in find_children("*", "Checkpoint", true, false):
		checkpoints.append(n as Checkpoint)
	checkpoints.sort_custom(func(a: Checkpoint, b: Checkpoint) -> bool: return a.index < b.index)
	for cp in checkpoints:
		cp.reached.connect(_on_checkpoint)
	for n in find_children("*", "StarPickup", true, false):
		(n as StarPickup).touched.connect(_on_star_touched)
	finish_zone.body_arrived.connect(_on_finish_body)
	finish_z = finish_zone.global_position.z
	var start := find_child("StartLine", true, false) as Node3D
	if start:
		start_z = start.global_position.z
	_path = get_bot_path()
	p_match.chaos.event_started.connect(_on_chaos_started)


func on_players_spawned(p_players: Array[PlayerCharacter]) -> void:
	super(p_players)
	for p in players:
		_best_progress[p.player_index] = 0.0
		p.fell_out.connect(func() -> void:
			if is_authority():
				_fell_since_checkpoint[p.player_index] = true
			reset_bot_path(p))
		p.bounced.connect(func(_s: float) -> void: stat(p, &"bounces"))


# ---------------------------------------------------------------- progress

func progress_of(p: PlayerCharacter) -> float:
	if finish_order.has(p.player_index):
		return 1.0
	return clampf((start_z - p.global_position.z) / maxf(start_z - finish_z, 1.0), 0.0, 1.0)


func best_progress_of(p: PlayerCharacter) -> float:
	return float(_best_progress.get(p.player_index, 0.0))


func has_finished(p: PlayerCharacter) -> bool:
	return finish_order.has(p.player_index)


## 1-based race position right now (finished racers first, then by progress).
func place_of(p: PlayerCharacter) -> int:
	if has_finished(p):
		return finish_order.find(p.player_index) + 1
	var place := finish_order.size() + 1
	var mine := progress_of(p)
	for other in players:
		if other == p or has_finished(other):
			continue
		var theirs := progress_of(other)
		if theirs > mine or (is_equal_approx(theirs, mine) and other.player_index < p.player_index):
			place += 1
	return place


func mode_physics_process(_delta: float) -> void:
	for p in players:
		if not p.is_respawning:
			_best_progress[p.player_index] = maxf(best_progress_of(p), progress_of(p))
	if _pending_tip_at > 0.0 and MatchClock.now(self) >= _pending_tip_at:
		_pending_tip_at = -1.0
		message(_pending_tip, Color("fff3a3"), 2.4)
	if _end_queued_at > 0.0 and MatchClock.now(self) >= _end_queued_at:
		_end_queued_at = -1.0
		finish(_someone_who_counts_finished())


func _someone_who_counts_finished() -> bool:
	var humans := human_players()
	if humans.is_empty():
		return not finish_order.is_empty()
	for h in humans:
		if has_finished(h):
			return true
	return false


# ---------------------------------------------------------------- events

func _on_checkpoint(p: PlayerCharacter, cp: Checkpoint) -> void:
	if not is_authority():
		# Online phone: our own creature remembers the spot right away; the
		# server confirms it (and gives the points).
		if p.is_simulated():
			p.respawn_position = cp.get_respawn_point(p.player_index)
		return
	p.respawn_position = cp.get_respawn_point(p.player_index)
	sfx(&"checkpoint")
	award(p, ScoreKeeper.OBJECTIVE, 25, "Checkpoint!")
	stat(p, &"checkpoints")
	if _fell_since_checkpoint.get(p.player_index, false):
		_fell_since_checkpoint.erase(p.player_index)
		award(p, ScoreKeeper.RECOVERY, 30, "Back on track!")
		stat(p, &"recoveries")


func _on_star_touched(p: PlayerCharacter, star: StarPickup) -> void:
	if not is_playing() or not is_authority():
		return
	collect_star(p, star)


func _on_finish_body(body: Node3D) -> void:
	var p := body as PlayerCharacter
	if p == null or not is_playing() or has_finished(p) or p.is_respawning or not is_authority():
		return
	finish_order.append(p.player_index)
	_finish_times[p.player_index] = match_node.elapsed
	var place := finish_order.size()
	_best_progress[p.player_index] = 1.0
	award(p, ScoreKeeper.OBJECTIVE, 100, "Finished!")
	award(p, ScoreKeeper.OBJECTIVE, PLACE_POINTS[mini(place - 1, PLACE_POINTS.size() - 1)],
			"%s place!" % UiKit.ordinal(place))
	var secs := int(time_left())
	if secs > 0:
		award(p, ScoreKeeper.TIME, secs * 3, "Speedy!")
	if place == 1:
		stat(p, &"won")
	p.controls_enabled = false
	if p.input:
		p.input.reset()
	p.celebrate()
	p.set_meta(&"camera_ignore", true)
	finish_zone.celebrate()
	match_node.fx.confetti(p.global_position + Vector3(0, 2.0, 0))
	sfx(&"finish_line")
	net_event(&"finished", [p.player_index])
	if p.is_human:
		message("%s finished %s!" % [p.display_name, UiKit.ordinal(place)], Color("7dffb0"), 2.4)
	_check_end()


func _check_end() -> void:
	if finish_order.size() >= players.size():
		_end_queued_at = MatchClock.now(self) + 1.2
		return
	var people_left := 0
	for h in human_players():
		if not has_finished(h):
			people_left += 1
	if not human_players().is_empty() and people_left == 0:
		match_node.time_left = minf(match_node.time_left, ALL_PEOPLE_DONE_TIME)
	elif not _hurry_started:
		_hurry_started = true
		if match_node.time_left > HURRY_TIME:
			match_node.time_left = HURRY_TIME
			message("HURRY! %d seconds to reach the finish!" % int(HURRY_TIME), Color("ffd23f"), 2.4)


func on_time_up() -> void:
	# Racers still on the course get points for how far they got.
	for p in players:
		if not has_finished(p):
			var pts := int(150.0 * best_progress_of(p))
			if pts > 0:
				award(p, ScoreKeeper.OBJECTIVE, pts, "Nice try!")


func _on_chaos_started(ev: ChaosEvent) -> void:
	if not is_playing() or not is_authority():
		return
	var tip := ""
	match ev.id:
		&"moon":
			tip = "Moon Mode: floaty jumps! Don't overshoot the platforms."
		&"bounce":
			tip = "Bounce Mode: the whole course is a trampoline!"
		&"slippery":
			tip = "Slippery Mode: careful on the narrow bits!"
		&"tiny":
			tip = "Tiny Mode: little steps, but the bounce pads still launch you high!"
	if tip != "" and bool(GameState.get_setting("show_tips", true)):
		_pending_tip = tip
		_pending_tip_at = MatchClock.now(self) + 2.6


# ---------------------------------------------------------------- online

func get_net_state() -> Dictionary:
	var progress := PackedFloat32Array()
	var times := PackedFloat32Array()
	for p in players:
		progress.append(best_progress_of(p))
		times.append(float(_finish_times.get(p.player_index, -1.0)))
	return {"fo": PackedInt32Array(finish_order), "bp": progress, "ft": times, "st": stars_net_state()}


func apply_net_state(state: Dictionary) -> void:
	var order = state.get("fo")
	if typeof(order) == TYPE_PACKED_INT32_ARRAY:
		var clean: Array[int] = []
		for i: int in order:
			if i >= 0 and i < players.size() and not clean.has(i):
				clean.append(i)
		finish_order = clean
	var progress = state.get("bp")
	var times = state.get("ft")
	for p in players:
		var i := p.player_index
		if typeof(progress) == TYPE_PACKED_FLOAT32_ARRAY and i < (progress as PackedFloat32Array).size():
			_best_progress[i] = clampf(progress[i], 0.0, 1.0)
		if typeof(times) == TYPE_PACKED_FLOAT32_ARRAY and i < (times as PackedFloat32Array).size() and times[i] >= 0.0:
			_finish_times[i] = times[i]
		if has_finished(p):
			p.set_meta(&"camera_ignore", true)
	apply_stars_net_state(state.get("st"))


func apply_net_event(event_name: StringName, args: Array) -> void:
	if _apply_common_event(event_name, args):
		return
	if event_name == &"finished" and args.size() == 1:
		var p := _player_by_index(int(args[0]))
		if p:
			if not finish_order.has(p.player_index):
				finish_order.append(p.player_index)
			p.set_meta(&"camera_ignore", true)
		finish_zone.celebrate()


# ---------------------------------------------------------------- HUD & results

func get_objective_text() -> String:
	var humans := human_players()
	if humans.size() == 1:
		var h := humans[0]
		if has_finished(h):
			return "You finished %s!" % UiKit.ordinal(place_of(h))
		return "Race to the finish! You're %s" % UiKit.ordinal(place_of(h))
	return "Race to the finish line!"


func create_objective_widget() -> Control:
	var w := RaceBoard.new()
	w.mode = self
	return w


func get_finish_banner(_success: bool) -> String:
	return "RACE OVER!" if not finish_order.is_empty() else "TIME'S UP!"


func get_result_text(p_success: bool) -> Dictionary:
	var humans := human_players()
	if humans.size() == 1:
		var h := humans[0]
		if has_finished(h):
			var place := place_of(h)
			var head := "YOU WON THE RACE!" if place == 1 else "You finished %s!" % UiKit.ordinal(place)
			return {"headline": head, "subline": "Finish time %.1f seconds. Boing boing!" % float(_finish_times.get(h.player_index, 0.0))}
		return {"headline": "So close!", "subline": "You got %d%% of the way. One more try?" % int(best_progress_of(h) * 100.0)}
	if p_success:
		return {"headline": "RACE OVER!", "subline": "What a bouncy race!"}
	return {"headline": "Time's up!", "subline": "Nobody made it this time. Try again!"}


func get_award_candidates() -> Array[Dictionary]:
	return [
		{"stat": &"won", "title": "Bounce Champ", "text": "First across the finish line"},
		{"stat": &"bounces", "title": "Boing Boing", "text": "Bounced the most"},
		{"stat": &"checkpoints", "title": "Flag Collector", "text": "Reached the most checkpoints"},
	]


func get_progress_stats(_success: bool) -> Dictionary:
	var finished := 0
	var best := INF
	for h in human_players():
		if has_finished(h):
			finished += 1
			best = minf(best, float(_finish_times.get(h.player_index, INF)))
	var out := {"races_finished": finished}
	if best < INF:
		out["best_time"] = best
	return out


# ---------------------------------------------------------------- CPU buddies

func get_bot_goal(p: PlayerCharacter) -> Dictionary:
	if not is_playing() or p.is_respawning or has_finished(p):
		return {"wait": true}
	return path_goal(p, _path)
