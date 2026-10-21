class_name TouchState
extends RefCounted
## Shared state written by the on-screen touch controls and read by player 1's
## LocalInputSource. Kept separate from the UI so gameplay never depends on it.

static var stick: Vector2 = Vector2.ZERO
static var jump_held: bool = false
static var _jump_pressed: bool = false
static var _interact_pressed: bool = false


static func press_jump() -> void:
	_jump_pressed = true


static func press_interact() -> void:
	_interact_pressed = true


static func consume_jump() -> bool:
	var p := _jump_pressed
	_jump_pressed = false
	return p


static func consume_interact() -> bool:
	var p := _interact_pressed
	_interact_pressed = false
	return p


static func reset() -> void:
	stick = Vector2.ZERO
	jump_held = false
	_jump_pressed = false
	_interact_pressed = false
