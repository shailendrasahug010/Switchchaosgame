@tool
class_name PushButton
extends Interactable
## A big arcade-style push button for Button Mayhem.
##
## Press it with the action button when you are close, or STOMP it by landing
## on top. The button only reports presses ([signal pressed_by]); the game mode
## decides whether it was the right one and then calls [method accept] or
## [method reject] for the matching feedback. Origin on the floor.

signal pressed_by(player: PlayerCharacter, button: PushButton, stomped: bool)

## Which color (see Catalog.BUTTON_COLORS). The symbol comes with the color.
@export var color_id: StringName = &"red":
	set(v):
		color_id = v
		_changed()
## Size of the pedestal. Small buttons ride on toy cars.
@export_range(0.3, 1.5, 0.05) var radius: float = 0.8:
	set(v):
		radius = v
		_changed()

var lit := false
var _cap: Node3D
var _cap_material: StandardMaterial3D
var _symbol: Node3D
var _arrow: Node3D
var _press_anim := 0.0
var _flash := 0.0
var _flash_color := Color.WHITE
var _shake := 0.0
var _time := 0.0
var _stomp_area: Area3D
var _stomp_cooldowns: Dictionary = {}
var _queued := false


func _ready() -> void:
	super()
	prompt = "PRESS"
	prompt_icon = &"buttons"
	cooldown = 0.8
	if interact_radius < radius + 1.0:
		interact_radius = radius + 1.3
	_rebuild()


func _changed() -> void:
	if not is_inside_tree() or _queued:
		return
	_queued = true
	_rebuild.call_deferred()


func get_info() -> Dictionary:
	return Catalog.button_color(color_id)


func get_color() -> Color:
	return get_info().color


func _rebuild() -> void:
	_queued = false
	Gen.clear(self)
	var info := get_info()
	var col: Color = info.color
	var h := 0.3 * radius / 0.8
	# Solid pedestal you can stand on (for stomping).
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	Gen.add(self, body)
	Gen.cylinder_shape(body, radius, h + 0.16, Vector3(0, (h + 0.16) * 0.5, 0))
	Gen.mesh(body, MeshFactory.cylinder(radius, radius * 1.08, h, 28), ToyMaterials.plastic(Color("3b3561")),
			Vector3(0, h * 0.5, 0))
	Gen.mesh(body, MeshFactory.torus(radius * 0.86, radius * 1.02, 28, 8), ToyMaterials.plastic(Color("fff8ee")),
			Vector3(0, h, 0), Vector3(1, 0.6, 1), Vector3.ZERO, false)
	# The cap that goes down when pressed.
	_cap = Gen.node(self, Vector3(0, h, 0))
	_cap_material = ToyMaterials.plastic(col).duplicate() as StandardMaterial3D
	Gen.mesh(_cap, MeshFactory.cylinder(radius * 0.78, radius * 0.8, 0.16, 28), _cap_material, Vector3(0, 0.08, 0))
	Gen.mesh(_cap, MeshFactory.sphere(radius * 0.78, radius * 0.5, 28, 8), _cap_material, Vector3(0, 0.16, 0),
			Vector3(1, 0.55, 1), Vector3.ZERO, false)
	_symbol = Gen.node(_cap, Vector3(0, 0.33, 0))
	_build_symbol(StringName(info.symbol), radius * 0.42)
	# Stomp detector just above the cap.
	_stomp_area = Area3D.new()
	_stomp_area.collision_layer = Layers.TRIGGERS
	_stomp_area.collision_mask = Layers.PLAYERS
	_stomp_area.monitorable = false
	Gen.add(self, _stomp_area)
	Gen.cylinder_shape(_stomp_area, radius * 0.95, 0.6, Vector3(0, h + 0.16 + 0.3, 0))
	if Gen.in_game():
		_stomp_area.body_entered.connect(_on_stomp_area_entered)
	# Hint arrow (hidden until the mode lights the button up).
	_arrow = Gen.node(self, Vector3(0, 2.6, 0))
	Gen.mesh(_arrow, MeshFactory.cone(0.42, 0.7, 4), ToyMaterials.glow(Color("fff3a3"), 0.9), Vector3.ZERO,
			Vector3.ONE, Vector3(180, 45, 0), false)
	Gen.mesh(_arrow, MeshFactory.box(Vector3(0.26, 0.5, 0.26)), ToyMaterials.glow(Color("fff3a3"), 0.9),
			Vector3(0, 0.55, 0), Vector3.ONE, Vector3(0, 45, 0), false)
	_arrow.visible = lit
	_apply_lit()


func _build_symbol(symbol: StringName, s: float) -> void:
	var white := ToyMaterials.plastic(Color.WHITE)
	match symbol:
		&"heart":
			Gen.mesh(_symbol, MeshFactory.sphere(s * 0.42, s * 0.5, 14, 6), white, Vector3(-s * 0.3, 0, -s * 0.18),
					Vector3(1, 0.5, 1), Vector3.ZERO, false)
			Gen.mesh(_symbol, MeshFactory.sphere(s * 0.42, s * 0.5, 14, 6), white, Vector3(s * 0.3, 0, -s * 0.18),
					Vector3(1, 0.5, 1), Vector3.ZERO, false)
			Gen.mesh(_symbol, MeshFactory.box(Vector3(s * 0.84, s * 0.25, s * 0.84)), white, Vector3(0, 0, s * 0.12),
					Vector3.ONE, Vector3(0, 45, 0), false)
		&"circle":
			Gen.mesh(_symbol, MeshFactory.torus(s * 0.45, s * 0.85, 24, 8), white, Vector3.ZERO, Vector3(1, 0.5, 1),
					Vector3.ZERO, false)
		&"star":
			Gen.mesh(_symbol, MeshFactory.star(s, s * 0.45, s * 0.25), white, Vector3.ZERO, Vector3.ONE,
					Vector3(-90, 0, 0), false)
		&"triangle":
			Gen.mesh(_symbol, MeshFactory.cylinder(s * 0.95, s * 0.95, s * 0.25, 3), white, Vector3.ZERO, Vector3.ONE,
					Vector3(0, 90, 0), false)
		&"diamond":
			# A 4-sided "cylinder" has its corners on the axes: a diamond.
			Gen.mesh(_symbol, MeshFactory.cylinder(s * 0.8, s * 0.8, s * 0.25, 4), white, Vector3.ZERO,
					Vector3(0.8, 1, 1.25), Vector3.ZERO, false)
		_:
			Gen.mesh(_symbol, MeshFactory.box(Vector3(s * 1.2, s * 0.25, s * 1.2)), white, Vector3.ZERO, Vector3.ONE,
					Vector3.ZERO, false)


## Makes this the glowing "press me" button (with a bobbing arrow) or not.
func set_lit(value: bool) -> void:
	if value == lit:
		return
	lit = value
	_apply_lit()


func _apply_lit() -> void:
	if _arrow:
		_arrow.visible = lit
	if _cap_material:
		_cap_material.emission_enabled = lit
		_cap_material.emission = get_color()
		_cap_material.emission_energy_multiplier = 0.5


## Feedback for a correct press.
func accept() -> void:
	_flash = 1.0
	_flash_color = Color("7dffb0")


## Feedback for a wrong press: a shake and a red flash.
func reject() -> void:
	_flash = 1.0
	_flash_color = Color("ff4d6d")
	_shake = 0.5


func _on_interact(player: PlayerCharacter) -> void:
	_press_anim = 1.0
	pressed_by.emit(player, self, false)


func _on_stomp_area_entered(body: Node3D) -> void:
	var player := body as PlayerCharacter
	# Only a real landing counts (not just stepping off a ledge next to it).
	if player == null or player.is_respawning or player.velocity.y > -2.0:
		return
	if not can_interact(player):
		return
	var id := player.get_instance_id()
	if _stomp_cooldowns.has(id):
		return
	_stomp_cooldowns[id] = 0.6
	_cooldown_left = cooldown
	_press_anim = 1.0
	pressed_by.emit(player, self, true)
	interacted.emit(player)


func _physics_process(delta: float) -> void:
	super(delta)
	if not Gen.in_game():
		return
	for id in _stomp_cooldowns.keys():
		_stomp_cooldowns[id] = float(_stomp_cooldowns[id]) - delta
		if _stomp_cooldowns[id] <= 0.0:
			_stomp_cooldowns.erase(id)


func _process(delta: float) -> void:
	if not Gen.in_game() or _cap == null:
		return
	_time += delta
	_press_anim = maxf(0.0, _press_anim - delta * 3.5)
	var down := sin(_press_anim * PI) * 0.12
	_cap.position.y = 0.3 * radius / 0.8 - down
	_cap.scale = Vector3(1.0 + down, 1.0 - down * 2.0, 1.0 + down)
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta)
		_cap.position.x = sin(_time * 60.0) * 0.06 * _shake * 2.0
	else:
		_cap.position.x = 0.0
	if _arrow and lit:
		_arrow.position.y = 2.5 + absf(sin(_time * 4.0)) * 0.5
		_arrow.rotation.y = _time * 1.5
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 1.6)
		_cap_material.emission_enabled = true
		_cap_material.emission = _flash_color
		_cap_material.emission_energy_multiplier = _flash * 1.4
	elif _cap_material.emission_enabled != lit or (lit and _cap_material.emission != get_color()):
		_apply_lit()
	elif lit:
		_cap_material.emission_energy_multiplier = 0.35 + 0.3 * absf(sin(_time * 3.0))
