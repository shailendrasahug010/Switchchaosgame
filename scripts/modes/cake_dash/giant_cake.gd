@tool
class_name GiantCake
extends RigidBody3D
## The giant birthday cake from Cake Dash.
##
## States: LOOSE (a normal physics object on the ground), CARRIED (held above
## a player's head, wobbling) and DELIVERED (sitting on the party table).
## The wobble is a small spring: sharp turns, sudden stops, big landings and
## bonks push it; steady walking and helpers calm it. Too much wobble and the
## cake tips off. Origin = bottom center of the cake.

signal dropped(by: PlayerCharacter)
signal fell_in_goo

enum State { LOOSE, CARRIED, DELIVERED }

const MAX_CANDLES := 5
## The cake model is built at a "normal" size and scaled up to look giant.
const CAKE_SCALE := 1.25
## How hard the carrier's acceleration pushes the wobble.
const SENSITIVITY := 0.42
const SPRING := 30.0
const DAMPING := 3.2

@export var frosting_color: Color = Color("ff8fc0"):
	set(v):
		frosting_color = v
		_changed()
@export var sponge_color: Color = Color("fff1d6"):
	set(v):
		sponge_color = v
		_changed()

var state: State = State.LOOSE
var carrier: PlayerCharacter = null
var helpers: Array[PlayerCharacter] = []
var candles: int = MAX_CANDLES
## Current lean (x/z), 1.0 = falls off.
var tilt: Vector2 = Vector2.ZERO
var tilt_velocity: Vector2 = Vector2.ZERO
var last_carrier_index: int = -1
var last_drop_time: float = -100.0

var _visual: Node3D
var _candle_flames: Array[Node3D] = []
var _last_carrier_velocity: Vector3 = Vector3.ZERO
var _queued := false


func _ready() -> void:
	collision_layer = Layers.PROPS
	collision_mask = Layers.WORLD | Layers.PROPS
	mass = 3.0
	linear_damp = 0.6
	angular_damp = 2.5
	continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.1
	physics_material_override = pm
	add_to_group(&"cake")
	_rebuild()


func _changed() -> void:
	if not is_inside_tree() or _queued:
		return
	_queued = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_queued = false
	Gen.clear(self)
	_candle_flames.clear()
	Gen.cylinder_shape(self, 0.85 * CAKE_SCALE, 1.15 * CAKE_SCALE, Vector3(0, 0.575 * CAKE_SCALE, 0))
	_visual = Gen.node(self)
	_visual.scale = Vector3.ONE * CAKE_SCALE
	var plate := ToyMaterials.plastic(Color("f2f2ff"))
	Gen.mesh(_visual, MeshFactory.cylinder(1.0, 0.95, 0.08, 28), plate, Vector3(0, 0.04, 0))
	var tiers := [[0.85, 0.5, 0.08], [0.62, 0.38, 0.58], [0.4, 0.3, 0.96]]
	for t in tiers:
		var r: float = t[0]
		var h: float = t[1]
		var y: float = t[2]
		Gen.mesh(_visual, MeshFactory.cylinder(r, r, h, 28), ToyMaterials.plastic(sponge_color), Vector3(0, y + h * 0.5, 0))
		# Frosting cap and drips.
		Gen.mesh(_visual, MeshFactory.cylinder(r + 0.03, r + 0.03, 0.1, 28), ToyMaterials.plastic(frosting_color),
				Vector3(0, y + h - 0.03, 0))
		var drips := int(r * 14.0)
		for i in drips:
			var a := TAU * float(i) / drips
			var drip_len := 0.08 + 0.1 * absf(sin(i * 2.3))
			Gen.mesh(_visual, MeshFactory.capsule(0.05, drip_len + 0.1, 6, 2), ToyMaterials.plastic(frosting_color),
					Vector3(cos(a) * (r + 0.02), y + h - 0.06 - drip_len * 0.4, sin(a) * (r + 0.02)), Vector3.ONE,
					Vector3.ZERO, false)
	# Strawberries on the middle tier.
	for i in 6:
		var a := TAU * float(i) / 6.0 + 0.3
		Gen.mesh(_visual, MeshFactory.sphere(0.09, 0.2, 8, 4), ToyMaterials.plastic(Color("ff3355")),
				Vector3(cos(a) * 0.52, 1.0, sin(a) * 0.52), Vector3.ONE, Vector3.ZERO, false)
	# Candles on top.
	for i in MAX_CANDLES:
		var a := TAU * float(i) / MAX_CANDLES
		var p := Vector3(cos(a) * 0.24, 1.26, sin(a) * 0.24)
		var stripe: Color = [Color("3f9dff"), Color("ffd23f"), Color("2fc97a"), Color("a77bff"), Color("ff5fa8")][i]
		Gen.mesh(_visual, MeshFactory.cylinder(0.04, 0.04, 0.26, 8), ToyMaterials.plastic(stripe), p + Vector3(0, 0.13, 0))
		var flame := Gen.node(_visual, p + Vector3(0, 0.32, 0))
		Gen.mesh(flame, MeshFactory.sphere(0.055, 0.14, 8, 4), ToyMaterials.glow(Color("ffb13b"), 1.6), Vector3.ZERO,
				Vector3.ONE, Vector3.ZERO, false)
		_candle_flames.append(flame)
	_refresh_candles()


func _refresh_candles() -> void:
	for i in _candle_flames.size():
		_candle_flames[i].visible = i < candles


func lose_candle() -> void:
	candles = maxi(0, candles - 1)
	_refresh_candles()


func reset_cake(at: Vector3) -> void:
	state = State.LOOSE
	carrier = null
	helpers.clear()
	tilt = Vector2.ZERO
	tilt_velocity = Vector2.ZERO
	freeze = false
	collision_layer = Layers.PROPS
	global_transform = Transform3D(Basis(), at)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	reset_physics_interpolation()
	if _visual:
		_visual.rotation = Vector3.ZERO


# ---------------------------------------------------------------- carrying

func pick_up(p: PlayerCharacter) -> void:
	state = State.CARRIED
	carrier = p
	last_carrier_index = p.player_index
	helpers.erase(p)
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	collision_layer = 0
	tilt = Vector2.ZERO
	tilt_velocity = Vector2.ZERO
	_last_carrier_velocity = p.velocity
	p.visual.set_carrying(true)
	_follow_carrier()


## Lets go of the cake. [param tumble] = it fell (wobble or bonk) instead of
## being put down gently.
func release(tumble: bool, now: float) -> void:
	if state != State.CARRIED:
		return
	var by := carrier
	state = State.LOOSE
	if by:
		by.visual.set_carrying(false)
		by.visual.set_struggling(false)
	for h in helpers:
		h.visual.set_carrying(false)
	helpers.clear()
	carrier = null
	freeze = false
	collision_layer = Layers.PROPS
	if _visual:
		_visual.rotation = Vector3.ZERO
	var forward := by.facing if by else Vector3.FORWARD
	if tumble:
		var lean := Vector3(tilt.x, 0, tilt.y)
		if lean.length() < 0.1:
			lean = forward
		var out := lean.normalized()
		global_position = (by.global_position if by else global_position) + out * 1.1 + Vector3(0, 1.4, 0)
		linear_velocity = (by.velocity * 0.5 if by else Vector3.ZERO) + out * 2.5 + Vector3(0, 2.5, 0)
		angular_velocity = Vector3(out.z, 0, -out.x) * 4.0
		last_drop_time = now
		lose_candle()
		dropped.emit(by)
	else:
		global_transform = Transform3D(Basis(), (by.global_position if by else global_position) + forward * 1.3)
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
	tilt = Vector2.ZERO
	tilt_velocity = Vector2.ZERO
	reset_physics_interpolation()


func add_helper(p: PlayerCharacter) -> void:
	if not helpers.has(p) and p != carrier:
		helpers.append(p)
		p.visual.set_carrying(true)


func remove_helper(p: PlayerCharacter) -> void:
	if helpers.has(p):
		helpers.erase(p)
		p.visual.set_carrying(false)


## Called every physics tick while carried. [param sensitivity_mult] comes
## from chaos rules (cake_wobble) and helpers. Returns true if it tipped over.
func update_carried(delta: float, sensitivity_mult: float, extra_damping: float) -> bool:
	if carrier == null:
		return false
	var v := carrier.velocity
	var accel := (Vector3(v.x, 0, v.z) - Vector3(_last_carrier_velocity.x, 0, _last_carrier_velocity.z)) / maxf(delta, 0.001)
	_last_carrier_velocity = v
	if accel.length() > 120.0:
		accel = accel.normalized() * 120.0  # teleports / respawns are not "shakes"
	# The cake leans against the acceleration (like a real wobbly tower).
	tilt_velocity += -Vector2(accel.x, accel.z) * SENSITIVITY * sensitivity_mult * delta
	tilt_velocity += -tilt * SPRING * delta
	tilt_velocity *= exp(-(DAMPING + extra_damping) * delta)
	tilt += tilt_velocity * delta
	_follow_carrier()
	carrier.visual.set_struggling(tilt.length() > 0.6)
	return tilt.length() >= 1.0


## A sudden shake: a landing or a bonk.
func jolt(direction: Vector3, strength: float) -> void:
	var d := Vector2(direction.x, direction.z)
	if d.length() < 0.01:
		d = Vector2.from_angle(randf() * TAU)
	tilt_velocity += d.normalized() * strength


func _follow_carrier() -> void:
	if carrier == null:
		return
	var anchor := carrier.carry_point.global_position
	var yaw := atan2(-carrier.facing.x, -carrier.facing.z)
	global_transform = Transform3D(Basis(Vector3.UP, yaw), anchor)
	if _visual:
		# Visual lean in world terms, converted into the cake's yaw frame.
		var lean := Vector3(tilt.x, 0, tilt.y).rotated(Vector3.UP, -yaw)
		var max_angle := deg_to_rad(26.0)
		_visual.rotation = Vector3(lean.z * max_angle, 0, -lean.x * max_angle)


# ---------------------------------------------------------------- goo & delivery

## Called by KillZone when the cake drops into the goo.
func fell_in() -> void:
	fell_in_goo.emit()


func deliver_to(spot: Vector3) -> void:
	if carrier:
		carrier.visual.set_carrying(false)
		carrier.visual.set_struggling(false)
	for h in helpers:
		h.visual.set_carrying(false)
	helpers.clear()
	carrier = null
	state = State.DELIVERED
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	collision_layer = 0
	if _visual:
		_visual.rotation = Vector3.ZERO
	var t := create_tween()
	t.tween_property(self, "global_position", spot, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func wobble_amount() -> float:
	return clampf(tilt.length(), 0.0, 1.0)
