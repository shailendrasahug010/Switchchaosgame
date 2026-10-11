@tool
class_name Turntable
extends AnimatableBody3D
## A round spinning floor. Players standing on it ride around with it.
## Origin is the center of the top face, like Block.

@export_range(1.0, 12.0, 0.1) var radius: float = 4.0:
	set(v):
		radius = v
		_changed()
@export_range(0.2, 3.0, 0.05) var thickness: float = 0.6:
	set(v):
		thickness = v
		_changed()
@export_range(-180.0, 180.0, 1.0) var degrees_per_second: float = 35.0
@export var color: Color = Color("a77bff"):
	set(v):
		color = v
		_changed()
@export var stripe_color: Color = Color("fff3a3"):
	set(v):
		stripe_color = v
		_changed()

var _frozen := false
var _frozen_since := 0.0
var _frozen_total := 0.0
var _base_yaw := 0.0
var _queued := false


func _ready() -> void:
	collision_layer = Layers.WORLD
	collision_mask = 0
	sync_to_physics = true
	_base_yaw = rotation.y
	add_to_group(&"freezable")
	_rebuild()


func _changed() -> void:
	if not is_inside_tree() or _queued:
		return
	_queued = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_queued = false
	Gen.clear(self)
	Gen.mesh(self, MeshFactory.cylinder(radius, radius, thickness, 36), ToyMaterials.matte(color),
			Vector3(0, -thickness * 0.5, 0))
	# Pie-slice stripes so the spinning is easy to see.
	for i in 6:
		Gen.mesh(self, MeshFactory.box(Vector3(radius * 1.94, 0.04, 0.45)), ToyMaterials.matte(stripe_color),
				Vector3(0, 0.02, 0), Vector3.ONE, Vector3(0, i * 30.0, 0), false)
	Gen.mesh(self, MeshFactory.cylinder(0.6, 0.6, 0.08, 20), ToyMaterials.plastic(color.lightened(0.4)),
			Vector3(0, 0.04, 0), Vector3.ONE, Vector3.ZERO, false)
	Gen.cylinder_shape(self, radius, thickness, Vector3(0, -thickness * 0.5, 0))


func _physics_process(_delta: float) -> void:
	if not Gen.in_game():
		return
	var t := (_frozen_since if _frozen else MatchClock.time) - _frozen_total
	rotation.y = _base_yaw + deg_to_rad(degrees_per_second * t)


func set_frozen(value: bool) -> void:
	if value == _frozen:
		return
	if value:
		_frozen_since = MatchClock.time
	else:
		_frozen_total += MatchClock.time - _frozen_since
	_frozen = value
