extends TestCase
## What the players see: every rule switch gets a card with its picture, name,
## tip and countdown BEFORE it starts, stays listed while active, and says when
## it is over. Works with the sound off (everything here is visual).


func after_each() -> void:
	await end_scene()


func _start() -> MatchController:
	var setup := MatchSetup.quick(&"cake_dash", 1, 1)
	setup.chaos_enabled = false
	setup.seed = 12
	var m := await start_match(setup)
	m.chaos.auto_schedule = false
	# Keep the CPU buddy still: these tests force all eight events one after
	# another, and a buddy delivering the cake would end the round first.
	m.players[1].input = ScriptedInputSource.new()
	await physics_frames(5)
	return m


func test_every_event_is_announced_visually_with_a_countdown() -> void:
	var m := await _start()
	var hud := m.hud
	for ev in m.chaos.library:
		check_eq(m.phase, MatchController.Phase.PLAYING, "%s: the round is still running" % ev.id)
		m.chaos.force_event(ev.id, false, 3.0)
		await physics_frames(20)
		check(hud.is_banner_visible(), "%s: card on screen during the warning" % ev.id)
		check(hud.get_banner_title().contains(ev.display_name.to_upper()), "%s: card names the event" % ev.id)
		check_eq(hud._banner_tip.text, ev.tip, "%s: card shows the tip" % ev.id)
		check_eq((hud._banner_icon as Icon).icon, ev.icon, "%s: card shows the picture" % ev.id)
		check(hud._banner_count.visible and int(hud._banner_count.text) in [2, 3], "%s: countdown number shown" % ev.id)
		check(not m.chaos.is_active(ev.id), "%s: not active during the warning" % ev.id)
		await seconds(3.0)
		check(m.chaos.is_active(ev.id), "%s: active after the countdown" % ev.id)
		check_eq(hud._banner_kicker.text, "THE RULES SWITCHED!", "%s: card says the rules switched" % ev.id)
		check(hud._chaos_rows.has(ev.id), "%s: listed while active" % ev.id)
		m.chaos.end_event(ev.id)
		await physics_frames(3)
		check(hud._toast.visible and hud._toast_label.text.contains("is over"), "%s: says when it is over" % ev.id)
		await seconds(0.6)
		check(not hud._chaos_rows.has(ev.id), "%s: removed from the list" % ev.id)


func test_card_is_not_lost_when_a_warning_is_cancelled() -> void:
	var m := await _start()
	m.chaos.force_event(&"moon", false, 3.0)
	await physics_frames(10)
	m.chaos.stop()                       # cancels the warning (fade-out starts)
	await physics_frames(2)
	m.chaos.force_event(&"penguin", true)
	await seconds(0.5)
	check(m.hud.is_banner_visible(), "the new card stays on screen")
	check(m.hud.get_banner_title().contains("PENGUIN"), "and it is the new event's card")


func test_timer_turns_urgent_near_the_end() -> void:
	var m := await _start()
	await physics_frames(2)
	check_eq(m.hud._timer_label.text, UiKit.format_time(m.time_left), "timer shows the round time")
	m.time_left = 8.0
	await physics_frames(3)
	var c: Color = m.hud._timer_label.get_theme_color("font_color")
	check(c.r > 0.9 and c.g < 0.6, "timer turns red in the last 10 seconds")


func test_objective_text_follows_the_mission() -> void:
	var m := await _start()
	await physics_frames(2)
	check_eq(m.hud._objective_label.text, "Grab the cake!", "objective line under the timer")
	var p := m.players[0]
	p.input = ScriptedInputSource.new()
	var mode := m.mode as CakeDashMode
	p.teleport(mode.cake.global_position + Vector3(1.4, 0.2, 0))
	await physics_frames(10)
	p.input.press_interact()
	await physics_frames(5)
	check_eq(m.hud._objective_label.text, "Carry the cake to the party table!", "objective updates after grabbing")
