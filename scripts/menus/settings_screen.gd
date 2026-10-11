extends Control
## Settings: sound, touch controls, comfort and graphics options.
## Every change is saved right away (GameState.set_setting).

var _rows: Dictionary = {}   # key -> Button (toggles) for refreshing labels
var _confirm: Control


func _ready() -> void:
	AudioManager.play_music(&"menu")
	add_child(MenuBackground.new())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	UiKit.full_rect(scroll)
	var margin := UiKit.margin(28, 18, 28, 24)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)
	var col := UiKit.vbox(12)
	margin.add_child(col)

	var head := UiKit.hbox(16)
	col.add_child(head)
	var back := UiKit.icon_button("", &"back", &"DarkButton", 72)
	back.pressed.connect(_back)
	head.add_child(back)
	head.add_child(Icon.new(&"gear", Color.WHITE, 52))
	head.add_child(UiKit.label("Settings", &"HeaderLabel"))

	_section(col, "Sound", &"sound")
	_toggle(col, "muted", "Sound", "Turn all sound off or on.", true)
	_slider(col, "sfx_volume", "Sound effects volume")
	_slider(col, "music_volume", "Music volume")

	_section(col, "Controls", &"hand")
	_cycle(col, "touch_controls", "Touch buttons", "Auto shows them on phones and tablets.",
			["auto", "on", "off"], ["Auto", "On", "Off"])
	_toggle(col, "simple_controls", "Simple controls", "One big button that jumps, or grabs when you're next to something.")
	_cycle(col, "button_scale", "Button size", "Bigger buttons are easier to hit.", [1.0, 1.25], ["Normal", "Big"])
	_toggle(col, "left_handed", "Left-handed", "Puts the jump buttons on the left and the stick on the right.")

	_section(col, "Comfort and graphics", &"info")
	_toggle(col, "reduced_motion", "Calm camera", "No camera shaking and softer flashes.")
	_toggle(col, "shadows", "Shadows", "Turn off if the game feels slow on an older phone.")
	_toggle(col, "show_tips", "Tips", "Little hints when the rules switch.")

	_section(col, "For grown-ups", &"lock")
	_toggle(col, "debug_tools", "Debug tools", "Testing panel in a round: trigger any rule switch on demand (F1 key or bug button).")
	var reset := UiKit.icon_button("Reset progress...", &"restart", &"PinkButton", 70)
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.pressed.connect(_ask_reset)
	col.add_child(reset)
	_refresh()


func _section(parent: Control, title: String, icon: StringName) -> void:
	parent.add_child(UiKit.spacer(6))
	var row := UiKit.hbox(10)
	row.add_child(Icon.new(icon, Color("ffd23f"), 36))
	row.add_child(UiKit.label(title, &"SubHeaderLabel"))
	parent.add_child(row)


func _row(parent: Control, title: String, help: String) -> HBoxContainer:
	var panel := UiKit.color_panel(Color(0.14, 0.12, 0.3, 0.7), 22, 12)
	parent.add_child(panel)
	var row := UiKit.hbox(16)
	panel.add_child(row)
	var text := UiKit.vbox(0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	text.add_child(UiKit.label(title, &"HudLabel"))
	if help != "":
		var h := UiKit.wrap_label(help, &"SmallLabel")
		h.custom_minimum_size.x = 600
		text.add_child(h)
	return row


func _toggle(parent: Control, key: String, title: String, help: String, inverted: bool = false) -> void:
	var row := _row(parent, title, help)
	var b := UiKit.button("", &"GreenButton", 64)
	b.custom_minimum_size.x = 150
	b.set_meta(&"inverted", inverted)
	b.pressed.connect(func() -> void:
		GameState.set_setting(key, not bool(GameState.get_setting(key, false)))
		_refresh())
	row.add_child(b)
	_rows[key] = b


func _cycle(parent: Control, key: String, title: String, help: String, values: Array, names: Array) -> void:
	var row := _row(parent, title, help)
	var b := UiKit.button("", &"BlueButton", 64)
	b.custom_minimum_size.x = 150
	b.set_meta(&"values", values)
	b.set_meta(&"names", names)
	b.pressed.connect(func() -> void:
		var idx := _index_of(values, GameState.get_setting(key, values[0]))
		GameState.set_setting(key, values[(idx + 1) % values.size()])
		_refresh())
	row.add_child(b)
	_rows[key] = b


func _slider(parent: Control, key: String, title: String) -> void:
	var row := _row(parent, title, "")
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.custom_minimum_size = Vector2(320, 48)
	s.value = float(GameState.get_setting(key, 0.8))
	s.value_changed.connect(func(v: float) -> void:
		GameState.set_setting(key, v)
		AudioManager.play(&"ui_click"))
	row.add_child(s)


## Index of [param value] in [param values] (numbers compared loosely, since
## saved JSON numbers come back as floats). 0 when not found.
func _index_of(values: Array, value: Variant) -> int:
	for i in values.size():
		var v: Variant = values[i]
		if (v is float or v is int) and (value is float or value is int):
			if is_equal_approx(float(v), float(value)):
				return i
		elif v == value:
			return i
	return 0


func _refresh() -> void:
	for key: String in _rows:
		var b: Button = _rows[key]
		var value: Variant = GameState.get_setting(key, false)
		if b.has_meta(&"values"):
			var values: Array = b.get_meta(&"values")
			var names: Array = b.get_meta(&"names")
			var idx := _index_of(values, value)
			b.text = String(names[idx])
		else:
			var on := bool(value)
			if b.get_meta(&"inverted", false):
				on = not on
			b.text = "ON" if on else "OFF"
			b.theme_type_variation = &"GreenButton" if on else &"DarkButton"


func _ask_reset() -> void:
	_confirm = Control.new()
	add_child(_confirm)
	UiKit.full_rect(_confirm)
	_confirm.add_child(UiKit.dimmer(0.65))
	var center := CenterContainer.new()
	_confirm.add_child(center)
	UiKit.full_rect(center)
	var card := UiKit.panel(&"CardPanel")
	center.add_child(card)
	var col := UiKit.vbox(14)
	col.custom_minimum_size.x = 560
	card.add_child(col)
	col.add_child(UiKit.label("Start over?", &"DarkHeaderLabel", HORIZONTAL_ALIGNMENT_CENTER))
	var text := UiKit.wrap_label("This clears your stars, rounds played and earned hats and colors on this device. Settings stay the same.",
			&"DarkLabel", HORIZONTAL_ALIGNMENT_CENTER)
	text.custom_minimum_size.x = 540
	col.add_child(text)
	var row := UiKit.hbox(12, BoxContainer.ALIGNMENT_CENTER)
	col.add_child(row)
	var keep := UiKit.button("Keep my progress", &"GreenButton", 70)
	keep.pressed.connect(func() -> void: _confirm.queue_free())
	row.add_child(keep)
	var wipe := UiKit.button("Reset", &"PinkButton", 70)
	wipe.pressed.connect(func() -> void:
		GameState.reset_progress()
		_confirm.queue_free())
	row.add_child(wipe)
	UiKit.focus_later(keep)


func _back() -> void:
	Router.go(Router.back_target)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		if is_instance_valid(_confirm):
			_confirm.queue_free()
		else:
			_back()
