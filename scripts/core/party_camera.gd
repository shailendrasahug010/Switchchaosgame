class_name PartyCamera
extends Camera3D
## Follows the action from a fixed, kid-friendly angle.
##
## The angle never rotates on its own, so "push the stick up" always means
## "go away from the camera". The camera frames a weighted set of targets
## (for example the cake counts more than a CPU buddy) and zooms out when
## players spread apart.

@export var yaw_degrees: float = 0.0
@export_range(-89.0, -5.0, 0.5) var pitch_degrees: float = -38.0
@export var base_distance: float = 12.0
@export var min_distance: float = 9.0
@export var max_distance: float = 24.0
## Extra distance per meter that targets are spread apart.
@export var spread_zoom: float = 0.8
## World-space offset added to the focus point (look a little ahead).
@export var look_ahead: Vector3 = Vector3(0, 0, -2.0)
@export var follow_speed: float = 4.0
@export var target_height: float = 1.0
## Optional limits for the focus point (zero size = no limits).
@export var bounds: AABB = AABB()

var reduced_motion: bool = false

var _targets: Array[Dictionary] = []  # {node: Node3D, weight: float}
var _focus: Vector3 = Vector3.ZERO
var _distance: float = 12.0
var _shake: float = 0.0
var _shake_time: float = 0.0
var _has_focus := false


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_distance = base_distance


## Heading of "forward" for player controls, in radians.
func get_control_yaw() -> float:
	return deg_to_rad(yaw_degrees)


func set_targets(targets: Array[Dictionary]) -> void:
	_targets = targets


func add_target(node: Node3D, weight: float = 1.0) -> void:
	_targets.append({"node": node, "weight": weight})


func clear_targets() -> void:
	_targets.clear()


## Jumps straight to the current framing (no smoothing), e.g. at round start.
func snap() -> void:
	var info := _compute_goal()
	if info.is_empty():
		return
	_focus = info.focus
	_distance = info.distance
	_has_focus = true
	_apply(0.0)


func shake(amount: float = 0.3) -> void:
	if reduced_motion:
		return
	_shake = maxf(_shake, amount)


func _process(delta: float) -> void:
	var info := _compute_goal()
	if not info.is_empty():
		if not _has_focus:
			_focus = info.focus
			_distance = info.distance
			_has_focus = true
		var k := 1.0 - exp(-follow_speed * delta)
		_focus = _focus.lerp(info.focus, k)
		_distance = lerpf(_distance, info.distance, 1.0 - exp(-2.5 * delta))
	_apply(delta)


func _compute_goal() -> Dictionary:
	var total := 0.0
	var center := Vector3.ZERO
	var points: Array[Vector3] = []
	for t in _targets:
		var node: Node3D = t.node
		if not is_instance_valid(node) or not node.is_inside_tree() or not node.visible:
			continue
		var w: float = t.weight
		if w <= 0.0:
			continue
		var p := node.get_global_transform_interpolated().origin
		center += p * w
		total += w
		points.append(p)
	if total <= 0.0:
		return {}
	center /= total
	var spread := 0.0
	for p in points:
		spread = maxf(spread, Vector2(p.x - center.x, p.z - center.z).length())
	var focus := center + look_ahead + Vector3(0, target_height, 0)
	if bounds.size != Vector3.ZERO:
		focus.x = clampf(focus.x, bounds.position.x, bounds.end.x)
		focus.z = clampf(focus.z, bounds.position.z, bounds.end.z)
	var dist := clampf(base_distance + spread * spread_zoom, min_distance, max_distance)
	return {"focus": focus, "distance": dist}


func _apply(delta: float) -> void:
	var rot_basis := Basis.from_euler(Vector3(deg_to_rad(pitch_degrees), deg_to_rad(yaw_degrees), 0.0), EULER_ORDER_YXZ)
	var forward := -rot_basis.z
	var pos := _focus - forward * _distance
	if _shake > 0.0:
		_shake_time += delta * 40.0
		pos += Vector3(sin(_shake_time * 1.3), sin(_shake_time * 1.7 + 1.0), 0.0) * _shake * 0.35
		_shake = maxf(0.0, _shake - delta * 2.5)
	global_transform = Transform3D(rot_basis, pos)
