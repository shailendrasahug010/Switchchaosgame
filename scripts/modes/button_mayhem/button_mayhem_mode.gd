class_name ButtonMayhemMode
extends GameMode
## Mode B: press the colored buttons in the right order.
##
## The round has three waves (3, 4 and 5 buttons). The HUD shows the whole
## sequence; the next button starts glowing (with an arrow) if nobody has found
## it after a few seconds. Some buttons are easy, some sit on a high platform,
## a spinning turntable or a sliding platform, one hides in a toy fort with a
## tiny door, and one rides a wind-up car that runs away.
##
## Pressing the wrong button just goes "BZZT" and bounces you back: no points
## are lost. Points go to right presses, quick hand-offs between teammates
## ("Team combo!") and getting it right after a mistake ("Nice recovery!").

const WAVES: Array[int] = [4, 5, 6]
const HINT_DELAY := 5.0
const COMBO_WINDOW := 6.0
const RECOVERY_WINDOW := 8.0
## CPU buddies "think" this long before going for a new button...
const BOT_THINK_TIME := 1.6
## ...and leave it to a person who is closer for this long.
const HUMAN_HEAD_START := 6.0

var buttons: Dictionary = {}          # color id -> PushButton
var sequence: Array[StringName] = []  # the current wave, in order
var step := 0
var wave := 0
var right_presses := 0
var completed := false
var car: RunawayCar

var _wait_spots: Dictionary = {}      # color id -> Marker3D where bots wait for a moving button
var _step_started_at := 0.0
var _hint_shown := false
var _last_correct_by := -1
var _last_correct_time := -100.0
var _last_wrong: Dictionary = {}      # player index -> time of the last wrong press
var _last_pressed: StringName = &""
var _roles: Dictionary = {}
var _roles_frame := -1
var _focus_proxy: Marker3D
var _pending_tip := ""
var _pending_tip_at := -1.0
var _stars: Array[StarPickup] = []


func setup_mode(p_match: MatchController) -> void:
	super(p_match)
	for n in find_children("*", "PushButton", true, false):
		var b := n as PushButton
		buttons[b.color_id] = b
		b.pressed_by.connect(_on_button_pressed)
	for n in find_children("*", "RunawayCar", true, false):
		car = n as RunawayCar
	for n in find_children("*", "StarPickup", true, false):
		var s := n as StarPickup
		_stars.append(s)
		s.touched.connect(_on_star_touched)
	for m: Node in find_children("*", "Marker3D", true, false):
		if m.is_in_group(&"button_wait"):
			_wait_spots[StringName(String(m.get_meta(&"button", "")))] = m
	_focus_proxy = Marker3D.new()
	_focus_proxy.name = "CameraFocusProxy"
	_focus_proxy.visible = false
	add_child(_focus_proxy)
	p_match.chaos.event_started.connect(_on_chaos_started)


func on_players_spawned(p_players: Array[PlayerCharacter]) -> void:
	super(p_players)
	if car:
		var list: Array[Node3D] = []
		for p in players:
			list.append(p)
		car.chasers = list
	for p in players:
		p.fell_out.connect(func() -> void: reset_bot_path(p))


func on_round_started() -> void:
	super()
	wave = 0
	_new_wave()


# ---------------------------------------------------------------- the sequence

func _new_wave() -> void:
	var ids: Array[StringName] = []
	for id: StringName in buttons.keys():
		ids.append(id)
	ids.sort()  # dictionary order must not leak into the seeded shuffle
	var count := mini(WAVES[wave], ids.size())
	# Seeded shuffle so a round is repeatable (tests, online play).
	for i in range(ids.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := ids[i]
		ids[i] = ids[j]
		ids[j] = tmp
	# Don't start a wave with the button that was just pressed.
	if ids[0] == _last_pressed and ids.size() > 1:
		var tmp := ids[0]
		ids[0] = ids[ids.size() - 1]
		ids[ids.size() - 1] = tmp
	sequence = ids.slice(0, count)
	step = 0
	_start_step()
	objective_changed.emit()


func _start_step() -> void:
	_step_started_at = MatchClock.now(self)
	_hint_shown = false
	for b: PushButton in buttons.values():
		b.set_lit(false)


func current_target() -> StringName:
	if completed or step >= sequence.size():
		return &""
	return sequence[step]


func next_target() -> StringName:
	if completed or step + 1 >= sequence.size():
		return &""
	return sequence[step + 1]


func total_needed() -> int:
	var n := 0
	for w in WAVES:
		n += w
	return n


func _on_button_pressed(player: PlayerCharacter, button: PushButton, stomped: bool) -> void:
	if not is_playing() or completed or not is_authority():
		return
	var now := MatchClock.now(self)
	if button.color_id == current_target():
		_correct_press(player, button, stomped, now)
	else:
		_wrong_press(player, button, now)


func _correct_press(player: PlayerCharacter, button: PushButton, stomped: bool, now: float) -> void:
	button.accept()
	sfx(&"button_right")
	net_event(&"press", [String(button.color_id), true])
	right_presses += 1
	_last_pressed = button.color_id
	stat(player, &"right_presses")
	if stomped:
		stat(player, &"stomps")
	if button.get_parent() is RunawayCar:
		stat(player, &"car_presses")
	award(player, ScoreKeeper.OBJECTIVE, 60, "Stomp!" if stomped else "Right button!")
	player.react(&"happy")
	# Quick hand-off between two different teammates.
	if _last_correct_by >= 0 and _last_correct_by != player.player_index and now - _last_correct_time <= COMBO_WINDOW:
		award(player, ScoreKeeper.TEAMWORK, 25, "Team combo!")
		for p in players:
			if p.player_index == _last_correct_by:
				award(p, ScoreKeeper.TEAMWORK, 25, "")
				stat(p, &"combos")
		stat(player, &"combos")
	_last_correct_by = player.player_index
	_last_correct_time = now
	# Getting it right after a mistake.
	if _last_wrong.has(player.player_index) and now - float(_last_wrong[player.player_index]) <= RECOVERY_WINDOW:
		award(player, ScoreKeeper.RECOVERY, 40, "Nice recovery!")
		stat(player, &"recoveries")
		_last_wrong.erase(player.player_index)
	match_node.fx.puff(button.global_position + Vector3(0, 1.0, 0), button.get_color().lightened(0.4))
	step += 1
	if step < sequence.size():
		_start_step()
		objective_changed.emit()
		return
	# Wave complete.
	award_everyone(ScoreKeeper.OBJECTIVE, 100, "Wave %d done!" % (wave + 1))
	match_node.fx.confetti(button.global_position + Vector3(0, 2.0, 0))
	sfx(&"wave_done")
	wave += 1
	if wave >= WAVES.size():
		_complete()
		return
	message("Wave %d! Now find %d buttons!" % [wave + 1, WAVES[wave]], Color("7dffb0"), 2.4)
	_new_wave()


func _wrong_press(player: PlayerCharacter, button: PushButton, now: float) -> void:
	button.reject()
	sfx(&"buzzer")
	net_event(&"press", [String(button.color_id), false])
	stat(player, &"wrong_presses")
	_last_wrong[player.player_index] = now
	player.knock(button.global_position, 4.5, 3.5)
	var want := Catalog.button_color(current_target())
	message("BZZT! Not that one. Find the %s %s!" % [String(want.name).to_upper(), String(want.symbol)],
			Color("ffd23f"), 2.0)


func _complete() -> void:
	completed = true
	for b: PushButton in buttons.values():
		b.set_lit(false)
	award_everyone(ScoreKeeper.OBJECTIVE, 200, "All buttons!")
	var secs := int(time_left())
	if secs > 0:
		award_everyone(ScoreKeeper.TIME, secs * 4, "Speedy!")
	message("BUTTON MASTERS! Every button pressed!", Color("7dffb0"), 3.0)
	finish(true)


func on_time_up() -> void:
	if completed:
		return
	var pts := 25 * right_presses
	if pts > 0:
		award_everyone(ScoreKeeper.OBJECTIVE, pts, "So close!")


# ---------------------------------------------------------------- every tick

func mode_physics_process(_delta: float) -> void:
	if car:
		car.speed_scale = match_node.chaos.rules.mul(&"speed")
	var hint := _update_hint()
	if hint and not _hint_shown:
		_hint_shown = true
		var info := Catalog.button_color(current_target())
		message("Hint: follow the arrow to the %s button!" % String(info.name).to_upper(), info.color.lightened(0.3), 2.0)
	if _pending_tip_at > 0.0 and MatchClock.now(self) >= _pending_tip_at:
		_pending_tip_at = -1.0
		message(_pending_tip, Color("fff3a3"), 2.6)


## Online phones: the arrow and camera follow the server's sequence.
func mode_client_process(_delta: float) -> void:
	if car:
		car.speed_scale = match_node.chaos.rules.mul(&"speed")
	_update_hint()


## Lights the hinted button (with its arrow) once nobody has found it for a
## while, and points the camera at it. Returns true while the hint is on.
func _update_hint() -> bool:
	var target := current_target()
	var age := MatchClock.now(self) - _step_started_at
	var hint := target != &"" and age >= HINT_DELAY
	for id: StringName in buttons:
		(buttons[id] as PushButton).set_lit(hint and id == target)
	# The camera widens to show the hinted button (when it fits).
	if hint and buttons.has(target):
		_focus_proxy.global_position = (buttons[target] as PushButton).global_position
		_focus_proxy.visible = true
	else:
		_focus_proxy.visible = false
	return hint


## Some rule switches change how buttons can be reached: say so.
func _on_chaos_started(ev: ChaosEvent) -> void:
	if not is_playing() or not is_authority():
		return
	var tip := ""
	match ev.id:
		&"tiny":
			tip = "Tiny Mode: sneak into the toy fort through the little door!"
		&"moon":
			tip = "Moon Mode: jump up to high buttons, or right over the fort wall!"
		&"giant":
			tip = "Giant Mode: long arms! You can reach buttons from further away."
		&"bounce":
			tip = "Bounce Mode: bounce onto a button to stomp it!"
		&"sticky":
			tip = "Sticky Mode: the runaway car is stuck in the honey too!"
	if tip != "" and bool(GameState.get_setting("show_tips", true)):
		_pending_tip = tip
		_pending_tip_at = MatchClock.now(self) + 2.6


func _on_star_touched(p: PlayerCharacter, star: StarPickup) -> void:
	if not is_playing() or not is_authority():
		return
	collect_star(p, star)


# ---------------------------------------------------------------- online

func get_net_state() -> Dictionary:
	var seq := PackedStringArray()
	for id in sequence:
		seq.append(String(id))
	var out := {"sq": seq, "s": step, "w": wave, "rp": right_presses, "c": completed,
			"t0": _step_started_at, "st": stars_net_state()}
	if car:
		out["car"] = car.get_net_state()
	return out


func apply_net_state(state: Dictionary) -> void:
	var changed := false
	var seq = state.get("sq")
	if typeof(seq) == TYPE_PACKED_STRING_ARRAY:
		var clean: Array[StringName] = []
		for id: String in seq:
			if buttons.has(StringName(id)):
				clean.append(StringName(id))
		if clean != sequence:
			sequence = clean
			changed = true
	var new_step := clampi(int(state.get("s", step)), 0, sequence.size())
	var new_wave := clampi(int(state.get("w", wave)), 0, WAVES.size())
	if new_step != step or new_wave != wave:
		step = new_step
		wave = new_wave
		changed = true
	right_presses = maxi(0, int(state.get("rp", right_presses)))
	var done := bool(state.get("c", completed))
	if done != completed:
		completed = done
		changed = true
	var t0 := float(state.get("t0", _step_started_at))
	if not is_equal_approx(t0, _step_started_at):
		_step_started_at = t0
	if car and state.has("car"):
		car.apply_net_state(state.car)
	apply_stars_net_state(state.get("st"))
	if changed:
		objective_changed.emit()


func apply_net_event(event_name: StringName, args: Array) -> void:
	if _apply_common_event(event_name, args):
		return
	if event_name == &"press" and args.size() == 2:
		var button: PushButton = buttons.get(StringName(str(args[0])))
		if button == null:
			return
		button.play_press()
		if bool(args[1]):
			button.accept()
		else:
			button.reject()


# ---------------------------------------------------------------- HUD & results

func get_objective_text() -> String:
	if completed:
		return "BUTTON MASTERS!"
	var target := current_target()
	if target == &"":
		return ""
	var info := Catalog.button_color(target)
	return "Press the %s %s button!" % [String(info.name).to_upper(), String(info.symbol)]


func create_objective_widget() -> Control:
	var w := ButtonBoard.new()
	w.mode = self
	return w


func get_result_text(p_success: bool) -> Dictionary:
	if p_success:
		return {"headline": "BUTTON MASTERS!",
				"subline": "All %d buttons pressed in the right order!" % total_needed()}
	return {"headline": "The buttons won this time!",
			"subline": "You pressed %d of %d buttons. Try again!" % [right_presses, total_needed()]}


func get_award_candidates() -> Array[Dictionary]:
	return [
		{"stat": &"right_presses", "title": "Button Boss", "text": "Pressed the most right buttons"},
		{"stat": &"car_presses", "title": "Car Catcher", "text": "Caught the runaway button"},
		{"stat": &"combos", "title": "Combo Crew", "text": "Best at quick team hand-offs"},
		{"stat": &"stomps", "title": "Stomp Star", "text": "Stomped buttons with style"},
	]


func get_progress_stats(p_success: bool) -> Dictionary:
	var human_presses := 0
	for p in players:
		if p.is_human:
			human_presses += int(match_node.score.get_stat(p.player_index, &"right_presses"))
	var out := {"buttons_pressed": human_presses}
	if p_success:
		out["best_time"] = match_node.elapsed
	return out


func get_camera_targets() -> Array[Dictionary]:
	var out := super()
	out.append({"node": _focus_proxy, "priority": PartyCamera.Priority.SHOULD, "height": 1.2})
	return out


# ---------------------------------------------------------------- CPU buddies

## After a short think, one CPU buddy goes for the current button (unless a
## person is closer: they get a head start), another wanders toward the next
## one, the rest collect stars or stay near the people.
func _update_roles() -> void:
	if _roles_frame == Engine.get_physics_frames():
		return
	_roles_frame = Engine.get_physics_frames()
	_roles.clear()
	var target := current_target()
	if target == &"":
		return
	var age := MatchClock.now(self) - _step_started_at
	var bots: Array[PlayerCharacter] = []
	for p in players:
		if p.input is BotInputSource and not p.is_respawning:
			bots.append(p)
	var goal := _button_goal_point(target)
	var presser := _closest(bots, goal)
	if presser and age >= BOT_THINK_TIME:
		var person_first := false
		if age < HUMAN_HEAD_START:
			var bot_d := presser.global_position.distance_to(goal)
			for h in human_players():
				if not (h.input is BotInputSource) and not h.is_respawning \
						and h.global_position.distance_to(goal) < bot_d + 2.0:
					person_first = true
		if not person_first:
			_roles[presser.player_index] = {"kind": &"press", "id": target}
			bots.erase(presser)
	var nxt := next_target()
	if nxt != &"":
		var helper := _closest(bots, _button_goal_point(nxt))
		if helper:
			_roles[helper.player_index] = {"kind": &"prepare", "id": nxt}
			bots.erase(helper)
	for b in bots:
		_roles[b.player_index] = {"kind": &"roam"}


func _closest(list: Array[PlayerCharacter], point: Vector3) -> PlayerCharacter:
	var best: PlayerCharacter = null
	var best_d := INF
	for p in list:
		var d := p.global_position.distance_to(point)
		if d < best_d:
			best_d = d
			best = p
	return best


func _button_goal_point(id: StringName) -> Vector3:
	var b: PushButton = buttons.get(id)
	return b.global_position if b else Vector3.ZERO


func get_bot_goal(p: PlayerCharacter) -> Dictionary:
	if completed or not is_playing() or p.is_respawning:
		return {"wait": true}
	_update_roles()
	var role: Dictionary = _roles.get(p.player_index, {"kind": &"roam"})
	match role.kind:
		&"press":
			return _goal_for_button(p, role.id, true)
		&"prepare":
			# Drift toward the next button but stop a good way short of it:
			# helpful, but no camping on it.
			var spot := _button_goal_point(role.id)
			var toward_middle := Vector3(-spot.x, 0.0, 2.0 - spot.z)
			if toward_middle.length() > 0.1:
				spot += toward_middle.normalized() * 5.5
			spot.y = 0.0
			if has_navigation():
				spot = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, spot)
			return nav_goal(p, spot, 1.5)
	return _roam_goal(p)


func _goal_for_button(p: PlayerCharacter, id: StringName, press: bool) -> Dictionary:
	var button: PushButton = buttons.get(id)
	if button == null:
		return {"wait": true}
	var reach := button.interact_radius * maxf(1.0, p.size_scale)
	var extra := {"interact": press, "interact_at": button.global_position, "interact_distance": reach - 0.3}
	# The runaway car: aim where it is going.
	if button.get_parent() is RunawayCar:
		var c := button.get_parent() as RunawayCar
		return nav_goal(p, c.predict_position(0.5), 0.9, extra)
	# Buttons on something that slides past a fixed spot: wait there.
	if _wait_spots.has(id):
		extra["interact_distance"] = reach - 0.15
		return nav_goal(p, (_wait_spots[id] as Node3D).global_position, 0.3, extra)
	return nav_goal(p, button.global_position, 1.0, extra)


func _roam_goal(p: PlayerCharacter) -> Dictionary:
	var best: StarPickup = null
	var best_d := INF
	for s in _stars:
		if s.taken or s.global_position.y > 1.8:
			continue
		var d := s.global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = s
	if best and best_d < 14.0:
		return nav_goal(p, best.global_position, 0.3)
	for h in human_players():
		if h != p and not h.is_respawning:
			var side := Vector3(cos(p.player_index * 2.1), 0, sin(p.player_index * 2.1)) * 2.5
			return nav_goal(p, h.global_position + side, 1.2)
	return {"wait": true}
