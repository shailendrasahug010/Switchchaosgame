extends TestCase
## Pausing and resuming: everything freezes (timer, characters, obstacles,
## chaos countdowns) and continues exactly where it stopped.


func after_each() -> void:
	tree.paused = false
	await end_scene()


func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _tap(code: Key) -> void:
	_key(code, true)
	await process_frames(2)
	_key(code, false)
	await process_frames(2)


func test_pause_freezes_the_round_and_resume_continues() -> void:
	var setup := MatchSetup.quick(&"bounce_race", 1, 3)
	setup.seed = 77
	var m := await start_match(setup)
	await seconds(2.0)
	m.chaos.force_event(&"moon", false, 3.0)
	await seconds(0.5)
	m.set_paused(true)
	check(tree.paused, "tree paused")
	check(m.pause_menu.visible, "pause menu shown")
	var t0 := m.time_left
	var clock0 := MatchClock.time
	var pending0 := m.chaos.get_pending_time_left()
	var positions: Array[Vector3] = []
	for p in m.players:
		positions.append(p.global_position)
	await process_frames(90)
	check_near(m.time_left, t0, 0.0001, "round timer frozen while paused")
	check_near(MatchClock.time, clock0, 0.0001, "moving obstacles frozen while paused")
	check_near(m.chaos.get_pending_time_left(), pending0, 0.0001, "chaos countdown frozen while paused")
	for i in m.players.size():
		check(m.players[i].global_position.distance_to(positions[i]) < 0.001, "player %d frozen" % (i + 1))
	m.set_paused(false)
	check(not tree.paused and not m.pause_menu.visible, "resumed")
	await seconds(1.0)
	check(m.time_left < t0 - 0.9, "timer runs again after resuming")
	check(MatchClock.time > clock0 + 0.9, "obstacles move again")
	await seconds(3.0)
	check(m.chaos.is_active(&"moon"), "the announced event still starts after the pause")


func test_escape_pauses_and_resumes() -> void:
	var m := await start_match(MatchSetup.quick(&"cake_dash", 1, 1))
	await seconds(0.5)
	await _tap(KEY_ESCAPE)
	check(m.is_paused and tree.paused, "Esc pauses")
	await _tap(KEY_ESCAPE)
	check(not m.is_paused and not tree.paused, "Esc again resumes")
	await _tap(KEY_P)
	check(m.is_paused, "P pauses too")
	await _tap(KEY_P)
	check(not m.is_paused, "P resumes too")


func test_pause_menu_buttons_work_while_paused() -> void:
	var m := await start_match(MatchSetup.quick(&"cake_dash", 1, 1))
	await seconds(0.5)
	m.set_paused(true)
	await process_frames(5)
	var gs := tree.root.get_node("GameState")
	var was_muted: bool = gs.get_setting("muted", false)
	(m.pause_menu._sound as Button).pressed.emit()
	check(gs.get_setting("muted", false) != was_muted, "sound button toggles sound while paused")
	(m.pause_menu._sound as Button).pressed.emit()
	(m.pause_menu._resume as Button).pressed.emit()
	await process_frames(2)
	check(not m.is_paused, "Keep playing resumes")


func test_leaving_the_app_pauses_the_round() -> void:
	var m := await start_match(MatchSetup.quick(&"cake_dash", 1, 1))
	await seconds(0.5)
	m.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(m.is_paused, "switching apps pauses (so kids don't lose the round)")
	m.set_paused(false)
	m.request_finish(false)
	var frames := 0
	while m.phase != MatchController.Phase.RESULTS and frames < 400:
		await tree.physics_frame
		frames += 1
	m.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not m.is_paused, "no pause menu over the results screen")


func test_touch_state_is_cleared_on_pause() -> void:
	var m := await start_match(MatchSetup.quick(&"cake_dash", 1, 1))
	TouchState.stick = Vector2(1, 0)
	TouchState.jump_held = true
	m.set_paused(true)
	check_eq(TouchState.stick, Vector2.ZERO, "stick released on pause (no runaway character after resuming)")
	check(not TouchState.jump_held, "jump released on pause")
	m.set_paused(false)
