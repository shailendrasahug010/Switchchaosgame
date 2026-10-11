@tool
class_name KillZone
extends Area3D
## A pool of pink goo (or anything below the course). Players who fall in pop
## back at their last checkpoint; props get a "fell_in" call. Origin is the
## middle of the goo surface.

signal swallowed(body: Node3D)

@export var size: Vector3 = Vector3(30, 4, 30):
	set(v):
		size = v
		_changed()
@export var goo_color: Color = Color("ff9ccf"):
	set(v):
		goo_color = v
		_changed()
@export var show_goo: bool = true:
	set(v):
		show_goo = v
		_changed()

var _surface: MeshInstance3D
var _time := 0.0
var _queued := false


func _ready() -> void:
	collision_layer = Layers.TRIGGERS
	collision_mask = Layers.PLAYERS | Layers.PROPS
	monitorable = false
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
	# The trigger starts a little under the surface so you see the splash.
	Gen.box_shape(self, size, Vector3(0, -size.y * 0.5 - 0.4, 0))
	if show_goo:
		var mat := ToyMaterials.patterned(goo_color, goo_color.lightened(0.25), ToyMaterials.Pattern.DOTS, 0.25)
		_surface = Gen.mesh(self, MeshFactory.box(Vector3(size.x, 0.2, size.z)), mat, Vector3(0, -0.1, 0),
				Vector3.ONE, Vector3.ZERO, false)


func _process(delta: float) -> void:
	if Gen.in_game() and _surface:
		_time += delta
		_surface.position.y = -0.1 + sin(_time * 1.3) * 0.06


func _on_body_entered(body: Node3D) -> void:
	if body is PlayerCharacter:
		var player := body as PlayerCharacter
		# Online, puppets and proxies fall on their own device (it reports back).
		if not player.is_respawning and player.is_simulated():
			player.respawn_now()
	elif body.has_method("fell_in"):
		body.fell_in()
	swallowed.emit(body)
