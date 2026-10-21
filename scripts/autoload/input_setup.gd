extends Node
## Builds every gameplay input action at runtime, so all bindings live in this
## one readable file. Change keys here.
##
## One local player : WASD or arrow keys, Space to jump, E / Shift to interact,
##                    any gamepad, plus the touch controls.
## Two+ local players: P1 = WASD + Space + E   (+ gamepad 0)
##                     P2 = arrows + Enter + / (+ gamepad 1)
##                     P3 = gamepad 2, P4 = gamepad 3
## Touch controls always drive P1.

const MAX_LOCAL_PLAYERS := 4
const AXIS_DEADZONE := 0.25
const SUFFIXES: Array[String] = ["left", "right", "up", "down", "jump", "interact"]

const KEYSET_WASD := {
	"left": [KEY_A], "right": [KEY_D], "up": [KEY_W], "down": [KEY_S],
	"jump": [KEY_SPACE], "interact": [KEY_E, KEY_SHIFT],
}
const KEYSET_ARROWS := {
	"left": [KEY_LEFT], "right": [KEY_RIGHT], "up": [KEY_UP], "down": [KEY_DOWN],
	"jump": [KEY_ENTER, KEY_KP_0], "interact": [KEY_SLASH, KEY_KP_PERIOD],
}
## When only one person plays, they also get these extras.
const KEYSET_SOLO_EXTRA := {
	"jump": [KEY_K], "interact": [KEY_J, KEY_F],
}

var local_player_count: int = 1


func _ready() -> void:
	_build_global_actions()
	configure_local_players(1)


## Rebinds the per-player actions for [param count] people on this device.
func configure_local_players(count: int) -> void:
	local_player_count = clampi(count, 1, MAX_LOCAL_PLAYERS)
	for slot in range(1, MAX_LOCAL_PLAYERS + 1):
		for suffix in SUFFIXES:
			var action := action_name(slot, suffix)
			if InputMap.has_action(action):
				InputMap.erase_action(action)
			InputMap.add_action(action, AXIS_DEADZONE)
	if local_player_count == 1:
		_bind_keys(1, KEYSET_WASD)
		_bind_keys(1, KEYSET_ARROWS)
		_bind_keys(1, KEYSET_SOLO_EXTRA)
		_bind_gamepad(1, -1)  # -1 = any connected gamepad
	else:
		_bind_keys(1, KEYSET_WASD)
		_bind_gamepad(1, 0)
		_bind_keys(2, KEYSET_ARROWS)
		_bind_gamepad(2, 1)
		_bind_gamepad(3, 2)
		_bind_gamepad(4, 3)


static func action_name(slot: int, suffix: String) -> StringName:
	return StringName("p%d_%s" % [slot, suffix])


func _bind_keys(slot: int, keyset: Dictionary) -> void:
	for suffix in keyset:
		for keycode in keyset[suffix]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action_name(slot, suffix), ev)


func _bind_gamepad(slot: int, device: int) -> void:
	_add_axis(slot, "left", device, JOY_AXIS_LEFT_X, -1.0)
	_add_axis(slot, "right", device, JOY_AXIS_LEFT_X, 1.0)
	_add_axis(slot, "up", device, JOY_AXIS_LEFT_Y, -1.0)
	_add_axis(slot, "down", device, JOY_AXIS_LEFT_Y, 1.0)
	_add_button(slot, "left", device, JOY_BUTTON_DPAD_LEFT)
	_add_button(slot, "right", device, JOY_BUTTON_DPAD_RIGHT)
	_add_button(slot, "up", device, JOY_BUTTON_DPAD_UP)
	_add_button(slot, "down", device, JOY_BUTTON_DPAD_DOWN)
	_add_button(slot, "jump", device, JOY_BUTTON_A)
	_add_button(slot, "interact", device, JOY_BUTTON_X)
	_add_button(slot, "interact", device, JOY_BUTTON_B)


func _add_axis(slot: int, suffix: String, device: int, axis: JoyAxis, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.device = device
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action_name(slot, suffix), ev)


func _add_button(slot: int, suffix: String, device: int, button: JoyButton) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = device
	ev.button_index = button
	InputMap.action_add_event(action_name(slot, suffix), ev)


func _build_global_actions() -> void:
	_ensure_action(&"pause", [KEY_ESCAPE, KEY_P], [JOY_BUTTON_START])
	_ensure_action(&"debug_panel", [KEY_F1, KEY_QUOTELEFT], [])
	for i in range(1, 10):
		_ensure_action(StringName("debug_event_%d" % i), [KEY_0 + i], [])
	_ensure_action(&"debug_clear_events", [KEY_0], [])


func _ensure_action(action: StringName, keys: Array, buttons: Array) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
	for b in buttons:
		var jb := InputEventJoypadButton.new()
		jb.device = -1
		jb.button_index = b
		InputMap.action_add_event(action, jb)
