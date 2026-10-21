extends TestCase
## The buttons a player needs are completely on the screen, with no
## scrolling, on common phone and tablet shapes:
##   16:9 phone 1280x720, 20:9 phone 2400x1080 (1600x720 after scaling),
##   4:3 tablet 1024x768 (1280x960 after scaling).
## (Headless runs have no real window, so the tests set the screen size.)

const SHAPES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(2400, 1080), Vector2i(1024, 768)]

var gs: Node
var router: Node
var net: Node
var _old_size := Vector2i.ZERO


func before_each() -> void:
	gs = tree.root.get_node("GameState")
	router = tree.root.get_node("Router")
	net = tree.root.get_node("Net")
	gs.reset_to_defaults()
	gs.settings.debug_tools = true
	_old_size = tree.root.size


func after_each() -> void:
	tree.root.size = _old_size
	net.room_info = {}
	gs.reset_to_defaults()
	gs.settings.debug_tools = true
	await end_scene()


func _set_shape(shape: Vector2i) -> void:
	tree.root.size = shape
	await process_frames(3)


func _open(id: StringName) -> Node:
	router.busy = false
	router.go(id, false)
	await process_frames(8)
	return tree.current_scene


static func _text(b: Button) -> String:
	var l := b.find_child("Text", true, false) as Label
	return l.text if l else b.text


func _button(root: Node, text: String) -> Button:
	for n in root.find_children("*", "Button", true, false):
		if _text(n as Button) == text:
			return n as Button
	return null


## Checks that the buttons (found by their text or node name) are visible
## and fully inside the screen.
func _check_on_screen(root: Node, names: Array, where: String) -> void:
	var screen := tree.root.get_visible_rect()
	for what in names:
		var b := _button(root, what)
		if b == null:
			b = root.find_child(what, true, false) as Button
		if not check(b != null, "%s: button '%s' exists" % [where, what]):
			continue
		var r := b.get_global_rect()
		check(b.is_visible_in_tree() and screen.encloses(r),
				"%s: '%s' is on the screen (button %s, screen %s)" % [where, what, r, screen.size])


func test_menus_fit_every_screen_shape() -> void:
	for shape in SHAPES:
		await _set_shape(shape)
		var tag := "%dx%d" % [shape.x, shape.y]
		var menu := await _open(&"menu")
		_check_on_screen(menu, ["PLAY!", "Wardrobe", "Online (beta)", "Grown-ups"], tag + " main menu")
		var setup := await _open(&"setup")
		_check_on_screen(setup, ["START!"], tag + " party setup")


func test_online_screens_fit_every_screen_shape() -> void:
	gs.settings.online_allowed = true
	for shape in SHAPES:
		await _set_shape(shape)
		var tag := "%dx%d" % [shape.x, shape.y]
		var lobby := await _open(&"online")
		_check_on_screen(lobby, ["MakeRoom", "JoinWithCode"], tag + " online start")
		lobby._show_code_entry()
		await process_frames(3)
		var keys: Array = ["JoinButton", "DeleteKey", "Cancel"]
		for ch in NetProtocol.CODE_ALPHABET:
			keys.append("Key_" + ch)
		_check_on_screen(lobby, keys, tag + " code entry")
		# A full room, seen by the host and by a friend (made-up room data:
		# no server involved).
		net.room_info = _room(true)
		lobby._show_room()
		await process_frames(3)
		_check_on_screen(lobby, ["StartButton", "LeaveButton", "Mode_cake_dash", "Mode_button_mayhem",
				"Mode_bounce_race", "CpuToggle"], tag + " room (host)")
		net.room_info = _room(false)
		lobby._show_room()
		await process_frames(3)
		_check_on_screen(lobby, ["LeaveButton"], tag + " room (friend)")


func _room(host: bool) -> Dictionary:
	var players := []
	for i in 4:
		players.append({"label": "P%d" % (i + 1), "color": i, "connected": true, "host": i == 0,
				"you": i == (0 if host else 1),
				"look": {"character": String(Catalog.CHARACTERS[i].id), "hat": "none", "paint": "classic"}})
	return {"code": "K7QXM", "players": players, "mode": "cake_dash", "cpus": true, "state": "lobby", "host": host}


func test_pause_and_results_buttons_fit_every_screen_shape() -> void:
	var setup := MatchSetup.quick(&"cake_dash", 1, 3)
	setup.seed = 5
	var m := await start_match(setup)
	await seconds(2.0)
	for shape in SHAPES:
		await _set_shape(shape)
		var tag := "%dx%d" % [shape.x, shape.y]
		m.set_paused(true)
		await process_frames(4)
		_check_on_screen(m.pause_menu, ["Keep playing", "Start over", "Back to menu"], tag + " pause")
		m.set_paused(false)
		await process_frames(2)
	m.request_finish(true)
	var frames := 0
	while m.phase != MatchController.Phase.RESULTS and frames < 900:
		await tree.physics_frame
		frames += 1
	if not check_eq(m.phase, MatchController.Phase.RESULTS, "the round reached the results"):
		return
	# The tallest results: every player with points in every category, plus
	# three new unlocks to announce.
	var r: Dictionary = m.result.duplicate(true)
	for info in r.players:
		for cat in ScoreKeeper.CATEGORIES:
			info.breakdown[cat] = 10
	r.unlocked = Catalog.HATS.slice(1, 4)
	for online in [false, true]:
		r.online = online
		m.results_screen.show_results(r)
		for shape in SHAPES:
			await _set_shape(shape)
			var names := ["Back to the room", "Leave room"] if online else ["Play again", "Next game", "Menu"]
			_check_on_screen(m.results_screen, names, "%dx%d %s results" % [shape.x, shape.y, "online" if online else "local"])
