class_name TestCase
extends RefCounted
## Base class for automated tests (see tests/run_tests.gd).
## Test methods are named test_* and may use await.

var tree: SceneTree
var failures: PackedStringArray = []
var notes: PackedStringArray = []


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func check(condition: bool, message: String) -> bool:
	if not condition:
		failures.append(message)
	return condition


func check_eq(actual: Variant, expected: Variant, message: String) -> bool:
	return check(actual == expected, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func check_near(actual: float, expected: float, epsilon: float, message: String) -> bool:
	return check(absf(actual - expected) <= epsilon, "%s (expected %.4f +/- %.4f, got %.4f)" % [message, expected, epsilon, actual])


func note(text: String) -> void:
	notes.append(text)


func physics_frames(count: int) -> void:
	for i in count:
		await tree.physics_frame


func process_frames(count: int) -> void:
	for i in count:
		await tree.process_frame


func seconds(s: float) -> void:
	await physics_frames(int(ceil(s * Engine.physics_ticks_per_second)))


## Loads the match scene with [param setup] and returns the controller.
func start_match(setup: MatchSetup, skip_intro: bool = true) -> MatchController:
	setup.no_progress = true
	var gs := tree.root.get_node("GameState")
	gs.current_setup = setup
	tree.paused = false
	tree.change_scene_to_file("res://scenes/match/match.tscn")
	await tree.process_frame
	await tree.process_frame
	var m := tree.current_scene as MatchController
	if m and skip_intro:
		m.skip_intro()
	return m


## Leaves the current scene so the next test starts clean.
func end_scene() -> void:
	tree.paused = false
	var flat := Node.new()
	flat.name = "Empty"
	var packed := PackedScene.new()
	packed.pack(flat)
	flat.free()
	tree.change_scene_to_packed(packed)
	await tree.process_frame
	await tree.process_frame


## A small flat test arena with a floor, for movement tests.
func make_flat_world(floor_size: Vector3 = Vector3(60, 2, 60)) -> Node3D:
	var world := Node3D.new()
	world.name = "TestWorld"
	var floor := Block.new()
	floor.size = floor_size
	world.add_child(floor)
	return world


func spawn_test_player(world: Node3D, pos: Vector3, rules: ModifierStack) -> PlayerCharacter:
	var p: PlayerCharacter = load("res://scenes/player/player.tscn").instantiate()
	p.input = ScriptedInputSource.new()
	p.rules = rules
	p.controls_enabled = true
	p.kill_y = -20.0
	world.add_child(p)
	p.teleport(pos)
	p.respawn_position = pos
	return p
