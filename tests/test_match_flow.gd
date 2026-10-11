extends TestCase
## Plays whole rounds with CPU players and checks the round lifecycle:
## intro -> countdown -> playing -> finished -> results, scoring, restart.


func _play_round(mode_id: StringName, seed_value: int, max_seconds: float = 140.0) -> MatchController:
	var setup := MatchSetup.quick(mode_id, 0, 4)
	setup.seed = seed_value
	var m := await start_match(setup)
	if not check(m != null, "match scene loaded for %s" % mode_id):
		return null
	var started: Array[StringName] = []
	var ended: Array[StringName] = []
	var announced: Array[StringName] = []
	m.chaos.event_announced.connect(func(ev: ChaosEvent, _t: float) -> void: announced.append(ev.id))
	m.chaos.event_started.connect(func(ev: ChaosEvent) -> void: started.append(ev.id))
	m.chaos.event_ended.connect(func(ev: ChaosEvent) -> void: ended.append(ev.id))
	var frames := 0
	var limit := int(max_seconds * 60.0)
	while m.phase != MatchController.Phase.RESULTS and frames < limit:
		await tree.physics_frame
		frames += 1
	note("%s seed %d: success=%s, play time %.1fs, events started %s" % [mode_id, seed_value, m.success, m.elapsed, str(started)])
	note("scores: %s" % str(range(m.players.size()).map(func(i: int) -> int: return m.score.total(i))))
	check_eq(m.phase, MatchController.Phase.RESULTS, "round reached the results screen")
	check(m.results_screen.visible, "results screen is visible")
	check(m.score.team_total() > 0, "someone scored points")
	check(started.size() >= 2, "at least two chaos events happened during the round")
	# Every started event must have been announced first.
	for id in started:
		check(announced.has(id), "event %s was announced before starting" % id)
	# After the round all rule changes are gone.
	check(m.chaos.rules.is_empty(), "no chaos modifiers left after the round")
	for p in m.players:
		check_near(p.stat(&"gravity"), 1.0, 0.0001, "gravity back to normal for %s" % p.name)
		check(not p.is_reversed(), "controls not reversed after round for %s" % p.name)
	return m


func test_cake_dash_full_round_with_bots() -> void:
	var m := await _play_round(&"cake_dash", 1234)
	if m:
		var mode := m.mode as CakeDashMode
		note("cake candles left: %d, progress %.2f, delivered=%s" % [mode.cake.candles, mode.progress(), mode.delivered])
		check(mode.progress() > 0.3, "CPU team carried the cake at least 30% of the way")
	await end_scene()


func test_restart_creates_fresh_round() -> void:
	var setup := MatchSetup.quick(&"cake_dash", 1, 3)
	setup.seed = 99
	var m := await start_match(setup)
	await seconds(3.0)
	m.request_finish(false)
	var frames := 0
	while m.phase != MatchController.Phase.RESULTS and frames < 600:
		await tree.physics_frame
		frames += 1
	check_eq(m.phase, MatchController.Phase.RESULTS, "forced finish reaches results")
	m.restart_round()
	# Router fades out then swaps the scene.
	for i in 90:
		await tree.process_frame
	var m2 := tree.current_scene as MatchController
	check(m2 != null and m2 != m, "a new match scene was created")
	if m2:
		check_eq(m2.phase, MatchController.Phase.INTRO, "new round starts at the intro")
		check_eq(m2.score.team_total(), 0, "scores reset in the new round")
		check(m2.chaos.rules.is_empty(), "no chaos left over in the new round")
		check_near(m2.time_left, m2.round_length, 0.01, "timer reset")
	await end_scene()
