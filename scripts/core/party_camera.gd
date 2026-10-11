class_name PartyCamera
extends Camera3D
## Follows the action from a fixed, kid-friendly angle.
##
## The angle never rotates on its own, so "push the stick up" always means
## "go away from the camera". Every frame the camera works out a framing that
## keeps its targets inside the part of the screen the HUD leaves free:
##
##   priority 1 (MUST)   people playing on this device: never lost off-screen
##   priority 2 (SHOULD) the objective (the cake...): kept in view when it fits
##   priority 3 (NICE)   CPU buddies: only used when there is nothing else
##
## It zooms out (up to [member max_distance]) when targets spread apart, and if
## priority-2 targets cannot fit together with the players, they are dropped so
## the players stay visible.

enum Priority { MUST = 1, SHOULD = 2, NICE = 3 }

@export var yaw_degrees: float = 0.0
@export_range(-89.0, -5.0, 0.5) var pitch_degrees: float = -38.0
@export var base_distance: float = 12.0
@export var min_distance: float = 9.0
@export var max_distance: float = 24.0
## World-space offset added to the focus point (look a little ahead).
@export var look_ahead: Vector3 = Vector3(0, 0, -2.0)
@export var follow_speed: float = 4.0
## Optional limits for the focus point (zero size = no limits).
@export var bounds: AABB = AABB()
## Screen area (normalized device coords, -1..1, y up) that targets must stay
## inside. The top is kept free for the HUD, the bottom corners for touch buttons.
@export var safe_left: float = -0.78
@export var safe_right: float = 0.78
@export var safe_bottom: float = -0.72
@export var safe_top: float = 0.40

var reduced_motion: bool = false

var _targets: Array[Dictionary] = []  # {node: Node3D, priority: int, height: float}
var _focus: Vector3 = Vector3.ZERO
var _distance: float = 12.0
var _shake: float = 0.0
var _shake_time: float = 0.0
var _has_focus := false
var _last_fit_ok := true


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_distance = base_distance


## Heading of "forward" for player controls, in radians.
func get_control_yaw() -> float:
	return deg_to_rad(yaw_degrees)


## [param targets]: [{node, priority (1..3), height (optional, meters above the origin to keep in view)}]
## A legacy "weight" key is accepted: weight >= 1 -> MUST, > 0 -> SHOULD.
func set_targets(targets: Array[Dictionary]) -> void:
	_targets.clear()
	for t in targets:
		add_target(t.node, int(t.get("priority", _priority_from_weight(float(t.get("weight", 1.0))))),
				float(t.get("height", 1.8)))


func add_target(node: Node3D, priority: int = Priority.MUST, height: float = 1.8) -> void:
	_targets.append({"node": node, "priority": clampi(priority, 1, 3), "height": height})


func clear_targets() -> void:
	_targets.clear()


func _priority_from_weight(w: float) -> int:
	if w >= 1.0:
		return Priority.MUST
	if w > 0.0:
		return Priority.SHOULD
	return Priority.NICE


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


## True when the last computed framing fitted every MUST target on screen.
func is_framing_ok() -> bool:
	return _last_fit_ok


func _process(delta: float) -> void:
	var info := _compute_goal()
	if not info.is_empty():
		if not _has_focus:
			_focus = info.focus
			_distance = info.distance
			_has_focus = true
		var k := 1.0 - exp(-follow_speed * delta)
		_focus = _focus.lerp(info.focus, k)
		# Zoom out quickly (someone is about to leave the screen), zoom in gently.
		var zoom_rate := 5.0 if info.distance > _distance else 1.6
		_distance = lerpf(_distance, info.distance, 1.0 - exp(-zoom_rate * delta))
	_apply(delta)


# ---------------------------------------------------------------- framing

func _rot_basis() -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(pitch_degrees), deg_to_rad(yaw_degrees), 0.0), EULER_ORDER_YXZ)


## Collects the points (feet and head) of the visible targets of each priority.
func _points_by_priority() -> Dictionary:
	var out := {1: [], 2: [], 3: []}
	for t in _targets:
		var node: Node3D = t.node
		if not is_instance_valid(node) or not node.is_inside_tree() or not node.visible:
			continue
		if node.get("is_respawning") == true:
			continue
		var p := node.get_global_transform_interpolated().origin
		var list: Array = out[int(t.priority)]
		list.append(p)
		list.append(p + Vector3(0, float(t.height), 0))
	return out


func _compute_goal() -> Dictionary:
	var by_priority := _points_by_priority()
	var must: Array = by_priority[1]
	var should: Array = by_priority[2]
	var nice: Array = by_priority[3]
	var sets: Array = []
	if not must.is_empty():
		if not should.is_empty():
			sets.append(must + should)
		sets.append(must)
	elif not should.is_empty():
		sets.append(should + nice)
		sets.append(should)
	elif not nice.is_empty():
		sets.append(nice)
	if sets.is_empty():
		return {}
	var fallback: Dictionary = {}
	for i in sets.size():
		var result := _fit(sets[i])
		if result.fits:
			_last_fit_ok = true
			return result
		if i == sets.size() - 1:
			fallback = result
	# Nothing fits even at max distance (players far apart): best effort.
	_last_fit_ok = false
	return fallback


## Smallest distance (>= the comfortable base distance) at which every point
## sits inside the safe screen area.
func _fit(points: Array) -> Dictionary:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for p: Vector3 in points:
		lo = lo.min(p)
		hi = hi.max(p)
	var center := (lo + hi) * 0.5
	var focus := Vector3(center.x, lo.y + 1.0, center.z) + look_ahead
	if bounds.size != Vector3.ZERO:
		focus.x = clampf(focus.x, bounds.position.x, bounds.end.x)
		focus.z = clampf(focus.z, bounds.position.z, bounds.end.z)
	var basis := _rot_basis()
	var spread := Vector2(hi.x - lo.x, hi.z - lo.z).length() * 0.5
	var start := clampf(base_distance + maxf(0.0, spread - 4.0) * 0.35, min_distance, max_distance)
	var d := start
	while true:
		if _all_inside(points, focus, d, basis):
			return {"focus": focus, "distance": d, "fits": true}
		if d >= max_distance:
			break
		d = minf(max_distance, d + 0.5)
	return {"focus": focus, "distance": max_distance, "fits": false}


func _all_inside(points: Array, focus: Vector3, distance: float, basis: Basis) -> bool:
	var xf := _camera_transform(focus, distance, basis)
	var inv := xf.affine_inverse()
	var tan_v := tan(deg_to_rad(fov) * 0.5)
	var vp := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 720)
	var tan_h := tan_v * (vp.x / maxf(vp.y, 1.0))
	for p: Vector3 in points:
		var v := inv * p
		var depth := -v.z
		if depth <= near:
			return false
		var nx := v.x / (depth * tan_h)
		var ny := v.y / (depth * tan_v)
		if nx < safe_left or nx > safe_right or ny < safe_bottom or ny > safe_top:
			return false
	return true


## Camera transform for a focus point and distance. The camera is shifted up a
## little (like a lens shift) so the focus lands in the middle of the safe area
## rather than the middle of the screen.
func _camera_transform(focus: Vector3, distance: float, basis: Basis) -> Transform3D:
	var forward := -basis.z
	var tan_v := tan(deg_to_rad(fov) * 0.5)
	var screen_center_y := (safe_top + safe_bottom) * 0.5
	var lift := -screen_center_y * distance * tan_v
	return Transform3D(basis, focus - forward * distance + basis.y * lift)


func _apply(delta: float) -> void:
	var basis := _rot_basis()
	var xf := _camera_transform(_focus, _distance, basis)
	if _shake > 0.0:
		_shake_time += delta * 40.0
		xf.origin += Vector3(sin(_shake_time * 1.3), sin(_shake_time * 1.7 + 1.0), 0.0) * _shake * 0.35
		_shake = maxf(0.0, _shake - delta * 2.5)
	global_transform = xf
