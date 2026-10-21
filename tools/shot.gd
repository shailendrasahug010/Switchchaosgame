extends SceneTree
## Renders a screenshot for visual checks (needs a display; use Xvfb on Linux).
##
##   godot --path . --rendering-driver opengl3 --resolution 1280x720 -s tools/shot.gd -- \
##       --showcase --out=/tmp/showcase.png
##   godot ... -s tools/shot.gd -- --scene=res://scenes/main/main.tscn --frames=90 --out=/tmp/menu.png
##
## Options: --scene=PATH  --showcase  --out=FILE  --frames=N  --wait=SECONDS

var _frames_left := 60
var _out := "user://shot.png"
var _elapsed := 0.0
var _wait := 0.0
var _at: Array[int] = []
var _frame := 0


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var parts := a.trim_prefix("--").split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else "true"
	_out = args.get("out", _out)
	_frames_left = int(args.get("frames", "60"))
	_wait = float(args.get("wait", "0"))
	if args.has("at"):
		for part in String(args.at).split(","):
			_at.append(int(part))
	if args.has("scene"):
		var packed: PackedScene = load(args.scene)
		change_scene_to_packed(packed)
	else:
		var scene := _build_showcase(args)
		root.add_child(scene)


func _process(delta: float) -> bool:
	_elapsed += delta
	_frame += 1
	if not _at.is_empty():
		if _at.has(_frame):
			var path := _out.get_basename() + "_%d.png" % _frame
			root.get_texture().get_image().save_png(path)
			print("shot saved: ", path)
			if _frame >= _at.max():
				quit()
		# Software rendering is slow: only draw the few frames before each capture.
		var next_capture := 1 << 30
		for f in _at:
			if f > _frame:
				next_capture = mini(next_capture, f)
		RenderingServer.render_loop_enabled = next_capture - _frame <= 3
		return false
	_frames_left -= 1
	if _frames_left <= 0 and _elapsed >= _wait:
		var img := root.get_texture().get_image()
		var err := img.save_png(_out)
		print("shot saved: ", _out, " ", img.get_size(), " err=", err)
		quit()
	return false


func _build_showcase(args: Dictionary) -> Node3D:
	var world := Node3D.new()
	world.name = "Showcase"
	var env := ToyEnvironment.new()
	env.sun_energy = float(args.get("sun", str(env.sun_energy)))
	env.ambient_energy = float(args.get("amb", str(env.ambient_energy)))
	env.exposure = float(args.get("exp", str(env.exposure)))
	env.tonemap = int(args.get("tm", str(env.tonemap)))
	world.add_child(env)
	var floor := Block.new()
	floor.size = Vector3(30, 2, 30)
	floor.color = Color("ffb3d6")
	floor.pattern = ToyMaterials.Pattern.CHECKER
	floor.pattern_color = Color("ffe0ef")
	floor.top_color = Color("fff0f7")
	world.add_child(floor)
	var plat := Block.new()
	plat.size = Vector3(4, 1.5, 4)
	plat.color = Color("7fd6ff")
	plat.position = Vector3(-8, 1.5, -6)
	world.add_child(plat)
	var spinner := Spinner.new()
	spinner.position = Vector3(8, 0, -6)
	world.add_child(spinner)
	var pend := Pendulum.new()
	pend.position = Vector3(0, 0, -10)
	world.add_child(pend)
	var roller := Roller.new()
	roller.position = Vector3(0, 0, -3)
	world.add_child(roller)
	var pad := BouncePad.new()
	pad.position = Vector3(-4, 0, 2)
	world.add_child(pad)
	var tramp := BouncePad.new()
	tramp.trampoline = true
	tramp.radius = 1.8
	tramp.position = Vector3(5, 0, 3)
	world.add_child(tramp)
	var star := StarPickup.new()
	star.position = Vector3(-2, 1.4, 4)
	world.add_child(star)
	var cp := Checkpoint.new()
	cp.position = Vector3(0, 0, -13)
	cp.width = 8
	world.add_child(cp)
	var mp := MovingPlatform.new()
	mp.position = Vector3(-10, 0.5, 2)
	mp.travel = Vector3(0, 0, -6)
	world.add_child(mp)
	var kinds := [Decor.Kind.BALLOONS, Decor.Kind.LOLLIPOP, Decor.Kind.GIFT, Decor.Kind.CUPCAKE, Decor.Kind.TOY_BLOCK,
			Decor.Kind.CANDY_CANE, Decor.Kind.TEDDY, Decor.Kind.CRAYON, Decor.Kind.MUSHROOM, Decor.Kind.DONUT]
	for i in kinds.size():
		var d := Decor.new()
		d.kind = kinds[i]
		d.position = Vector3(-13 + i * 2.9, 0, -14)
		d.color = [Color("ff5fa8"), Color("3f9dff"), Color("2fc97a"), Color("ffd23f"), Color("a77bff")][i % 5]
		world.add_child(d)
	var players_scene: PackedScene = load("res://scenes/player/player.tscn")
	var looks := [[&"bloop", &"party_hat"], [&"jelly", &"bow"], [&"mossy", &"crown"], [&"sunny", &"shades"]]
	var cam := PartyCamera.new()
	cam.pitch_degrees = -30
	cam.base_distance = 9.0
	world.add_child(cam)
	for i in 4:
		var p: PlayerCharacter = players_scene.instantiate()
		p.position = Vector3(-3.0 + i * 2.0, 0.1, 6.5)
		p.facing = Vector3(0, 0, 1)
		world.add_child(p)
		p.setup_look(looks[i][0], looks[i][1], &"classic", Catalog.PLAYER_TAG_COLORS[i], "P%d" % (i + 1))
		cam.add_target(p, PartyCamera.Priority.MUST)
	cam.look_ahead = Vector3(0, 0, -3.0)
	if args.has("closeup"):
		cam.pitch_degrees = -14.0
		cam.base_distance = 6.0
		cam.min_distance = 4.0
		cam.look_ahead = Vector3.ZERO
	cam.current = true
	return world
