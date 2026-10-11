@tool
class_name BouncePad
extends Area3D
## A spring pad that launches players straight up. Always the same height for
## the same rules, so kids can learn it. Origin on the floor.

signal launched(player: PlayerCharacter)

@export_range(4.0, 40.0, 0.5) var launch_speed: float = 15.0
@export_range(0.4, 4.0, 0.05) var radius: float = 0.9:
	set(v):
		radius = v
		_changed()
## Big round trampoline look instead of a small spring pad.
@export var trampoline: bool = false:
	set(v):
		trampoline = v
		_changed()
@export var color: Color = Color("ff5fa8"):
	set(v):
		color = v
		_changed()

var _top: Node3D
var _cooldowns: Dictionary = {}
var _squash := 0.0
var _queued := false


func _ready() -> void:
	collision_layer = Layers.TRIGGERS
	collision_mask = Layers.PLAYERS
	monitorable = false
	_rebuild()


func _changed() -> void:
	if not is_inside_tree() or _queued:
		return
	_queued = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_queued = false
	Gen.clear(self)
	if trampoline:
		# Solid frame ring around a springy mat.
		var frame := StaticBody3D.new()
		frame.collision_layer = Layers.WORLD
		frame.collision_mask = 0
		Gen.add(self, frame)
		Gen.mesh(frame, MeshFactory.torus(radius - 0.05, radius + 0.35, 32, 10), ToyMaterials.plastic(color),
				Vector3(0, 0.55, 0), Vector3(1, 1.6, 1))
		for i in 6:
			var a := TAU * float(i) / 6.0
			Gen.mesh(frame, MeshFactory.cylinder(0.1, 0.12, 0.55, 8), ToyMaterials.plastic(color.darkened(0.3)),
					Vector3(cos(a) * (radius + 0.15), 0.27, sin(a) * (radius + 0.15)))
		_top = Gen.node(self, Vector3(0, 0.5, 0))
		Gen.mesh(_top, MeshFactory.cylinder(radius, radius, 0.08, 32), ToyMaterials.matte(Color("3b3561")))
		Gen.mesh(_top, MeshFactory.cylinder(radius * 0.45, radius * 0.45, 0.1, 24), ToyMaterials.matte(color.lightened(0.3)),
				Vector3(0, 0.01, 0), Vector3.ONE, Vector3.ZERO, false)
		Gen.cylinder_shape(self, radius, 0.9, Vector3(0, 0.55, 0))
	else:
		Gen.mesh(self, MeshFactory.cylinder(radius * 1.05, radius * 1.15, 0.2, 24), ToyMaterials.plastic(Color("4b4573")),
				Vector3(0, 0.1, 0))
		for i in 3:
			Gen.mesh(self, MeshFactory.torus(radius * 0.35, radius * 0.5, 16, 6), ToyMaterials.plastic(Color("d9d9e6")),
					Vector3(0, 0.22 + i * 0.07, 0), Vector3.ONE, Vector3.ZERO, false)
		_top = Gen.node(self, Vector3(0, 0.42, 0))
		Gen.mesh(_top, MeshFactory.cylinder(radius, radius * 0.95, 0.14, 24), ToyMaterials.plastic(color))
		Gen.mesh(_top, MeshFactory.cylinder(radius * 0.5, radius * 0.5, 0.16, 20), ToyMaterials.plastic(color.lightened(0.35)),
				Vector3(0, 0.01, 0), Vector3.ONE, Vector3.ZERO, false)
		Gen.cylinder_shape(self, radius, 0.8, Vector3(0, 0.4, 0))


func _physics_process(delta: float) -> void:
	if not Gen.in_game():
		return
	for id in _cooldowns.keys():
		_cooldowns[id] = float(_cooldowns[id]) - delta
		if _cooldowns[id] <= 0.0:
			_cooldowns.erase(id)
	for body in get_overlapping_bodies():
		var player := body as PlayerCharacter
		if player == null or player.is_respawning or _cooldowns.has(player.get_instance_id()):
			continue
		if player.velocity.y > 2.0:
			continue
		_cooldowns[player.get_instance_id()] = 0.3
		player.launch(launch_speed)
		_squash = 1.0
		launched.emit(player)
	_squash = maxf(0.0, _squash - delta * 4.0)
	if _top:
		_top.scale = Vector3(1.0 + _squash * 0.15, 1.0 - _squash * 0.5, 1.0 + _squash * 0.15)
		_top.position.y = (0.5 if trampoline else 0.42) - _squash * 0.2


## Apex height (meters above the pad) a launch reaches under normal gravity.
func apex_height(gravity: float = 26.0) -> float:
	return launch_speed * launch_speed / (2.0 * gravity)
