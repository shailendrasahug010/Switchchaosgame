@tool
class_name Decor
extends Node3D
## Giant toys and sweets that dress up the arenas. Purely decorative unless
## [member solid] is on. Origin on the floor.

enum Kind { BALLOONS, LOLLIPOP, GIFT, CLOUD, CANDY_CANE, CUPCAKE, TOY_BLOCK, CRAYON, TEDDY, BUNTING, DONUT, MUSHROOM }

@export var kind: Kind = Kind.LOLLIPOP:
	set(v):
		kind = v
		_changed()
@export var color: Color = Color("ff5fa8"):
	set(v):
		color = v
		_changed()
@export var accent: Color = Color("fff8ee"):
	set(v):
		accent = v
		_changed()
@export_range(0.2, 6.0, 0.05) var size_scale: float = 1.0:
	set(v):
		size_scale = v
		_changed()
## Toy blocks: the letter painted on the sides.
@export var letter: String = "A":
	set(v):
		letter = v
		_changed()
## Bunting: length of the flag string along local X.
@export_range(1.0, 40.0, 0.5) var span: float = 8.0:
	set(v):
		span = v
		_changed()
## Adds a simple collision shape so players bump into it.
@export var solid: bool = false:
	set(v):
		solid = v
		_changed()

var _root: Node3D
var _sway: Array[Node3D] = []
var _time := 0.0
var _queued := false


func _ready() -> void:
	_rebuild()
	if Gen.in_game():
		_time = global_position.x * 0.31 + global_position.z * 0.17


func _changed() -> void:
	if not is_inside_tree() or _queued:
		return
	_queued = true
	_rebuild.call_deferred()


func _p(c: Color) -> Material:
	return ToyMaterials.plastic(c)


func _m(c: Color) -> Material:
	return ToyMaterials.matte(c)


func _rebuild() -> void:
	_queued = false
	Gen.clear(self)
	_sway.clear()
	_root = Gen.node(self)
	_root.scale = Vector3.ONE * size_scale
	match kind:
		Kind.BALLOONS:
			var colors: Array[Color] = [color, Color("ffd23f"), Color("3f9dff"), Color("2fc97a"), Color("a77bff")]
			for i in 5:
				var a := TAU * float(i) / 5.0
				var bob := Gen.node(_root, Vector3(cos(a) * 0.55, 3.2 + (i % 2) * 0.5, sin(a) * 0.55))
				Gen.mesh(bob, MeshFactory.sphere(0.5, 1.2, 16, 8), _p(colors[i]), Vector3.ZERO)
				Gen.mesh(bob, MeshFactory.cone(0.1, 0.16, 8), _p(colors[i]), Vector3(0, -0.66, 0), Vector3.ONE, Vector3(180, 0, 0), false)
				Gen.mesh(bob, MeshFactory.cylinder(0.012, 0.012, 2.6, 4), _m(Color.WHITE), Vector3(0, -2.0, 0),
						Vector3.ONE, Vector3(cos(a) * 9.0, 0, sin(a) * 9.0), false)
				_sway.append(bob)
			Gen.mesh(_root, MeshFactory.box(Vector3(0.5, 0.4, 0.5)), _p(accent), Vector3(0, 0.2, 0))
		Kind.LOLLIPOP:
			Gen.mesh(_root, MeshFactory.cylinder(0.1, 0.12, 3.0, 10), _p(Color.WHITE), Vector3(0, 1.5, 0))
			var head := Gen.node(_root, Vector3(0, 3.5, 0))
			Gen.mesh(head, MeshFactory.cylinder(1.0, 1.0, 0.35, 32), _p(color), Vector3.ZERO, Vector3.ONE, Vector3(90, 0, 0))
			Gen.mesh(head, MeshFactory.torus(0.45, 0.62, 24, 6), _p(accent), Vector3(0, 0, 0.12), Vector3(1, 1, 0.6),
					Vector3(90, 0, 0), false)
			Gen.mesh(head, MeshFactory.torus(0.45, 0.62, 24, 6), _p(accent), Vector3(0, 0, -0.12), Vector3(1, 1, 0.6),
					Vector3(90, 0, 0), false)
			_sway.append(head)
			if solid:
				_solid_cylinder(0.25, 3.0)
		Kind.GIFT:
			Gen.mesh(_root, MeshFactory.box(Vector3(2, 1.6, 2)), _p(color), Vector3(0, 0.8, 0))
			Gen.mesh(_root, MeshFactory.box(Vector3(2.12, 0.3, 2.12)), _p(color.lightened(0.15)), Vector3(0, 1.6, 0))
			Gen.mesh(_root, MeshFactory.box(Vector3(0.36, 1.92, 2.16)), _p(accent), Vector3(0, 0.85, 0), Vector3.ONE, Vector3.ZERO, false)
			Gen.mesh(_root, MeshFactory.box(Vector3(2.16, 1.92, 0.36)), _p(accent), Vector3(0, 0.85, 0), Vector3.ONE, Vector3.ZERO, false)
			for side: float in [-1.0, 1.0]:
				Gen.mesh(_root, MeshFactory.torus(0.18, 0.42, 16, 6), _p(accent), Vector3(side * 0.35, 1.95, 0),
						Vector3(1, 1, 0.7), Vector3(90, 0, side * 30.0), false)
			if solid:
				_solid_box(Vector3(2, 1.75, 2), Vector3(0, 0.875, 0))
		Kind.CLOUD:
			var puffs: Array[Vector4] = [Vector4(0, 0, 0, 1.3), Vector4(1.2, -0.2, 0.2, 1.0), Vector4(-1.2, -0.25, -0.1, 0.95),
					Vector4(0.5, 0.5, -0.3, 0.9), Vector4(-0.5, 0.4, 0.3, 0.85)]
			for p in puffs:
				Gen.mesh(_root, MeshFactory.sphere(p.w, p.w * 1.7, 14, 7), ToyMaterials.matte(Color(1, 1, 1)),
						Vector3(p.x, p.y, p.z), Vector3.ONE, Vector3.ZERO, false)
			_sway.append(_root)
		Kind.CANDY_CANE:
			var n := 8
			for i in n:
				Gen.mesh(_root, MeshFactory.cylinder(0.22, 0.22, 0.4, 14), _p(color if i % 2 == 0 else accent),
						Vector3(0, 0.2 + i * 0.4, 0))
			var hook := Gen.node(_root, Vector3(0.5, n * 0.4, 0))
			for i in 7:
				var a := PI * float(i) / 6.0
				Gen.mesh(hook, MeshFactory.sphere(0.24, 0.48, 12, 6), _p(color if i % 2 == 0 else accent),
						Vector3(-cos(a) * 0.5, sin(a) * 0.5, 0))
			if solid:
				_solid_cylinder(0.25, n * 0.4)
		Kind.CUPCAKE:
			Gen.mesh(_root, MeshFactory.cylinder(1.0, 0.75, 1.1, 18), _p(accent), Vector3(0, 0.55, 0))
			Gen.mesh(_root, MeshFactory.sphere(1.15, 1.3, 20, 8), _p(color), Vector3(0, 1.35, 0))
			Gen.mesh(_root, MeshFactory.sphere(0.8, 0.9, 16, 6), _p(color.lightened(0.2)), Vector3(0, 1.85, 0))
			Gen.mesh(_root, MeshFactory.sphere(0.25, 0.5, 12, 6), _p(Color("ff3355")), Vector3(0, 2.35, 0))
			if solid:
				_solid_cylinder(1.0, 2.2)
		Kind.TOY_BLOCK:
			Gen.mesh(_root, MeshFactory.box(Vector3(2, 2, 2)), _m(color), Vector3(0, 1, 0))
			for i in 4:
				var lbl := Label3D.new()
				lbl.text = letter
				lbl.font = load("res://assets/fonts/fredoka_bold.tres")
				lbl.font_size = 200
				lbl.pixel_size = 0.0075
				lbl.modulate = accent
				lbl.outline_size = 0
				var a := float(i) * PI * 0.5
				lbl.position = Vector3(sin(a) * 1.01, 1.0, cos(a) * 1.01)
				lbl.rotation = Vector3(0, a, 0)
				Gen.add(_root, lbl)
			if solid:
				_solid_box(Vector3(2, 2, 2), Vector3(0, 1, 0))
		Kind.CRAYON:
			Gen.mesh(_root, MeshFactory.cylinder(0.45, 0.45, 3.0, 8), _m(color), Vector3(0, 1.5, 0))
			Gen.mesh(_root, MeshFactory.cylinder(0.47, 0.47, 0.5, 8), _m(color.darkened(0.25)), Vector3(0, 2.4, 0))
			Gen.mesh(_root, MeshFactory.cylinder(0.0, 0.45, 0.8, 8), _m(color), Vector3(0, 3.4, 0))
			if solid:
				_solid_cylinder(0.45, 3.0)
		Kind.TEDDY:
			Gen.mesh(_root, MeshFactory.sphere(0.9, 1.9, 18, 9), _p(color), Vector3(0, 1.0, 0))
			Gen.mesh(_root, MeshFactory.sphere(0.5, 1.0, 14, 7), _p(accent), Vector3(0, 0.95, -0.55), Vector3(1, 1, 0.5))
			Gen.mesh(_root, MeshFactory.sphere(0.7, 1.35, 18, 9), _p(color), Vector3(0, 2.35, 0))
			Gen.mesh(_root, MeshFactory.sphere(0.3, 0.5, 12, 6), _p(accent), Vector3(0, 2.2, -0.6))
			Gen.mesh(_root, MeshFactory.sphere(0.09, 0.18, 8, 4), _p(Color("2a2238")), Vector3(0, 2.32, -0.88))
			for side: float in [-1.0, 1.0]:
				Gen.mesh(_root, MeshFactory.sphere(0.25, 0.5, 12, 6), _p(color), Vector3(side * 0.55, 2.85, 0))
				Gen.mesh(_root, MeshFactory.sphere(0.1, 0.2, 8, 4), _p(Color("2a2238")), Vector3(side * 0.25, 2.5, -0.62))
				Gen.mesh(_root, MeshFactory.sphere(0.3, 0.75, 12, 6), _p(color), Vector3(side * 0.85, 1.35, -0.1),
						Vector3.ONE, Vector3(0, 0, side * 35.0))
				Gen.mesh(_root, MeshFactory.sphere(0.35, 0.6, 12, 6), _p(color), Vector3(side * 0.45, 0.25, -0.55))
			if solid:
				_solid_cylinder(0.9, 2.4)
		Kind.BUNTING:
			for side: float in [-1.0, 1.0]:
				Gen.mesh(_root, MeshFactory.cylinder(0.08, 0.1, 3.6, 8), _p(Color("fff8ee")), Vector3(side * span * 0.5, 1.8, 0))
			var count := int(span / 0.8)
			var colors: Array[Color] = [color, Color("ffd23f"), Color("3f9dff"), Color("2fc97a")]
			for i in count:
				var t := (i + 0.5) / count
				var sag := 0.5 * (1.0 - pow(2.0 * t - 1.0, 2.0))
				Gen.mesh(_root, MeshFactory.cone(0.26, 0.45, 3), _p(colors[i % colors.size()]),
						Vector3(-span * 0.5 + t * span, 3.25 - sag, 0), Vector3(1, 1, 0.2), Vector3(180, 0, 0), false)
		Kind.DONUT:
			Gen.mesh(_root, MeshFactory.torus(0.45, 1.1, 24, 10), _p(Color("e9a65b")), Vector3(0, 0.33, 0), Vector3(1, 0.9, 1))
			Gen.mesh(_root, MeshFactory.torus(0.5, 1.03, 24, 8), _p(color), Vector3(0, 0.45, 0), Vector3(1, 0.7, 1))
			if solid:
				_solid_cylinder(1.1, 0.7)
		Kind.MUSHROOM:
			Gen.mesh(_root, MeshFactory.cylinder(0.35, 0.45, 1.2, 14), _p(accent), Vector3(0, 0.6, 0))
			Gen.mesh(_root, MeshFactory.hemisphere(1.1, 20, 6), _p(color), Vector3(0, 1.15, 0), Vector3(1, 1.1, 1))
			for i in 5:
				var a := TAU * float(i) / 5.0
				Gen.mesh(_root, MeshFactory.sphere(0.16, 0.2, 8, 4), _p(Color.WHITE), Vector3(cos(a) * 0.7, 1.55, sin(a) * 0.7),
						Vector3.ONE, Vector3.ZERO, false)
			if solid:
				_solid_cylinder(0.45, 1.6)


func _solid_cylinder(radius: float, height: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	Gen.add(_root, body)
	Gen.cylinder_shape(body, radius, height, Vector3(0, height * 0.5, 0))


func _solid_box(size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	Gen.add(_root, body)
	Gen.box_shape(body, size, pos)


func _process(delta: float) -> void:
	if not Gen.in_game() or _sway.is_empty():
		return
	_time += delta
	for i in _sway.size():
		var n := _sway[i]
		n.rotation.z = sin(_time * 1.2 + i) * 0.08
		n.rotation.x = cos(_time * 0.9 + i * 1.7) * 0.06
