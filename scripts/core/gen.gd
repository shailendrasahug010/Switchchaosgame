class_name Gen
extends RefCounted
## Helpers for props that build their own meshes and shapes from code.
##
## Generated nodes are added as *internal* children marked with metadata, so
## they are never saved into .tscn files and never show up in the editor's
## scene tree. Props rebuild them in _ready() and whenever an exported
## property changes (also in the editor, because props are @tool scripts).
## Collision shapes stay direct children of their body, as Godot requires.

const MARK := &"_generated"


## Frees everything a previous build generated on [param node].
static func clear(node: Node) -> void:
	for c in node.get_children(true):
		if c.has_meta(MARK):
			node.remove_child(c)
			c.queue_free()


static func add(parent: Node, child: Node) -> Node:
	child.set_meta(MARK, true)
	parent.add_child(child, false, Node.INTERNAL_MODE_BACK)
	return child


static func node(parent: Node, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation_degrees = rot_deg
	add(parent, n)
	return n


static func mesh(parent: Node, m: Mesh, material: Material, pos: Vector3 = Vector3.ZERO,
		scl: Vector3 = Vector3.ONE, rot_deg: Vector3 = Vector3.ZERO, shadow: bool = true) -> MeshInstance3D:
	var mi := MeshFactory.make(m, material, pos, scl, rot_deg, shadow)
	add(parent, mi)
	return mi


static func box_shape(parent: Node, size: Vector3, pos: Vector3 = Vector3.ZERO,
		rot_deg: Vector3 = Vector3.ZERO) -> CollisionShape3D:
	var shape := BoxShape3D.new()
	shape.size = size
	return _shape(parent, shape, pos, rot_deg)


static func cylinder_shape(parent: Node, radius: float, height: float,
		pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO) -> CollisionShape3D:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	return _shape(parent, shape, pos, rot_deg)


static func sphere_shape(parent: Node, radius: float, pos: Vector3 = Vector3.ZERO) -> CollisionShape3D:
	var shape := SphereShape3D.new()
	shape.radius = radius
	return _shape(parent, shape, pos, Vector3.ZERO)


static func _shape(parent: Node, shape: Shape3D, pos: Vector3, rot_deg: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = pos
	cs.rotation_degrees = rot_deg
	add(parent, cs)
	return cs


## True while the game is running (not just open in the editor).
static func in_game() -> bool:
	return not Engine.is_editor_hint()
