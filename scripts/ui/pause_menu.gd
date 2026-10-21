class_name PauseMenu
extends Control
## Pause overlay. Works while the game tree is paused.

var match_ctl: MatchController
var _resume: Button
var _sound: Button
var _card: Control


func setup(p_match: MatchController) -> void:
	match_ctl = p_match
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.dimmer(0.6))
	var center := CenterContainer.new()
	add_child(center)
	UiKit.full_rect(center)
	_card = UiKit.panel()
	center.add_child(_card)
	var col := UiKit.vbox(16)
	col.custom_minimum_size.x = 520
	_card.add_child(col)
	var online := match_ctl.is_online()
	# Online the round goes on for everyone else while this card is open.
	col.add_child(UiKit.label("Taking a break" if online else "Paused", &"HeaderLabel", HORIZONTAL_ALIGNMENT_CENTER))
	if online:
		var note := UiKit.wrap_label("The round keeps going for your friends. Your creature waits for you.",
				&"BodyLabel", HORIZONTAL_ALIGNMENT_CENTER)
		note.custom_minimum_size.x = 500
		col.add_child(note)
	var mode := match_ctl.mode
	var mission := UiKit.wrap_label("%s: %s" % [mode.mission_title, mode.mission_text], &"BodyLabel",
			HORIZONTAL_ALIGNMENT_CENTER)
	mission.custom_minimum_size.x = 500
	col.add_child(mission)
	_resume = UiKit.icon_button("Keep playing", &"play", &"GreenButton", 88)
	_resume.pressed.connect(func() -> void: match_ctl.set_paused(false))
	col.add_child(_resume)
	if not online:
		var restart := UiKit.icon_button("Start over", &"restart", &"BlueButton", 80)
		restart.pressed.connect(func() -> void:
			match_ctl.set_paused(false)
			match_ctl.restart_round())
		col.add_child(restart)
	_sound = UiKit.icon_button("", &"sound", &"YellowButton", 80, Color("1c1a33"))
	_sound.pressed.connect(func() -> void:
		GameState.set_setting("muted", not bool(GameState.get_setting("muted", false)))
		_refresh_sound())
	col.add_child(_sound)
	var quit := UiKit.icon_button("Leave the room" if online else "Back to menu", &"back", &"PinkButton", 80)
	quit.pressed.connect(func() -> void: match_ctl.quit_to_menu())
	col.add_child(quit)
	_refresh_sound()


func _refresh_sound() -> void:
	var muted := bool(GameState.get_setting("muted", false))
	UiKit.set_icon_button_text(_sound, "Sound: OFF" if muted else "Sound: ON")


func open() -> void:
	_refresh_sound()
	UiKit.pop_in(_card, 0.0, 0.8)
	UiKit.focus_later(_resume)


## While paused the match itself gets no input, so the same keys that paused
## (Esc / P / gamepad Start) and "back" resume from here.
func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause")):
		match_ctl.set_paused(false)
		get_viewport().set_input_as_handled()
