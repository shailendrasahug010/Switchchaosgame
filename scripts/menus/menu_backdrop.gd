class_name MenuBackdrop
extends Node3D
## The living 3D scene behind the main menu: a round candy island where the
## four toy creatures hop around and pull funny faces.

var characters: Array[PlayerCharacter] = []
var camera: Camera3D
var _inputs: Array[ScriptedInputSource] = []
var _rules := ModifierStack.new()
var _time := 0.0
var _next_trick := 3.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	MatchClock.externally_driven = false
	var env := ToyEnvironment.new()
	env.sun_yaw = 20.0
	add_child(env)
	var island := StaticBody3D.new()
	island.collision_layer = Layers.WORLD
	add_child(island)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 7.0
	cyl.height = 2.0
	shape.shape = cyl
	shape.position = Vector3(0, -1, 0)
	island.add_child(shape)
	island.add_child(MeshFactory.make(MeshFactory.cylinder(7.0, 6.6, 2.0, 40), ToyMaterials.matte(Color("e889b5")), Vector3(0, -1.05, 0)))
	island.add_child(MeshFactory.make(MeshFactory.cylinder(7.12, 7.12, 0.22, 40),
			ToyMaterials.patterned(Color("ffc4dc"), Color("ffe3ee"), ToyMaterials.Pattern.CHECKER, 0.5), Vector3(0, -0.09, 0)))
	var goo := MeshFactory.make(MeshFactory.cylinder(60, 60, 0.2, 48),
			ToyMaterials.patterned(Color("ff9ccf"), Color("ffb8dc"), ToyMaterials.Pattern.DOTS, 0.2), Vector3(0, -1.8, 0),
			Vector3.ONE, Vector3.ZERO, false)
	add_child(goo)
	var decor_spots := [
		[Decor.Kind.BALLOONS, Vector3(-5.2, 0, -3.0), Color("ff5fa8")],
		[Decor.Kind.LOLLIPOP, Vector3(5.4, 0, -3.4), Color("3f9dff")],
		[Decor.Kind.CUPCAKE, Vector3(-4.6, 0, -5.4), Color("b39bff")],
		[Decor.Kind.GIFT, Vector3(4.2, 0, -5.6), Color("2fc97a")],
		[Decor.Kind.CANDY_CANE, Vector3(0.0, 0, -6.2), Color("ff5f7e")],
	]
	for d in decor_spots:
		var deco := Decor.new()
		deco.kind = d[0]
		deco.position = d[1]
		deco.color = d[2]
		add_child(deco)
	var scene: PackedScene = load("res://scenes/player/player.tscn")
	var ids: Array[StringName] = [GameState.profile.character]
	for c in Catalog.CHARACTERS:
		if not ids.has(c.id):
			ids.append(c.id)
	for i in 4:
		var p: PlayerCharacter = scene.instantiate()
		var input := ScriptedInputSource.new()
		p.input = input
		p.rules = _rules
		p.controls_enabled = true
		p.kill_y = -6.0
		add_child(p)
		var pos := Vector3(-2.7 + i * 1.8, 0.1, 0.6 + (0.5 if i % 2 == 1 else 0.0))
		p.teleport(pos, Vector3(0, 0, 1))
		p.respawn_position = pos
		var hat: StringName = GameState.profile.hat if i == 0 else &"none"
		var paint: StringName = GameState.profile.paint if i == 0 else &"classic"
		p.setup_look(ids[i], hat, paint, Catalog.PLAYER_TAG_COLORS[i], "")
		p.name_tag.visible = false
		characters.append(p)
		_inputs.append(input)
	camera = Camera3D.new()
	camera.fov = 50.0
	add_child(camera)
	camera.current = true


func _physics_process(delta: float) -> void:
	_time += delta
	MatchClock.advance(delta)
	for i in characters.size():
		var p := characters[i]
		var input := _inputs[i]
		# Wander a little around a home spot, then come back facing the camera.
		var home := Vector3(-2.7 + i * 1.8, 0, 0.6)
		var wander := Vector3(sin(_time * 0.6 + i * 2.1), 0, cos(_time * 0.45 + i * 1.3)) * 0.9
		var to := home + wander - p.global_position
		to.y = 0
		var stick := Vector2(to.x, to.z)
		input.move = stick.limit_length(1.0) * (0.55 if stick.length() > 0.3 else 0.0)
		if _rng.randf() < delta * 0.35:
			input.press_jump()
			input.jump_held = _rng.randf() < 0.5
		if p.global_position.y < 0.2 and not p.is_on_floor():
			input.jump_held = false
		if input.move == Vector2.ZERO and p.is_on_floor():
			p.facing = p.facing.slerp(Vector3(0, 0, 1), clampf(delta * 3.0, 0, 1)).normalized()
	_next_trick -= delta
	if _next_trick <= 0.0:
		_next_trick = _rng.randf_range(4.0, 7.0)
		_do_trick()


func _do_trick() -> void:
	var tricks := [&"moon", &"giant", &"tiny", &"bounce", &"celebrate"]
	var t: StringName = tricks[_rng.randi() % tricks.size()]
	_rules.clear()
	match t:
		&"moon":
			_rules.set_source(&"menu", {&"gravity": 0.45})
		&"giant":
			_rules.set_source(&"menu", {&"size": 1.5})
		&"tiny":
			_rules.set_source(&"menu", {&"size": 0.6})
		&"bounce":
			_rules.set_source(&"menu", {&"floor_bounce": 0.8, &"min_bounce": 6.0})
		&"celebrate":
			for p in characters:
				p.celebrate()
	for p in characters:
		p.react(&"surprised" if t != &"celebrate" else &"happy")
	get_tree().create_timer(2.6).timeout.connect(func() -> void: _rules.clear())


func _process(_delta: float) -> void:
	if camera:
		var sway := sin(_time * 0.25) * 0.8
		camera.global_transform = Transform3D(Basis(), Vector3(-2.2 + sway, 3.0, 9.0))
		camera.look_at(Vector3(-1.6 + sway * 0.5, 0.9, 0.0))
