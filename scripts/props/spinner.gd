@tool
class_name Spinner
extends Node3D
## A soft foam bar sweeping around a pillar. Players jump over it or get a
## gentle bonk (never a "hit": just a push and a dizzy face).
##
## Place it with its origin on the floor. The rotation angle is computed from
## the shared MatchClock so it is the same on every device.

@export_range(1.0, 12.0, 0.1) var arm_length: float = 5.0:
	set(v):
		arm_length = v
		_changed()
## Height of the bar's center above the floor. Under ~1.0 can be jumped over.
@export_range(0.3, 3.0, 0.05) var arm_height: float = 0.6:
	set(v):
		arm_height = v
		_changed()
@export_range(-360.0, 360.0, 1.0) var degrees_per_second: float = 75.0
@export_range(0.0, 360.0, 1.0) var start_angle: float = 0.0
## Two bars (both directions) instead of one.
@export var double_arm: bool = true:
	set(v):
		double_arm = v
		_changed()
@export var color: Color = Color("ff6f91"):
	set(v):
		color = v
		_changed()
@export var knock_strength: float = 9.0

var _pivot: Node3D
var _knock: KnockArea
var _queued := false


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
	# Center pillar (solid).
	var pillar := StaticBody3D.new()
	pillar.collision_layer = Layers.WORLD
	pillar.collision_mask = 0
	Gen.add(self, pillar)
	var pillar_h := arm_height + 0.7
	Gen.cylinder_shape(pillar, 0.45, pillar_h, Vector3(0, pillar_h * 0.5, 0))
	Gen.mesh(pillar, MeshFactory.cylinder(0.42, 0.5, pillar_h, 20), ToyMaterials.plastic(Color("fff3a3")),
			Vector3(0, pillar_h * 0.5, 0))
	Gen.mesh(pillar, MeshFactory.sphere(0.55, 0.8, 20, 8), ToyMaterials.plastic(color.lightened(0.2)),
			Vector3(0, pillar_h, 0))
	# Rotating bar(s).
	_pivot = Gen.node(self, Vector3(0, arm_height, 0))
	var start := 0.55 if double_arm else 0.3
	var length := arm_length - start
	var arms := [1.0, -1.0] if double_arm else [1.0]
	for side: float in arms:
		var center_x := side * (start + length * 0.5)
		var bar := Gen.mesh(_pivot, MeshFactory.capsule(0.32, length, 16, 4), ToyMaterials.plastic(color),
				Vector3(center_x, 0, 0), Vector3.ONE, Vector3(0, 0, 90))
		bar.name = "Bar"
		# Candy stripes.
		var stripes := int(length / 0.8)
		for i in stripes:
			var x := side * (start + 0.4 + i * 0.8)
			Gen.mesh(_pivot, MeshFactory.cylinder(0.335, 0.335, 0.16, 16), ToyMaterials.plastic(Color.WHITE),
					Vector3(x, 0, 0), Vector3.ONE, Vector3(0, 0, 90), false)
	_knock = KnockArea.new()
	_knock.strength = knock_strength
	_knock.push_direction = _push_dir
	Gen.add(_pivot, _knock)
	var reach := arm_length * 2.0 if double_arm else arm_length
	var shape_center := 0.0 if double_arm else arm_length * 0.5
	Gen.box_shape(_knock, Vector3(reach, 0.7, 0.75), Vector3(shape_center, 0, 0))
	_apply_angle()


func _physics_process(_delta: float) -> void:
	if Gen.in_game():
		_apply_angle()


func _apply_angle() -> void:
	if _pivot:
		var t := MatchClock.now(self) if Gen.in_game() else 0.0
		_pivot.rotation.y = deg_to_rad(start_angle + degrees_per_second * t)


## Push along the bar's motion, a little outward.
func _push_dir(player: PlayerCharacter) -> Vector3:
	var r := player.global_position - global_position
	r.y = 0.0
	if r.length() < 0.01:
		return Vector3.FORWARD
	var tangent := Vector3.UP.cross(r).normalized() * signf(degrees_per_second)
	return (tangent + r.normalized() * 0.35).normalized()
