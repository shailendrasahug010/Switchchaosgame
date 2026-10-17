extends SceneTree
## Generates the arena scenes in res://scenes/arenas/ from code blueprints.
##
##   godot --headless --path . -s tools/build_arenas.gd             (all arenas)
##   godot --headless --path . -s tools/build_arenas.gd -- cake_dash
##
## WARNING: re-running overwrites the .tscn files. Once you start editing an
## arena by hand in the Godot editor, treat the .tscn as the source of truth
## and stop regenerating it (or copy your changes back into this script).

const BP := preload("res://tools/blueprint.gd")


var _done := false


# Building waits for the first frame: baking navigation needs a running tree.
func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_build_requested()
	return false


func _build_requested() -> void:
	var which := OS.get_cmdline_user_args()
	if which.is_empty() or which.has("cake_dash"):
		build_cake_dash()
	if which.is_empty() or which.has("button_mayhem"):
		if has_method("build_button_mayhem"):
			call("build_button_mayhem")
	if which.is_empty() or which.has("bounce_race"):
		if has_method("build_bounce_race"):
			call("build_bounce_race")
	quit()


func _mode_root(script_path: String, name: String) -> Node3D:
	var root := Node3D.new()
	root.name = name
	root.set_script(load(script_path))
	return root


# =====================================================================
# Cake Dash: bakery -> Sprinkle Street -> Frosting River -> Jelly Hills
#            -> Tea Party -> party table. The course runs toward -Z.
# =====================================================================

func build_cake_dash() -> void:
	var root := _mode_root("res://scripts/modes/cake_dash/cake_dash_mode.gd", "CakeDash")
	root.set("mode_id", &"cake_dash")
	root.set("mission_title", "Cake Dash")
	root.set("mission_text", "Carry the giant birthday cake to the party table. Don't let it wobble off!")
	root.set("mission_icon", &"cake")
	root.set("round_time", 90.0)
	root.set("team_mode", true)
	root.set("kill_height", -8.0)
	root.set("camera_pitch", -40.0)
	root.set("camera_distance", 11.0)
	root.set("camera_min_distance", 9.0)
	root.set("camera_max_distance", 19.0)
	root.set("camera_look_ahead", Vector3(0, 0, -2))

	var env := ToyEnvironment.new()
	env.name = "Environment"
	env.style = ToyEnvironment.Style.CANDY
	root.add_child(env)

	var level := BP.group_node(root, "Level")
	var obstacles := BP.group_node(root, "Obstacles")
	var pickups := BP.group_node(root, "Stars")
	var deco := BP.group_node(root, "Decor")
	var markers := BP.group_node(root, "Markers")

	var goo := KillZone.new()
	goo.name = "FrostingSea"
	goo.size = Vector3(90, 8, 175)
	goo.position = Vector3(0, -2.6, -56)
	goo.goo_color = Color("6cc4f0")
	root.add_child(goo)

	# ---- Bakery (start)
	BP.block(level, "BakeryFloor", Vector3(0, 0, 0), Vector3(16, 2, 18), Color("e070a6"), Color("ffa3cd"),
			ToyMaterials.Pattern.CHECKER, Color("ffd3e8"), 0.5)
	BP.block(level, "BakeryBackWall", Vector3(0, 0.9, 8.75), Vector3(16, 1.2, 0.5), Color("ff5f7e"), Color("fff8ee"),
			ToyMaterials.Pattern.STRIPES, Color("ff5f7e"), 1.2)
	BP.rails(level, "BakeryRail", 9.0, -9.0, 7.75)
	for i in 4:
		var x := -3.0 + i * 2.0
		BP.marker(markers, "Spawn%d" % (i + 1), Vector3(x, 0.05, 5.0 + (0.5 if i in [1, 2] else 0.0)), &"spawn")
	var cake := GiantCake.new()
	cake.name = "Cake"
	cake.position = Vector3(0, 0.02, -2.5)
	root.add_child(cake)
	BP.sign(deco, "BakerySign", "BAKERY", Vector3(0, 3.6, 8.9), 150, Color("fff3a3"), Color("e8559a"))
	BP.decor(deco, "Cupcake1", Decor.Kind.CUPCAKE, Vector3(-5.8, 0, 6.2), Color("ff8fc0"), Color("8fd3ff"), 1.0, 0, true)
	BP.decor(deco, "Cupcake2", Decor.Kind.CUPCAKE, Vector3(5.8, 0, 6.2), Color("b39bff"), Color("ffd27f"), 1.0, 0, true)
	BP.decor(deco, "Lolly1", Decor.Kind.LOLLIPOP, Vector3(-6.6, 0, -6.5), Color("ff5fa8"), Color("fff8ee"), 1.0, 20)
	BP.decor(deco, "Lolly2", Decor.Kind.LOLLIPOP, Vector3(6.6, 0, -6.5), Color("3f9dff"), Color("fff8ee"), 1.0, -20)
	BP.decor(deco, "Balloons1", Decor.Kind.BALLOONS, Vector3(6.4, 0, 2.5), Color("ff5fa8"))

	# ---- Sprinkle Street (rolling donuts)
	BP.block(level, "SprinkleStreet", Vector3(0, 0, -24), Vector3(12, 2, 30), Color("c98a45"), Color("f7cf94"),
			ToyMaterials.Pattern.SPRINKLES, Color.WHITE, 0.35)
	BP.rails(level, "StreetRail", -9.0, -39.0, 6.0)
	var r1 := Roller.new()
	r1.name = "Donut1"
	r1.position = Vector3(0, 0, -15)
	r1.travel_width = 9.0
	r1.period = 4.6
	obstacles.add_child(r1)
	var r2 := Roller.new()
	r2.name = "Donut2"
	r2.position = Vector3(0, 0, -29)
	r2.travel_width = 9.0
	r2.period = 5.2
	r2.phase = 0.5
	r2.frosting_color = Color("8fd3ff")
	obstacles.add_child(r2)
	var pad := BouncePad.new()
	pad.name = "StreetPad"
	pad.position = Vector3(4.2, 0, -22)
	pad.launch_speed = 15.0
	obstacles.add_child(pad)
	BP.star(pickups, "Star01", Vector3(4.2, 4.4, -22))
	BP.star(pickups, "Star02", Vector3(-4.6, 1.2, -11))
	BP.star(pickups, "Star03", Vector3(-4.0, 1.2, -36))
	BP.sign(deco, "StreetSign", "Sprinkle Street", Vector3(-9.5, 2.6, -12), 72, Color.WHITE, Color("d9a65f"), 30)
	for i in 3:
		var z := -14.0 - i * 9.0
		var side := -1.0 if i % 2 == 0 else 1.0
		BP.block(deco, "Island%d" % i, Vector3(side * 11.5, -0.4, z), Vector3(4, 3, 4), Color("8fd3ff"), Color("d8f1ff"))
		BP.decor(deco, "IslandToy%d" % i, [Decor.Kind.LOLLIPOP, Decor.Kind.GIFT, Decor.Kind.CANDY_CANE][i],
				Vector3(side * 11.5, -0.4, z), [Color("ff5fa8"), Color("2fc97a"), Color("ff5f7e")][i])
	var cp1 := Checkpoint.new()
	cp1.name = "Checkpoint1"
	cp1.index = 1
	cp1.width = 11.0
	cp1.position = Vector3(0, 0, -36.5)
	root.add_child(cp1)

	# ---- Frosting River (bridge with swinging candy hammers)
	BP.block(level, "Bridge", Vector3(0, 0, -50), Vector3(5, 1.2, 22.4), Color("b9784a"), Color("f3c98b"),
			ToyMaterials.Pattern.STRIPES, Color("ffe2b0"), 0.8)
	for i in 2:
		var z := -45.0 - i * 10.0
		var pend := Pendulum.new()
		pend.name = "Hammer%d" % (i + 1)
		pend.position = Vector3(0, 0, z)
		pend.frame_width = 8.0
		pend.period = 3.4
		pend.phase = 0.5 * i
		pend.color = Color("ff5fa8") if i == 0 else Color("a77bff")
		obstacles.add_child(pend)
		for side: float in [-1.0, 1.0]:
			BP.block(level, "HammerBase%d%s" % [i, "L" if side < 0 else "R"], Vector3(side * 4.0, 0, z),
					Vector3(1.2, 3.5, 1.2), Color("fff8ee"), Color("ffd6e8"))
	var mp1 := MovingPlatform.new()
	mp1.name = "RaftLeft"
	mp1.position = Vector3(-7.5, 0, -41)
	mp1.size = Vector3(3, 0.6, 3)
	mp1.travel = Vector3(0, 0, -17)
	mp1.period = 9.0
	mp1.color = Color("8fd3ff")
	obstacles.add_child(mp1)
	var mp2 := MovingPlatform.new()
	mp2.name = "RaftRight"
	mp2.position = Vector3(7.5, 0, -58)
	mp2.size = Vector3(3, 0.6, 3)
	mp2.travel = Vector3(0, 0, 17)
	mp2.period = 9.0
	mp2.phase = 0.5
	mp2.color = Color("ffd27f")
	obstacles.add_child(mp2)
	BP.star(pickups, "Star04", Vector3(-7.5, 1.3, -49.5))
	BP.star(pickups, "Star05", Vector3(7.5, 1.3, -49.5))
	BP.sign(deco, "RiverSign", "Frosting River", Vector3(9.0, 2.8, -40), 72, Color.WHITE, Color("e8559a"), -30)

	# ---- Jelly Hills (plateau with a tiny-only tunnel)
	BP.block(level, "JellyFloor", Vector3(0, 0, -74), Vector3(12, 2, 26), Color("3fa874"), Color("8fe3b5"),
			ToyMaterials.Pattern.DOTS, Color("c4f5d9"), 0.45)
	BP.rails(level, "HillsRail", -61.0, -87.0, 6.0, 0.0, Color("2fc97a"))
	BP.ramp(level, "RampUp", Vector3(0, 0, -64.4), Vector3(0, 1.5, -68.2), 5.0, Color("3fa874"), Color("b6f0cf"))
	BP.block(level, "Plateau", Vector3(0, 1.5, -73), Vector3(5, 3.5, 10), Color("3fa874"), Color("b6f0cf"),
			ToyMaterials.Pattern.DOTS, Color("e2fbec"), 0.45)
	BP.ramp(level, "RampDown", Vector3(0, 1.5, -77.8), Vector3(0, 0, -81.6), 5.0, Color("3fa874"), Color("b6f0cf"))
	# Cookie wall with a little mouse hole in the middle: only Tiny Mode fits.
	var cookie := Color("c98b4a")
	BP.block(level, "CookieWallL", Vector3(-1.55, 3.7, -73), Vector3(1.9, 2.2, 1.0), cookie, Color("e8b77a"),
			ToyMaterials.Pattern.DOTS, Color("6b3f1f"), 1.2)
	BP.block(level, "CookieWallR", Vector3(1.55, 3.7, -73), Vector3(1.9, 2.2, 1.0), cookie, Color("e8b77a"),
			ToyMaterials.Pattern.DOTS, Color("6b3f1f"), 1.2)
	BP.block(level, "CookieWallTop", Vector3(0, 3.7, -73), Vector3(1.25, 1.45, 1.0), cookie, Color("e8b77a"),
			ToyMaterials.Pattern.DOTS, Color("6b3f1f"), 1.2)
	BP.sign(deco, "TinySign", "TINY ONLY!", Vector3(0, 4.4, -72.4), 48, Color("fff3a3"), Color("6b3f1f"))
	BP.star(pickups, "Star06", Vector3(0, 1.95, -73))
	var jelly := BP.block(level, "JellyBlock", Vector3(4.3, 0.35, -70), Vector3(2.4, 0.5, 2.4), Color("ff5fa8"),
			Color("ff9ccf"), ToyMaterials.Pattern.NONE)
	jelly.bounce = 13.0
	BP.star(pickups, "Star07", Vector3(4.3, 4.9, -70))
	BP.sign(deco, "HillsSign", "Jelly Hills", Vector3(-9.5, 2.6, -66), 72, Color.WHITE, Color("2fc97a"), 30)
	var cp2 := Checkpoint.new()
	cp2.name = "Checkpoint2"
	cp2.index = 2
	cp2.width = 11.0
	cp2.position = Vector3(0, 0, -62.5)
	cp2.color = Color("3f9dff")
	root.add_child(cp2)

	# ---- Tea Party (big sweeping spoon)
	BP.block(level, "TeaFloor", Vector3(0, 0, -98), Vector3(12, 2, 22), Color("7c68d9"), Color("c9bdff"),
			ToyMaterials.Pattern.GRID, Color("e6e0ff"), 0.5)
	BP.rails(level, "TeaRail", -87.0, -109.0, 6.0, 0.0, Color("a77bff"))
	var spin := Spinner.new()
	spin.name = "SpinningSpoon"
	spin.position = Vector3(0, 0, -98)
	spin.arm_length = 5.6
	spin.degrees_per_second = 55.0
	spin.color = Color("ffb35c")
	obstacles.add_child(spin)
	BP.star(pickups, "Star08", Vector3(-4.5, 1.2, -104))
	var cp3 := Checkpoint.new()
	cp3.name = "Checkpoint3"
	cp3.index = 3
	cp3.width = 11.0
	cp3.position = Vector3(0, 0, -88.5)
	cp3.color = Color("ffb35c")
	root.add_child(cp3)
	BP.decor(deco, "TeaCup1", Decor.Kind.CUPCAKE, Vector3(-9, -0.4, -95), Color("ffd27f"), Color("ff8fc0"), 1.3)
	BP.block(deco, "TeaIsland", Vector3(-9, -0.4, -95), Vector3(4, 3, 4), Color("ffd27f"), Color("fff0c4"))
	BP.decor(deco, "Teddy1", Decor.Kind.TEDDY, Vector3(9, -0.4, -101), Color("c98b5a"), Color("f3d2b0"), 1.0, -30)
	BP.block(deco, "TeddyIsland", Vector3(9, -0.4, -101), Vector3(4, 3, 4), Color("ff8fc0"), Color("ffd6e8"))
	BP.sign(deco, "TeaSign", "Tea Party", Vector3(9.5, 2.6, -90), 72, Color.WHITE, Color("7c68d9"), -30)

	# ---- Party (finish)
	BP.block(level, "PartyFloor", Vector3(0, 0, -116), Vector3(16, 2, 14), Color("e0912e"), Color("ffd98a"),
			ToyMaterials.Pattern.CHECKER, Color("fff0c4"), 0.5)
	BP.rails(level, "PartyRail", -109.0, -123.0, 7.75, 0.0, Color("ffb35c"))
	BP.block(level, "PartyBackWall", Vector3(0, 0.9, -122.75), Vector3(16, 1.2, 0.5), Color("ffb35c"), Color("fff8ee"),
			ToyMaterials.Pattern.STRIPES, Color("ffb35c"), 1.2)
	var finish := FinishZone.new()
	finish.name = "PartyZone"
	finish.position = Vector3(0, 0, -112.5)
	finish.size = Vector3(15, 4, 3)
	finish.label = "PARTY!"
	finish.detect_props = true
	root.add_child(finish)
	BP.block(level, "PartyTable", Vector3(0, 1.0, -118), Vector3(7, 0.25, 2.4), Color("ffffff"), Color("fff8ee"),
			ToyMaterials.Pattern.CHECKER, Color("ffb3d6"), 1.5, false)
	for sx: float in [-3.2, 3.2]:
		for sz: float in [-1.0, 1.0]:
			BP.block(level, "TableLeg%d%d" % [int(sx), int(sz)], Vector3(sx, 0.75, -118 + sz), Vector3(0.25, 0.75, 0.25),
					Color("e8d9f2"), Color("e8d9f2"), ToyMaterials.Pattern.NONE, Color.WHITE, 0.5, false)
	BP.marker(markers, "TableSpot", Vector3(0, 1.0, -118), &"table_spot")
	BP.decor(deco, "PartyBalloons1", Decor.Kind.BALLOONS, Vector3(-5.5, 0, -119), Color("ff5fa8"))
	BP.decor(deco, "PartyBalloons2", Decor.Kind.BALLOONS, Vector3(5.5, 0, -119), Color("3f9dff"))
	BP.decor(deco, "Guest1", Decor.Kind.TEDDY, Vector3(-2.6, 0, -120.6), Color("c98b5a"), Color("f3d2b0"), 0.8)
	BP.decor(deco, "Guest2", Decor.Kind.TEDDY, Vector3(2.6, 0, -120.6), Color("ffb35c"), Color("fff0c4"), 0.8)
	BP.decor(deco, "Guest3", Decor.Kind.TEDDY, Vector3(0, 0, -121.0), Color("a77bff"), Color("e6e0ff"), 0.8)
	BP.decor(deco, "Bunting", Decor.Kind.BUNTING, Vector3(0, 0.3, -122.2), Color("ff5fa8"), Color.WHITE, 1.0, 0, false, "A")
	(deco.get_node("Bunting") as Decor).span = 14.0
	BP.sign(deco, "BirthdaySign", "HAPPY BIRTHDAY!", Vector3(0, 5.6, -122.5), 120, Color("fff3a3"), Color("e8559a"))

	# ---- Bot path (CPU buddies carry the cake along these points)
	var path := [
		Vector3(0, 0, -2.5), Vector3(0, 0, -12), Vector3(0, 0, -22), Vector3(0, 0, -33), Vector3(0, 0, -40),
		Vector3(0, 0, -50), Vector3(0, 0, -60), Vector3(-4.3, 0, -64), Vector3(-4.3, 0, -73), Vector3(-4.3, 0, -81),
		Vector3(0, 0, -86), Vector3(0, 0, -92), Vector3(0, 0, -104), Vector3(0, 0, -112),
	]
	for i in path.size():
		BP.marker(markers, "Path%02d" % (i + 1), path[i], &"bot_path")
	# Helpers and cake fetchers walk around the cookie wall and stay on the
	# bridge using a navigation mesh (the carrier follows the path above).
	# The bouncy jelly block is off limits for them (it would fling them away).
	var no_jelly := BP.nav_blocker(level, "NavNoJelly", Vector3(4.3, 0.35, -70), Vector3(2.4, 2.0, 2.4))
	BP.bake_navigation(self, root, [level])
	level.remove_child(no_jelly)
	no_jelly.free()

	BP.save(root, "res://scenes/arenas/cake_dash.tscn")


# =====================================================================
# Button Mayhem: a walled toy-box playroom (+Z = where the players start).
# Six buttons, each needing a different skill: open floor (red), a high
# deck (blue), a turntable (yellow), a sliding shuttle (green), a toy fort
# with a tiny door (orange) and a runaway wind-up car (purple).
# =====================================================================

func build_button_mayhem() -> void:
	var root := _mode_root("res://scripts/modes/button_mayhem/button_mayhem_mode.gd", "ButtonMayhem")
	root.set("mode_id", &"button_mayhem")
	root.set("mission_title", "Button Mayhem")
	root.set("mission_text", "Press the colored buttons in the order shown at the top. Some of them run away!")
	root.set("mission_icon", &"buttons")
	root.set("round_time", 100.0)
	root.set("team_mode", true)
	root.set("kill_height", -5.0)
	root.set("camera_pitch", -50.0)
	root.set("camera_distance", 14.0)
	root.set("camera_min_distance", 11.0)
	root.set("camera_max_distance", 24.0)
	root.set("camera_look_ahead", Vector3(0, 0, -1))

	var env := ToyEnvironment.new()
	env.name = "Environment"
	env.style = ToyEnvironment.Style.TOYBOX
	root.add_child(env)

	var level := BP.group_node(root, "Level")
	var props := BP.group_node(root, "Buttons")
	var obstacles := BP.group_node(root, "Moving")
	var pickups := BP.group_node(root, "Stars")
	var deco := BP.group_node(root, "Decor")
	var markers := BP.group_node(root, "Markers")

	var below := KillZone.new()
	below.name = "BelowTheFloor"
	below.size = Vector3(70, 4, 60)
	below.position = Vector3(0, -6, 0)
	below.show_goo = false
	root.add_child(below)

	# ---- Play mat and toy-box rim
	BP.block(level, "PlayMat", Vector3(0, 0, 0), Vector3(40, 2, 32), Color("6f86e0"), Color("a4bcff"),
			ToyMaterials.Pattern.GRID, Color("d2deff"), 0.5)
	var rim := Color("ffb35c")
	BP.block(level, "WallN", Vector3(0, 1.5, -16.25), Vector3(41, 1.5, 0.5), rim, Color("fff3d6"),
			ToyMaterials.Pattern.STRIPES, rim, 1.2)
	BP.block(level, "WallS", Vector3(0, 1.0, 16.25), Vector3(41, 1.0, 0.5), rim, Color("fff3d6"),
			ToyMaterials.Pattern.STRIPES, rim, 1.2)
	BP.block(level, "WallW", Vector3(-20.25, 1.5, 0), Vector3(0.5, 1.5, 32), rim, Color("fff3d6"),
			ToyMaterials.Pattern.STRIPES, rim, 1.2)
	BP.block(level, "WallE", Vector3(20.25, 1.5, 0), Vector3(0.5, 1.5, 32), rim, Color("fff3d6"),
			ToyMaterials.Pattern.STRIPES, rim, 1.2)
	for i in 4:
		var x := -3.0 + i * 2.0
		BP.marker(markers, "Spawn%d" % (i + 1), Vector3(x, 0.05, 12.0 + (0.5 if i in [1, 2] else 0.0)), &"spawn")

	# ---- Red: out in the open (the easy one)
	BP.push_button(props, "RedButton", &"red", Vector3(-4.5, 0, 6.5))

	# ---- Purple: rides the runaway car around the block tower
	BP.block(level, "Tower", Vector3(0, 3.0, -3), Vector3(3, 3, 3), Color("ff5fa8"), Color("ffc4dc"),
			ToyMaterials.Pattern.DOTS, Color("fff0f6"), 0.6)
	BP.star(pickups, "Star01", Vector3(0, 3.8, -3))
	var tower_pad := BouncePad.new()
	tower_pad.name = "TowerPad"
	tower_pad.position = Vector3(-3.2, 0, -3)
	tower_pad.launch_speed = 15.0
	obstacles.add_child(tower_pad)
	var car := RunawayCar.new()
	car.name = "RunawayCar"
	car.loop_center = Vector3(0, 0, -3)
	car.loop_radii = Vector2(6.5, 4.8)
	car.position = Vector3(0, 0, 1.8)
	obstacles.add_child(car)
	BP.push_button(car, "PurpleButton", &"purple", Vector3(0, 0.77, 0), 0.5, 2.2)

	# ---- Blue: up on the high deck (ramp around the side, or the bounce pad)
	BP.block(level, "HighDeck", Vector3(-14, 3, -10), Vector3(6, 3, 6), Color("3f7fdf"), Color("8fc4ff"),
			ToyMaterials.Pattern.STRIPES, Color("c4e0ff"), 0.6)
	BP.ramp(level, "DeckRamp", Vector3(-14, 0, 1.5), Vector3(-14, 3, -7.2), 2.8, Color("3f7fdf"), Color("8fc4ff"))
	BP.push_button(props, "BlueButton", &"blue", Vector3(-14, 3, -10.5))
	var deck_pad := BouncePad.new()
	deck_pad.name = "DeckPad"
	deck_pad.position = Vector3(-9.0, 0, -10)
	deck_pad.launch_speed = 15.0
	deck_pad.color = Color("3f9dff")
	obstacles.add_child(deck_pad)
	BP.star(pickups, "Star02", Vector3(-9.0, 3.9, -10))
	BP.star(pickups, "Star03", Vector3(-15.8, 4.0, -12.2))
	BP.sign(deco, "DeckSign", "HIGH DECK", Vector3(-14, 4.6, -12.9), 64, Color.WHITE, Color("3f7fdf"))

	# ---- Yellow: on a slowly spinning turntable
	var spin := Turntable.new()
	spin.name = "Turntable"
	spin.position = Vector3(-12, 0.03, 8)
	spin.radius = 3.6
	spin.degrees_per_second = 28.0
	spin.color = Color("ffb35c")
	spin.stripe_color = Color("fff3a3")
	obstacles.add_child(spin)
	BP.push_button(spin, "YellowButton", &"yellow", Vector3(2.2, 0, 0))
	BP.star(pickups, "Star04", Vector3(-12, 1.2, 8))

	# ---- Green: on a shuttle sliding between two pillars by the east wall
	var green_col := Color("2fc97a")
	BP.block(level, "PillarA", Vector3(18, 2, 9), Vector3(3, 2, 3), green_col, Color("a3f0c8"),
			ToyMaterials.Pattern.DOTS, Color("e2fbec"), 0.6)
	BP.block(level, "PillarB", Vector3(18, 2, -2), Vector3(3, 2, 3), green_col, Color("a3f0c8"),
			ToyMaterials.Pattern.DOTS, Color("e2fbec"), 0.6)
	BP.ramp(level, "PillarRampA", Vector3(12.6, 0, 9), Vector3(16.6, 2, 9), 2.4, green_col, Color("a3f0c8"))
	BP.ramp(level, "PillarRampB", Vector3(12.8, 0, -2), Vector3(16.6, 2, -2), 2.4, green_col, Color("a3f0c8"))
	var shuttle := MovingPlatform.new()
	shuttle.name = "Shuttle"
	shuttle.position = Vector3(18, 2, 6.2)
	shuttle.size = Vector3(2.6, 0.5, 2.6)
	shuttle.travel = Vector3(0, 0, -5.4)
	shuttle.period = 7.0
	shuttle.hold = 0.22
	shuttle.color = Color("7dffb0")
	obstacles.add_child(shuttle)
	BP.push_button(shuttle, "GreenButton", &"green", Vector3(0, 0, 0), 0.65, 2.4)
	BP.star(pickups, "Star05", Vector3(18, 3.6, 3.5))

	# ---- Orange: inside the toy fort. Big door round the back, tiny door in front.
	var fort := Color("ff8fc0")
	var fort_top := Color("ffd6e8")
	BP.block(level, "FortN", Vector3(13, 2.6, -14.75), Vector3(8, 2.6, 0.5), fort, fort_top)
	BP.block(level, "FortW", Vector3(9.25, 2.6, -11), Vector3(0.5, 2.6, 8), fort, fort_top)
	BP.block(level, "FortSL", Vector3(10.8, 2.6, -7.25), Vector3(3.6, 2.6, 0.5), fort, fort_top)
	BP.block(level, "FortSR", Vector3(15.2, 2.6, -7.25), Vector3(3.6, 2.6, 0.5), fort, fort_top)
	BP.block(level, "FortSTop", Vector3(13, 2.6, -7.25), Vector3(0.8, 1.75, 0.5), fort, fort_top)
	BP.block(level, "FortEN", Vector3(16.75, 2.6, -13.6), Vector3(0.5, 2.6, 2.8), fort, fort_top)
	BP.block(level, "FortES", Vector3(16.75, 2.6, -8.4), Vector3(0.5, 2.6, 2.8), fort, fort_top)
	BP.block(level, "FortETop", Vector3(16.75, 2.6, -11), Vector3(0.5, 0.4, 2.4), fort, fort_top)
	for i in 6:
		BP.block(deco, "Battlement%d" % i, Vector3(9.6 + i * 1.36, 3.0, -14.75), Vector3(0.6, 0.4, 0.6), fort, fort_top,
				ToyMaterials.Pattern.NONE, Color.WHITE, 0.5, false)
	BP.push_button(props, "OrangeButton", &"orange", Vector3(13, 0, -11))
	BP.sign(deco, "TinyDoorSign", "TINY DOOR", Vector3(13, 1.7, -6.85), 40, Color("fff3a3"), Color("e8559a"))
	BP.sign(deco, "FortSign", "TOY FORT", Vector3(13, 3.6, -15.1), 72, Color.WHITE, Color("e8559a"))
	BP.star(pickups, "Star06", Vector3(10.6, 1.2, -13.4))

	# ---- Decorations along the walls
	BP.decor(deco, "BlockA", Decor.Kind.TOY_BLOCK, Vector3(-18.4, 0, -14.4), Color("ff5f7e"), Color("fff8ee"), 1.2, 15, true, "A")
	BP.decor(deco, "BlockB", Decor.Kind.TOY_BLOCK, Vector3(-4.0, 0, -14.6), Color("3f9dff"), Color("fff8ee"), 1.0, -10, true, "B")
	BP.decor(deco, "BlockC", Decor.Kind.TOY_BLOCK, Vector3(4.2, 0, -14.6), Color("2fc97a"), Color("fff8ee"), 1.0, 8, true, "C")
	BP.decor(deco, "Crayon1", Decor.Kind.CRAYON, Vector3(-18.6, 0, -1.0), Color("a77bff"), Color("fff8ee"), 1.3, 0)
	BP.decor(deco, "Teddy", Decor.Kind.TEDDY, Vector3(-18.2, 0, 14.0), Color("c98b5a"), Color("f3d2b0"), 1.2, 30)
	BP.decor(deco, "Balloons1", Decor.Kind.BALLOONS, Vector3(-7.0, 0, 14.6), Color("ff5fa8"))
	BP.decor(deco, "Balloons2", Decor.Kind.BALLOONS, Vector3(9.0, 0, 14.6), Color("ffd23f"))
	BP.sign(deco, "TitleSign", "BUTTON MAYHEM", Vector3(-5, 3.2, -16.6), 110, Color("fff3a3"), Color("7b5cff"))

	# ---- CPU buddies: a navigation mesh for getting around, plus a spot to
	# wait for buttons that move past a fixed point (the shuttle).
	BP.marker(markers, "WaitGreen", Vector3(18, 2, 7.85), &"button_wait", {"button": "green"})
	BP.bake_navigation(self, root, [level])

	BP.save(root, "res://scenes/arenas/button_mayhem.tscn")


# =====================================================================
# Bounce Race: start -> Trampoline Lagoon -> Spinner Plaza -> sliding
# platforms -> Boing Climb -> Hammer Bridge -> slide -> FINISH. Toward -Z.
# =====================================================================

func build_bounce_race() -> void:
	var root := _mode_root("res://scripts/modes/bounce_race/bounce_race_mode.gd", "BounceRace")
	root.set("mode_id", &"bounce_race")
	root.set("mission_title", "Bounce Race")
	root.set("mission_text", "Race through the bouncy course. First to the finish wins! Fall in the goo? You pop back at the last flag.")
	root.set("mission_icon", &"bounce")
	root.set("round_time", 90.0)
	root.set("team_mode", false)
	root.set("kill_height", -6.0)
	root.set("camera_pitch", -36.0)
	root.set("camera_distance", 11.5)
	root.set("camera_min_distance", 9.5)
	root.set("camera_max_distance", 19.0)
	root.set("camera_look_ahead", Vector3(0, 0, -4))

	var env := ToyEnvironment.new()
	env.name = "Environment"
	env.style = ToyEnvironment.Style.MEADOW
	root.add_child(env)

	var level := BP.group_node(root, "Level")
	var obstacles := BP.group_node(root, "Obstacles")
	var pickups := BP.group_node(root, "Stars")
	var deco := BP.group_node(root, "Decor")
	var markers := BP.group_node(root, "Markers")

	var goo := KillZone.new()
	goo.name = "JellyGoo"
	goo.size = Vector3(80, 8, 175)
	goo.position = Vector3(0, -2.5, -68)
	goo.goo_color = Color("a35cf0")
	root.add_child(goo)

	# ---- Start
	BP.block(level, "StartPad", Vector3(0, 0, 2), Vector3(14, 2, 16), Color("3fae6a"), Color("94e3b0"),
			ToyMaterials.Pattern.CHECKER, Color("c7f5d6"), 0.5)
	BP.block(level, "StartBackWall", Vector3(0, 0.9, 10.25), Vector3(14, 1.2, 0.5), Color("2fc97a"), Color("fff8ee"),
			ToyMaterials.Pattern.STRIPES, Color("2fc97a"), 1.2)
	BP.rails(level, "StartRail", 10.0, -6.0, 7.0, 0.0, Color("2fc97a"))
	BP.marker(markers, "StartLine", Vector3(0, 0, 6), &"start_line")
	for i in 4:
		var x := -3.0 + i * 2.0
		BP.marker(markers, "Spawn%d" % (i + 1), Vector3(x, 0.05, 7.0 + (0.5 if i in [1, 2] else 0.0)), &"spawn")
	BP.sign(deco, "RaceSign", "BOUNCE RACE", Vector3(0, 3.4, 10.5), 140, Color("fff3a3"), Color("2fa05e"))
	BP.decor(deco, "StartBalloons1", Decor.Kind.BALLOONS, Vector3(-6.2, 0, 9.0), Color("ff5fa8"))
	BP.decor(deco, "StartBalloons2", Decor.Kind.BALLOONS, Vector3(6.2, 0, 9.0), Color("3f9dff"))

	# ---- Trampoline Lagoon (bounce across; the narrow beam is the slow, safe way)
	var tramps := [Vector3(-1.5, 0, -11), Vector3(1.5, 0, -17.5), Vector3(-1, 0, -24)]
	for i in tramps.size():
		var at: Vector3 = tramps[i]
		BP.block(level, "TrampPost%d" % (i + 1), at, Vector3(5.0, 6, 5.0), Color("e0912e"), Color("ffd98a"))
		var t := BouncePad.new()
		t.name = "Trampoline%d" % (i + 1)
		t.trampoline = true
		t.radius = 2.0
		t.launch_speed = 16.0
		t.color = [Color("ff5fa8"), Color("3f9dff"), Color("ffd23f")][i]
		t.position = at
		obstacles.add_child(t)
		BP.star(pickups, "StarT%d" % (i + 1), at + Vector3(0, 4.3, 0))
	BP.block(level, "Beam", Vector3(5.5, 0, -18), Vector3(1.4, 0.8, 24.4), Color("ff8fc0"), Color("ffd6e8"))
	BP.sign(deco, "LagoonSign", "Trampoline Lagoon", Vector3(-8.5, 2.6, -9), 72, Color.WHITE, Color("a35cf0"), 30)

	# ---- Spinner Plaza
	BP.block(level, "Plaza", Vector3(0, 0, -41), Vector3(16, 2, 22), Color("e6b422"), Color("ffe27a"),
			ToyMaterials.Pattern.DOTS, Color("fff3c4"), 0.45)
	BP.rails(level, "PlazaRail", -30.0, -52.0, 8.0, 0.0, Color("ffb35c"))
	var cp1 := Checkpoint.new()
	cp1.name = "Checkpoint1"
	cp1.index = 1
	cp1.width = 15.0
	cp1.position = Vector3(0, 0, -31.6)
	root.add_child(cp1)
	var spinner := Spinner.new()
	spinner.name = "BigSpinner"
	spinner.position = Vector3(0, 0, -41.5)
	spinner.arm_length = 7.4
	spinner.degrees_per_second = 62.0
	spinner.color = Color("ff5fa8")
	obstacles.add_child(spinner)
	for side: float in [-1.0, 1.0]:
		var pad := BouncePad.new()
		pad.name = "PlazaPad%s" % ("L" if side < 0 else "R")
		pad.position = Vector3(side * 6.0, 0, -36.0 if side < 0 else -47.0)
		pad.launch_speed = 15.0
		obstacles.add_child(pad)
		BP.star(pickups, "StarP%s" % ("L" if side < 0 else "R"), pad.position + Vector3(0, 4.3, 0))
	var cp2 := Checkpoint.new()
	cp2.name = "Checkpoint2"
	cp2.index = 2
	cp2.width = 15.0
	cp2.color = Color("3f9dff")
	cp2.position = Vector3(0, 0, -48.6)
	root.add_child(cp2)
	BP.sign(deco, "PlazaSign", "Spinner Plaza", Vector3(9.0, 2.6, -33), 72, Color.WHITE, Color("e0912e"), -30)

	# ---- Sliding platforms over the goo (always covering the middle lane)
	var plat_z := [-55.4, -60.6, -65.8, -71.0]
	var plat_cols := [Color("7fd6ff"), Color("ffd27f"), Color("b39bff"), Color("7dffb0")]
	for i in plat_z.size():
		var mp := MovingPlatform.new()
		mp.name = "Slider%d" % (i + 1)
		var from_x := -2.0 if i % 2 == 0 else 2.0
		mp.position = Vector3(from_x, 0, plat_z[i])
		mp.size = Vector3(6, 0.6, 3.6)
		mp.travel = Vector3(-2.0 * from_x, 0, 0)
		mp.period = 3.8 + i * 0.4
		mp.phase = i * 0.25
		mp.hold = 0.1
		mp.color = plat_cols[i]
		obstacles.add_child(mp)
	BP.star(pickups, "StarS1", Vector3(0, 1.7, -58.0))
	BP.star(pickups, "StarS2", Vector3(0, 1.7, -68.4))
	BP.sign(deco, "SliderSign", "Slidey Platforms", Vector3(-9.0, 2.0, -56), 64, Color.WHITE, Color("3f9dff"), 30)

	# ---- Boing Climb: bounce pads up two big steps
	var climb := Color("f08a5d")
	BP.block(level, "ClimbBase", Vector3(0, 0, -79.95), Vector3(14, 2, 11.1), climb, Color("ffc2a3"),
			ToyMaterials.Pattern.STRIPES, Color("ffe0d0"), 0.6)
	BP.rails(level, "ClimbRail", -74.4, -85.5, 7.0, 0.0, Color("ff8a4c"))
	var cp3 := Checkpoint.new()
	cp3.name = "Checkpoint3"
	cp3.index = 3
	cp3.width = 13.0
	cp3.color = Color("ffb35c")
	cp3.position = Vector3(0, 0, -76.0)
	root.add_child(cp3)
	BP.block(level, "Step1", Vector3(0, 3, -90), Vector3(14, 5, 9), climb, Color("ffc2a3"),
			ToyMaterials.Pattern.STRIPES, Color("ffe0d0"), 0.6)
	BP.block(level, "Step2", Vector3(0, 6, -98), Vector3(14, 8, 7), climb, Color("ffc2a3"),
			ToyMaterials.Pattern.STRIPES, Color("ffe0d0"), 0.6)
	BP.rails(level, "Step1Rail", -85.5, -94.5, 7.0, 3.0, Color("ff8a4c"))
	BP.rails(level, "Step2Rail", -94.5, -101.5, 7.0, 6.0, Color("ff8a4c"))
	for x: float in [-4.0, 0.0, 4.0]:
		for level_y: float in [0.0, 3.0]:
			var pad := BouncePad.new()
			pad.name = "ClimbPad%d%s" % [int(level_y), ("L" if x < 0 else ("M" if x == 0 else "R"))]
			pad.position = Vector3(x, level_y, -82.6 if level_y == 0.0 else -91.6)
			pad.launch_speed = 15.5
			pad.color = Color("ffd23f") if level_y == 0.0 else Color("ff5fa8")
			obstacles.add_child(pad)
	var cp4 := Checkpoint.new()
	cp4.name = "Checkpoint4"
	cp4.index = 4
	cp4.width = 13.0
	cp4.color = Color("a77bff")
	cp4.position = Vector3(0, 6, -96.5)
	root.add_child(cp4)
	BP.star(pickups, "StarC1", Vector3(-6, 4.2, -88))
	BP.star(pickups, "StarC2", Vector3(6, 7.2, -98))
	BP.sign(deco, "ClimbSign", "Boing Climb", Vector3(-8.5, 3.6, -80), 72, Color.WHITE, Color("f08a5d"), 30)

	# ---- Hammer Bridge (high up!)
	BP.block(level, "Bridge", Vector3(0, 6, -110.25), Vector3(5, 1.2, 17.5), Color("e8559a"), Color("ffc4dc"),
			ToyMaterials.Pattern.STRIPES, Color("ffe3ee"), 0.8)
	for i in 2:
		var z := -106.0 - i * 8.0
		var pend := Pendulum.new()
		pend.name = "Hammer%d" % (i + 1)
		pend.position = Vector3(0, 6, z)
		pend.frame_width = 7.0
		pend.period = 3.0 + i * 0.4
		pend.phase = 0.5 * i
		pend.color = Color("ff5fa8") if i == 0 else Color("a77bff")
		obstacles.add_child(pend)
		for side: float in [-1.0, 1.0]:
			BP.block(level, "HammerPost%d%s" % [i, "L" if side < 0 else "R"], Vector3(side * 3.5, 6, z),
					Vector3(1.2, 8, 1.2), Color("fff8ee"), Color("ffd6e8"))
	BP.star(pickups, "StarB", Vector3(0, 7.3, -110))
	BP.sign(deco, "BridgeSign", "Hammer Bridge", Vector3(6.5, 8.6, -104), 72, Color.WHITE, Color("e8559a"), -30)

	# ---- Slide down to the finish
	BP.ramp(level, "Slide", Vector3(0, 6, -119.0), Vector3(0, 0, -129.0), 6.0, Color("ff5fa8"), Color("ffc4dc"),
			ToyMaterials.Pattern.STRIPES, Color("ffe3ee"))
	BP.block(level, "FinishPad", Vector3(0, 0, -136), Vector3(16, 2, 14), Color("e0912e"), Color("ffd98a"),
			ToyMaterials.Pattern.CHECKER, Color("fff0c4"), 0.5)
	BP.rails(level, "FinishRail", -129.0, -143.0, 8.0, 0.0, Color("ffb35c"))
	BP.block(level, "FinishBackWall", Vector3(0, 0.9, -143.25), Vector3(16, 1.2, 0.5), Color("ffb35c"), Color("fff8ee"),
			ToyMaterials.Pattern.STRIPES, Color("ffb35c"), 1.2)
	var finish := FinishZone.new()
	finish.name = "FinishLine"
	finish.position = Vector3(0, 0, -133)
	finish.size = Vector3(15, 4, 3)
	finish.label = "FINISH!"
	finish.color = Color("ff5fa8")
	root.add_child(finish)
	BP.block(deco, "Podium1", Vector3(0, 1.2, -140), Vector3(2.4, 1.2, 2.4), Color("ffd23f"), Color("fff3a3"))
	BP.block(deco, "Podium2", Vector3(-2.6, 0.8, -140), Vector3(2.4, 0.8, 2.4), Color("c9c9dc"), Color("eeeef8"))
	BP.block(deco, "Podium3", Vector3(2.6, 0.5, -140), Vector3(2.4, 0.5, 2.4), Color("e0912e"), Color("ffd98a"))
	BP.decor(deco, "FinishBalloons1", Decor.Kind.BALLOONS, Vector3(-6.5, 0, -141), Color("ffd23f"))
	BP.decor(deco, "FinishBalloons2", Decor.Kind.BALLOONS, Vector3(6.5, 0, -141), Color("ff5fa8"))

	# ---- CPU racers follow these points (jump = take off before a gap)
	var path := [
		[Vector3(0, 0, 3), {}],
		[Vector3(-1.5, 0, -4.5), {}],
		[Vector3(-1.5, 0, -11), {"jump": true, "jump_distance": 5.0, "no_brake": true, "arrive_radius": 2.0}],
		[Vector3(1.5, 0, -17.5), {"no_brake": true, "arrive_radius": 2.0}],
		[Vector3(-1, 0, -24), {"no_brake": true, "arrive_radius": 2.0}],
		[Vector3(0, 0, -34), {}],
		[Vector3(2.5, 0, -41.5), {}],
		[Vector3(0, 0, -50.2), {}],
		[Vector3(0, 0, -55.4), {"jump": true, "jump_distance": 3.8}],
		[Vector3(0, 0, -60.6), {"jump": true, "jump_distance": 3.8}],
		[Vector3(0, 0, -65.8), {"jump": true, "jump_distance": 3.8}],
		[Vector3(0, 0, -71.0), {"jump": true, "jump_distance": 3.8}],
		[Vector3(0, 0, -77.0), {"jump": true, "jump_distance": 4.6}],
		[Vector3(0, 0, -82.6), {"no_pass": true}],
		[Vector3(0, 3, -88.5), {}],
		[Vector3(0, 3, -91.6), {"no_pass": true}],
		[Vector3(0, 6, -97.5), {}],
		[Vector3(0, 6, -103), {}],
		[Vector3(0, 6, -110), {}],
		[Vector3(0, 6, -117.5), {}],
		[Vector3(0, 3, -124), {}],
		[Vector3(0, 0, -133.5), {}],
	]
	for i in path.size():
		BP.marker(markers, "Path%02d" % (i + 1), path[i][0], &"bot_path", path[i][1])

	BP.save(root, "res://scenes/arenas/bounce_race.tscn")
