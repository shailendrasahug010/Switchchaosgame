class_name LocalInputSource
extends PlayerInputSource
## Keyboard, gamepad and (for player 1) touch input on this device.
## Bindings come from the InputSetup autoload.

var slot: int = 1
var use_touch: bool = true

var _left: StringName
var _right: StringName
var _up: StringName
var _down: StringName
var _jump: StringName
var _interact: StringName


func _init(p_slot: int = 1) -> void:
	slot = p_slot
	use_touch = slot == 1
	_left = StringName("p%d_left" % slot)
	_right = StringName("p%d_right" % slot)
	_up = StringName("p%d_up" % slot)
	_down = StringName("p%d_down" % slot)
	_jump = StringName("p%d_jump" % slot)
	_interact = StringName("p%d_interact" % slot)


func update(_delta: float, _player: Node) -> void:
	var mv := Vector2.ZERO
	var held := false
	if InputMap.has_action(_left):
		mv = Input.get_vector(_left, _right, _up, _down)
		held = Input.is_action_pressed(_jump)
		if Input.is_action_just_pressed(_jump):
			press_jump()
		if Input.is_action_just_pressed(_interact):
			press_interact()
	if use_touch:
		if TouchState.stick.length() > mv.length():
			mv = TouchState.stick
		held = held or TouchState.jump_held
		if TouchState.consume_jump():
			press_jump()
		if TouchState.consume_interact():
			press_interact()
	move = mv.limit_length(1.0)
	jump_held = held


func get_kind_label() -> String:
	return "P%d" % slot
