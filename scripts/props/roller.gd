@tool
class_name Roller
extends Node3D
## A giant frosted donut rolling back and forth along the local X axis.
## Rotate the node to change the rolling direction. Origin on the floor.

@export_range(2.0, 30.0, 0.1) var travel_width: float = 10.0
@export_range(0.5, 2.5, 0.05) var radius: float = 1.1:
	set(v):
		radius = v
		_changed()
@export_range(1.0, 15.0, 0.1) var period: float = 4.5
@export_range(0.0, 1.0, 0.01) var phase: float = 0.0
@export var dough_color: Color = Color("e9a65b"):
	set(v):
		dough_color = v
		_changed()
@export var frosting_color: Color = Color("ff7eb6"):
	set(v):
		frosting_color = v
		_changed()
@export var knock_strength: float = 9.0

var _wheel: Node3D
var _spin: Node3D
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
	_wheel = Gen.node(self, Vector3(0, radius, 0))
	_spin = Gen.node(_wheel)
	var thickness := radius * 0.55
	# A torus standing upright (ring in the XY plane), rolling along X.
	Gen.mesh(_spin, MeshFactory.torus(radius * 0.38, radius, 26, 12), ToyMaterials.plastic(dough_color),
			Vector3.ZERO, Vector3(1, 1, 1), Vector3(90, 0, 0))
	Gen.mesh(_spin, MeshFactory.torus(radius * 0.45, radius * 0.93, 26, 10), ToyMaterials.plastic(frosting_color),
			Vector3(0, 0, thickness * 0.18), Vector3(1, 0.9, 1), Vector3(90, 0, 0), false)
	# Sprinkles on the frosting.
	for i in 10:
		var a := TAU * float(i) / 10.0
		var r := radius * 0.7
		Gen.mesh(_spin, MeshFactory.capsule(0.05, 0.22, 6, 2),
				ToyMaterials.plastic(ToyMaterials.SPRINKLE_COLORS[i % ToyMaterials.SPRINKLE_COLORS.size()]),
				Vector3(cos(a) * r, sin(a) * r, thickness * 0.38), Vector3.ONE, Vector3(0, 0, rad_to_deg(a) + 40.0), false)
	var knock := KnockArea.new()
	knock.strength = knock_strength
	knock.push_direction = _push_dir
	Gen.add(_wheel, knock)
	Gen.cylinder_shape(knock, radius * 1.02, thickness + 0.3, Vector3.ZERO, Vector3(90, 0, 0))
	_apply()


func _physics_process(_delta: float) -> void:
	if Gen.in_game():
		_apply()


func _offset_at(t: float) -> float:
	var u := fposmod(t / period + phase, 1.0)
	var tri := 1.0 - absf(2.0 * u - 1.0)
	return (0.5 - 0.5 * cos(PI * tri) - 0.5) * travel_width


func _apply() -> void:
	if _wheel == null:
		return
	var t := MatchClock.now(self) if Gen.in_game() else 0.0
	var x := _offset_at(t)
	_wheel.position = Vector3(x, radius, 0)
	_spin.rotation.z = -x / radius


func _push_dir(player: PlayerCharacter) -> Vector3:
	var t := MatchClock.now(self)
	var moving := signf(_offset_at(t + 0.05) - _offset_at(t))
	var along := global_transform.basis.x * (moving if moving != 0.0 else 1.0)
	var away := player.global_position - _wheel.global_position
	away.y = 0.0
	return (along + away.normalized() * 0.5).normalized()
