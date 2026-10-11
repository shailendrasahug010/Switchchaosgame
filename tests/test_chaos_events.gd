extends TestCase
## The Chaos Switch event manager: every event on its own, expiry and cleanup,
## overlapping events, exclusive groups, scheduling rules and remote commands.
##
## Behaviour checks drive a real PlayerCharacter on a flat floor with scripted
## input, so they test what a player actually feels, not just the numbers.

const DT := 1.0 / 60.0

var world: Node3D
var chaos: ChaosManager
var player: PlayerCharacter


func before_each() -> void:
	world = make_flat_world(Vector3(400, 2, 400))
	tree.root.add_child(world)
	chaos = ChaosManager.new()
	chaos.auto_schedule = false
	world.add_child(chaos)
	player = spawn_test_player(world, Vector3(0, 0.1, 0), chaos.rules)
	await physics_frames(10)


func after_each() -> void:
	if is_instance_valid(world):
		world.queue_free()
	await process_frames(2)


# ---------------------------------------------------------------- helpers

func _reset_player() -> void:
	var input := player.input
	input.reset()
	player.teleport(Vector3(0, 0.1, 0))
	await physics_frames(30)  # let size springs and landings settle


## Runs the player with a held stick (and optionally one jump) and returns
## how far it went, its highest point and how far it slid after letting go.
func _run(stick: Vector2, seconds: float, jump: bool = false, release_for: float = 0.0) -> Dictionary:
	await _reset_player()
	var start := player.global_position
	var max_y := start.y
	player.input.move = stick
	if jump:
		player.input.press_jump()
		player.input.jump_held = true
	var frames := int(seconds * 60.0)
	for i in frames:
		await tree.physics_frame
		max_y = maxf(max_y, player.global_position.y)
	var moved := player.global_position - start
	player.input.move = Vector2.ZERO
	player.input.jump_held = false
	var at_release := player.global_position
	for i in int(release_for * 60.0):
		await tree.physics_frame
		max_y = maxf(max_y, player.global_position.y)
	var slide := Vector2(player.global_position.x - at_release.x, player.global_position.z - at_release.z).length()
	return {"dx": moved.x, "dz": moved.z, "max_rise": max_y - start.y, "max_y": max_y, "slide": slide}


func _baseline_rules_ok(label: String) -> void:
	for stat_name: StringName in [&"gravity", &"speed", &"jump", &"traction", &"size", &"push", &"air_control"]:
		check_near(player.stat(stat_name), 1.0, 0.0001, "%s: %s multiplier back to 1" % [label, stat_name])
	check_near(player.stat_max(&"floor_bounce", 0.0), 0.0, 0.0001, "%s: no trampoline floor" % label)
	check_near(player.stat_max(&"waddle", 0.0), 0.0, 0.0001, "%s: no waddle" % label)
	check(not player.is_reversed(), "%s: controls not reversed" % label)
	check(chaos.rules.is_empty(), "%s: rule stack empty" % label)


# ---------------------------------------------------------------- every event on its own

func test_library_has_eight_valid_events() -> void:
	var ids := {}
	for ev in chaos.library:
		check(ev.id != &"", "event has an id")
		check(not ids.has(ev.id), "event id %s is unique" % ev.id)
		ids[ev.id] = true
		check(ev.display_name != "" and ev.tip != "" and ev.tagline != "", "%s has name, tagline and tip" % ev.id)
		check(ev.duration >= 5.0 and ev.duration <= 20.0, "%s lasts a sensible time (%.1fs)" % [ev.id, ev.duration])
		check(not ev.modifiers.is_empty(), "%s changes something" % ev.id)
		check(ev.icon != &"", "%s has an icon for the announcement" % ev.id)
	for want: StringName in [&"penguin", &"moon", &"slippery", &"giant", &"bounce", &"reverse", &"tiny", &"sticky"]:
		check(ids.has(want), "event %s exists" % want)


func test_each_event_changes_play_and_restores_it() -> void:
	# Baselines with no chaos.
	var walk := await _run(Vector2(1, 0), 1.2)
	var hop := await _run(Vector2.ZERO, 1.2, true)
	var stop := await _run(Vector2(1, 0), 1.0, false, 1.0)
	var idle := await _run(Vector2.ZERO, 1.5)
	note("baseline: walk %.2f m, jump %.2f m, slide %.2f m, idle rise %.2f m" % [walk.dx, hop.max_rise, stop.slide, idle.max_rise])
	check(walk.dx > 6.0, "baseline: player walks right")
	check(hop.max_rise > 1.2 and hop.max_rise < 2.4, "baseline: a normal jump height")
	check(idle.max_rise < 0.05, "baseline: standing still stays on the floor")

	for ev in chaos.library:
		var id: StringName = ev.id
		check(chaos.force_event(id, true), "%s can be forced" % id)
		check(chaos.is_active(id), "%s is active" % id)
		await physics_frames(40)
		var effect: Dictionary
		match id:
			&"moon":
				effect = await _run(Vector2.ZERO, 2.4, true)
				check(effect.max_rise > hop.max_rise * 1.6, "moon: jumps go much higher (%.2f vs %.2f)" % [effect.max_rise, hop.max_rise])
			&"penguin":
				effect = await _run(Vector2(1, 0), 1.2)
				check(effect.dx < walk.dx * 0.85, "penguin: waddling is slower (%.2f vs %.2f)" % [effect.dx, walk.dx])
				check(player.stat_max(&"waddle") > 0.0, "penguin: waddle flag set")
			&"slippery":
				effect = await _run(Vector2(1, 0), 1.0, false, 1.0)
				check(effect.slide > stop.slide * 3.0 and effect.slide > 1.0,
						"slippery: sliding after letting go (%.2f vs %.2f)" % [effect.slide, stop.slide])
			&"giant":
				await physics_frames(30)
				check_near(player.size_scale, 1.75, 0.08, "giant: player grows")
				check(player.collision.shape.radius > player.base_radius * 1.6, "giant: collision grows too")
			&"tiny":
				await physics_frames(30)
				check_near(player.size_scale, 0.5, 0.05, "tiny: player shrinks")
				check(player.collision.shape.radius < player.base_radius * 0.6, "tiny: collision shrinks too")
			&"bounce":
				effect = await _run(Vector2.ZERO, 1.5)
				check(effect.max_y > 0.8, "bounce: the floor bounces you without jumping (%.2f m)" % effect.max_y)
			&"reverse":
				effect = await _run(Vector2(1, 0), 1.0)
				check(effect.dx < -3.0, "reverse: pushing right moves left (%.2f)" % effect.dx)
				check(player.is_reversed(), "reverse: flag set")
			&"sticky":
				effect = await _run(Vector2(1, 0), 1.2)
				check(effect.dx < walk.dx * 0.65, "sticky: much slower (%.2f vs %.2f)" % [effect.dx, walk.dx])
		chaos.end_event(id)
		check(not chaos.is_active(id), "%s ended" % id)
		await physics_frames(45)
		_baseline_rules_ok("after %s" % id)
		check_near(player.size_scale, 1.0, 0.03, "after %s: normal size" % id)
		var walk2 := await _run(Vector2(1, 0), 1.2)
		check_near(walk2.dx, walk.dx, 0.25, "after %s: walking feels normal again" % id)
		var hop2 := await _run(Vector2.ZERO, 1.2, true)
		check_near(hop2.max_rise, hop.max_rise, 0.08, "after %s: jumping feels normal again" % id)


func test_events_expire_on_their_own() -> void:
	chaos.force_event(&"moon", true)
	var duration: float = chaos.find_event(&"moon").duration
	await seconds(duration - 0.5)
	check(chaos.is_active(&"moon"), "moon still active just before its time is up")
	await seconds(0.7)
	check(not chaos.is_active(&"moon"), "moon ended after %.1f seconds" % duration)
	_baseline_rules_ok("moon expiry")


# ---------------------------------------------------------------- overlaps

func test_overlapping_events_restore_the_right_baseline() -> void:
	chaos.max_active = 3
	chaos.force_event(&"moon", true)
	chaos.force_event(&"giant", true)
	check(chaos.is_active(&"moon") and chaos.is_active(&"giant"), "moon and giant run together")
	check_near(player.stat(&"gravity"), 0.45, 0.0001, "moon gravity while giant runs")
	check_near(player.stat(&"jump"), 1.15, 0.0001, "giant jump bonus while moon runs")
	chaos.end_event(&"moon")
	check_near(player.stat(&"gravity"), 1.0, 0.0001, "gravity back to normal after moon, giant still on")
	check_near(player.stat(&"size"), 1.75, 0.0001, "giant size kept after moon ended")
	chaos.force_event(&"reverse", true)
	chaos.force_event(&"sticky", true)
	check_near(player.stat(&"speed"), 1.1 * 0.5, 0.0001, "speed multipliers combine (giant x sticky)")
	check(player.is_reversed(), "reverse active alongside others")
	chaos.end_event(&"giant")
	check_near(player.stat(&"size"), 1.0, 0.0001, "size normal after giant")
	check_near(player.stat(&"speed"), 0.5, 0.0001, "sticky speed remains after giant ends")
	chaos.end_event(&"reverse")
	check(not player.is_reversed(), "controls normal after reverse ends")
	chaos.end_event(&"sticky")
	_baseline_rules_ok("after the overlap chain")


func test_forcing_an_active_event_again_does_not_stack() -> void:
	chaos.force_event(&"moon", true)
	await seconds(2.0)
	chaos.force_event(&"moon", true)
	check_near(player.stat(&"gravity"), 0.45, 0.0001, "moon applied once, not twice")
	var left: float = chaos.get_active_entries()[0].left
	check(left > chaos.find_event(&"moon").duration - 0.2, "timer refreshed")
	chaos.end_all_events()
	_baseline_rules_ok("after refreshed moon")


func test_exclusive_groups_never_overlap() -> void:
	chaos.max_active = 4
	chaos.force_event(&"giant", true)
	chaos.force_event(&"tiny", true)
	check(not chaos.is_active(&"giant"), "giant ends when tiny starts (same size group)")
	check_near(player.stat(&"size"), 0.5, 0.0001, "tiny size, not giant x tiny")
	chaos.force_event(&"bounce", true)
	chaos.force_event(&"slippery", true)
	check(not chaos.is_active(&"bounce"), "bounce ends when slippery starts (same floor group)")
	check(chaos.is_active(&"tiny") and chaos.is_active(&"slippery"), "different groups can share")
	chaos.end_all_events()
	_baseline_rules_ok("after exclusive groups")


func test_max_active_is_respected() -> void:
	chaos.max_active = 2
	chaos.force_event(&"moon", true)
	await seconds(1.0)
	chaos.force_event(&"giant", true)
	chaos.force_event(&"reverse", true)
	check_eq(chaos.get_active_ids().size(), 2, "never more than max_active events")
	check(not chaos.is_active(&"moon"), "the event closest to finishing made room")
	chaos.stop()
	_baseline_rules_ok("after stop")


func test_stop_cancels_the_announcement_and_clears_rules() -> void:
	var cancelled: Array[StringName] = []
	chaos.announcement_cancelled.connect(func(ev: ChaosEvent) -> void: cancelled.append(ev.id))
	chaos.force_event(&"giant", true)
	chaos.force_event(&"moon", false, 2.0)
	check(chaos.get_pending_event() != null, "moon is being announced")
	chaos.stop()
	check(cancelled.has(&"moon"), "announcement cancelled on stop")
	check(chaos.get_pending_event() == null, "nothing pending after stop")
	check(chaos.get_active_ids().is_empty(), "nothing active after stop")
	_baseline_rules_ok("after stop")


# ---------------------------------------------------------------- scheduling

func test_scheduler_announces_first_and_avoids_repeats() -> void:
	chaos.auto_schedule = true
	var events_log: Array[Dictionary] = []
	var t := [0.0]
	chaos.event_announced.connect(func(ev: ChaosEvent, lead: float) -> void:
		events_log.append({"kind": "announce", "id": ev.id, "t": t[0], "lead": lead}))
	chaos.countdown_changed.connect(func(ev: ChaosEvent, secs: int) -> void:
		events_log.append({"kind": "count", "id": ev.id, "t": t[0], "secs": secs}))
	chaos.event_started.connect(func(ev: ChaosEvent) -> void: events_log.append({"kind": "start", "id": ev.id, "t": t[0]}))
	chaos.event_ended.connect(func(ev: ChaosEvent) -> void: events_log.append({"kind": "end", "id": ev.id, "t": t[0]}))
	chaos.start(2024)
	var max_seen := 0
	var clash := ""
	for i in int(240.0 * 60.0):
		await tree.physics_frame
		t[0] += DT
		var ids := chaos.get_active_ids()
		max_seen = maxi(max_seen, ids.size())
		for a in ids:
			for b in ids:
				if a != b and not chaos.find_event(a).can_coexist_with(chaos.find_event(b)):
					clash = "%s+%s" % [a, b]
	chaos.stop()
	var starts := events_log.filter(func(e: Dictionary) -> bool: return e.kind == "start")
	note("%d events in 240 s: %s" % [starts.size(), str(starts.map(func(e: Dictionary) -> String: return String(e.id)))])
	check(starts.size() >= 12, "events keep coming during a long session")
	check(max_seen <= chaos.max_active, "never more than %d events at once (saw %d)" % [chaos.max_active, max_seen])
	check(clash == "", "no incompatible events together (%s)" % clash)
	# Every start was announced with a countdown, at least announce_time earlier.
	for s: Dictionary in starts:
		var announce: Dictionary = {}
		for e: Dictionary in events_log:
			if e.t > s.t:
				break
			if e.kind == "announce" and e.id == s.id:
				announce = e
		if check(not announce.is_empty(), "%s announced before starting" % s.id):
			check(s.t - float(announce.t) >= chaos.announce_time - 0.05,
					"%s warned %.2f s ahead" % [s.id, s.t - float(announce.t)])
			var counts := events_log.filter(func(e: Dictionary) -> bool:
				return e.kind == "count" and e.id == s.id and e.t >= announce.t and e.t <= s.t)
			check(counts.size() >= 3, "%s had a visible countdown" % s.id)
	# No immediate repeats, and the last two are avoided when others are free.
	for i in range(1, starts.size()):
		check(starts[i].id != starts[i - 1].id, "no back-to-back repeat at #%d (%s)" % [i, starts[i].id])
	_baseline_rules_ok("after a long session")


func test_enabled_list_is_respected() -> void:
	chaos.auto_schedule = true
	chaos.enabled_ids = [&"moon", &"tiny"]
	var started: Array[StringName] = []
	chaos.event_started.connect(func(ev: ChaosEvent) -> void: started.append(ev.id))
	chaos.start(7)
	await seconds(90.0)
	chaos.stop()
	note("started: %s" % str(started))
	check(started.size() >= 4, "events happen with a short list")
	for id in started:
		check(id == &"moon" or id == &"tiny", "only enabled events start (%s)" % id)


func test_same_seed_gives_the_same_events() -> void:
	var runs: Array = []
	for r in 2:
		var picks: Array[StringName] = []
		chaos.auto_schedule = true
		var cb := func(ev: ChaosEvent) -> void: picks.append(ev.id)
		chaos.event_started.connect(cb)
		chaos.start(31337)
		await seconds(60.0)
		chaos.stop()
		chaos.event_started.disconnect(cb)
		runs.append(picks)
	check(not (runs[0] as Array).is_empty(), "events happened")
	check_eq(runs[1], runs[0], "a seed repeats the same sequence (needed for online play and replays)")


# ---------------------------------------------------------------- online clients

func test_remote_commands_drive_a_client_manager() -> void:
	chaos.is_authority = false
	chaos.auto_schedule = true
	chaos.apply_remote(&"moon", "announce", 2.0)
	check(chaos.get_pending_event() != null, "client shows the announcement")
	await seconds(3.0)
	check(not chaos.is_active(&"moon"), "a client never starts an event by itself")
	chaos.apply_remote(&"moon", "start", 12.0)
	check(chaos.is_active(&"moon"), "server start command applies the event")
	check_near(player.stat(&"gravity"), 0.45, 0.0001, "moon rules on the client")
	chaos.apply_remote(&"moon", "end")
	check(not chaos.is_active(&"moon"), "server end command removes it")
	_baseline_rules_ok("client after end")
	# If the end command is lost, the client cleans up shortly after the duration.
	chaos.apply_remote(&"tiny", "start", 1.0)
	await seconds(1.2)
	check(chaos.is_active(&"tiny"), "client waits briefly for the server's end")
	await seconds(1.6)
	check(not chaos.is_active(&"tiny"), "client ends a stale event by itself")
	_baseline_rules_ok("client after a lost end command")
