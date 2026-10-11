class_name PlayerVisual
extends Node3D
## Builds and animates the squishy toy creature from primitive shapes.
##
## Purely cosmetic: reads the parent PlayerCharacter's state and never
## changes gameplay. All motion (squash & stretch, running feet, waddling,
## blinking, reactions, chaos costumes) is procedural, so there are no
## animation files to author or license.

const EYE_WHITE := Color(1, 1, 1)
const PUPIL := Color(0.11, 0.1, 0.2)
const CHEEK := Color(1.0, 0.56, 0.76)

## Per-shape layout. Units are meters at size 1. Front of the creature is -Z.
const SHAPES := {
	&"ball": {"top": 1.13, "eye_y": 0.74, "eye_z": -0.45, "eye_x": 0.2, "eye_r": 0.18, "width": 0.56, "arm_y": 0.55},
	&"bean": {"top": 1.37, "eye_y": 1.0, "eye_z": -0.37, "eye_x": 0.17, "eye_r": 0.16, "width": 0.43, "arm_y": 0.7},
	&"gumdrop": {"top": 1.16, "eye_y": 0.74, "eye_z": -0.43, "eye_x": 0.19, "eye_r": 0.16, "width": 0.6, "arm_y": 0.5},
	&"egg": {"top": 1.37, "eye_y": 0.88, "eye_z": -0.45, "eye_x": 0.18, "eye_r": 0.17, "width": 0.5, "arm_y": 0.62},
}

var shape_id: StringName = &"ball"
var body_color: Color = Color.WHITE
var accent_color: Color = Color.WHITE
var layout: Dictionary = SHAPES[&"ball"]

var _yaw: Node3D
var _lift: Node3D
var _squash: Node3D
var _parts: Node3D
var _eyes: Array[Node3D] = []
var _eye_whites: Array[Node3D] = []
var _pupils: Array[Node3D] = []
var _mouth: MeshInstance3D
var _arm_pivots: Array[Node3D] = []
var _arm_meshes: Array[MeshInstance3D] = []
var _feet: Array[Node3D] = []
var _accessory: Node3D
var _spinner: Node3D  # propeller blades (if any)
var _hat: Node3D
var _looks: Dictionary = {}  # look key -> Node3D
var _active_looks: Array[StringName] = []
var _emote_root: Node3D
var _dizzy_stars: Node3D
var _alert: Node3D
var _reverse_icon: Node3D
var _sweat: MeshInstance3D
var _dust: CPUParticles3D

var _time: float = 0.0
var _squash_amount: float = 1.0
var _squash_velocity: float = 0.0
var _blink_timer: float = 2.0
var _blink_left: float = 0.0
var _run_phase: float = 0.0
var _reaction: StringName = &""
var _reaction_left: float = 0.0
var _celebrate_left: float = 0.0
var _carrying: bool = false
var _pop_in: float = 1.0
var _lift_amount: float = 0.0
var _built: bool = false


func _ready() -> void:
	if not _built:
		build(&"bloop", &"none", &"classic")


## (Re)creates the creature for a character, hat and paint job.
func build(character_id: StringName, hat_id: StringName, paint_id: StringName) -> void:
	for c in get_children():
		c.free()
	_eyes.clear()
	_eye_whites.clear()
	_pupils.clear()
	_arm_pivots.clear()
	_arm_meshes.clear()
	_feet.clear()
	_looks.clear()
	_active_looks.clear()
	_spinner = null

	var info := Catalog.character(character_id)
	shape_id = info.shape
	layout = SHAPES.get(shape_id, SHAPES[&"ball"])
	body_color = Catalog.body_color(character_id, paint_id)
	accent_color = info.accent

	_yaw = Node3D.new()
	_yaw.name = "Yaw"
	add_child(_yaw)
	_lift = Node3D.new()
	_yaw.add_child(_lift)
	_squash = Node3D.new()
	_squash.name = "Squash"
	_lift.add_child(_squash)
	_parts = Node3D.new()
	_squash.add_child(_parts)

	_build_body()
	_build_face()
	_build_limbs()
	_build_accessory(info.accessory)
	_build_hat(hat_id)
	_build_emotes()
	_built = true


# ---------------------------------------------------------------- building

func _plastic(c: Color) -> StandardMaterial3D:
	return ToyMaterials.plastic(c)


func _add(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, scl: Vector3 = Vector3.ONE,
		rot: Vector3 = Vector3.ZERO, shadow: bool = true) -> MeshInstance3D:
	var mi := MeshFactory.make(mesh, _plastic(color), pos, scl, rot, shadow)
	parent.add_child(mi)
	return mi


func _build_body() -> void:
	match shape_id:
		&"ball":
			_add(_parts, MeshFactory.sphere(0.56, 1.06, 24, 12), body_color, Vector3(0, 0.6, 0))
		&"bean":
			_add(_parts, MeshFactory.capsule(0.43, 1.32, 20, 6), body_color, Vector3(0, 0.71, 0))
		&"gumdrop":
			_add(_parts, MeshFactory.cylinder(0.43, 0.61, 0.78, 22), body_color, Vector3(0, 0.46, 0))
			_add(_parts, MeshFactory.sphere(0.44, 0.62, 22, 8), body_color, Vector3(0, 0.86, 0))
			# soft rounded bottom edge
			_add(_parts, MeshFactory.torus(0.4, 0.62, 22, 8), body_color.darkened(0.06), Vector3(0, 0.1, 0), Vector3(1, 0.9, 1))
		&"egg":
			_add(_parts, MeshFactory.sphere(0.51, 1.32, 24, 12), body_color, Vector3(0, 0.71, 0))
	# A lighter belly patch gives every shape a friendly front.
	var belly := _add(_parts, MeshFactory.sphere(0.3, 0.6, 16, 8), body_color.lightened(0.35),
			Vector3(0, layout.eye_y - 0.38, layout.eye_z + 0.12), Vector3(1.0, 0.85, 0.35), Vector3.ZERO, false)
	belly.name = "Belly"


func _build_face() -> void:
	var eye_r: float = layout.eye_r
	for side in [-1.0, 1.0]:
		var eye := Node3D.new()
		eye.position = Vector3(side * layout.eye_x, layout.eye_y, layout.eye_z)
		eye.rotation_degrees = Vector3(0, -side * 12.0, 0)
		_parts.add_child(eye)
		var white := Node3D.new()
		eye.add_child(white)
		_add(white, MeshFactory.sphere(eye_r, eye_r * 2.0, 16, 8), EYE_WHITE, Vector3.ZERO, Vector3(1.0, 1.18, 0.55), Vector3.ZERO, false)
		var pupil := Node3D.new()
		pupil.position = Vector3(0, -0.01, -eye_r * 0.42)
		white.add_child(pupil)
		var pm := MeshFactory.make(MeshFactory.sphere(eye_r * 0.52, eye_r * 1.04, 12, 6), ToyMaterials.plastic(PUPIL),
				Vector3.ZERO, Vector3(1.0, 1.15, 0.6), Vector3.ZERO, false)
		pupil.add_child(pm)
		var shine := MeshFactory.make(MeshFactory.sphere(eye_r * 0.17, eye_r * 0.34, 8, 4), ToyMaterials.flat(EYE_WHITE),
				Vector3(-eye_r * 0.2, eye_r * 0.22, -eye_r * 0.27), Vector3.ONE, Vector3.ZERO, false)
		pupil.add_child(shine)
		_eyes.append(eye)
		_eye_whites.append(white)
		_pupils.append(pupil)
		# blush
		_add(_parts, MeshFactory.sphere(0.075, 0.15, 10, 5), CHEEK,
				Vector3(side * (layout.eye_x + 0.15), layout.eye_y - 0.17, layout.eye_z + 0.06),
				Vector3(1.3, 0.7, 0.45), Vector3(0, -side * 25.0, 0), false)
	_mouth = _add(_parts, MeshFactory.sphere(0.06, 0.12, 10, 5), PUPIL,
			Vector3(0, layout.eye_y - 0.22, layout.eye_z + 0.03), Vector3(1.0, 0.9, 0.5), Vector3.ZERO, false)
	_mouth.visible = false


func _build_limbs() -> void:
	var width: float = layout.width
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(side * (width - 0.06), layout.arm_y, 0)
		_parts.add_child(pivot)
		var arm := _add(pivot, MeshFactory.capsule(0.09, 0.36, 10, 3), body_color.darkened(0.08), Vector3(0, -0.15, 0))
		_arm_pivots.append(pivot)
		_arm_meshes.append(arm)
	for side in [-1.0, 1.0]:
		var foot := Node3D.new()
		foot.position = Vector3(side * 0.2, 0.07, 0)
		_yaw.add_child(foot)
		_add(foot, MeshFactory.sphere(0.16, 0.32, 12, 6), body_color.darkened(0.18), Vector3.ZERO, Vector3(1.0, 0.55, 1.3))
		_feet.append(foot)


func _build_accessory(kind: StringName) -> void:
	_accessory = Node3D.new()
	_accessory.position = Vector3(0, layout.top - 0.04, 0)
	_parts.add_child(_accessory)
	match kind:
		&"antenna":
			_add(_accessory, MeshFactory.cylinder(0.025, 0.03, 0.36, 8), body_color.darkened(0.15), Vector3(0.05, 0.17, 0), Vector3.ONE, Vector3(0, 0, -14))
			_add(_accessory, MeshFactory.sphere(0.085, 0.17, 12, 6), accent_color, Vector3(0.1, 0.36, 0))
		&"bunny_ears":
			for side in [-1.0, 1.0]:
				var ear := Node3D.new()
				ear.position = Vector3(side * 0.16, -0.02, 0.04)
				ear.rotation_degrees = Vector3(-8, 0, -side * 14.0)
				_accessory.add_child(ear)
				_add(ear, MeshFactory.capsule(0.085, 0.52, 10, 3), body_color, Vector3(0, 0.24, 0))
				_add(ear, MeshFactory.capsule(0.045, 0.38, 8, 3), CHEEK, Vector3(0, 0.24, -0.06), Vector3(1, 1, 0.5), Vector3.ZERO, false)
		&"sprout":
			_add(_accessory, MeshFactory.cylinder(0.022, 0.028, 0.2, 8), Color(0.24, 0.55, 0.22), Vector3(0, 0.1, 0))
			for side in [-1.0, 1.0]:
				_add(_accessory, MeshFactory.sphere(0.13, 0.26, 12, 6), accent_color if side < 0.0 else Color(0.45, 0.85, 0.3),
						Vector3(side * 0.1, 0.2, 0), Vector3(1.0, 0.28, 0.6), Vector3(0, 0, side * 32.0))
		&"propeller":
			_add(_accessory, MeshFactory.hemisphere(0.3, 18, 5), accent_color, Vector3(0, -0.05, 0), Vector3(1, 0.62, 1))
			_add(_accessory, MeshFactory.cylinder(0.025, 0.025, 0.14, 8), Color(0.3, 0.3, 0.35), Vector3(0, 0.17, 0))
			_spinner = Node3D.new()
			_spinner.position = Vector3(0, 0.25, 0)
			_accessory.add_child(_spinner)
			_add(_spinner, MeshFactory.box(Vector3(0.62, 0.025, 0.1)), Color(0.36, 0.72, 1.0), Vector3.ZERO)
			_add(_spinner, MeshFactory.box(Vector3(0.1, 0.025, 0.62)), Color(1.0, 0.45, 0.45), Vector3.ZERO)


func _build_hat(hat_id: StringName) -> void:
	_hat = Node3D.new()
	_hat.position = Vector3(0, layout.top - 0.05, 0)
	_parts.add_child(_hat)
	match hat_id:
		&"party_hat":
			_hat.rotation_degrees = Vector3(-6, 0, 12)
			_hat.position += Vector3(-0.12, 0, 0)
			_add(_hat, MeshFactory.cone(0.21, 0.46, 16), Color(1.0, 0.36, 0.55), Vector3(0, 0.22, 0))
			_add(_hat, MeshFactory.torus(0.16, 0.22, 16, 6), Color(1.0, 0.88, 0.3), Vector3(0, 0.04, 0), Vector3(1, 0.6, 1))
			_add(_hat, MeshFactory.sphere(0.075, 0.15, 10, 5), Color(1.0, 0.95, 0.4), Vector3(0, 0.47, 0))
		&"bow":
			_hat.position += Vector3(0.18, -0.02, 0.02)
			_hat.rotation_degrees = Vector3(0, 0, -18)
			for side in [-1.0, 1.0]:
				_add(_hat, MeshFactory.cone(0.12, 0.2, 12), Color(1.0, 0.33, 0.55), Vector3(side * 0.1, 0.05, 0), Vector3(1, 1, 0.55), Vector3(0, 0, side * 90.0))
			_add(_hat, MeshFactory.sphere(0.065, 0.13, 10, 5), Color(1.0, 0.55, 0.7), Vector3(0, 0.05, 0))
		&"shades":
			_hat.position = Vector3(0, layout.eye_y + 0.01, layout.eye_z - 0.1)
			for side in [-1.0, 1.0]:
				_add(_hat, MeshFactory.cylinder(layout.eye_r * 1.08, layout.eye_r * 1.08, 0.03, 16), Color(0.12, 0.12, 0.18),
						Vector3(side * layout.eye_x, 0, 0), Vector3(1, 1, 0.85), Vector3(90, 0, 0), false)
			_add(_hat, MeshFactory.box(Vector3(layout.eye_x * 0.9, 0.03, 0.03)), Color(0.12, 0.12, 0.18), Vector3(0, 0.03, 0), Vector3.ONE, Vector3.ZERO, false)
		&"chef_hat":
			_add(_hat, MeshFactory.cylinder(0.2, 0.2, 0.22, 16), Color(0.98, 0.98, 1.0), Vector3(0, 0.1, 0))
			_add(_hat, MeshFactory.sphere(0.27, 0.32, 16, 6), Color(1, 1, 1), Vector3(0, 0.27, 0))
		&"flower":
			_hat.position += Vector3(0.17, -0.04, -0.05)
			for i in 5:
				var a := TAU * float(i) / 5.0
				_add(_hat, MeshFactory.sphere(0.07, 0.14, 8, 4), Color(1.0, 0.55, 0.8), Vector3(cos(a) * 0.08, 0.06 + sin(a) * 0.08, 0), Vector3(1, 1, 0.5))
			_add(_hat, MeshFactory.sphere(0.05, 0.1, 8, 4), Color(1.0, 0.86, 0.25), Vector3(0, 0.06, -0.02))
		&"crown":
			_add(_hat, MeshFactory.cylinder(0.24, 0.2, 0.18, 16), Color(1.0, 0.8, 0.2), Vector3(0, 0.07, 0))
			for i in 5:
				var a := TAU * float(i) / 5.0
				_add(_hat, MeshFactory.sphere(0.045, 0.09, 8, 4), Color(1.0, 0.35, 0.4) if i % 2 == 0 else Color(0.35, 0.6, 1.0),
						Vector3(cos(a) * 0.23, 0.2, sin(a) * 0.23))
		&"headphones":
			_hat.position = Vector3(0, layout.eye_y + 0.05, 0)
			_add(_hat, MeshFactory.torus(layout.width * 0.98, layout.width * 1.1, 24, 6), Color(0.3, 0.3, 0.4),
					Vector3(0, 0.0, 0.05), Vector3(1, 1.0, 0.6), Vector3(0, 0, 0))
			for side in [-1.0, 1.0]:
				_add(_hat, MeshFactory.cylinder(0.13, 0.13, 0.1, 14), accent_color, Vector3(side * (layout.width + 0.02), 0, 0.05), Vector3.ONE, Vector3(0, 0, 90))
			_hat.rotation_degrees = Vector3(90, 0, 0)
		&"top_hat":
			_add(_hat, MeshFactory.cylinder(0.26, 0.26, 0.03, 18), Color(0.15, 0.13, 0.2), Vector3(0, 0.01, 0))
			_add(_hat, MeshFactory.cylinder(0.16, 0.17, 0.3, 16), Color(0.15, 0.13, 0.2), Vector3(0, 0.16, 0))
			_add(_hat, MeshFactory.cylinder(0.172, 0.172, 0.06, 16), accent_color, Vector3(0, 0.06, 0))


func _build_emotes() -> void:
	_emote_root = Node3D.new()
	_emote_root.position = Vector3(0, layout.top + 0.45, 0)
	_lift.add_child(_emote_root)
	# Dizzy stars orbiting the head.
	_dizzy_stars = Node3D.new()
	_emote_root.add_child(_dizzy_stars)
	for i in 3:
		var a := TAU * float(i) / 3.0
		var s := MeshFactory.make(MeshFactory.star(0.11, 0.05, 0.05), ToyMaterials.glow(Color(1.0, 0.86, 0.25), 0.6),
				Vector3(cos(a) * 0.38, -0.15, sin(a) * 0.38), Vector3.ONE, Vector3.ZERO, false)
		_dizzy_stars.add_child(s)
	_dizzy_stars.visible = false
	# "!" alert.
	_alert = Node3D.new()
	_emote_root.add_child(_alert)
	_alert.add_child(MeshFactory.make(MeshFactory.capsule(0.06, 0.3, 8, 2), ToyMaterials.glow(Color(1.0, 0.35, 0.3), 0.5), Vector3(0, 0.15, 0), Vector3.ONE, Vector3.ZERO, false))
	_alert.add_child(MeshFactory.make(MeshFactory.sphere(0.065, 0.13, 8, 4), ToyMaterials.glow(Color(1.0, 0.35, 0.3), 0.5), Vector3(0, -0.1, 0), Vector3.ONE, Vector3.ZERO, false))
	_alert.visible = false
	# Reverse Mode: two arrows chasing each other.
	_reverse_icon = Node3D.new()
	_emote_root.add_child(_reverse_icon)
	for side in [-1.0, 1.0]:
		var arrow := Node3D.new()
		arrow.position = Vector3(side * 0.22, 0.05, 0)
		arrow.rotation_degrees = Vector3(0, 0, 90.0 * side)
		_reverse_icon.add_child(arrow)
		arrow.add_child(MeshFactory.make(MeshFactory.cone(0.1, 0.18, 10), ToyMaterials.glow(Color(0.75, 0.45, 1.0), 0.7), Vector3(0, 0.12, 0), Vector3.ONE, Vector3.ZERO, false))
		arrow.add_child(MeshFactory.make(MeshFactory.cylinder(0.04, 0.04, 0.16, 8), ToyMaterials.glow(Color(0.75, 0.45, 1.0), 0.7), Vector3(0, -0.02, 0), Vector3.ONE, Vector3.ZERO, false))
	_reverse_icon.visible = false
	# Sweat drop for "uh-oh" moments.
	_sweat = _add(_parts, MeshFactory.sphere(0.06, 0.14, 8, 4), Color(0.55, 0.85, 1.0),
			Vector3(layout.width * 0.7, layout.top - 0.1, layout.eye_z * 0.5), Vector3(1, 1.3, 0.8), Vector3.ZERO, false)
	_sweat.visible = false
	# Landing dust.
	_dust = CPUParticles3D.new()
	_dust.emitting = false
	_dust.one_shot = true
	_dust.amount = 8
	_dust.lifetime = 0.45
	_dust.explosiveness = 1.0
	_dust.direction = Vector3(0, 1, 0)
	_dust.spread = 80.0
	_dust.initial_velocity_min = 1.5
	_dust.initial_velocity_max = 2.6
	_dust.gravity = Vector3(0, -3, 0)
	_dust.scale_amount_min = 0.6
	_dust.scale_amount_max = 1.0
	_dust.mesh = MeshFactory.sphere(0.09, 0.18, 6, 3)
	_dust.material_override = ToyMaterials.flat(Color(1, 1, 1, 1))
	_dust.position = Vector3(0, 0.05, 0)
	add_child(_dust)


func _ensure_look(key: StringName) -> Node3D:
	if _looks.has(key):
		return _looks[key]
	var root := Node3D.new()
	match key:
		&"moon":
			var r: float = maxf(layout.width, 0.5) + 0.22
			var center_y: float = layout.top * 0.55 + 0.1
			root.add_child(MeshFactory.make(MeshFactory.sphere(r, r * 2.0 * (layout.top / 1.2), 20, 10),
					ToyMaterials.glass(Color(0.7, 0.85, 1.0), 0.22), Vector3(0, center_y, 0), Vector3.ONE, Vector3.ZERO, false))
			root.add_child(MeshFactory.make(MeshFactory.torus(r * 0.82, r * 1.0, 20, 6), ToyMaterials.plastic(Color(0.85, 0.85, 0.92)),
					Vector3(0, 0.12, 0), Vector3.ONE, Vector3.ZERO, false))
			_squash.add_child(root)
		&"penguin":
			root.add_child(MeshFactory.make(MeshFactory.cone(0.08, 0.2, 10), ToyMaterials.plastic(Color(1.0, 0.6, 0.15)),
					Vector3(0, layout.eye_y - 0.15, layout.eye_z - 0.1), Vector3(1.3, 1, 0.8), Vector3(-90, 0, 0), false))
			root.add_child(MeshFactory.make(MeshFactory.sphere(0.32, 0.64, 16, 8), ToyMaterials.plastic(Color(1, 1, 1)),
					Vector3(0, layout.eye_y - 0.42, layout.eye_z + 0.13), Vector3(1.0, 1.0, 0.35), Vector3.ZERO, false))
			_parts.add_child(root)
		&"ice":
			for side in [-1.0, 1.0]:
				root.add_child(MeshFactory.make(MeshFactory.box(Vector3(0.05, 0.05, 0.46)), ToyMaterials.plastic(Color(0.85, 0.92, 1.0)),
						Vector3(side * 0.2, 0.0, -0.02), Vector3.ONE, Vector3.ZERO, false))
			_yaw.add_child(root)
		&"sticky":
			for side in [-1.0, 1.0]:
				root.add_child(MeshFactory.make(MeshFactory.sphere(0.17, 0.26, 12, 6), ToyMaterials.plastic(Color(1.0, 0.72, 0.15)),
						Vector3(side * 0.2, 0.05, 0.02), Vector3(1.15, 0.6, 1.25), Vector3.ZERO, false))
			root.add_child(MeshFactory.make(MeshFactory.sphere(0.09, 0.2, 8, 4), ToyMaterials.plastic(Color(1.0, 0.72, 0.15)),
					Vector3(0.1, layout.top - 0.08, 0.0), Vector3(1.2, 0.8, 1.0), Vector3.ZERO, false))
			_yaw.add_child(root)
		&"bounce":
			for side in [-1.0, 1.0]:
				for i in 3:
					root.add_child(MeshFactory.make(MeshFactory.torus(0.05, 0.11, 12, 6), ToyMaterials.plastic(Color(0.8, 0.82, 0.9)),
							Vector3(side * 0.2, 0.02 + i * 0.07, 0), Vector3.ONE, Vector3(0, 0, 8.0 * side), false))
			_yaw.add_child(root)
	root.visible = false
	_looks[key] = root
	return root


# ---------------------------------------------------------------- events from the player

func on_jump() -> void:
	_squash_amount = 1.32
	_squash_velocity = 0.0


func on_land(impact: float) -> void:
	var amount := clampf(impact / 18.0, 0.08, 0.38)
	_squash_amount = 1.0 - amount
	_squash_velocity = 0.0
	if impact > 6.0 and _dust:
		_dust.restart()


func on_bounce() -> void:
	_squash_amount = 0.62
	_squash_velocity = 6.0


func on_respawn() -> void:
	_pop_in = 0.0
	react(&"surprised")


func play_celebration(duration: float = 6.0) -> void:
	_celebrate_left = duration


func set_carrying(value: bool) -> void:
	_carrying = value


## Short funny reaction: surprised, dizzy, happy, oops.
func react(kind: StringName) -> void:
	_reaction = kind
	_reaction_left = {&"surprised": 0.9, &"dizzy": 1.4, &"happy": 1.0, &"oops": 1.3}.get(kind, 0.8)
	if kind == &"surprised" or kind == &"happy":
		_squash_amount = 1.22


## Shows the costume pieces that match the running chaos events.
func set_chaos_looks(vfx_keys: Array[StringName]) -> void:
	for key in _looks:
		(_looks[key] as Node3D).visible = false
	_active_looks = vfx_keys.duplicate()
	for key in vfx_keys:
		if key in [&"moon", &"penguin", &"ice", &"sticky", &"bounce"]:
			_ensure_look(key).visible = true


# ---------------------------------------------------------------- animation

func _process(delta: float) -> void:
	if not _built:
		return
	_time += delta
	var player := get_parent() as PlayerCharacter
	var velocity := Vector3.ZERO
	var on_floor := true
	var facing := Vector3.FORWARD
	if player:
		velocity = player.velocity
		on_floor = player.grounded()
		facing = player.facing
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var run := clampf(hspeed / 7.0, 0.0, 1.0)

	# Face movement direction.
	_yaw.rotation.y = atan2(-facing.x, -facing.z)

	# Squash & stretch spring (volume-preserving scale). Integrated in small
	# fixed steps so it stays stable even when the frame rate drops.
	var steps := clampi(ceili(delta * 120.0), 1, 12)
	var dt := delta / float(steps)
	for i in steps:
		_squash_velocity += (1.0 - _squash_amount) * 180.0 * dt
		_squash_velocity -= _squash_velocity * 11.0 * dt
		_squash_amount += _squash_velocity * dt
	var stretch := _squash_amount
	if not on_floor:
		stretch += clampf(velocity.y * 0.012, -0.08, 0.14)
	else:
		stretch += sin(_time * 2.4) * 0.025 * (1.0 - run)
	stretch = clampf(stretch, 0.55, 1.5)
	var wide := 1.0 / sqrt(stretch)
	_pop_in = minf(1.0, _pop_in + delta * 4.0)
	var pop := ease(_pop_in, 0.4)
	_squash.scale = Vector3(wide, stretch, wide) * pop

	# Running bob + lean.
	_run_phase += delta * (4.0 + hspeed * 1.6) * (1.0 if run > 0.05 else 0.0)
	var bob := absf(sin(_run_phase)) * 0.07 * run if on_floor else 0.0
	var waddling := _active_looks.has(&"penguin") and run > 0.05
	var sway := sin(_run_phase) * deg_to_rad(16.0) if waddling else 0.0
	_squash.position = Vector3(0, bob, 0)
	_squash.rotation = Vector3(-run * deg_to_rad(10.0), 0, sway)

	# Spring shoes in Bounce Mode lift the body a little.
	var want_lift := 0.2 if _active_looks.has(&"bounce") else 0.0
	_lift_amount = lerpf(_lift_amount, want_lift, clampf(delta * 8.0, 0.0, 1.0))
	_lift.position.y = _lift_amount

	# Feet.
	for i in _feet.size():
		var side := -1.0 if i == 0 else 1.0
		var phase := _run_phase + (PI if i == 1 else 0.0)
		var step := sin(phase) * run if on_floor else 0.0
		var foot := _feet[i]
		foot.position = Vector3(side * (0.2 + (0.06 if waddling else 0.0)), 0.07 + maxf(0.0, step) * 0.12 + _lift_amount * 0.0,
				-step * 0.16)
		if not on_floor:
			foot.position.y = 0.07 - 0.03

	# Arms.
	var arm_up := 0.0
	if _carrying:
		arm_up = 1.0
	elif not on_floor and velocity.y < -6.0:
		arm_up = 0.85
	elif _reaction in [&"surprised", &"oops"] and _reaction_left > 0.0:
		arm_up = 0.9
	if _celebrate_left > 0.0:
		arm_up = 0.6 + 0.4 * absf(sin(_time * 8.0))
	var flipper := waddling
	for i in _arm_pivots.size():
		var side := -1.0 if i == 0 else 1.0
		var swing := sin(_run_phase + (0.0 if i == 0 else PI)) * 0.7 * run * (1.0 - arm_up)
		var out_angle := lerpf(deg_to_rad(22.0), deg_to_rad(160.0), arm_up)
		if flipper:
			out_angle = deg_to_rad(38.0) + absf(sin(_time * 14.0)) * 0.5
		_arm_pivots[i].rotation = Vector3(swing, 0, side * out_angle)
		_arm_meshes[i].scale = Vector3(1.6, 1.0, 0.45) if flipper else Vector3.ONE

	# Accessory wiggle + propeller spin.
	if _accessory:
		_accessory.rotation.x = clampf(-velocity.y * 0.012, -0.3, 0.3) + sin(_time * 3.0) * 0.04
		_accessory.rotation.z = sin(_run_phase) * 0.12 * run
	if _spinner:
		var spin_speed := 6.0 + (22.0 if not on_floor else run * 10.0)
		_spinner.rotate_y(spin_speed * delta)

	_update_face(delta, on_floor, velocity)
	_update_emotes(delta)

	# Celebration: happy hops and spins.
	if _celebrate_left > 0.0:
		_celebrate_left -= delta
		_yaw.rotation.y = fmod(_time * 3.0, TAU)
		_squash.position.y += absf(sin(_time * 6.0)) * 0.35


func _update_face(delta: float, on_floor: bool, velocity: Vector3) -> void:
	_blink_timer -= delta
	if _blink_timer <= 0.0:
		_blink_timer = randf_range(2.2, 5.0)
		_blink_left = 0.12
	_blink_left = maxf(0.0, _blink_left - delta)
	var blink := 0.12 if _blink_left > 0.0 else 1.0

	_reaction_left = maxf(0.0, _reaction_left - delta)
	var reaction := _reaction if _reaction_left > 0.0 else &""
	var reversed := _active_looks.has(&"reverse")
	var eye_scale := Vector3.ONE
	var pupil_scale := 1.0
	var pupil_offset := Vector2.ZERO
	var mouth := false
	match reaction:
		&"surprised":
			eye_scale = Vector3(1.18, 1.25, 1.0)
			pupil_scale = 0.75
			mouth = true
		&"dizzy":
			var a := _time * 12.0
			pupil_offset = Vector2(cos(a), sin(a)) * 0.05
		&"happy":
			eye_scale = Vector3(1.05, 0.55, 1.0)
		&"oops":
			eye_scale = Vector3(1.1, 1.2, 1.0)
			mouth = true
	if reversed and reaction == &"":
		var a2 := _time * 7.0
		pupil_offset = Vector2(cos(a2), -sin(a2)) * 0.045
	if not on_floor and velocity.y < -9.0:
		mouth = true
		eye_scale = Vector3(1.15, 1.2, 1.0)
	if _celebrate_left > 0.0:
		eye_scale = Vector3(1.05, 0.6, 1.0)
	for i in _eye_whites.size():
		_eye_whites[i].scale = Vector3(eye_scale.x, eye_scale.y * blink, eye_scale.z)
		_pupils[i].scale = Vector3.ONE * pupil_scale
		_pupils[i].position.x = pupil_offset.x * (1.0 if i == 0 else -1.0)
		_pupils[i].position.y = -0.01 + pupil_offset.y
	if _mouth:
		_mouth.visible = mouth
	if _sweat:
		_sweat.visible = reaction == &"oops" or _carrying_struggle
		_sweat.position.y = layout.top - 0.1 - fmod(_time * 0.4, 0.3)


## Set by game modes when a carried object is about to fall.
var _carrying_struggle: bool = false


func set_struggling(value: bool) -> void:
	_carrying_struggle = value


func _update_emotes(delta: float) -> void:
	var reaction := _reaction if _reaction_left > 0.0 else &""
	_dizzy_stars.visible = reaction == &"dizzy"
	if _dizzy_stars.visible:
		_dizzy_stars.rotate_y(delta * 6.0)
	_alert.visible = reaction == &"surprised"
	if _alert.visible:
		_alert.position.y = sin(_time * 18.0) * 0.03
	_reverse_icon.visible = _active_looks.has(&"reverse")
	if _reverse_icon.visible:
		_reverse_icon.rotate_y(delta * 3.0)
