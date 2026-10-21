extends TestCase
## Stress rounds: CPU-driven "people" play every mode while the rules switch
## far more often than in a normal game, so many events overlap and expire
## mid-action. Any engine error fails the test, and every rule must be back to
## normal afterwards.


func after_each() -> void:
	await end_scene()


func _hectic_round(mode_id: StringName, seed_value: int, players: int) -> void:
	var setup := MatchSetup.quick(mode_id, 1, players - 1)
	setup.seed = seed_value
	setup.slots[0].autopilot = true
	var m := await start_match(setup)
	m.chaos.first_event_delay = 0.5
	m.chaos.interval_min = 3.5
	m.chaos.interval_max = 5.0
	m.chaos.announce_time = 1.5
	m.chaos.max_active = 2
	var started: Array[StringName] = []
	m.chaos.event_started.connect(func(ev: ChaosEvent) -> void: started.append(ev.id))
	var frames := 0
	while m.phase != MatchController.Phase.RESULTS and frames < 160 * 60:
		await tree.physics_frame
		frames += 1
	note("%s seed %d, %d players: %d switches %s, success=%s" % [mode_id, seed_value, players, started.size(),
			str(started), m.success])
	check_eq(m.phase, MatchController.Phase.RESULTS, "%s reached the results" % mode_id)
	check(started.size() >= 3, "%s: several switches happened" % mode_id)
	check(m.chaos.rules.is_empty(), "%s: no rules left over" % mode_id)
	for p in m.players:
		check_near(p.stat(&"gravity"), 1.0, 0.0001, "%s: gravity normal" % p.name)
		check_near(p.stat(&"speed") , 1.0, 0.0001, "%s: speed normal" % p.name)
		check(not p.is_reversed(), "%s: controls normal" % p.name)
	await end_scene()


func test_hectic_cake_dash() -> void:
	await _hectic_round(&"cake_dash", 101, 4)
	await _hectic_round(&"cake_dash", 202, 2)


func test_hectic_button_mayhem() -> void:
	await _hectic_round(&"button_mayhem", 303, 4)
	await _hectic_round(&"button_mayhem", 404, 3)


func test_hectic_bounce_race() -> void:
	await _hectic_round(&"bounce_race", 505, 4)
	await _hectic_round(&"bounce_race", 606, 2)
