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


func _initialize() -> void:
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

	BP.save(root, "res://scenes/arenas/cake_dash.tscn")
