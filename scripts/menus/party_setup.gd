extends Control
## Party setup: pick a game, who is playing (people on this device or CPU
## buddies), which characters, and the rules. Choices are remembered.

const BOT_SKILLS: Array[float] = [0.35, 0.6, 0.85]
const SKILL_NAMES: Array[String] = ["Sleepy buddies", "Normal buddies", "Sharp buddies"]
const PLAYLIST: Array[StringName] = [&"cake_dash", &"button_mayhem", &"bounce_race"]
const MODE_ICONS := {&"cake_dash": &"cake", &"button_mayhem": &"buttons", &"bounce_race": &"bounce", &"party": &"star"}

var _party: Dictionary
var _mode_buttons: Dictionary = {}
var _count_buttons: Array[Button] = []
var _slots_row: HFlowContainer
var _chaos_btn: Button
var _events_btn: Button
var _length_btn: Button
var _skill_btn: Button
var _note: Label
var _start: Button
var _events_overlay: Control


func _ready() -> void:
	AudioManager.play_music(&"menu")
	_party = GameState.party.duplicate(true)
	_party.count = clampi(int(_party.get("count", 4)), 2, 4)
	var kinds: Array = _party.get("kinds", [])
	var chars: Array = _party.get("characters", [])
	while kinds.size() < 4:
		kinds.append("cpu")
	while chars.size() < 4:
		chars.append(String(Catalog.CHARACTERS[chars.size()].id))
	kinds[0] = "human"
	chars[0] = String(GameState.profile.character)
	_party.kinds = kinds
	_party.characters = chars
	_build()
	_refresh_all()


func _build() -> void:
	var bg := MenuBackground.new()
	add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	UiKit.full_rect(scroll)
	var margin := UiKit.margin(28, 18, 28, 18)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)
	var col := UiKit.vbox(10)
	margin.add_child(col)

	var head := UiKit.hbox(16)
	col.add_child(head)
	var back := UiKit.icon_button("", &"back", &"DarkButton", 72)
	back.pressed.connect(_go_back)
	head.add_child(back)
	head.add_child(UiKit.label("Party Setup", &"HeaderLabel"))
	head.add_child(UiKit.spacer(0, false))
	_start = UiKit.icon_button("START!", &"play", &"BigButton", 90)
	_start.custom_minimum_size.x = 300
	_start.pressed.connect(_start_match)
	head.add_child(_start)

	col.add_child(UiKit.label("1. Pick a game", &"SubHeaderLabel"))
	# Flow containers wrap onto a second line on narrow (4:3 tablet) screens.
	var modes := _flow(14)
	col.add_child(modes)
	for m in Catalog.MODES:
		modes.add_child(_mode_card(m.id, m.name, m.blurb, m.color))
	modes.add_child(_mode_card(&"party", "Chaos Party", "Play all three games in a row!", Color("ffb35c")))

	col.add_child(UiKit.label("2. Who's playing?", &"SubHeaderLabel"))
	var count_row := _flow(12)
	col.add_child(count_row)
	var picked := UiKit.style(UiKit.VIOLET, 22, 12, UiKit.SUN, 6, 4)
	for n in [2, 3, 4]:
		var b := UiKit.button("%d players" % n, &"DarkButton", 64)
		b.toggle_mode = true
		b.custom_minimum_size.x = 170
		b.add_theme_stylebox_override("pressed", picked)
		b.add_theme_stylebox_override("hover_pressed", picked)
		b.pressed.connect(func() -> void:
			_party.count = n
			_refresh_all())
		count_row.add_child(b)
		_count_buttons.append(b)
	_note = UiKit.wrap_label("", &"SmallLabel")
	_note.custom_minimum_size.x = 480
	_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_row.add_child(_note)
	_slots_row = _flow(14)
	col.add_child(_slots_row)

	col.add_child(UiKit.label("3. Rules", &"SubHeaderLabel"))
	var rules := _flow(12)
	col.add_child(rules)
	_chaos_btn = UiKit.button("", &"PinkButton", 70)
	_chaos_btn.pressed.connect(func() -> void:
		_party.chaos = not bool(_party.chaos)
		_refresh_rules())
	rules.add_child(_chaos_btn)
	_events_btn = UiKit.button("Pick switches...", &"BlueButton", 70)
	_events_btn.pressed.connect(_open_events)
	rules.add_child(_events_btn)
	_length_btn = UiKit.button("", &"DarkButton", 70)
	_length_btn.pressed.connect(func() -> void:
		_party.quick = not bool(_party.quick)
		_refresh_rules())
	rules.add_child(_length_btn)
	_skill_btn = UiKit.button("", &"DarkButton", 70)
	_skill_btn.pressed.connect(func() -> void:
		_party.skill = (int(_party.skill) + 1) % BOT_SKILLS.size()
		_refresh_rules())
	rules.add_child(_skill_btn)


func _flow(separation: int) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", separation)
	f.add_theme_constant_override("v_separation", separation)
	return f


func _mode_card(id: StringName, title: String, blurb: String, color: Color) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(272, 150)
	b.focus_mode = Control.FOCUS_ALL
	var normal := UiKit.style(color.darkened(0.1), 26, 14, Color(1, 1, 1, 0.6), 0, 3)
	var selected := UiKit.style(color, 26, 14, Color("ffd23f"), 0, 7)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	b.add_theme_stylebox_override("pressed", selected)
	b.add_theme_stylebox_override("hover_pressed", selected)
	b.add_theme_stylebox_override("focus", UiKit.style(Color(0, 0, 0, 0), 26, 0, Color("ffffff"), 0, 3))
	var inner := UiKit.vbox(2)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 14
	inner.offset_right = -14
	inner.offset_top = 10
	inner.offset_bottom = -10
	b.add_child(inner)
	var top := UiKit.hbox(8)
	inner.add_child(top)
	var ic := Icon.new(MODE_ICONS.get(id, &"star"), Color.WHITE, 44)
	ic.shadow = true
	top.add_child(ic)
	var name_label := UiKit.label(title, &"HudLabel")
	name_label.add_theme_font_size_override("font_size", 26)
	top.add_child(name_label)
	var text := UiKit.wrap_label(blurb, &"HudLabel")
	text.add_theme_font_size_override("font_size", 19)
	text.add_theme_constant_override("outline_size", 6)
	text.custom_minimum_size.x = 240
	inner.add_child(text)
	b.pressed.connect(func() -> void:
		_party.mode = String(id)
		_party.playlist = id == &"party"
		_refresh_modes())
	_mode_buttons[id] = b
	return b


func _slot_card(i: int) -> Control:
	var color: Color = Catalog.PLAYER_TAG_COLORS[i]
	var kind := String(_party.kinds[i])
	var human := kind == "human"
	var card := UiKit.color_panel(Color(0.14, 0.12, 0.3, 0.86), 24, 12, color, 6, 4)
	card.custom_minimum_size = Vector2(220, 0)
	var col := UiKit.vbox(4, BoxContainer.ALIGNMENT_CENTER)
	card.add_child(col)
	var tag := "P1 (you)" if i == 0 else ("Player %d" % (i + 1) if human else "CPU buddy")
	var tag_label := UiKit.label(tag, &"HudLabel", HORIZONTAL_ALIGNMENT_CENTER)
	tag_label.add_theme_color_override("font_color", color.lightened(0.35))
	col.add_child(tag_label)
	var row := UiKit.hbox(4, BoxContainer.ALIGNMENT_CENTER)
	col.add_child(row)
	var prev := UiKit.icon_button("", &"back", &"GhostButton", 56)
	prev.custom_minimum_size = Vector2(52, 56)
	prev.pressed.connect(func() -> void: _cycle_character(i, -1))
	row.add_child(prev)
	var cid := StringName(String(_party.characters[i]))
	var portrait := CharacterPortrait.new(cid, 104)
	if i == 0:
		portrait.hat_id = GameState.profile.hat
		portrait.paint_id = GameState.profile.paint
	row.add_child(portrait)
	var next := UiKit.icon_button("", &"next", &"GhostButton", 56)
	next.custom_minimum_size = Vector2(52, 56)
	next.pressed.connect(func() -> void: _cycle_character(i, 1))
	row.add_child(next)
	col.add_child(UiKit.label(Catalog.character(cid).name, &"HudLabel", HORIZONTAL_ALIGNMENT_CENTER))
	if i > 0:
		var toggle := UiKit.icon_button("Person" if human else "CPU", &"person" if human else &"cpu",
				&"BlueButton" if human else &"DarkButton", 56)
		toggle.pressed.connect(func() -> void:
			_party.kinds[i] = "cpu" if human else "human"
			_refresh_all())
		col.add_child(toggle)
	return card


func _cycle_character(i: int, step: int) -> void:
	var idx := Catalog.character_index(StringName(String(_party.characters[i])))
	idx = (idx + step + Catalog.CHARACTERS.size()) % Catalog.CHARACTERS.size()
	_party.characters[i] = String(Catalog.CHARACTERS[idx].id)
	if i == 0:
		GameState.set_profile(Catalog.CHARACTERS[idx].id, GameState.profile.hat, GameState.profile.paint)
	AudioManager.play(&"voice_happy", Catalog.CHARACTERS[idx].voice_pitch, -4.0)
	_refresh_slots()


func _refresh_all() -> void:
	_refresh_modes()
	for b in _count_buttons:
		b.button_pressed = b.text.begins_with(str(_party.count))
	_refresh_slots()
	_refresh_rules()


func _refresh_modes() -> void:
	var current := StringName(String(_party.mode)) if not bool(_party.playlist) else &"party"
	for id in _mode_buttons:
		(_mode_buttons[id] as Button).set_pressed_no_signal(id == current)


func _refresh_slots() -> void:
	for c in _slots_row.get_children():
		c.queue_free()
	for i in int(_party.count):
		_slots_row.add_child(_slot_card(i))
	var humans := 0
	for i in int(_party.count):
		if String(_party.kinds[i]) == "human":
			humans += 1
	var notes: PackedStringArray = []
	if humans >= 2:
		notes.append("P1: WASD + Space + E.  P2: arrow keys + Enter + /.  P3 and P4 need gamepads.")
	else:
		notes.append("CPU buddies are friendly helpers. Switch a slot to \"Person\" to play with a friend on a keyboard or gamepad.")
	if humans >= 2 and GameState.wants_touch_controls():
		notes.append("On a phone only P1 uses the touch controls.")
	_note.text = " ".join(notes)


func _refresh_rules() -> void:
	_chaos_btn.text = "Chaos switches: ON" if bool(_party.chaos) else "Chaos switches: OFF"
	_events_btn.disabled = not bool(_party.chaos)
	var n := (_party.events as Array).size()
	_events_btn.text = "Switches: all" if n == 0 else "Switches: %d" % n
	_length_btn.text = "Round: quick" if bool(_party.quick) else "Round: normal"
	_skill_btn.text = SKILL_NAMES[clampi(int(_party.skill), 0, 2)]


# ---------------------------------------------------------------- events popup

func _open_events() -> void:
	if _events_overlay:
		_events_overlay.queue_free()
	_events_overlay = Control.new()
	add_child(_events_overlay)
	UiKit.full_rect(_events_overlay)
	_events_overlay.add_child(UiKit.dimmer(0.6))
	var center := CenterContainer.new()
	_events_overlay.add_child(center)
	UiKit.full_rect(center)
	var card := UiKit.panel()
	center.add_child(card)
	var col := UiKit.vbox(12)
	card.add_child(col)
	col.add_child(UiKit.label("Which rule switches can happen?", &"SubHeaderLabel", HORIZONTAL_ALIGNMENT_CENTER))
	var grid := GridContainer.new()
	grid.columns = 4
	col.add_child(grid)
	var library := Catalog.load_chaos_library()
	var selected: Array = (_party.events as Array).duplicate()
	if selected.is_empty():
		for ev in library:
			selected.append(String(ev.id))
	var buttons: Dictionary = {}
	for ev in library:
		var b := UiKit.icon_button(ev.display_name.replace(" Mode", ""), ev.icon, &"DarkButton", 70)
		b.toggle_mode = true
		b.custom_minimum_size.x = 230
		b.add_theme_stylebox_override("pressed", UiKit.style(ev.color, 22, 12, Color.WHITE, 6, 3))
		b.add_theme_stylebox_override("hover_pressed", UiKit.style(ev.color, 22, 12, Color.WHITE, 6, 3))
		b.button_pressed = selected.has(String(ev.id))
		grid.add_child(b)
		buttons[String(ev.id)] = b
	var row := UiKit.hbox(12, BoxContainer.ALIGNMENT_CENTER)
	col.add_child(row)
	var all := UiKit.button("All on", &"BlueButton", 70)
	all.pressed.connect(func() -> void:
		for id in buttons:
			(buttons[id] as Button).button_pressed = true)
	row.add_child(all)
	var done := UiKit.button("Done", &"GreenButton", 70)
	done.pressed.connect(func() -> void:
		var chosen: Array = []
		for id in buttons:
			if (buttons[id] as Button).button_pressed:
				chosen.append(id)
		if chosen.is_empty() or chosen.size() == buttons.size():
			chosen = []
		_party.events = chosen
		_refresh_rules()
		_events_overlay.queue_free()
		_events_overlay = null)
	row.add_child(done)
	UiKit.pop_in(card)


# ---------------------------------------------------------------- start

func build_setup() -> MatchSetup:
	var setup := MatchSetup.new()
	if bool(_party.playlist):
		setup.playlist = PLAYLIST.duplicate()
		setup.playlist_index = 0
		setup.mode_id = PLAYLIST[0]
	else:
		setup.mode_id = StringName(String(_party.mode))
	var local_index := 0
	for i in int(_party.count):
		var s := MatchSetup.Slot.new()
		var human := String(_party.kinds[i]) == "human" or i == 0
		s.kind = MatchSetup.Kind.HUMAN if human else MatchSetup.Kind.CPU
		if human:
			local_index += 1
			s.local_index = local_index
		s.character_id = StringName(String(_party.characters[i]))
		if i == 0:
			s.hat_id = GameState.profile.hat
			s.paint_id = GameState.profile.paint
		s.bot_skill = BOT_SKILLS[clampi(int(_party.skill), 0, 2)]
		setup.slots.append(s)
	setup.chaos_enabled = bool(_party.chaos)
	for id in (_party.events as Array):
		setup.enabled_events.append(StringName(String(id)))
	setup.round_time = 60.0 if bool(_party.quick) else 0.0
	return setup


func _start_match() -> void:
	GameState.party = _party.duplicate(true)
	GameState.save_game()
	Router.start_match(build_setup())


func _go_back() -> void:
	GameState.party = _party.duplicate(true)
	GameState.save_game()
	Router.go(&"menu")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and _events_overlay == null:
		_go_back()
