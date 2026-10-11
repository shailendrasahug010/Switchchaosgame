class_name KnockArea
extends Area3D
## A soft "bonk" zone used by spinners, swingers and rollers.
##
## Any player touching it is pushed in [member push_direction] (or away from
## the area if no direction function is set) with a short dizzy reaction.
## Hits are predictable: same strength every time, with a cooldown so one
## touch is one bonk.

signal knocked(player: PlayerCharacter)

var strength: float = 9.0
var lift: float = 5.0
var cooldown: float = 0.7
## Optional: func(player: PlayerCharacter) -> Vector3 giving the push direction.
var push_direction: Callable
var enabled: bool = true

var _cooldowns: Dictionary = {}  # instance id -> seconds left


func _ready() -> void:
	collision_layer = Layers.TRIGGERS
	collision_mask = Layers.PLAYERS
	monitorable = false
	if Gen.in_game():
		body_entered.connect(_try_knock)


func _physics_process(delta: float) -> void:
	if not Gen.in_game():
		return
	for id in _cooldowns.keys():
		_cooldowns[id] = float(_cooldowns[id]) - delta
		if _cooldowns[id] <= 0.0:
			_cooldowns.erase(id)
	# Someone standing still inside the zone gets bonked again once the cooldown ends.
	if enabled and monitoring:
		for body in get_overlapping_bodies():
			_try_knock(body)


func _try_knock(body: Node3D) -> void:
	if not enabled:
		return
	var player := body as PlayerCharacter
	if player == null or player.is_respawning:
		return
	var id := player.get_instance_id()
	if _cooldowns.has(id):
		return
	_cooldowns[id] = cooldown
	var dir := Vector3.ZERO
	if push_direction.is_valid():
		dir = push_direction.call(player)
	if dir.length() < 0.01:
		dir = player.global_position - global_position
	dir.y = 0.0
	if dir.length() < 0.01:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	player.knock(player.global_position - dir, strength, lift)
	knocked.emit(player)
