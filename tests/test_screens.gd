extends TestCase
## Every menu screen opens without errors and its main buttons do what they say.

var gs: Node
var router: Node


func before_each() -> void:
	gs = tree.root.get_node("GameState")
	router = tree.root.get_node("Router")
	gs.reset_to_defaults()
	gs.settings.debug_tools = true


func after_each() -> void:
	gs.reset_to_defaults()
	gs.settings.debug_tools = true
	await end_scene()


## Opens a screen through the Router and waits for it.
func _open(id: StringName) -> Node:
	router.busy = false
	router.go(id, false)
	await process_frames(6)
	return tree.current_scene


## Waits until the Router finished a (faded) screen change.
func _wait_router() -> void:
	for i in 120:
		await tree.process_frame
		if not router.busy:
			break
	await process_frames(3)


static func _button_text(b: Button) -> String:
	var l := b.find_child("Text", true, false) as Label
	return l.text if l else b.text


func _find_button(root: Node, text: String) -> Button:
	for n in root.find_children("*", "Button", true, false):
		var b := n as Button
		if _button_text(b) == text:
			return b
	return null


func test_every_screen_opens_cleanly() -> void:
	for id: StringName in router.SCENES:
		if id == &"match":
			continue
		var scene := await _open(id)
		if check(scene != null, "screen %s opened" % id):
			check_eq(scene.scene_file_path, router.SCENES[id], "screen %s is the right scene" % id)
		await process_frames(20)


func test_main_menu_play_goes_to_party_setup() -> void:
	var menu := await _open(&"menu")
	var play := _find_button(menu, "PLAY!")
	if not check(play != null, "PLAY! button exists"):
		return
	check(play.custom_minimum_size.y >= 100.0, "PLAY! is a big button")
	play.pressed.emit()
	await _wait_router()
	check_eq(tree.current_scene.scene_file_path, router.SCENES[&"setup"], "PLAY! opens party setup")


func test_party_setup_builds_the_chosen_match() -> void:
	var setup_screen := await _open(&"setup")
	var setup: MatchSetup = setup_screen.build_setup()
	check_eq(setup.slots.size(), 4, "4 players by default")
	check_eq(setup.slots[0].kind, MatchSetup.Kind.HUMAN, "P1 is a person")
	check_eq(setup.human_count(), 1, "others are CPU buddies by default")
	var two := _find_button(setup_screen, "2 players")
	two.pressed.emit()
	await process_frames(2)
	setup = setup_screen.build_setup()
	check_eq(setup.slots.size(), 2, "2 players chosen")
	# Switch P2 to a person sharing the keyboard.
	var person := _find_button(setup_screen, "CPU")
	person.pressed.emit()
	await process_frames(2)
	setup = setup_screen.build_setup()
	check_eq(setup.human_count(), 2, "P2 switched to a person")
	check_eq(setup.slots[1].local_index, 2, "P2 uses the second control set")
	check(setup_screen._note.text.contains("arrow keys"), "the screen explains P2's keys")
	# Chaos Party plays all three games.
	for b in setup_screen.find_children("*", "Button", true, false):
		if (b as Button).toggle_mode and b.find_child("*", true, false) and setup_screen._mode_buttons.get(&"party") == b:
			(b as Button).pressed.emit()
	await process_frames(2)
	setup = setup_screen.build_setup()
	check_eq(setup.playlist, [&"cake_dash", &"button_mayhem", &"bounce_race"], "Chaos Party playlist")
	# Rules.
	setup_screen._chaos_btn.pressed.emit()
	setup = setup_screen.build_setup()
	check(not setup.chaos_enabled, "chaos can be switched off")
	setup_screen._length_btn.pressed.emit()
	setup = setup_screen.build_setup()
	check_near(setup.round_time, 60.0, 0.01, "quick rounds are 60 seconds")
	# START opens the match with that setup.
	setup_screen._start.pressed.emit()
	await _wait_router()
	var m := tree.current_scene as MatchController
	if check(m != null, "START opens a match"):
		check_eq(m.players.size(), 2, "match has the chosen 2 players")
		check_eq(m.setup.mode_id, &"cake_dash", "Chaos Party starts with Cake Dash")
		check(not m.setup.chaos_enabled, "match uses the chosen rules")


func test_party_setup_remembers_choices() -> void:
	var setup_screen := await _open(&"setup")
	_find_button(setup_screen, "3 players").pressed.emit()
	(setup_screen._mode_buttons[&"bounce_race"] as Button).pressed.emit()
	setup_screen._go_back()
	await _wait_router()
	setup_screen = await _open(&"setup")
	var setup: MatchSetup = setup_screen.build_setup()
	check_eq(setup.slots.size(), 3, "player count remembered")
	check_eq(setup.mode_id, &"bounce_race", "game remembered")


func test_wardrobe_explains_locked_items_and_equips_earned_ones() -> void:
	var w := await _open(&"wardrobe")
	w._show_tab(w.Tab.HATS)
	await process_frames(2)
	var crown_btn: Button = w._items[&"crown"]
	crown_btn.pressed.emit()
	check(w._detail_label.text.contains("Finish 3 races"), "locked crown explains its goal: %s" % w._detail_label.text)
	check_eq(gs.profile.hat, &"none", "locked crown not equipped")
	gs.record_round({"races_finished": 3})
	w._show_tab(w.Tab.HATS)
	await process_frames(2)
	(w._items[&"crown"] as Button).pressed.emit()
	check_eq(gs.profile.hat, &"crown", "earned crown equipped")
	w._show_tab(w.Tab.CHARACTERS)
	await process_frames(2)
	(w._items[&"sunny"] as Button).pressed.emit()
	check_eq(gs.profile.character, &"sunny", "character picked")
	check_eq(gs.profile.hat, &"crown", "hat kept when switching character")


func test_settings_change_and_save_options() -> void:
	var s := await _open(&"settings")
	var muted: bool = gs.get_setting("muted")
	(s._rows["muted"] as Button).pressed.emit()
	check(gs.get_setting("muted") != muted, "sound toggle works")
	(s._rows["touch_controls"] as Button).pressed.emit()
	check_eq(gs.get_setting("touch_controls"), "on", "touch buttons cycle auto -> on")
	(s._rows["button_scale"] as Button).pressed.emit()
	check_near(float(gs.get_setting("button_scale")), 1.25, 0.001, "big buttons")
	(s._rows["reduced_motion"] as Button).pressed.emit()
	check(bool(gs.get_setting("reduced_motion")), "calm camera on")
	gs.record_round({"stars": 5})
	s._ask_reset()
	await process_frames(2)
	_find_button(s._confirm, "Keep my progress").pressed.emit()
	await process_frames(2)
	check_eq(int(gs.stats.stars), 5, "keeping progress keeps it")
	s._ask_reset()
	await process_frames(2)
	_find_button(s._confirm, "Reset").pressed.emit()
	await process_frames(2)
	check_eq(int(gs.stats.stars), 0, "reset clears progress")
	check(bool(gs.get_setting("reduced_motion")), "reset keeps settings")


func test_grown_up_gate_guards_online_play() -> void:
	var page := await _open(&"parents")
	check(not bool(gs.get_setting("online_allowed")), "online play starts switched off")
	page._online_btn.pressed.emit()
	await process_frames(3)
	var gate: GrownUpGate = null
	for c in page.get_children():
		if c is GrownUpGate:
			gate = c
	if not check(gate != null, "switching online on asks a grown-up first"):
		return
	check(gate.answer >= 36, "the question is a two-digit multiplication (%d)" % gate.answer)
	for d in str(gate.answer + 1):
		gate._type(d)
	gate._check()
	check(not bool(gs.get_setting("online_allowed")), "a wrong answer does not switch it on")
	for d in str(gate.answer):
		gate._type(d)
	gate._check()
	await process_frames(2)
	check(bool(gs.get_setting("online_allowed")), "the right answer switches online play on")
	page._online_btn.pressed.emit()
	check(not bool(gs.get_setting("online_allowed")), "switching it off needs no check")


func test_online_code_entry_and_server_address() -> void:
	gs.settings.online_allowed = true
	var lobby := await _open(&"online")
	lobby._show_code_entry()
	await process_frames(2)
	var join := lobby.find_child("JoinButton", true, false) as Button
	if not check(join != null, "the code screen has a Join! button"):
		return
	check(join.disabled, "Join! starts switched off")
	for ch in "B0OC7":  # 0 and O are look-alikes, so codes never use them
		lobby._type(ch)
	check_eq(lobby._code_typed, "BC7", "characters that are not in codes are ignored")
	for ch in "KMQ":
		lobby._type(ch)
	check_eq(lobby._code_typed, "BC7KM", "a code has at most 5 characters")
	check(not join.disabled, "Join! lights up with all 5")
	lobby._delete()
	check(join.disabled, "deleting one switches Join! off again")
	for good in ["192.168.1.20", "game.example.org", "10.0.0.5:7777"]:
		check(lobby.is_valid_server_address(good), "server address %s is accepted" % good)
	for bad in ["", "http://x.org", "a b", "x:99999", "x:0", "host:port"]:
		check(not lobby.is_valid_server_address(bad), "server address '%s' is refused" % bad)
