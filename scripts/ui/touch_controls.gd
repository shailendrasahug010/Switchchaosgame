class_name TouchControls
extends Control
## On-screen controls for phones and tablets: a floating joystick on the left
## half, a big JUMP button and a contextual ACTION button on the right.
##
## Multi-touch: every control follows its own finger. Writes into TouchState,
## which player 1's LocalInputSource reads, so gameplay never depends on this
## node. Options (Settings): simple controls (one action button), bigger
## buttons, left-handed layout.

const ZONE_TOP := 110.0

var match_ctl: MatchController
var simple := false
var left_handed := false
var button_scale := 1.0

var _stick_touch := -1
var _stick_base := Vector2.ZERO
var _stick_knob := Vector2.ZERO
var _stick_radius := 105.0
var _jump_touch := -1
var _action_touch := -1
var _jump_center := Vector2.ZERO
var _jump_radius := 92.0
var _action_center := Vector2.ZERO
var _action_radius := 74.0
var _prompt := ""
var _prompt_icon: StringName = &"hand"
var _font: Font
var _player: PlayerCharacter


func setup(p_match: MatchController) -> void:
	match_ctl = p_match
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = load("res://assets/fonts/fredoka_bold.tres")
	for p in match_ctl.players:
		var local := p.input as LocalInputSource
		if p.is_human and local and local.use_touch:
			_player = p
			break
	_apply_settings()
	GameState.settings_changed.connect(_apply_settings)
	resized.connect(_layout)
	_layout()


func _apply_settings() -> void:
	simple = bool(GameState.get_setting("simple_controls", false))
	left_handed = bool(GameState.get_setting("left_handed", false))
	button_scale = float(GameState.get_setting("button_scale", 1.0))
	visible = GameState.wants_touch_controls() and _player != null
	_release_all()
	_layout()


func _layout() -> void:
	var s := button_scale
	_jump_radius = (108.0 if simple else 92.0) * s
	_action_radius = 74.0 * s
	_stick_radius = 105.0 * s
	_jump_center = Vector2(size.x - 150.0 * s, size.y - 140.0 * s)
	_action_center = _jump_center + Vector2(-178.0 * s, -88.0 * s)
	if left_handed:
		_jump_center.x = size.x - _jump_center.x
		_action_center.x = size.x - _action_center.x
	if _stick_touch == -1:
		_stick_base = _rest_position()
		_stick_knob = _stick_base
	queue_redraw()


func _rest_position() -> Vector2:
	var p := Vector2(185.0 * button_scale, size.y - 175.0 * button_scale)
	if left_handed:
		p.x = size.x - p.x
	return p


func _in_stick_zone(pos: Vector2) -> bool:
	if pos.y < ZONE_TOP:
		return false
	return pos.x > size.x * 0.55 if left_handed else pos.x < size.x * 0.45


func _input(event: InputEvent) -> void:
	if not visible or match_ctl == null:
		return
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed:
			if _handle_press(e.index, e.position):
				get_viewport().set_input_as_handled()
		else:
			if _handle_release(e.index):
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _stick_touch:
			_move_stick(d.position)
			get_viewport().set_input_as_handled()


func _handle_press(index: int, pos: Vector2) -> bool:
	if _jump_touch == -1 and pos.distance_to(_jump_center) <= _jump_radius * 1.2:
		_jump_touch = index
		if simple and _prompt != "":
			TouchState.press_interact()
		else:
			TouchState.press_jump()
			TouchState.jump_held = true
		queue_redraw()
		return true
	if not simple and _action_touch == -1 and pos.distance_to(_action_center) <= _action_radius * 1.2:
		_action_touch = index
		TouchState.press_interact()
		queue_redraw()
		return true
	if _stick_touch == -1 and _in_stick_zone(pos):
		_stick_touch = index
		_stick_base = Vector2(clampf(pos.x, _stick_radius, size.x - _stick_radius),
				clampf(pos.y, ZONE_TOP + _stick_radius * 0.5, size.y - _stick_radius * 0.6))
		_move_stick(pos)
		return true
	return false


func _handle_release(index: int) -> bool:
	var used := false
	if index == _jump_touch:
		_jump_touch = -1
		TouchState.jump_held = false
		used = true
	if index == _action_touch:
		_action_touch = -1
		used = true
	if index == _stick_touch:
		_stick_touch = -1
		TouchState.stick = Vector2.ZERO
		_stick_base = _rest_position()
		_stick_knob = _stick_base
		used = true
	if used:
		queue_redraw()
	return used


func _move_stick(pos: Vector2) -> void:
	var offset := pos - _stick_base
	# Drag far beyond the ring and the ring follows the finger.
	if offset.length() > _stick_radius * 1.4:
		_stick_base = pos - offset.normalized() * _stick_radius * 1.4
		offset = pos - _stick_base
	var v := offset / _stick_radius
	if v.length() > 1.0:
		v = v.normalized()
	if v.length() < 0.12:
		v = Vector2.ZERO
	TouchState.stick = v
	_stick_knob = _stick_base + v * _stick_radius
	queue_redraw()


func _release_all() -> void:
	_stick_touch = -1
	_jump_touch = -1
	_action_touch = -1
	TouchState.reset()
	if size.x > 0.0:
		_stick_base = _rest_position()
		_stick_knob = _stick_base


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release_all()


func _process(_delta: float) -> void:
	if not visible or _player == null:
		return
	var prompt := ""
	var icon: StringName = &"hand"
	if match_ctl.is_playing():
		prompt = match_ctl.mode.get_interact_prompt(_player)
		icon = match_ctl.mode.get_interact_icon(_player)
	if prompt != _prompt or icon != _prompt_icon:
		_prompt = prompt
		_prompt_icon = icon
		queue_redraw()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if match_ctl == null:
		return
	var active := _stick_touch != -1
	# Joystick.
	draw_circle(_stick_base, _stick_radius, Color(0.14, 0.12, 0.3, 0.28 if active else 0.18))
	draw_arc(_stick_base, _stick_radius, 0.0, TAU, 48, Color(1, 1, 1, 0.75 if active else 0.4), 5.0, true)
	draw_circle(_stick_knob, _stick_radius * 0.46, Color(1, 1, 1, 0.9 if active else 0.55))
	draw_circle(_stick_knob, _stick_radius * 0.3, Color("7b5cff") if active else Color(0.48, 0.36, 1.0, 0.6))
	# Jump (or the single action button in simple mode).
	var jump_pressed := _jump_touch != -1
	var simple_action := simple and _prompt != ""
	var jump_color := Color("2f9dff") if simple_action else Color("ff5fa8")
	_draw_round_button(_jump_center, _jump_radius, jump_color, jump_pressed,
			_prompt_icon if simple_action else &"up", _prompt if simple_action else "JUMP")
	if not simple:
		var has := _prompt != ""
		var col := Color("2f9dff") if has else Color(0.4, 0.42, 0.55)
		_draw_round_button(_action_center, _action_radius, col, _action_touch != -1, _prompt_icon,
				_prompt if has else "", 1.0 if has else 0.45)


func _draw_round_button(center: Vector2, radius: float, color: Color, pressed: bool, icon: StringName,
		text: String, alpha: float = 1.0) -> void:
	var r := radius * (0.94 if pressed else 1.0)
	var lip := 0.0 if pressed else radius * 0.09
	draw_circle(center + Vector2(0, lip), r, Color(color.darkened(0.35), 0.85 * alpha))
	draw_circle(center, r, Color(color, 0.9 * alpha))
	draw_arc(center, r, 0.0, TAU, 48, Color(1, 1, 1, 0.55 * alpha), 4.0, true)
	var icon_size := r * (0.8 if text == "" else 0.62)
	var icon_center := center + (Vector2(0, -r * 0.16) if text != "" else Vector2.ZERO)
	IconDraw.draw(self, icon, icon_center - Vector2(icon_size, icon_size) * 0.5, icon_size, Color(1, 1, 1, alpha))
	if text != "" and _font:
		var fs := int(clampf(r * 0.3, 16.0, 34.0))
		var width := r * 1.8
		var pos := Vector2(center.x - width * 0.5, center.y + r * 0.52)
		draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, fs, 8, Color(0.1, 0.07, 0.22, 0.8 * alpha))
		draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, fs, Color(1, 1, 1, alpha))


## For automated tests: current on-screen button centers.
func get_layout_points() -> Dictionary:
	return {"jump": _jump_center, "action": _action_center, "stick_rest": _rest_position(), "stick_radius": _stick_radius}
