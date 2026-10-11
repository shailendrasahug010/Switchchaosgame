@tool
class_name MovingPlatform
extends AnimatableBody3D
## A platform that glides to [member travel] and back, pausing at both ends.
##
## Its position is computed from the shared MatchClock (never accumulated
## deltas), so it is predictable for players and identical on every device.
## Players standing on it are carried along automatically.

@export var size: Vector3 = Vector3(4, 0.6, 4):
	set(v):
		size = v.max(Vector3(0.1, 0.1, 0.1))
		_changed()
@export var color: Color = Color("7fd6ff"):
	set(v):
		color = v
		_changed()
## Offset of the far end of the trip, relative to where the platform is placed.
@export var travel: Vector3 = Vector3(6, 0, 0):
	set(v):
		travel = v
		_changed()
## Seconds for a full there-and-back trip.
@export_range(0.5, 30.0, 0.1) var period: float = 6.0
## Where in its trip the platform starts (0..1), to offset neighbours.
@export_range(0.0, 1.0, 0.01) var phase: float = 0.0
## Share of the trip spent waiting at each end, so it is easy to hop on.
@export_range(0.0, 0.45, 0.01) var hold: float = 0.15
@export var show_rail: bool = true:
	set(v):
		show_rail = v
		_changed()

var _start: Vector3
var _frozen := false
var _frozen_since := 0.0
var _frozen_total := 0.0
var _queued := false


func _ready() -> void:
	collision_layer = Layers.WORLD
	collision_mask = 0
	sync_to_physics = true
	_start = position
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
	Gen.mesh(self, MeshFactory.box(size), ToyMaterials.matte(color.darkened(0.1)), Vector3(0, -size.y * 0.5, 0))
	var t := minf(0.16, size.y * 0.45)
	Gen.mesh(self, MeshFactory.box(Vector3(size.x + 0.1, t, size.z + 0.1)),
			ToyMaterials.patterned(color.lightened(0.25), Color(1, 1, 1), ToyMaterials.Pattern.STRIPES, 0.6),
			Vector3(0, -t * 0.5 + 0.02, 0))
	Gen.box_shape(self, size, Vector3(0, -size.y * 0.5, 0))
	if show_rail and travel.length() > 0.1:
		_build_rail()


## A thin guide rail showing where the platform goes. It stays where the
## platform was placed, so it is a top-level node that does not move along.
func _build_rail() -> void:
	var rail := Gen.node(self)
	rail.top_level = true
	rail.transform = global_transform if is_inside_tree() else transform
	var dir := travel.normalized()
	var vertical := absf(dir.y) > 0.7
	var mid := travel * 0.5
	if vertical:
		mid += Vector3(size.x * 0.5 + 0.35, 0, 0)
	else:
		mid += Vector3(0, -size.y - 0.3, 0)
	var length := travel.length() + (0.6 if vertical else size.z * 0.5)
	var mi := Gen.mesh(rail, MeshFactory.box(Vector3(0.2, 0.2, length)),
			ToyMaterials.matte(color.darkened(0.35)), Vector3.ZERO, Vector3.ONE, Vector3.ZERO, false)
	var up := Vector3.FORWARD if vertical else Vector3.UP
	mi.transform = Transform3D(Basis.looking_at(dir, up), mid)


func _physics_process(_delta: float) -> void:
	if not Gen.in_game():
		return
	position = _start + travel * progress_at(local_time())


## 0 at the start point, 1 at the far end.
func progress_at(t: float) -> float:
	var u := fposmod(t / maxf(period, 0.01) + phase, 1.0)
	var tri := 1.0 - absf(2.0 * u - 1.0)
	var moving := clampf((tri - hold) / maxf(1.0 - 2.0 * hold, 0.01), 0.0, 1.0)
	return 0.5 - 0.5 * cos(PI * moving)


## Time used for this platform's motion; stops advancing while frozen.
func local_time() -> float:
	if _frozen:
		return _frozen_since - _frozen_total
	return MatchClock.now(self) - _frozen_total


func set_frozen(value: bool) -> void:
	if value == _frozen:
		return
	if value:
		_frozen_since = MatchClock.now(self)
	else:
		_frozen_total += MatchClock.now(self) - _frozen_since
	_frozen = value


func is_frozen() -> bool:
	return _frozen


## World position of the platform's top center [param seconds_ahead] from now
## (bots use this to time their jumps).
func predict_position(seconds_ahead: float) -> Vector3:
	var parent_xform := Transform3D.IDENTITY
	if get_parent() is Node3D:
		parent_xform = (get_parent() as Node3D).global_transform
	var t := local_time() + (0.0 if _frozen else seconds_ahead)
	return parent_xform * (_start + travel * progress_at(t))
