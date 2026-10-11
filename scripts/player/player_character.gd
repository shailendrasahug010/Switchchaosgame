class_name PlayerCharacter
extends CharacterBody3D
## A squishy toy creature that runs, jumps and bounces.
##
## Movement only: this script knows nothing about game modes, scoring or UI.
## Every tunable number is exported. Chaos events never change these numbers
## directly — they register multipliers on [member rules] (shared by the whole
## match) and the effective values are recomputed every physics tick, so when
## an event ends its effect is gone without any manual "undo" code.

signal jumped
signal landed(impact_speed: float)
signal bounced(strength: float)
signal fell_out
signal respawned
signal knocked(direction: Vector3)
signal interact_requested(player: PlayerCharacter)
## A funny reaction (surprised, dizzy, happy, oops): the match plays a voice for it.
signal reacted(kind: StringName)

@export_group("Movement")
@export var max_speed: float = 7.0
@export var ground_accel: float = 55.0
@export var ground_decel: float = 60.0
@export var air_accel: float = 24.0
@export var turn_speed: float = 14.0
@export_group("Jumping")
@export var jump_velocity: float = 9.5
@export var gravity: float = 26.0
@export var fall_gravity_multiplier: float = 1.35
@export var jump_cut_multiplier: float = 0.5
@export var max_fall_speed: float = 32.0
@export var coyote_time: float = 0.12
@export var jump_buffer_time: float = 0.14
@export_group("Body")
@export var base_radius: float = 0.45
@export var base_height: float = 1.3
@export var push_strength: float = 2.2
@export var respawn_delay: float = 0.55

## Which player this is (0..3); set by the match.
var player_index: int = 0
var display_name: String = ""
var character_id: StringName = &"bloop"
var tag_color: Color = Color.WHITE
var is_human: bool = true
var input: PlayerInputSource = null
## Shared chaos rules for the match. May be null (no chaos).
var rules: ModifierStack = null
## Effects that belong to this player only (carrying a cake, being stunned...).
var personal: ModifierStack = ModifierStack.new()
## Movement is relative to the camera's yaw so "up" on the stick is "away from camera".
var camera_yaw: float = 0.0
var controls_enabled: bool = false
var respawn_position: Vector3 = Vector3.ZERO
var kill_y: float = -15.0
## World-space direction the creature looks towards.
var facing: Vector3 = Vector3.FORWARD
var size_scale: float = 1.0
var is_respawning: bool = false

var _coyote: float = 0.0
var _jump_buffer: float = 0.0
var _jumping: bool = false
var _was_on_floor: bool = false
var _waddle_phase: float = 0.0
var _stun: float = 0.0
var _respawn_timer: float = 0.0
var _size_velocity: float = 0.0
var _applied_size: float = 1.0
var _blocked_from_growing: bool = false
var _room_query: PhysicsShapeQueryParameters3D
var _room_shape: CapsuleShape3D
var _standing_time: float = 0.0

@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var visual: PlayerVisual = $Visual
@onready var carry_point: Marker3D = $CarryPoint
@onready var name_tag: Label3D = $NameTag

var _shape: CapsuleShape3D


func _ready() -> void:
	collision_layer = Layers.PLAYERS
	collision_mask = Layers.WORLD | Layers.PROPS
	floor_snap_length = 0.2
	floor_max_angle = deg_to_rad(50.0)
	# Each player needs its own shape so size changes don't affect the others.
	_shape = (collision.shape as CapsuleShape3D).duplicate() if collision.shape is CapsuleShape3D else CapsuleShape3D.new()
	collision.shape = _shape
	_room_shape = CapsuleShape3D.new()
	_room_query = PhysicsShapeQueryParameters3D.new()
	_room_query.shape = _room_shape
	_room_query.collision_mask = Layers.WORLD
	_apply_size(1.0)


## Gives the creature its look. Call before or after adding to the tree.
func setup_look(p_character_id: StringName, hat_id: StringName, paint_id: StringName,
		p_tag_color: Color, label: String) -> void:
	character_id = p_character_id
	tag_color = p_tag_color
	if not is_node_ready():
		await ready
	visual.build(p_character_id, hat_id, paint_id)
	name_tag.text = label
	name_tag.modulate = p_tag_color.lightened(0.15)
	name_tag.outline_modulate = Color(0.08, 0.06, 0.18)


# ---------------------------------------------------------------- stats

## Effective multiplier for [param stat] from chaos rules and personal effects.
func stat(stat_name: StringName) -> float:
	var v := personal.mul(stat_name)
	if rules:
		v *= rules.mul(stat_name)
	return v


func stat_max(stat_name: StringName, fallback: float = 0.0) -> float:
	var v := personal.max_of(stat_name, fallback)
	if rules:
		v = maxf(v, rules.max_of(stat_name, fallback))
	return v


func stat_flag(stat_name: StringName) -> bool:
	return personal.any(stat_name) or (rules != null and rules.any(stat_name))


func is_reversed() -> bool:
	return stat_flag(&"reverse")


func is_stunned() -> bool:
	return _stun > 0.0


# ---------------------------------------------------------------- physics

func _physics_process(delta: float) -> void:
	if is_respawning:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_finish_respawn()
		return

	if input:
		input.update(delta, self)
	_update_size(delta)
	_stun = maxf(0.0, _stun - delta)

	var on_floor := is_on_floor()
	var gravity_scale := stat(&"gravity")

	# --- gravity
	if not on_floor:
		var g := gravity * gravity_scale
		if velocity.y < 0.0:
			g *= fall_gravity_multiplier
		velocity.y -= g * delta
		velocity.y = maxf(velocity.y, -max_fall_speed * sqrt(maxf(gravity_scale, 0.05)))

	# --- stick -> world direction
	var stick := Vector2.ZERO
	if controls_enabled and input:
		stick = input.move
	if is_reversed():
		stick = -stick
	if _stun > 0.0:
		stick *= 0.25
	var dir := Vector3(stick.x, 0.0, stick.y).rotated(Vector3.UP, camera_yaw)
	if dir.length() > 1.0:
		dir = dir.normalized()

	# --- horizontal speed
	var speed := max_speed * stat(&"speed")
	var waddle := stat_max(&"waddle", 0.0)
	if waddle > 0.0 and dir.length() > 0.1:
		_waddle_phase += delta * 10.0
		speed *= lerpf(1.0, 0.3 + 0.7 * absf(sin(_waddle_phase)), waddle)
	var target := dir * speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate: float
	if on_floor:
		var traction := stat(&"traction")
		rate = (ground_accel if dir.length() > 0.05 else ground_decel) * traction
	else:
		rate = air_accel * stat(&"air_control")
	if _stun > 0.0:
		rate *= 0.3
	horizontal = horizontal.move_toward(target, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	# --- jumping (buffered + coyote time)
	if on_floor:
		_coyote = coyote_time
		_jumping = false
	else:
		_coyote -= delta
	if controls_enabled and input and input.consume_jump():
		_jump_buffer = jump_buffer_time
	else:
		_jump_buffer -= delta
	if _jump_buffer > 0.0 and _coyote > 0.0:
		velocity.y = jump_velocity * stat(&"jump")
		_jump_buffer = 0.0
		_coyote = 0.0
		_jumping = true
		visual.on_jump()
		jumped.emit()
	elif _jumping and velocity.y > 0.0 and input and not input.jump_held:
		# Short tap = short hop.
		velocity.y *= jump_cut_multiplier
		_jumping = false

	# --- interacting
	if controls_enabled and input and input.consume_interact():
		interact_requested.emit(self)

	# --- move
	var vertical_before := velocity.y
	move_and_slide()
	_push_props()

	var now_on_floor := is_on_floor()
	if now_on_floor and not _was_on_floor:
		var impact := maxf(0.0, -vertical_before)
		visual.on_land(impact)
		landed.emit(impact)
		_standing_time = 0.0
		_try_floor_bounce(impact)
	elif now_on_floor:
		# Standing on a trampoline floor (Bounce Mode, jelly blocks): start bouncing.
		_standing_time += delta
		if _standing_time > 0.2:
			_try_floor_bounce(0.0, true)
	_was_on_floor = now_on_floor

	if horizontal.length() > 0.4:
		var want := horizontal.normalized()
		facing = facing.slerp(want, clampf(turn_speed * delta, 0.0, 1.0)).normalized() if facing.dot(want) > -0.98 else want

	if global_position.y < kill_y:
		_start_respawn()


func _try_floor_bounce(impact: float, standing: bool = false) -> void:
	var surface := _floor_surface_bounce()
	var hold_bonus := 1.25 if (input and input.jump_held and controls_enabled) else 1.0
	if surface > 0.0:
		# Jelly blocks: always the same, predictable launch.
		_standing_time = 0.0
		launch(surface * hold_bonus, false)
		return
	var bounciness := stat_max(&"floor_bounce", 0.0)
	if bounciness <= 0.0 or (impact < 1.0 and not standing):
		return
	_standing_time = 0.0
	var strength := maxf(impact * bounciness, stat_max(&"min_bounce", 0.0))
	launch(minf(strength * hold_bonus, 18.0), false)


## Launch speed of the bouncy surface we stand on (0 = normal floor).
func _floor_surface_bounce() -> float:
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		if hit.get_normal().y < 0.6:
			continue
		var body := hit.get_collider()
		if body and body.has_method("get_surface_bounce"):
			var b: float = body.get_surface_bounce()
			if b > 0.0:
				return b
	return 0.0


## Sends the player upward (bounce pads, trampoline floors).
func launch(up_speed: float, from_pad: bool = true) -> void:
	velocity.y = up_speed
	_jumping = false
	_coyote = 0.0
	visual.on_bounce()
	bounced.emit(up_speed)
	if from_pad:
		# Pads are predictable: always the same height, whatever the floor rules.
		pass


## A soft bonk from an obstacle: slide away from [param from_point] and get dizzy.
func knock(from_point: Vector3, strength: float = 8.0, lift: float = 4.5) -> void:
	if is_respawning:
		return
	var away := global_position - from_point
	away.y = 0.0
	if away.length() < 0.01:
		away = -facing
	away = away.normalized()
	velocity.x = away.x * strength
	velocity.z = away.z * strength
	velocity.y = maxf(velocity.y, lift)
	_stun = 0.45
	_jumping = false
	react(&"dizzy")
	knocked.emit(away)


func _push_props() -> void:
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		var body := hit.get_collider() as RigidBody3D
		if body == null or body.freeze:
			continue
		var push := -hit.get_normal()
		push.y = 0.0
		if push.length() < 0.01:
			continue
		var strength := push_strength * stat(&"push") * size_scale
		body.apply_impulse(push.normalized() * strength * get_physics_process_delta_time() * 10.0,
				hit.get_position() - body.global_position)


# ---------------------------------------------------------------- size

func _update_size(delta: float) -> void:
	var target := clampf(stat(&"size"), 0.3, 2.5)
	_blocked_from_growing = false
	if target > size_scale + 0.02 and not _has_room_for(target):
		target = size_scale
		_blocked_from_growing = true
		_size_velocity = minf(_size_velocity, 0.0)
	# A springy "boing" toward the target size.
	_size_velocity += (target - size_scale) * 130.0 * delta
	_size_velocity -= _size_velocity * 15.0 * delta
	size_scale = clampf(size_scale + _size_velocity * delta, 0.25, 2.8)
	if absf(size_scale - _applied_size) > 0.002:
		_apply_size(size_scale)


## True when a capsule of the bigger size would not poke into a ceiling.
## Sideways overlap is fine: move_and_slide gently pushes us out of walls.
func _has_room_for(new_scale: float) -> bool:
	if not is_inside_tree():
		return true
	_room_shape.radius = base_radius * minf(new_scale, size_scale) * 0.9
	_room_shape.height = maxf(base_height * new_scale * 1.05, _room_shape.radius * 2.0)
	_room_query.transform = Transform3D(Basis(), global_position + Vector3(0.0, _room_shape.height * 0.5 + 0.08, 0.0))
	_room_query.exclude = [get_rid()]
	var hits := get_world_3d().direct_space_state.intersect_shape(_room_query, 1)
	return hits.is_empty()


func is_blocked_from_growing() -> bool:
	return _blocked_from_growing


func _apply_size(s: float) -> void:
	_applied_size = s
	_shape.radius = base_radius * s
	_shape.height = maxf(base_height * s, _shape.radius * 2.0)
	collision.position = Vector3(0.0, _shape.height * 0.5, 0.0)
	visual.scale = Vector3.ONE * s
	carry_point.position = Vector3(0.0, base_height * s + 0.25, 0.0)
	name_tag.position = Vector3(0.0, base_height * s + 0.75, 0.0)


# ---------------------------------------------------------------- respawn

func _start_respawn() -> void:
	if is_respawning:
		return
	is_respawning = true
	_respawn_timer = respawn_delay
	velocity = Vector3.ZERO
	visual.visible = false
	name_tag.visible = false
	fell_out.emit()


func _finish_respawn() -> void:
	is_respawning = false
	teleport(respawn_position)
	visual.visible = true
	name_tag.visible = true
	visual.on_respawn()
	respawned.emit()


## Moves instantly (no interpolation smear) and stops all motion.
func teleport(position_: Vector3, new_facing: Vector3 = Vector3.ZERO) -> void:
	global_position = position_
	velocity = Vector3.ZERO
	_jumping = false
	_was_on_floor = false
	if new_facing != Vector3.ZERO:
		facing = new_facing.normalized()
	reset_physics_interpolation()


## Forces an immediate respawn at the current respawn point (used by modes).
func respawn_now() -> void:
	_start_respawn()
	_respawn_timer = 0.0


func celebrate() -> void:
	visual.play_celebration()


func react(kind: StringName) -> void:
	visual.react(kind)
	reacted.emit(kind)
