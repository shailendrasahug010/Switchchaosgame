@tool
class_name FinishZone
extends Area3D
## The finish / delivery area with a big arch. Origin on the floor, center.
## Reports players (and props such as the cake) that enter it.

signal body_arrived(body: Node3D)

@export var size: Vector3 = Vector3(10, 4, 4):
	set(v):
		size = v
		_changed()
@export var label: String = "FINISH":
	set(v):
		label = v
		_changed()
@export var color: Color = Color("ff5fa8"):
	set(v):
		color = v
		_changed()
## Also detect rigid props (the cake), not only players.
@export var detect_props: bool = false

var _confetti: CPUParticles3D
var _queued := false


func _ready() -> void:
	collision_layer = Layers.TRIGGERS
	collision_mask = Layers.PLAYERS | (Layers.PROPS if detect_props else 0)
	monitorable = false
	add_to_group(&"finish")
	_rebuild()
	if Gen.in_game():
		body_entered.connect(func(b: Node3D) -> void: body_arrived.emit(b))


func _changed() -> void:
	if not is_inside_tree() or _queued:
		return
	_queued = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_queued = false
	Gen.clear(self)
	Gen.box_shape(self, size, Vector3(0, size.y * 0.5, 0))
	var h := 5.0
	var w := size.x * 0.5 + 0.5
	var stripes: Array[Color] = [color, Color("fff8ee")]
	for side: float in [-1.0, 1.0]:
		for i in 8:
			Gen.mesh(self, MeshFactory.cylinder(0.42, 0.42, h / 8.0, 16), ToyMaterials.plastic(stripes[i % 2]),
					Vector3(side * w, h / 16.0 + i * h / 8.0, 0))
		Gen.mesh(self, MeshFactory.sphere(0.6, 1.2, 16, 8), ToyMaterials.plastic(Color("ffd23f")), Vector3(side * w, h + 0.4, 0))
	Gen.mesh(self, MeshFactory.box(Vector3(w * 2.0 + 0.6, 1.1, 0.5)), ToyMaterials.plastic(color), Vector3(0, h + 0.2, 0))
	var text := Label3D.new()
	text.text = label
	text.font = load("res://assets/fonts/fredoka_bold.tres")
	text.font_size = 110
	text.pixel_size = 0.008
	text.outline_size = 22
	text.outline_modulate = color.darkened(0.45)
	text.modulate = Color.WHITE
	text.position = Vector3(0, h + 0.2, 0.27)
	text.double_sided = false
	Gen.add(self, text)
	var back := text.duplicate() as Label3D
	back.position = Vector3(0, h + 0.2, -0.27)
	back.rotation_degrees = Vector3(0, 180, 0)
	Gen.add(self, back)
	_confetti = CPUParticles3D.new()
	_confetti.emitting = false
	_confetti.one_shot = true
	_confetti.amount = 60
	_confetti.lifetime = 2.2
	_confetti.explosiveness = 0.9
	_confetti.position = Vector3(0, h + 0.4, 0)
	_confetti.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_confetti.emission_box_extents = Vector3(w, 0.2, 0.3)
	_confetti.direction = Vector3(0, 1, 0)
	_confetti.spread = 70.0
	_confetti.initial_velocity_min = 3.0
	_confetti.initial_velocity_max = 7.0
	_confetti.gravity = Vector3(0, -4.0, 0)
	_confetti.angular_velocity_min = -360.0
	_confetti.angular_velocity_max = 360.0
	_confetti.mesh = MeshFactory.box(Vector3(0.14, 0.02, 0.09))
	_confetti.material_override = ToyMaterials.flat(Color.WHITE)
	_confetti.color_ramp = _confetti_colors()
	Gen.add(self, _confetti)


func _confetti_colors() -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	g.colors = PackedColorArray([Color("ff5fa8"), Color("ffd23f"), Color("3f9dff"), Color("2fc97a")])
	return g


## Fires the confetti cannon (a finish, a delivery).
func celebrate() -> void:
	if _confetti:
		_confetti.restart()
