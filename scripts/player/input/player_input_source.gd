class_name PlayerInputSource
extends RefCounted
## Where a player's intentions come from.
##
## PlayerCharacter never reads a device directly. It asks its input source for
## a move vector and button presses, so the exact same movement code runs for
## keyboard, touch, gamepads, CPU bots, automated tests and — later — remote
## players whose inputs arrive over the network.

## Stick direction. x = right, y = down (pushing "up"/forward gives y = -1).
var move: Vector2 = Vector2.ZERO
var jump_held: bool = false
var _jump_pressed: bool = false
var _interact_pressed: bool = false


## Called once per physics tick by the player before it moves.
func update(_delta: float, _player: Node) -> void:
	pass


func press_jump() -> void:
	_jump_pressed = true


func press_interact() -> void:
	_interact_pressed = true


## Returns true once per press.
func consume_jump() -> bool:
	var pressed := _jump_pressed
	_jump_pressed = false
	return pressed


func consume_interact() -> bool:
	var pressed := _interact_pressed
	_interact_pressed = false
	return pressed


func reset() -> void:
	move = Vector2.ZERO
	jump_held = false
	_jump_pressed = false
	_interact_pressed = false


## Short label for UI ("P1", "CPU", ...).
func get_kind_label() -> String:
	return ""
