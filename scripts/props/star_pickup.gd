@tool
class_name StarPickup
extends Area3D
## An optional golden star. Touching it emits [signal touched]; the game mode
## decides whether it counts (online, the server confirms first) and then
## calls [method collect]. Place the origin where the star should float.

signal touched(player: PlayerCharacter, star: StarPickup)
signal collected(player: PlayerCharacter, star: StarPickup)

@export var points: int = 50
@export var color: Color = Color("ffd23f"):
	set(v):
		color = v
		_changed()

var taken := false
var collected_by: int = -1

var _spin: Node3D
var _time := 0.0
var _pop := 0.0
var _queued := false


func _ready() -> void:
	collision_layer = Layers.TRIGGERS
	collision_mask = Layers.PLAYERS
	monitorable = false
	add_to_group(&"star")
	_rebuild()
	if Gen.in_game():
		_time = global_position.x * 0.37 + global_position.z * 0.11
		body_entered.connect(_on_body_entered)


func _changed() -> void:
	if not is_inside_tree() or _queued:
		return
	_queued = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_queued = false
	Gen.clear(self)
	_spin = Gen.node(self)
	Gen.mesh(_spin, MeshFactory.star(0.5, 0.24, 0.2), ToyMaterials.glow(color, 0.55), Vector3.ZERO, Vector3.ONE,
			Vector3.ZERO, false)
	Gen.mesh(_spin, MeshFactory.sphere(0.07, 0.14, 8, 4), ToyMaterials.flat(Color.WHITE),
			Vector3(-0.12, 0.12, 0.2), Vector3.ONE, Vector3.ZERO, false)
	Gen.sphere_shape(self, 0.8)


func _process(delta: float) -> void:
	if not Gen.in_game() or _spin == null:
		return
	_time += delta
	if taken:
		_pop = minf(1.0, _pop + delta * 3.0)
		_spin.scale = Vector3.ONE * (1.0 + _pop * 0.8) * (1.0 - _pop)
		_spin.position.y = _pop * 1.2
		_spin.rotate_y(delta * 18.0)
		if _pop >= 1.0:
			_spin.visible = false
		return
	_spin.rotation.y = _time * 2.4
	_spin.position.y = sin(_time * 2.0) * 0.15


func _on_body_entered(body: Node3D) -> void:
	var player := body as PlayerCharacter
	if taken or player == null or player.is_respawning:
		return
	touched.emit(player, self)


## Marks the star as taken by [param player] (call once the mode accepts it).
func collect(player: PlayerCharacter) -> void:
	if taken:
		return
	taken = true
	collected_by = player.player_index if player else -1
	_pop = 0.0
	set_deferred("monitoring", false)
	collected.emit(player, self)


func reset() -> void:
	taken = false
	collected_by = -1
	_pop = 0.0
	monitoring = true
	if _spin:
		_spin.visible = true
		_spin.scale = Vector3.ONE
