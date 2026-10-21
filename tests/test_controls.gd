extends TestCase
## Keyboard and touch input, from the real input events all the way to the
## character moving: key presses go through Input/InputMap, touches go through
## the on-screen TouchControls. Also checks Reverse Mode and simple controls.

var _saved_settings: Dictionary


func before_each() -> void:
	var gs := tree.root.get_node("GameState")
	_saved_settings = gs.settings.duplicate(true)
	Input.flush_buffered_events()


func after_each() -> void:
	_release_all_keys()
	var gs := tree.root.get_node("GameState")
	gs.settings = _saved_settings
	tree.root.get_node("InputSetup").configure_local_players(1)
	TouchState.reset()
	await end_scene()


# ---------------------------------------------------------------- helpers

var _held: Array[Key] = []


func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	if pressed and not _held.has(code):
		_held.append(code)
	elif not pressed:
		_held.erase(code)


func _release_all_keys() -> void:
	for code in _held.duplicate():
		_key(code, false)


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _drag(index: int, pos: Vector2, relative: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = pos
	ev.relative = relative
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


## Converts a point in the TouchControls' own coordinates to window coordinates.
func _to_screen(tc: Control, local: Vector2) -> Vector2:
	return tc.get_viewport().get_final_transform() * (tc.get_global_transform_with_canvas() * local)


func _start(mode_id: StringName, humans: int, cpus: int) -> MatchController:
	var setup := MatchSetup.quick(mode_id, humans, cpus)
	setup.seed = 4242
	setup.chaos_enabled = false
	tree.root.get_node("InputSetup").configure_local_players(maxi(1, humans))
	var m := await start_match(setup)
	await physics_frames(20)
	return m


# ---------------------------------------------------------------- keyboard

func test_keyboard_moves_and_jumps() -> void:
	var m := await _start(&"bounce_race", 1, 0)
	var p := m.players[0]
	check(p.input is LocalInputSource, "P1 reads the keyboard")
	var start := p.global_position
	_key(KEY_D, true)
	await physics_frames(40)
	_key(KEY_D, false)
	check(p.global_position.x > start.x + 2.0, "D moves right (%.2f m)" % (p.global_position.x - start.x))
	await physics_frames(20)
	var z0 := p.global_position.z
	_key(KEY_W, true)
	await physics_frames(30)
	_key(KEY_W, false)
	check(p.global_position.z < z0 - 1.5, "W moves forward, away from the camera")
	await physics_frames(20)
	var x0 := p.global_position.x
	_key(KEY_LEFT, true)
	await physics_frames(30)
	_key(KEY_LEFT, false)
	check(p.global_position.x < x0 - 1.5, "arrow keys also work for a single player")
	await physics_frames(20)
	check(p.is_on_floor(), "standing on the floor before jumping")
	_key(KEY_SPACE, true)
	var rose := false
	for i in 20:
		await tree.physics_frame
		if p.velocity.y > 3.0:
			rose = true
	_key(KEY_SPACE, false)
	check(rose, "Space jumps")


func test_two_people_on_one_keyboard_have_their_own_keys() -> void:
	var m := await _start(&"bounce_race", 2, 0)
	var p1 := m.players[0]
	var p2 := m.players[1]
	check((p1.input as LocalInputSource).slot == 1 and (p2.input as LocalInputSource).slot == 2, "two local slots")
	var a1 := p1.global_position
	var a2 := p2.global_position
	_key(KEY_D, true)
	await physics_frames(30)
	_key(KEY_D, false)
	check(p1.global_position.x > a1.x + 1.5, "WASD moves player 1")
	check(absf(p2.global_position.x - a2.x) < 0.05, "WASD does not move player 2")
	await physics_frames(20)
	a1 = p1.global_position
	a2 = p2.global_position
	_key(KEY_RIGHT, true)
	await physics_frames(30)
	_key(KEY_RIGHT, false)
	check(p2.global_position.x > a2.x + 1.5, "arrows move player 2")
	check(absf(p1.global_position.x - a1.x) < 0.05, "arrows do not move player 1")


func test_keyboard_interact_grabs_the_cake() -> void:
	var m := await _start(&"cake_dash", 1, 0)
	var mode := m.mode as CakeDashMode
	var p := m.players[0]
	p.teleport(mode.cake.global_position + Vector3(1.4, 0.2, 0))
	await physics_frames(20)
	check_eq(mode.get_interact_prompt(p), "GRAB", "prompt offered next to the cake")
	_key(KEY_E, true)
	await physics_frames(3)
	_key(KEY_E, false)
	await physics_frames(3)
	check(mode.cake.state == GiantCake.State.CARRIED and mode.cake.carrier == p, "E grabs the cake")


func test_controls_are_off_before_go_and_after_the_finish() -> void:
	var setup := MatchSetup.quick(&"bounce_race", 1, 0)
	setup.chaos_enabled = false
	var m := await start_match(setup, false)
	check_eq(m.phase, MatchController.Phase.INTRO, "round starts with the mission card")
	var p := m.players[0]
	var start := p.global_position
	_key(KEY_D, true)
	await physics_frames(40)
	check(absf(p.global_position.x - start.x) < 0.05, "no moving during the intro")
	_key(KEY_D, false)
	m.skip_intro()
	await physics_frames(5)
	m.request_finish(false)
	await physics_frames(5)
	check_eq(m.phase, MatchController.Phase.FINISHED, "round finished")
	var pos := p.global_position
	_key(KEY_D, true)
	await physics_frames(40)
	_key(KEY_D, false)
	check(absf(p.global_position.x - pos.x) < 0.3, "no moving after the round is over")


# ---------------------------------------------------------------- Reverse Mode

func test_reverse_mode_flips_controls_shows_a_warning_and_restores() -> void:
	var m := await _start(&"bounce_race", 1, 0)
	var p := m.players[0]
	m.chaos.force_event(&"reverse", true)
	await physics_frames(5)
	check(p.is_reversed(), "reverse active")
	check(m.hud._reverse_label.visible, "CONTROLS FLIPPED! label on screen")
	var x0 := p.global_position.x
	_key(KEY_D, true)
	await physics_frames(30)
	_key(KEY_D, false)
	check(p.global_position.x < x0 - 1.0, "D moves LEFT while reversed")
	m.chaos.end_event(&"reverse")
	await physics_frames(20)
	check(not p.is_reversed(), "controls back to normal")
	check(not m.hud._reverse_label.visible, "warning removed")
	x0 = p.global_position.x
	_key(KEY_D, true)
	await physics_frames(30)
	_key(KEY_D, false)
	check(p.global_position.x > x0 + 1.0, "D moves right again")


func test_reverse_mode_is_announced_before_controls_flip() -> void:
	var m := await _start(&"bounce_race", 1, 0)
	var p := m.players[0]
	m.chaos.force_event(&"reverse", false, 2.0)
	await physics_frames(20)  # the card pops in over a few frames
	check(m.hud.is_banner_visible(), "announcement card shown")
	check(m.hud.get_banner_title().contains("REVERSE"), "card names Reverse Mode")
	check(not p.is_reversed(), "controls still normal during the warning")
	await seconds(2.2)
	check(p.is_reversed(), "controls flip only after the countdown")


# ---------------------------------------------------------------- touch

func _touch_match(mode_id: StringName = &"cake_dash") -> MatchController:
	var gs := tree.root.get_node("GameState")
	gs.settings.touch_controls = "on"
	gs.settings.simple_controls = false
	gs.settings.left_handed = false
	gs.settings.button_scale = 1.0
	return await _start(mode_id, 1, 0)


func test_touch_stick_and_jump_button() -> void:
	var m := await _touch_match(&"bounce_race")
	var tc := m.touch_controls
	check(tc.visible, "touch controls shown when switched on")
	var pts := tc.get_layout_points()
	var p := m.players[0]
	var start := p.global_position
	var rest: Vector2 = pts.stick_rest
	var r: float = pts.stick_radius
	_touch(0, _to_screen(tc, rest), true)
	_drag(0, _to_screen(tc, rest + Vector2(r, 0)), Vector2(r, 0))
	await physics_frames(2)
	check(TouchState.stick.x > 0.8, "dragging the stick right pushes it right (%.2f)" % TouchState.stick.x)
	await physics_frames(40)
	check(p.global_position.x > start.x + 2.0, "the character walks right (%.2f m)" % (p.global_position.x - start.x))
	_touch(0, _to_screen(tc, rest + Vector2(r, 0)), false)
	await physics_frames(2)
	check_eq(TouchState.stick, Vector2.ZERO, "letting go recenters the stick")
	await physics_frames(30)
	var jumped := false
	_touch(1, _to_screen(tc, pts.jump), true)
	for i in 15:
		await tree.physics_frame
		if p.velocity.y > 3.0:
			jumped = true
	_touch(1, _to_screen(tc, pts.jump), false)
	check(jumped, "the JUMP button jumps")
	check(not TouchState.jump_held, "jump released")


func test_touch_action_button_grabs_the_cake() -> void:
	var m := await _touch_match()
	var mode := m.mode as CakeDashMode
	var tc := m.touch_controls
	var p := m.players[0]
	p.teleport(mode.cake.global_position + Vector3(1.4, 0.2, 0))
	await physics_frames(20)
	check_eq(tc._prompt, "GRAB", "action button shows GRAB next to the cake")
	var pts := tc.get_layout_points()
	_touch(2, _to_screen(tc, pts.action), true)
	await physics_frames(3)
	_touch(2, _to_screen(tc, pts.action), false)
	await physics_frames(3)
	check(mode.cake.carrier == p, "tapping the action button grabs the cake")


func test_simple_controls_one_button_jumps_or_grabs() -> void:
	var gs := tree.root.get_node("GameState")
	var m := await _touch_match()
	gs.set_setting("simple_controls", true)
	await physics_frames(2)
	var mode := m.mode as CakeDashMode
	var tc := m.touch_controls
	var p := m.players[0]
	var pts := tc.get_layout_points()
	# Away from the cake the big button jumps.
	p.teleport(mode.cake.global_position + Vector3(6.0, 0.2, 0))
	await physics_frames(30)
	var jumped := false
	_touch(1, _to_screen(tc, pts.jump), true)
	for i in 15:
		await tree.physics_frame
		jumped = jumped or p.velocity.y > 3.0
	_touch(1, _to_screen(tc, pts.jump), false)
	check(jumped, "simple button jumps when there is nothing to grab")
	await physics_frames(40)
	# Next to the cake the same button grabs.
	p.teleport(mode.cake.global_position + Vector3(1.4, 0.2, 0))
	await physics_frames(20)
	_touch(1, _to_screen(tc, pts.jump), true)
	await physics_frames(3)
	_touch(1, _to_screen(tc, pts.jump), false)
	await physics_frames(3)
	check(mode.cake.carrier == p, "simple button grabs next to the cake")


func test_left_handed_layout_mirrors_the_controls() -> void:
	var gs := tree.root.get_node("GameState")
	var m := await _touch_match(&"bounce_race")
	var tc := m.touch_controls
	var right_handed := tc.get_layout_points()
	gs.set_setting("left_handed", true)
	await physics_frames(2)
	var left_handed := tc.get_layout_points()
	check(left_handed.jump.x < tc.size.x * 0.5 and right_handed.jump.x > tc.size.x * 0.5, "jump button moves to the left")
	check(left_handed.stick_rest.x > tc.size.x * 0.5, "stick moves to the right")
	var p := m.players[0]
	var start := p.global_position
	var rest: Vector2 = left_handed.stick_rest
	_touch(0, _to_screen(tc, rest), true)
	_drag(0, _to_screen(tc, rest + Vector2(-left_handed.stick_radius, 0)), Vector2(-left_handed.stick_radius, 0))
	await physics_frames(30)
	_touch(0, _to_screen(tc, rest), false)
	check(p.global_position.x < start.x - 1.5, "the right-side stick steers")


func test_big_buttons_setting_scales_the_touch_buttons() -> void:
	var gs := tree.root.get_node("GameState")
	var m := await _touch_match(&"bounce_race")
	var tc := m.touch_controls
	var normal: float = tc._jump_radius
	gs.set_setting("button_scale", 1.25)
	await physics_frames(2)
	check_near(tc._jump_radius, normal * 1.25, 0.5, "jump button is 25% bigger")
	check(tc._jump_radius >= 100.0, "big jump button is easy to hit (%.0f px radius)" % tc._jump_radius)
