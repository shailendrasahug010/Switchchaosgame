@tool
class_name Pendulum
extends Node3D
## A big soft candy hammer swinging from an arch, along the node's local X axis.
## Rotate the node to aim the swing. Place the origin on the floor.

@export_range(1.5, 8.0, 0.1) var length: float = 3.6:
	set(v):
		length = v
		_changed()
@export_range(5.0, 85.0, 1.0) var swing_degrees: float = 55.0
@export_range(0.5, 10.0, 0.1) var period: float = 3.2
@export_range(0.0, 1.0, 0.01) var phase: float = 0.0
## Distance between the arch posts.
@export_range(2.0, 14.0, 0.1) var frame_width: float = 6.0:
	set(v):
		frame_width = v
		_changed()
@export var color: Color = Color("ff5fa8"):
	set(v):
		color = v
		_changed()
@export var knock_strength: float = 10.0

var _pivot: Node3D
var _queued := false
var _head_height := 0.9


func _ready() -> void:
	_rebuild()


func _changed() -> void:
	if not is_inside_tree() or _queued:
		return
	_queued = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_queued = false
	Gen.clear(self)
	var top := length + _head_height
	# Arch frame: two posts and a crossbar (posts are solid).
	var frame := StaticBody3D.new()
	frame.collision_layer = Layers.WORLD
	frame.collision_mask = 0
	Gen.add(self, frame)
	for side: float in [-1.0, 1.0]:
		var x := side * frame_width * 0.5
		Gen.cylinder_shape(frame, 0.3, top, Vector3(x, top * 0.5, 0))
		Gen.mesh(frame, MeshFactory.cylinder(0.28, 0.34, top, 14), ToyMaterials.plastic(Color("fff8ee")),
				Vector3(x, top * 0.5, 0))
		Gen.mesh(frame, MeshFactory.sphere(0.4, 0.8, 14, 7), ToyMaterials.plastic(color), Vector3(x, top + 0.1, 0))
	Gen.mesh(frame, MeshFactory.capsule(0.22, frame_width, 14, 4), ToyMaterials.plastic(Color("fff8ee")),
			Vector3(0, top, 0), Vector3.ONE, Vector3(0, 0, 90))
	# Swinging hammer.
	_pivot = Gen.node(self, Vector3(0, top, 0))
	Gen.mesh(_pivot, MeshFactory.cylinder(0.09, 0.09, length, 10), ToyMaterials.plastic(Color.WHITE),
			Vector3(0, -length * 0.5, 0))
	for i in int(length / 0.6):
		Gen.mesh(_pivot, MeshFactory.cylinder(0.1, 0.1, 0.18, 10), ToyMaterials.plastic(color),
				Vector3(0, -0.4 - i * 0.6, 0), Vector3.ONE, Vector3.ZERO, false)
	var head := Gen.node(_pivot, Vector3(0, -length, 0))
	Gen.mesh(head, MeshFactory.cylinder(0.75, 0.75, 1.5, 22), ToyMaterials.plastic(color), Vector3.ZERO,
			Vector3.ONE, Vector3(90, 0, 0))
	Gen.mesh(head, MeshFactory.cylinder(0.78, 0.78, 0.3, 22), ToyMaterials.plastic(Color.WHITE), Vector3.ZERO,
			Vector3.ONE, Vector3(90, 0, 0), false)
	var knock := KnockArea.new()
	knock.strength = knock_strength
	knock.push_direction = _push_dir
	Gen.add(head, knock)
	Gen.cylinder_shape(knock, 0.85, 1.6, Vector3.ZERO, Vector3(90, 0, 0))
	_apply_angle()


func _physics_process(_delta: float) -> void:
	if Gen.in_game():
		_apply_angle()


func _angle_at(t: float) -> float:
	return deg_to_rad(swing_degrees) * sin(TAU * (t / period + phase))


func _apply_angle() -> void:
	if _pivot:
		var t := MatchClock.now(self) if Gen.in_game() else period * 0.25
		_pivot.rotation.z = _angle_at(t)


func _push_dir(_player: PlayerCharacter) -> Vector3:
	var swing_speed := cos(TAU * (MatchClock.now(self) / period + phase))
	var dir := global_transform.basis.x * signf(swing_speed if absf(swing_speed) > 0.05 else 1.0)
	return dir
