@tool
class_name RunawayCar
extends AnimatableBody3D
## A wind-up toy car that drives around an oval, usually carrying a
## PushButton on its roof (add the button as a child in the scene).
##
## When someone gets close it zooms away ("Run away!") for a moment, then gets
## tired and crawls for a few seconds: that is the moment to catch it.
## It also obeys the floor rules: Sticky Mode slows it down, like everyone.
## Place the node anywhere on the oval; [member loop_center] is the oval's middle.

enum State { CRUISE, FLEE, TIRED }

signal state_changed(state: State)

@export var loop_center: Vector3 = Vector3.ZERO:
	set(v):
		loop_center = v
		_changed()
## Half-widths of the oval along X and Z.
@export var loop_radii: Vector2 = Vector2(7.0, 5.0):
	set(v):
		loop_radii = v
		_changed()
@export var cruise_speed: float = 2.2
@export var flee_speed: float = 4.6
@export var flee_radius: float = 4.0
@export var flee_time: float = 2.4
@export var tired_time: float = 3.2
## +1 drives counter-clockwise seen from above, -1 clockwise.
@export var direction: float = 1.0
@export var color: Color = Color("a77bff"):
	set(v):
		color = v
		_changed()

## Multiplier from the chaos rules (set by the game mode every tick).
var speed_scale: float = 1.0
## Things that make the car flee when they come close (the players).
var chasers: Array[Node3D] = []
var state: State = State.CRUISE
var velocity: Vector3 = Vector3.ZERO
## Online phones: the room server drives the car; this copy only follows it.
var net_puppet: bool = false

var _angle := 0.0
var _state_left := 0.0
var _visual: Node3D
var _key: Node3D
var _wheels: Array[Node3D] = []
var _sweat: Node3D
var _time := 0.0
var _queued := false
var _net_angle := 0.0
var _net_has_target := false


func _ready() -> void:
	collision_layer = Layers.WORLD
	collision_mask = 0
	sync_to_physics = true
	var rel := position - loop_center
	_angle = atan2(rel.z / maxf(loop_radii.y, 0.01), rel.x / maxf(loop_radii.x, 0.01))
	_rebuild()
	if Gen.in_game():
		_place(0.0)


func _changed() -> void:
	if not is_inside_tree() or _queued:
		return
	_queued = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_queued = false
	Gen.clear(self)
	_wheels.clear()
	Gen.box_shape(self, Vector3(1.0, 0.62, 1.5), Vector3(0, 0.46, 0))
	_visual = Gen.node(self)
	var body_mat := ToyMaterials.plastic(color)
	Gen.mesh(_visual, MeshFactory.box(Vector3(1.0, 0.5, 1.5)), body_mat, Vector3(0, 0.45, 0))
	Gen.mesh(_visual, MeshFactory.capsule(0.5, 1.5, 16, 4), body_mat, Vector3(0, 0.62, 0), Vector3(1, 0.42, 1),
			Vector3(90, 0, 0), false)
	# Wheels.
	for x: float in [-0.55, 0.55]:
		for z: float in [-0.48, 0.48]:
			var w := Gen.node(_visual, Vector3(x, 0.24, z))
			Gen.mesh(w, MeshFactory.cylinder(0.24, 0.24, 0.16, 16), ToyMaterials.plastic(Color("3b3561")), Vector3.ZERO,
					Vector3.ONE, Vector3(0, 0, 90))
			Gen.mesh(w, MeshFactory.cylinder(0.1, 0.1, 0.18, 10), ToyMaterials.plastic(Color("fff3a3")), Vector3.ZERO,
					Vector3.ONE, Vector3(0, 0, 90), false)
			_wheels.append(w)
	# Big friendly eyes on the front (-Z is forward).
	for x: float in [-0.22, 0.22]:
		Gen.mesh(_visual, MeshFactory.sphere(0.17, 0.34, 14, 7), ToyMaterials.plastic(Color.WHITE), Vector3(x, 0.62, -0.72))
		Gen.mesh(_visual, MeshFactory.sphere(0.08, 0.16, 10, 5), ToyMaterials.plastic(Color("1c1a33")),
				Vector3(x, 0.63, -0.86), Vector3.ONE, Vector3.ZERO, false)
	# Wind-up key on the back.
	_key = Gen.node(_visual, Vector3(0, 0.65, 0.85))
	Gen.mesh(_key, MeshFactory.cylinder(0.05, 0.05, 0.3, 8), ToyMaterials.plastic(Color("ffd23f")), Vector3(0, 0, 0.12),
			Vector3.ONE, Vector3(90, 0, 0), false)
	for side: float in [-1.0, 1.0]:
		Gen.mesh(_key, MeshFactory.torus(0.06, 0.16, 14, 6), ToyMaterials.plastic(Color("ffd23f")),
				Vector3(side * 0.17, 0, 0.3), Vector3.ONE, Vector3(0, 0, 90), false)
	# Sweat drops when tired.
	_sweat = Gen.node(_visual, Vector3(0.5, 1.3, -0.3))
	for i in 2:
		Gen.mesh(_sweat, MeshFactory.sphere(0.08, 0.2, 8, 4), ToyMaterials.glass(Color("8fd3ff"), 0.85),
				Vector3(i * 0.18, -i * 0.14, 0), Vector3.ONE, Vector3.ZERO, false)
	_sweat.visible = false
	_build_track()


## A dashed guide line on the floor showing the car's loop. It stays put
## (top level), only the car moves.
func _build_track() -> void:
	var track := Gen.node(self)
	track.top_level = true
	var parent_xform := Transform3D.IDENTITY
	if is_inside_tree() and get_parent() is Node3D:
		parent_xform = (get_parent() as Node3D).global_transform
	track.transform = Transform3D(Basis(), parent_xform * loop_center)
	var count := 36
	var mat := ToyMaterials.matte(color.lightened(0.45))
	for i in count:
		if i % 2 == 1:
			continue
		var a := TAU * float(i) / count
		var a2 := TAU * float(i + 1) / count
		var p1 := Vector3(cos(a) * loop_radii.x, 0.03, sin(a) * loop_radii.y)
		var p2 := Vector3(cos(a2) * loop_radii.x, 0.03, sin(a2) * loop_radii.y)
		var mi := Gen.mesh(track, MeshFactory.box(Vector3(0.22, 0.04, p1.distance_to(p2))), mat, Vector3.ZERO,
				Vector3.ONE, Vector3.ZERO, false)
		mi.transform = Transform3D(Basis.looking_at((p2 - p1).normalized(), Vector3.UP), (p1 + p2) * 0.5)


func _physics_process(delta: float) -> void:
	if not Gen.in_game():
		return
	_time += delta
	if net_puppet:
		# Keep driving on our own (smooth), and steer toward the server's car.
		if _net_has_target:
			_net_angle += direction * current_speed() * delta / maxf(_radius_at(_net_angle), 0.1)
			var error := _net_angle - _angle
			if absf(error) > 1.5:
				_angle = _net_angle
			else:
				_angle += error * clampf(delta * 6.0, 0.0, 1.0)
		_place(delta)
		return
	_update_state(delta)
	_place(delta)


func _update_state(delta: float) -> void:
	_state_left -= delta
	match state:
		State.CRUISE:
			if _someone_close():
				_set_state(State.FLEE, flee_time)
		State.FLEE:
			if _state_left <= 0.0:
				_set_state(State.TIRED, tired_time)
		State.TIRED:
			if _state_left <= 0.0:
				_set_state(State.CRUISE, 0.0)


func _set_state(s: State, seconds: float) -> void:
	state = s
	_state_left = seconds
	if _sweat:
		_sweat.visible = s == State.TIRED
	state_changed.emit(s)


func _someone_close() -> bool:
	for c in chasers:
		if not is_instance_valid(c) or c.get("is_respawning") == true:
			continue
		var d := c.global_position - global_position
		if Vector2(d.x, d.z).length() < flee_radius and absf(d.y) < 2.5:
			return true
	return false


func current_speed() -> float:
	var s := cruise_speed
	match state:
		State.FLEE:
			s = flee_speed
		State.TIRED:
			s = cruise_speed * 0.25
	return s * clampf(speed_scale, 0.2, 2.0)


func _radius_at(angle: float) -> float:
	return Vector2(maxf(loop_radii.x, 0.01) * sin(angle), maxf(loop_radii.y, 0.01) * cos(angle)).length()


## Room server: [angle, state] for the phones.
func get_net_state() -> PackedFloat32Array:
	return PackedFloat32Array([_angle, float(state)])


## Phone: follows the server's car (see [member net_puppet]).
func apply_net_state(data: Variant) -> void:
	if typeof(data) != TYPE_PACKED_FLOAT32_ARRAY or (data as PackedFloat32Array).size() < 2:
		return
	net_puppet = true
	_net_angle = data[0]
	if not _net_has_target:
		_angle = _net_angle
		_net_has_target = true
	var s := clampi(int(data[1]), 0, State.size() - 1) as State
	if s != state:
		_set_state(s, 0.0)


func _place(delta: float) -> void:
	var rx := maxf(loop_radii.x, 0.01)
	var rz := maxf(loop_radii.y, 0.01)
	# Advance by arc length so the speed is even all around the oval.
	if not net_puppet:
		_angle += direction * current_speed() * delta / maxf(_radius_at(_angle), 0.1)
	var parent_xform := Transform3D.IDENTITY
	if get_parent() is Node3D:
		parent_xform = (get_parent() as Node3D).global_transform
	var pos := parent_xform * (loop_center + Vector3(cos(_angle) * rx, 0.0, sin(_angle) * rz))
	var tangent := Vector3(-sin(_angle) * rx, 0.0, cos(_angle) * rz).normalized() * signf(direction)
	var old := global_position
	global_transform = Transform3D(Basis.looking_at(tangent, Vector3.UP), pos)
	if delta > 0.0:
		velocity = (pos - old) / delta
	# Wheels spin, the key turns, and the car bounces a little when fleeing.
	var spin := current_speed() * delta / 0.24
	for w in _wheels:
		w.rotate_x(-spin)
	if _key:
		_key.rotate_z(delta * (9.0 if state == State.FLEE else 2.5))
	if _visual:
		_visual.position.y = absf(sin(_time * 14.0)) * 0.08 if state == State.FLEE else 0.0


## Where the car will be in [param seconds] if nothing changes (for CPU buddies).
func predict_position(seconds: float) -> Vector3:
	var rx := maxf(loop_radii.x, 0.01)
	var rz := maxf(loop_radii.y, 0.01)
	var local_r := Vector2(rx * sin(_angle), rz * cos(_angle)).length()
	var a := _angle + direction * current_speed() * seconds / maxf(local_r, 0.1)
	var parent_xform := Transform3D.IDENTITY
	if get_parent() is Node3D:
		parent_xform = (get_parent() as Node3D).global_transform
	return parent_xform * (loop_center + Vector3(cos(a) * rx, 0.0, sin(a) * rz))
