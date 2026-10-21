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


# ---------------------------------------------------------------- CPU buddies

## For CPU buddies walking from [param from] toward [param to]: returns null
## when that is fine right now, or a spot just outside the hammer's lane to
## wait at until the hammer has swung past. [param top_speed] and
## [param cruise] are the walker's fastest and usual speeds (m/s), [param lag]
## how long it takes to get going. [param strictness] (1 = whole crossing must
## be clear, lower = only its first part) drops while a buddy waits, so it
## still goes at the best moment if a fully clear gap never comes. The swing
## only depends on the round clock, so the answer is fully predictable.
func bot_wait_spot(from: Vector3, to: Vector3, body_radius: float, body_height: float,
		top_speed: float, cruise: float, lag: float, strictness: float = 1.0) -> Variant:
	if _pivot == null:
		return null
	var a := to_local(from)
	var b := to_local(to)
	# Half-depth of the strip the hammer head sweeps (head is 1.6 long).
	var lane := 0.8 + body_radius
	if absf(a.z) <= lane:
		return null  # already crossing: keep going
	if absf(b.z) > lane and signf(a.z) == signf(b.z):
		return null  # not crossing this hammer
	if minf(a.y, b.y) > length + _head_height:
		return null  # passing above it
	var span := maxf(0.001, absf(a.z - b.z))
	var x_enter := lerpf(a.x, b.x, clampf((absf(a.z) - lane) / span, 0.0, 1.0))
	var x_exit := lerpf(a.x, b.x, clampf((absf(a.z) + lane) / span, 0.0, 1.0))
	# Earliest moment we could be in the lane, latest moment we are out of it.
	var t_enter := (absf(a.z) - lane) / maxf(top_speed, 0.5) - 0.1
	var t_exit := (absf(a.z) + lane + 0.3) / maxf(cruise, 0.5) + lag + 0.1
	t_exit = t_enter + (t_exit - t_enter) * clampf(strictness, 0.3, 1.0)
	if not danger_between(minf(x_enter, x_exit), maxf(x_enter, x_exit), t_enter, t_exit,
			body_radius, body_height):
		return null
	return to_global(Vector3(a.x, a.y, signf(a.z) * (lane + 0.8)))


## True when the hammer head may reach someone standing anywhere between
## local x [param x0] and [param x1] (inside its lane) at some moment from
## [param t_from] to [param t_to] seconds from now.
func danger_between(x0: float, x1: float, t_from: float, t_to: float, body_radius: float,
		body_height: float) -> bool:
	var top := length + _head_height
	var now := MatchClock.now(self)
	var reach := 0.85 + body_radius + 0.1
	var t := maxf(0.0, t_from)
	while t <= t_to:
		var ang := _angle_at(now + t)
		var hx := length * sin(ang)
		var hy := top - length * cos(ang)
		var dx := 0.0 if (hx >= x0 and hx <= x1) else minf(absf(hx - x0), absf(hx - x1))
		if dx < reach and hy - 0.85 < body_height:
			return true
		t += 0.05
	return false


func _push_dir(_player: PlayerCharacter) -> Vector3:
	var swing_speed := cos(TAU * (MatchClock.now(self) / period + phase))
	var dir := global_transform.basis.x * signf(swing_speed if absf(swing_speed) > 0.05 else 1.0)
	return dir
