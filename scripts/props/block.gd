@tool
class_name Block
extends StaticBody3D
## A chunky toy block for floors, walls, ramps and platforms.
##
## The origin is the CENTER OF THE TOP FACE, so a block's y position is simply
## the height of the floor it makes. Meshes and collision are generated from
## [member size], so resize blocks in the Inspector and the collision follows.

@export var size: Vector3 = Vector3(4, 1, 4):
	set(v):
		size = v.max(Vector3(0.05, 0.05, 0.05))
		_changed()
@export var color: Color = Color("ffb3d6"):
	set(v):
		color = v
		_changed()
## Color of the puffy top layer. Leave alpha at 0 for a lighter shade of [member color].
@export var top_color: Color = Color(0, 0, 0, 0):
	set(v):
		top_color = v
		_changed()
@export var pattern: ToyMaterials.Pattern = ToyMaterials.Pattern.NONE:
	set(v):
		pattern = v
		_changed()
@export var pattern_color: Color = Color(1, 1, 1):
	set(v):
		pattern_color = v
		_changed()
@export_range(0.05, 4.0, 0.05) var pattern_scale: float = 0.5:
	set(v):
		pattern_scale = v
		_changed()
## Adds a puffy, slightly overhanging top layer (frosting / cushion look).
@export var frosted: bool = true:
	set(v):
		frosted = v
		_changed()
## False = decoration only, players walk through it.
@export var solid: bool = true:
	set(v):
		solid = v
		_changed()
## Upward launch speed for players landing on this block (0 = ordinary floor).
@export var bounce: float = 0.0

var _queued := false


func _ready() -> void:
	collision_layer = Layers.WORLD
	collision_mask = 0
	_rebuild()


func _changed() -> void:
	if not is_inside_tree() or _queued:
		return
	_queued = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_queued = false
	Gen.clear(self)
	var top := top_color if top_color.a > 0.0 else color.lightened(0.28)
	var top_material: Material = ToyMaterials.patterned(top, pattern_color, pattern, pattern_scale)
	if frosted and size.y > 0.12:
		Gen.mesh(self, MeshFactory.box(size), ToyMaterials.matte(color), Vector3(0, -size.y * 0.5, 0))
		var over := minf(0.07, minf(size.x, size.z) * 0.05)
		var t := minf(0.18, size.y * 0.45)
		Gen.mesh(self, MeshFactory.box(Vector3(size.x + over * 2.0, t, size.z + over * 2.0)), top_material,
				Vector3(0, -t * 0.5 + 0.02, 0))
	else:
		Gen.mesh(self, MeshFactory.box(size), top_material, Vector3(0, -size.y * 0.5, 0))
	if solid:
		Gen.box_shape(self, size, Vector3(0, -size.y * 0.5, 0))


## Read by PlayerCharacter when landing.
func get_surface_bounce() -> float:
	return bounce
