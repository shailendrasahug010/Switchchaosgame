@tool
class_name Checkpoint
extends Area3D
## A flag arch across the course. Passing through it saves your respawn spot.
## Origin on the floor at the middle of the arch; players pass along -Z.

signal reached(player: PlayerCharacter, checkpoint: Checkpoint)

## Order along the course (1 = first checkpoint after the start).
@export var index: int = 1
@export_range(2.0, 30.0, 0.1) var width: float = 10.0:
	set(v):
		width = v
		_changed()
@export var color: Color = Color("2fc97a"):
	set(v):
		color = v
		_changed()
@export var show_arch: bool = true:
	set(v):
		show_arch = v
		_changed()

var _reached_by: Dictionary = {}  # player_index -> true
var _flags: Array[MeshInstance3D] = []
var _wave := 0.0
var _activated := false
var _queued := false


func _ready() -> void:
	collision_layer = Layers.TRIGGERS
	collision_mask = Layers.PLAYERS
	monitorable = false
	add_to_group(&"checkpoint")
	_rebuild()
	if Gen.in_game():
		body_entered.connect(_on_body_entered)


func _changed() -> void:
	if not is_inside_tree() or _queued:
		return
	_queued = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_queued = false
	Gen.clear(self)
	_flags.clear()
	Gen.box_shape(self, Vector3(width, 6.0, 1.6), Vector3(0, 3.0, 0))
	if not show_arch:
		return
	var h := 4.2
	for side: float in [-1.0, 1.0]:
		var x := side * (width * 0.5 + 0.3)
		Gen.mesh(self, MeshFactory.cylinder(0.18, 0.22, h, 12), ToyMaterials.plastic(Color("fff8ee")), Vector3(x, h * 0.5, 0))
		Gen.mesh(self, MeshFactory.sphere(0.3, 0.6, 12, 6), ToyMaterials.plastic(color), Vector3(x, h + 0.15, 0))
	# Bunting flags along a string.
	var count := int(width / 0.9)
	for i in count:
		var x := -width * 0.5 + (i + 0.5) * width / count
		var sag := 0.35 * (1.0 - pow(2.0 * (i + 0.5) / count - 1.0, 2.0))
		var flag := Gen.mesh(self, MeshFactory.cone(0.3, 0.5, 3), ToyMaterials.plastic(Color("d6d3e8")),
				Vector3(x, h - 0.35 - sag, 0), Vector3(1, 1, 0.25), Vector3(180, 0, 0), false)
		_flags.append(flag)
	_set_flag_colors()


func _set_flag_colors() -> void:
	var palette: Array[Color] = [color, Color("ffd23f"), Color("ff5fa8"), Color("3f9dff")]
	for i in _flags.size():
		var col: Color = palette[i % palette.size()] if _activated else Color("d6d3e8")
		_flags[i].material_override = ToyMaterials.plastic(col)


func _process(delta: float) -> void:
	if not Gen.in_game() or not _activated:
		return
	_wave += delta
	for i in _flags.size():
		_flags[i].rotation.x = PI + sin(_wave * 6.0 + i) * 0.25


func _on_body_entered(body: Node3D) -> void:
	var player := body as PlayerCharacter
	if player == null or player.is_respawning:
		return
	if _reached_by.has(player.player_index):
		return
	_reached_by[player.player_index] = true
	if not _activated:
		_activated = true
		_set_flag_colors()
	reached.emit(player, self)


func has_reached(player_index: int) -> bool:
	return _reached_by.has(player_index)


## A respawn spot just past the arch, spread out a little per player.
func get_respawn_point(player_index: int) -> Vector3:
	var lateral := (float(player_index) - 1.5) * minf(1.3, width / 5.0)
	return global_transform * Vector3(lateral, 0.3, -1.6)


func reset() -> void:
	_reached_by.clear()
	_activated = false
	_set_flag_colors()
