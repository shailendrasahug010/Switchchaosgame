extends TestCase
## The rules of each game mode, played with a scripted person: grabbing,
## helping, dropping and delivering the cake; right and wrong buttons; racing,
## checkpoints and falling. Chaos is off unless a test turns it on.


func after_each() -> void:
	await end_scene()


func _start(mode_id: StringName, cpus: int = 0, seed_value: int = 5) -> MatchController:
	var setup := MatchSetup.quick(mode_id, 1, cpus)
	setup.seed = seed_value
	setup.chaos_enabled = false
	var m := await start_match(setup)
	m.players[0].input = ScriptedInputSource.new()
	await physics_frames(10)
	return m


func _interact(p: PlayerCharacter) -> void:
	p.input.press_interact()
	await physics_frames(3)


# ---------------------------------------------------------------- Cake Dash

func test_cake_grab_put_down_and_carry_slowdown() -> void:
	var m := await _start(&"cake_dash")
	var mode := m.mode as CakeDashMode
	var p := m.players[0]
	var cake := mode.cake
	check_eq(mode.get_objective_text(), "Grab the cake!", "mission starts with grabbing the cake")
	p.teleport(cake.global_position + Vector3(1.4, 0.2, 0))
	await physics_frames(15)
	await _interact(p)
	check(cake.state == GiantCake.State.CARRIED and cake.carrier == p, "grabbed")
	check(p.stat(&"speed") < 1.0, "the heavy cake slows its carrier")
	check_eq(mode.get_interact_prompt(p), "PUT DOWN", "carrier can put it down")
	await _interact(p)
	check(cake.state == GiantCake.State.LOOSE, "put down gently")
	check_eq(cake.candles, GiantCake.MAX_CANDLES, "a gentle put-down costs no candle")
	await physics_frames(3)
	check_near(p.stat(&"speed"), 1.0, 0.001, "full speed again without the cake")


func test_helpers_steady_the_cake_and_earn_teamwork_points() -> void:
	var m := await _start(&"cake_dash", 2, 11)
	var mode := m.mode as CakeDashMode
	var p := m.players[0]
	p.teleport(mode.cake.global_position + Vector3(1.4, 0.2, 0))
	await physics_frames(15)
	await _interact(p)
	check(mode.cake.carrier == p, "person carries the cake")
	# CPU buddies come over and help on their own.
	var helped := false
	for i in 600:
		await tree.physics_frame
		if not mode.cake.helpers.is_empty():
			helped = true
			break
	check(helped, "a CPU buddy came to help carry")
	await seconds(3.0)
	var teamwork := 0
	for i in m.players.size():
		teamwork += m.score.category_points(i, ScoreKeeper.TEAMWORK)
	check(teamwork > 0, "carrying together earns teamwork points (%d)" % teamwork)
	check(p.stat(&"speed") > 0.76, "helpers make the carrier faster")


func test_wobble_drop_costs_a_candle_and_a_quick_regrab_is_a_recovery() -> void:
	var m := await _start(&"cake_dash")
	var mode := m.mode as CakeDashMode
	var p := m.players[0]
	p.teleport(mode.cake.global_position + Vector3(1.4, 0.2, 0))
	await physics_frames(15)
	await _interact(p)
	var dropped := [false]
	mode.cake.dropped.connect(func(_by: PlayerCharacter) -> void: dropped[0] = true)
	mode.cake.jolt(Vector3(1, 0, 0), 40.0)
	await physics_frames(10)
	check(dropped[0], "a big jolt tips the cake over")
	check_eq(mode.cake.candles, GiantCake.MAX_CANDLES - 1, "a tumble blows out one candle")
	check(mode.cake.state == GiantCake.State.LOOSE, "cake is loose after the tumble")
	await seconds(1.5)
	p.teleport(mode.cake.global_position + Vector3(1.2, 0.3, 0))
	await physics_frames(10)
	var before := m.score.category_points(0, ScoreKeeper.RECOVERY)
	await _interact(p)
	check(mode.cake.carrier == p, "grabbed again")
	check(m.score.category_points(0, ScoreKeeper.RECOVERY) > before, "quick re-grab after a drop scores 'Nice recovery!'")


func test_cake_in_the_goo_returns_to_the_checkpoint() -> void:
	var m := await _start(&"cake_dash")
	var mode := m.mode as CakeDashMode
	var home := mode.cake_checkpoint_pos
	mode.cake.global_position = Vector3(home.x, mode.kill_height - 3.0, home.z)
	await physics_frames(5)
	check(mode.cake.global_position.distance_to(home) < 1.5, "cake back at its checkpoint")
	check_eq(mode.cake.candles, GiantCake.MAX_CANDLES - 1, "splat costs a candle")
	check(m.is_playing(), "the round goes on")


func test_delivering_the_cake_wins_for_everyone() -> void:
	var m := await _start(&"cake_dash", 1)
	var mode := m.mode as CakeDashMode
	var p := m.players[0]
	p.teleport(mode.cake.global_position + Vector3(1.4, 0.2, 0))
	await physics_frames(15)
	await _interact(p)
	p.teleport(mode.finish_zone.global_position + Vector3(0, 0.2, 0))
	await physics_frames(10)
	check(mode.delivered, "walking into the party area delivers the cake")
	check(m.score.total(1) >= 400, "the CPU teammate shares the delivery points (%d)" % m.score.total(1))
	check(m.score.category_points(0, ScoreKeeper.TIME) > 0, "speedy bonus for time left")
	var frames := 0
	while m.phase != MatchController.Phase.RESULTS and frames < 400:
		await tree.physics_frame
		frames += 1
	check(m.success, "round won")
	check_eq(m.result.headline, "PARTY TIME!", "happy headline")
	for info: Dictionary in m.result.players:
		check(String(info.award.title) != "", "%s got a friendly award" % info.label)


# ---------------------------------------------------------------- Button Mayhem

func _button_spot(b: PushButton) -> Vector3:
	return b.global_position + Vector3(0.0, 0.3, b.interact_radius * 0.6)


func test_right_button_scores_and_wrong_button_costs_nothing() -> void:
	var m := await _start(&"button_mayhem")
	var mode := m.mode as ButtonMayhemMode
	var p := m.players[0]
	var target := mode.current_target()
	check(target != &"", "there is a button to press")
	check(mode.get_objective_text().contains(String(Catalog.button_color(target).name).to_upper()),
			"objective names the color: %s" % mode.get_objective_text())
	# A wrong (static) button first.
	var wrong: PushButton = null
	for id: StringName in mode.buttons:
		var b: PushButton = mode.buttons[id]
		if id != target and not (b.get_parent() is RunawayCar) and not (b.get_parent() is MovingPlatform):
			wrong = b
			break
	p.teleport(_button_spot(wrong))
	await physics_frames(10)
	var before := m.score.total(0)
	await _interact(p)
	check_eq(m.score.total(0), before, "a wrong button loses no points")
	check_eq(int(m.score.get_stat(0, &"wrong_presses")), 1, "wrong press counted (for the recovery bonus)")
	check_eq(mode.current_target(), target, "the sequence did not move on")
	await seconds(1.0)
	# Then the right one.
	var right: PushButton = mode.buttons[target]
	var tries := 0
	while mode.current_target() == target and tries < 20:
		var spot := _button_spot(right)
		if right.get_parent() is RunawayCar:
			spot = right.global_position + Vector3(0, 0.5, 0)
		p.teleport(spot)
		await physics_frames(4)
		await _interact(p)
		await physics_frames(50)
		tries += 1
	check(mode.current_target() != target, "pressing the right button moves the sequence on")
	check(m.score.category_points(0, ScoreKeeper.OBJECTIVE) >= 60, "right button scores")
	check(m.score.category_points(0, ScoreKeeper.RECOVERY) >= 40, "right after a mistake earns 'Nice recovery!'")


func test_hint_lights_the_next_button_after_a_while() -> void:
	var m := await _start(&"button_mayhem")
	var mode := m.mode as ButtonMayhemMode
	var target := mode.current_target()
	check(not (mode.buttons[target] as PushButton).lit, "no hint right away")
	await seconds(ButtonMayhemMode.HINT_DELAY + 0.3)
	check((mode.buttons[target] as PushButton).lit, "the right button glows after %.0f s" % ButtonMayhemMode.HINT_DELAY)
	var others_lit := 0
	for id: StringName in mode.buttons:
		if id != target and (mode.buttons[id] as PushButton).lit:
			others_lit += 1
	check_eq(others_lit, 0, "only the right button glows")


func test_every_button_color_has_a_symbol_for_colorblind_players() -> void:
	var symbols := {}
	for b in Catalog.BUTTON_COLORS:
		check(b.symbol != &"", "%s has a symbol" % b.id)
		check(not symbols.has(b.symbol), "%s symbol is unique" % b.id)
		symbols[b.symbol] = true


# ---------------------------------------------------------------- Bounce Race

func test_finishing_order_places_and_hurry_up() -> void:
	var m := await _start(&"bounce_race", 3, 9)
	var mode := m.mode as BounceRaceMode
	var p := m.players[0]
	check(m.time_left > BounceRaceMode.HURRY_TIME, "plenty of time at the start")
	p.teleport(mode.finish_zone.global_position + Vector3(0, 0.3, 0))
	await physics_frames(10)
	check(mode.has_finished(p), "crossing the line finishes the race")
	check_eq(mode.place_of(p), 1, "first across is 1st")
	check(m.score.category_points(0, ScoreKeeper.OBJECTIVE) >= 400, "finish + 1st place points")
	check(m.time_left <= ALL_DONE + 0.1, "with every person finished the round wraps up soon (%.1f s left)" % m.time_left)
	check(not p.controls_enabled, "finished racers wait at the finish (no walking back)")


const ALL_DONE := BounceRaceMode.ALL_PEOPLE_DONE_TIME


func test_hurry_up_when_a_cpu_finishes_first() -> void:
	var m := await _start(&"bounce_race", 1, 9)
	var mode := m.mode as BounceRaceMode
	var cpu := m.players[1]
	cpu.teleport(mode.finish_zone.global_position + Vector3(0, 0.3, 0))
	await physics_frames(10)
	check(mode.has_finished(cpu), "CPU finished")
	check(m.time_left <= BounceRaceMode.HURRY_TIME + 0.1, "everyone else gets a hurry-up countdown")
	check(m.is_playing(), "the person can still finish")


func test_falling_respawns_quickly_at_the_last_checkpoint() -> void:
	var m := await _start(&"bounce_race")
	var mode := m.mode as BounceRaceMode
	var p := m.players[0]
	var cp := mode.checkpoints[0]
	p.teleport(cp.global_position + Vector3(0, 0.4, 0))
	await physics_frames(10)
	check(cp.has_reached(p.player_index), "checkpoint reached")
	var respawn := p.respawn_position
	p.teleport(Vector3(respawn.x, mode.kill_height - 5.0, respawn.z))
	var frames := 0
	await physics_frames(2)
	check(p.is_respawning, "fell into the goo")
	while p.is_respawning and frames < 300:
		await tree.physics_frame
		frames += 1
	check(frames < 60, "back in the race in under a second (%d frames)" % frames)
	check(p.global_position.distance_to(respawn) < 1.0, "respawned at the checkpoint")
	# Reaching the next checkpoint after a fall is a comeback.
	if mode.checkpoints.size() > 1:
		var cp2 := mode.checkpoints[1]
		p.teleport(cp2.global_position + Vector3(0, 0.4, 0))
		await physics_frames(10)
		check(m.score.category_points(0, ScoreKeeper.RECOVERY) > 0, "'Back on track!' after a fall")


func test_time_up_still_rewards_progress() -> void:
	var m := await _start(&"bounce_race")
	var mode := m.mode as BounceRaceMode
	var p := m.players[0]
	p.teleport(Vector3(0, 2.0, lerpf(mode.start_z, mode.finish_z, 0.5)))
	await physics_frames(30)
	m.time_left = 0.05
	await physics_frames(5)
	check(m.score.category_points(0, ScoreKeeper.OBJECTIVE) > 0, "points for how far you got")
	check_eq(m.phase, MatchController.Phase.FINISHED, "round over")
