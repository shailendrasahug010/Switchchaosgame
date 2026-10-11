class_name Blueprint
extends RefCounted
## Tiny level-building helpers used by tools/build_arenas.gd.
## Each call adds a node to [param parent] and returns it.

static var _font: Font


static func block(parent: Node, name: String, pos: Vector3, size: Vector3, color: Color,
		top: Color = Color(0, 0, 0, 0), pattern: int = ToyMaterials.Pattern.NONE,
		pattern_color: Color = Color.WHITE, pattern_scale: float = 0.5, frosted: bool = true) -> Block:
	var b := Block.new()
	b.name = name
	b.size = size
	b.color = color
	b.top_color = top
	b.pattern = pattern
	b.pattern_color = pattern_color
	b.pattern_scale = pattern_scale
	b.frosted = frosted
	b.position = pos
	parent.add_child(b)
	return b


## A sloped block whose top surface runs from [param from] to [param to] (both
## are points on the center line of the top surface).
static func ramp(parent: Node, name: String, from: Vector3, to: Vector3, width: float, color: Color,
		top: Color = Color(0, 0, 0, 0), pattern: int = ToyMaterials.Pattern.NONE,
		pattern_color: Color = Color.WHITE) -> Block:
	var d := to - from
	var length := d.length() + 0.4
	var b := block(parent, name, (from + to) * 0.5, Vector3(width, 1.0, length), color, top, pattern, pattern_color)
	var horizontal := Vector2(d.x, d.z).length()
	b.rotation = Vector3(atan2(d.y, horizontal), atan2(-d.x, -d.z), 0)
	return b


## Thin candy-striped curbs along both sides of a straight section.
static func rails(parent: Node, name: String, z_from: float, z_to: float, half_width: float,
		y: float = 0.0, color: Color = Color("ff5f7e")) -> void:
	var length := absf(z_to - z_from)
	var mid := (z_from + z_to) * 0.5
	for side: float in [-1.0, 1.0]:
		block(parent, "%s%s" % [name, "L" if side < 0 else "R"], Vector3(side * (half_width + 0.25), y + 0.75, mid),
				Vector3(0.5, 1.1, length), color, Color("fff8ee"), ToyMaterials.Pattern.STRIPES, color, 1.2)


static func marker(parent: Node, name: String, pos: Vector3, group: StringName, meta: Dictionary = {},
		yaw_deg: float = 0.0) -> Marker3D:
	var m := Marker3D.new()
	m.name = name
	m.position = pos
	m.rotation_degrees.y = yaw_deg
	m.add_to_group(group, true)
	for k in meta:
		m.set_meta(k, meta[k])
	parent.add_child(m)
	return m


static func sign(parent: Node, name: String, text: String, pos: Vector3, font_size: int = 96,
		color: Color = Color.WHITE, outline: Color = Color("7b5cff"), yaw_deg: float = 0.0) -> Label3D:
	if _font == null:
		_font = load("res://assets/fonts/fredoka_bold.tres")
	var l := Label3D.new()
	l.name = name
	l.text = text
	l.font = _font
	l.font_size = font_size
	l.pixel_size = 0.01
	l.outline_size = maxi(8, font_size / 5)
	l.modulate = color
	l.outline_modulate = outline
	l.position = pos
	l.rotation_degrees.y = yaw_deg
	parent.add_child(l)
	return l


static func decor(parent: Node, name: String, kind: Decor.Kind, pos: Vector3, color: Color,
		accent: Color = Color("fff8ee"), scale: float = 1.0, yaw_deg: float = 0.0, solid: bool = false,
		letter: String = "A") -> Decor:
	var d := Decor.new()
	d.name = name
	d.kind = kind
	d.color = color
	d.accent = accent
	d.size_scale = scale
	d.solid = solid
	d.letter = letter
	d.position = pos
	d.rotation_degrees.y = yaw_deg
	parent.add_child(d)
	return d


static func star(parent: Node, name: String, pos: Vector3) -> StarPickup:
	var s := StarPickup.new()
	s.name = name
	s.position = pos
	parent.add_child(s)
	return s


static func group_node(parent: Node, name: String) -> Node3D:
	var n := Node3D.new()
	n.name = name
	parent.add_child(n)
	return n


## Makes every node below [param root] owned by it so PackedScene.pack saves them.
static func own_all(node: Node, root: Node) -> void:
	for c in node.get_children():
		c.owner = root
		# Instanced sub-scenes keep their own internals.
		if c.scene_file_path == "":
			own_all(c, root)


static func save(root: Node, path: String) -> void:
	own_all(root, root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		push_error("Blueprint: pack failed for %s: %s" % [path, error_string(err)])
		return
	err = ResourceSaver.save(packed, path)
	if err != OK:
		push_error("Blueprint: save failed for %s: %s" % [path, error_string(err)])
	else:
		print("Saved ", path)
	root.free()
