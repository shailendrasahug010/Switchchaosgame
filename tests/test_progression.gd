extends TestCase
## Local save data, earned cosmetics and fair-play rules for scoring.

const TEST_SAVE := "user://test_save_progression.json"

var gs: Node


func before_each() -> void:
	gs = tree.root.get_node("GameState")
	gs.reset_to_defaults()
	gs.save_path = TEST_SAVE
	gs.persist_enabled = true
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))


func after_each() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	gs.persist_enabled = false
	gs.save_path = gs.DEFAULT_SAVE_PATH
	gs.reset_to_defaults()
	gs.settings.debug_tools = true


# ---------------------------------------------------------------- save data

func test_new_player_starts_with_basics_unlocked() -> void:
	check(gs.is_unlocked(&"none") and gs.is_unlocked(&"classic"), "no hat and classic colors are free")
	check(not gs.is_unlocked(&"crown"), "the crown has to be earned")
	check_eq(int(gs.stats.rounds_played), 0, "no rounds yet")


func test_save_and_load_round_trip() -> void:
	gs.set_setting("sfx_volume", 0.3)
	gs.set_setting("left_handed", true)
	gs.record_round({"stars": 6, "party_points": 900, "cakes_delivered": 1, "mode_id": &"cake_dash", "best_time": 41.25})
	gs.set_profile(&"mossy", &"party_hat", &"classic")
	check(FileAccess.file_exists(TEST_SAVE), "save file written")
	# Wipe the in-memory state, then load it back from disk.
	gs.reset_to_defaults()
	check(not gs.is_unlocked(&"party_hat"), "memory cleared before loading")
	gs.load_game()
	check_near(float(gs.get_setting("sfx_volume")), 0.3, 0.001, "volume restored")
	check(bool(gs.get_setting("left_handed")), "left-handed restored")
	check_eq(int(gs.stats.rounds_played), 1, "rounds restored")
	check_eq(int(gs.stats.stars), 6, "stars restored")
	check(gs.is_unlocked(&"party_hat") and gs.is_unlocked(&"bow") and gs.is_unlocked(&"chef_hat"), "earned items restored")
	check_eq(gs.profile.character, &"mossy", "chosen character restored")
	check_eq(gs.profile.hat, &"party_hat", "chosen hat restored")
	check_near(float(gs.stats.best_times.cake_dash), 41.25, 0.01, "best time restored")


func test_save_file_holds_no_personal_data() -> void:
	gs.record_round({"stars": 2, "party_points": 100})
	var text := FileAccess.get_file_as_string(TEST_SAVE)
	var data: Dictionary = JSON.parse_string(text)
	var allowed := ["version", "settings", "stats", "unlocked", "profile", "last_player_count", "last_human_count", "party"]
	for key in data:
		check(allowed.has(key), "save only holds game data (found '%s')" % key)
	for word in ["name", "email", "birth", "age", "location", "address", "phone", "device_id", "advert"]:
		check(not text.to_lower().contains("\"%s" % word), "no '%s' field in the save" % word)


func test_broken_save_file_starts_fresh_without_crashing() -> void:
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string("{ this is not json ][")
	f = null
	gs.reset_to_defaults()
	gs.load_game()
	check_eq(int(gs.stats.rounds_played), 0, "broken save ignored")
	check(gs.is_unlocked(&"classic"), "defaults still usable")
	check(FileAccess.file_exists(TEST_SAVE + ".broken"), "damaged file kept aside")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE + ".broken"))


func test_old_save_gets_new_settings_defaults() -> void:
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "settings": {"muted": true}, "stats": {"stars": 3}}))
	f = null
	gs.reset_to_defaults()
	gs.load_game()
	check(bool(gs.get_setting("muted")), "old setting kept")
	check(gs.settings.has("reduced_motion"), "new settings get defaults")
	check_eq(int(gs.stats.stars), 3, "old stats kept")


func test_reset_progress_keeps_settings() -> void:
	gs.set_setting("music_volume", 0.2)
	gs.record_round({"stars": 30, "party_points": 9000})
	check(gs.is_unlocked(&"headphones"), "headphones earned")
	gs.reset_progress()
	check(not gs.is_unlocked(&"headphones"), "earned items cleared")
	check_eq(int(gs.stats.stars), 0, "stars cleared")
	check_near(float(gs.get_setting("music_volume")), 0.2, 0.001, "settings kept")


# ---------------------------------------------------------------- unlocks

func test_cosmetics_unlock_exactly_at_their_visible_goals() -> void:
	var crown: Dictionary = Catalog.hat(&"crown")
	check_eq(crown.unlock, {"races_finished": 3}, "crown goal: finish 3 races")
	gs.record_round({"races_finished": 1})
	gs.record_round({"races_finished": 1})
	check(not gs.is_unlocked(&"crown"), "not yet after 2 races")
	check_near(gs.unlock_progress(crown), 2.0 / 3.0, 0.01, "progress bar at 2/3")
	check(gs.unlock_rule_text(crown).contains("(2/3)"), "goal text shows progress: %s" % gs.unlock_rule_text(crown))
	var newly: Array = gs.record_round({"races_finished": 1})
	check(gs.is_unlocked(&"crown"), "unlocked on the third race")
	check(newly.any(func(i: Dictionary) -> bool: return i.id == &"crown"), "reported as new for the results screen")


func test_every_cosmetic_has_a_play_goal_and_no_price() -> void:
	for item in Catalog.all_cosmetics():
		for key in item.unlock:
			check(key in ["rounds_played", "stars", "party_points", "cakes_delivered", "buttons_pressed", "races_finished"],
					"%s unlocks through play (%s)" % [item.id, key])
		check(not item.has("price") and not item.has("cost") and not item.has("chance"), "%s has no price or random chance" % item.id)


func test_locked_items_cannot_be_equipped() -> void:
	gs.set_profile(&"jelly", &"top_hat", &"midnight")
	check_eq(gs.profile.character, &"jelly", "characters are always free")
	check_eq(gs.profile.hat, &"none", "a locked hat is not equipped")
	check_eq(gs.profile.paint, &"classic", "a locked color is not equipped")


func test_cosmetics_never_change_how_characters_play() -> void:
	var world := make_flat_world()
	tree.root.add_child(world)
	var looks := [[&"bloop", &"none", &"classic"], [&"jelly", &"crown", &"grape"], [&"mossy", &"top_hat", &"midnight"],
			[&"sunny", &"headphones", &"sunset"]]
	var results: Array[Vector3] = []
	for i in looks.size():
		var p := spawn_test_player(world, Vector3(i * 6.0 - 9.0, 0.1, 0), null)
		await p.setup_look(looks[i][0], looks[i][1], looks[i][2], Color.WHITE, "P")
		check_near(p.collision.shape.radius, p.base_radius, 0.0001, "%s: same body size" % looks[i][0])
	await physics_frames(10)
	var players: Array[PlayerCharacter] = []
	for n in world.get_children():
		if n is PlayerCharacter:
			players.append(n)
	var starts: Array[Vector3] = []
	for p in players:
		starts.append(p.global_position)
		p.input.move = Vector2(0, -1)
		p.input.press_jump()
		p.input.jump_held = true
	await physics_frames(50)
	for i in players.size():
		results.append(players[i].global_position - starts[i])
	for i in range(1, results.size()):
		check(results[i].distance_to(results[0]) < 0.01, "character %d moves exactly like character 1" % (i + 1))
	world.queue_free()


# ---------------------------------------------------------------- fair scoring

func test_scores_never_go_below_zero() -> void:
	var s := ScoreKeeper.new()
	s.reset(2)
	s.add(0, ScoreKeeper.OBJECTIVE, 50)
	s.add(0, ScoreKeeper.OBJECTIVE, -500)
	check_eq(s.total(0), 0, "no negative scores")
	s.add(1, &"pushing_people", 100)
	check_eq(s.category_points(1, ScoreKeeper.OBJECTIVE), 100, "unknown categories can't create new ways to score")


func test_only_positive_categories_exist() -> void:
	for c in ScoreKeeper.CATEGORIES:
		check(c in [&"objective", &"stars", &"teamwork", &"recovery", &"time"], "scoring category %s is a positive action" % c)


func test_players_pass_through_each_other() -> void:
	var world := make_flat_world()
	tree.root.add_child(world)
	var a := spawn_test_player(world, Vector3(0, 0.1, 0), null)
	var b := spawn_test_player(world, Vector3(2.5, 0.1, 0), null)
	await physics_frames(10)
	check_eq(a.collision_mask & Layers.PLAYERS, 0, "players do not collide with players")
	a.input.move = Vector2(1, 0)
	await physics_frames(60)
	check(a.global_position.x > b.global_position.x, "a runs right through b")
	check(absf(b.global_position.x - 2.5) < 0.01, "b is not pushed (nobody can shove others off the course)")
	world.queue_free()
