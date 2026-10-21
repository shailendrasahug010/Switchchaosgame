@tool
class_name Interactable
extends Node3D
## Something a player can use with the Interact button (a lever, a bell...).
## The game mode finds the nearest usable one and shows [method get_prompt]
## on the contextual button.

signal interacted(player: PlayerCharacter)

@export var prompt: String = "USE"
@export var prompt_icon: StringName = &"hand"
@export_range(0.5, 6.0, 0.1) var interact_radius: float = 2.0
@export_range(0.0, 30.0, 0.1) var cooldown: float = 0.5

var _cooldown_left := 0.0


func _ready() -> void:
	add_to_group(&"interactable")


func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(0.0, _cooldown_left - delta)


func can_interact(_player: PlayerCharacter) -> bool:
	return _cooldown_left <= 0.0


func get_prompt(_player: PlayerCharacter) -> String:
	return prompt


func get_interact_position() -> Vector3:
	return global_position


func cooldown_fraction() -> float:
	return 0.0 if cooldown <= 0.0 else clampf(_cooldown_left / cooldown, 0.0, 1.0)


func interact(player: PlayerCharacter) -> bool:
	if not can_interact(player):
		return false
	_cooldown_left = cooldown
	_on_interact(player)
	interacted.emit(player)
	return true


## Override for the actual effect.
func _on_interact(_player: PlayerCharacter) -> void:
	pass
