extends Control
## Online play (beta): make a private room or join one with a code, then wait
## for friends on the room screen. The host picks the game and starts.
##
## Online is off until a grown-up switches it on (Grown-ups page). There is
## no chat and nobody types a name: players show up as P1-P4 with their
## creature. See docs/ONLINE_MULTIPLAYER_PLAN.md.

const MODE_ICONS := {&"cake_dash": &"cake", &"button_mayhem": &"buttons", &"bounce_race": &"bounce"}

var _body: VBoxContainer
var _code_typed := ""
var _code_boxes: Array[Label] = []
var _join_btn: Button
var _view := ""
var _toast: PanelContainer
var _toast_label: Label


func _ready() -> void:
	AudioManager.play_music(&"menu")
	var bg := MenuBackground.new()
	bg.top_color = Color("1f6f5c")
	bg.bottom_color = Color("2fc97a")
	add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	UiKit.full_rect(scroll)
	var margin := UiKit.margin(28, 18, 28, 18)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)
	var col := UiKit.vbox(12)
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(col)
	var head := UiKit.hbox(16)
	col.add_child(head)
	var back := UiKit.icon_button("", &"back", &"DarkButton", 72)
	back.pressed.connect(_back)
	head.add_child(back)
	head.add_child(Icon.new(&"globe", Color("fff3a3"), 52))
	head.add_child(UiKit.label("Play online", &"HeaderLabel"))
	var beta := UiKit.color_panel(Color("ffd23f"), 14, 8)
	beta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	beta.add_child(UiKit.label("BETA", &"DarkSmallLabel"))
	head.add_child(beta)
	_body = UiKit.vbox(14)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_body)
	_build_toast()
	Net.status_changed.connect(func(_s: int) -> void: _refresh())
	Net.room_changed.connect(func(_info: Dictionary) -> void:
		if _view == "room":
			_show_room()
		else:
			_refresh())
	Net.error_raised.connect(_show_error)
	_refresh()


func _refresh() -> void:
	if not bool(GameState.get_setting("online_allowed", false)):
		_show_locked()
		return
	match Net.status:
		Net.Status.CONNECTING, Net.Status.CONNECTED:
			_show_busy("Connecting to the game server...")
		Net.Status.RECONNECTING:
			_show_busy("Connection lost. Reconnecting...")
		Net.Status.IN_ROOM:
			_show_room()
		_:
			if _view != "code":
				_show_start()


func _clear() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()


# ---------------------------------------------------------------- views

func _show_locked() -> void:
	_view = "locked"
	_clear()
	var card := _card()
	var col := UiKit.vbox(12, BoxContainer.ALIGNMENT_CENTER)
	card.add_child(col)
	var row := UiKit.hbox(14, BoxContainer.ALIGNMENT_CENTER)
	row.add_child(Icon.new(&"lock", UiKit.INK, 56))
	row.add_child(UiKit.label("Online play is switched off", &"DarkHeaderLabel"))
	col.add_child(row)
	var text := UiKit.wrap_label("A grown-up can switch it on in the Grown-ups page. Online play uses private rooms with a secret code, and there is no chat.",
			&"DarkLabel", HORIZONTAL_ALIGNMENT_CENTER)
	text.custom_minimum_size.x = 640
	col.add_child(text)
	var go := UiKit.icon_button("Grown-ups page", &"info", &"BlueButton", 76)
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go.pressed.connect(func() -> void: Router.go(&"parents"))
	col.add_child(go)
	UiKit.focus_later(go)


func _show_start() -> void:
	_view = "start"
	_clear()
	var intro := UiKit.wrap_label("Play with friends in a private room. One player makes a room and gets a code; friends type the code to join. No chat and no names: everyone is P1 to P4 with their creature.",
			&"BodyLabel")
	intro.custom_minimum_size.x = 900
	_body.add_child(intro)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 18)
	row.add_theme_constant_override("v_separation", 18)
	_body.add_child(row)
	var make := _big_choice("Make a room", "You'll get a code to share", &"plus", &"GreenButton")
	make.name = "MakeRoom"
	make.pressed.connect(func() -> void: Net.create_room())
	row.add_child(make)
	var join := _big_choice("Join with a code", "Type the code from your friend", &"next", &"BlueButton")
	join.name = "JoinWithCode"
	join.pressed.connect(_show_code_entry)
	row.add_child(join)
	_body.add_child(_look_chip())
	_body.add_child(UiKit.spacer())
	_body.add_child(_server_chip())
	UiKit.pop_in(make)
	UiKit.pop_in(join, 0.08)
	UiKit.focus_later(make)


func _show_code_entry() -> void:
	_view = "code"
	_clear()
	_code_typed = ""
	_body.add_child(UiKit.label("Type the room code", &"SubHeaderLabel"))
	var boxes := UiKit.hbox(10)
	_body.add_child(boxes)
	_code_boxes.clear()
	for i in NetProtocol.CODE_LENGTH:
		var p := UiKit.color_panel(UiKit.CREAM, 18, 10, UiKit.SUN, 4, 0)
		p.custom_minimum_size = Vector2(84, 96)
		var l := UiKit.label("", &"DarkHeaderLabel", HORIZONTAL_ALIGNMENT_CENTER)
		l.add_theme_font_size_override("font_size", 56)
		p.add_child(l)
		boxes.add_child(p)
		_code_boxes.append(l)
	var keys := GridContainer.new()
	keys.columns = 9
	keys.add_theme_constant_override("h_separation", 8)
	keys.add_theme_constant_override("v_separation", 8)
	_body.add_child(keys)
	for ch in NetProtocol.CODE_ALPHABET:
		var k := UiKit.button(ch, &"DarkButton", 66)
		k.name = "Key_" + ch
		k.custom_minimum_size.x = 76
		k.pressed.connect(func() -> void: _type(ch))
		keys.add_child(k)
	var row := UiKit.hbox(12)
	_body.add_child(row)
	var del := UiKit.icon_button("", &"backspace", &"PinkButton", 72)
	del.name = "DeleteKey"
	del.tooltip_text = "Delete"
	del.pressed.connect(_delete)
	row.add_child(del)
	_join_btn = UiKit.icon_button("Join!", &"play", &"GreenButton", 72)
	_join_btn.name = "JoinButton"
	_join_btn.custom_minimum_size.x = 220
	_join_btn.pressed.connect(_join)
	row.add_child(_join_btn)
	var cancel := UiKit.button("Cancel", &"DarkButton", 72)
	cancel.pressed.connect(_show_start)
	row.add_child(cancel)
	_update_code_boxes()
	UiKit.focus_later(keys.get_child(0) as Control)


func _show_busy(text: String) -> void:
	_view = "busy"
	_clear()
	var card := _card()
	var col := UiKit.vbox(14, BoxContainer.ALIGNMENT_CENTER)
	card.add_child(col)
	var spin := Icon.new(&"globe", UiKit.SKY, 72)
	spin.size_flags_horizontal = Control.SIZE_SHRINK_CENTER  # stays 72x72, so it turns in place
	spin.pivot_offset = Vector2(36, 36)
	col.add_child(spin)
	var t := spin.create_tween().set_loops()
	t.tween_property(spin, "rotation", TAU, 1.6).from(0.0)
	col.add_child(UiKit.label(text, &"DarkHeaderLabel", HORIZONTAL_ALIGNMENT_CENTER))
	var cancel := UiKit.button("Cancel", &"PinkButton", 72)
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(func() -> void:
		Net.leave_room()
		_show_start())
	col.add_child(cancel)


func _show_room() -> void:
	_view = "room"
	_clear()
	var info := Net.room_info
	var is_host := bool(info.get("host", false))
	var state := String(info.get("state", "lobby"))
	var mode_id := StringName(String(info.get("mode", "bounce_race")))
	var cpus := bool(info.get("cpus", true))
	var players: Array = info.get("players", [])

	# The code, big and clear to read out, next to who's here. Everything on
	# this screen fits a 1280x720 screen without scrolling.
	var top := HFlowContainer.new()
	top.add_theme_constant_override("h_separation", 14)
	top.add_theme_constant_override("v_separation", 12)
	_body.add_child(top)
	var code_card := UiKit.color_panel(UiKit.CREAM, 26, 14, UiKit.SUN, 6, 4)
	code_card.custom_minimum_size = Vector2(250, 0)
	var ccol := UiKit.vbox(0, BoxContainer.ALIGNMENT_CENTER)
	code_card.add_child(ccol)
	ccol.add_child(UiKit.label("ROOM CODE", &"DarkSmallLabel", HORIZONTAL_ALIGNMENT_CENTER))
	var code := UiKit.label(String(info.get("code", Net.room_code)), &"DarkHeaderLabel", HORIZONTAL_ALIGNMENT_CENTER)
	code.add_theme_font_size_override("font_size", 64)
	code.name = "RoomCode"
	ccol.add_child(code)
	top.add_child(code_card)
	for p in players:
		top.add_child(_player_card(p))
	for i in NetProtocol.MAX_SEATS - players.size():
		top.add_child(_empty_seat(cpus))
	_body.add_child(UiKit.label("Share the code only with friends you know. They tap \"Join with a code\" and type it in.",
			&"SmallLabel"))

	# The game and CPU buddies: the host chooses, everyone else sees the choice.
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 12)
	row.add_theme_constant_override("v_separation", 10)
	_body.add_child(row)
	if is_host:
		var game := UiKit.label("Game:", &"SubHeaderLabel")
		game.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(game)
		for m in Catalog.MODES:
			if not bool(m.get("online", false)):
				continue
			var b := UiKit.icon_button(m.name, MODE_ICONS.get(m.id, &"star"),
					&"GreenButton" if m.id == mode_id else &"DarkButton", 64)
			b.name = "Mode_" + String(m.id)
			b.pressed.connect(func() -> void: Net.set_room_options(String(m.id), bool(Net.room_info.get("cpus", true))))
			row.add_child(b)
		var cpu_btn := UiKit.icon_button("CPU buddies: %s" % ("ON" if cpus else "OFF"), &"cpu",
				&"BlueButton" if cpus else &"DarkButton", 64)
		cpu_btn.name = "CpuToggle"
		cpu_btn.tooltip_text = "CPU buddies fill the empty seats"
		cpu_btn.pressed.connect(func() -> void: Net.set_room_options(String(Net.room_info.get("mode", "bounce_race")), not cpus))
		row.add_child(cpu_btn)
	else:
		row.add_child(_info_chip(MODE_ICONS.get(mode_id, &"star"), "Game: %s" % Catalog.mode(mode_id).name))
		row.add_child(_info_chip(&"cpu", "CPU buddies: %s" % ("ON" if cpus else "OFF")))
		var picks := UiKit.label("The host picks.", &"HudLabel")
		picks.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(picks)

	_body.add_child(UiKit.spacer())
	var bottom := UiKit.hbox(14)
	_body.add_child(bottom)
	if state != "lobby":
		var busy := UiKit.label("A round is being played. You'll join the next one!", &"HudLabel")
		busy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bottom.add_child(busy)
	elif is_host:
		var start := UiKit.icon_button("START!", &"play", &"BigButton", 92)
		start.name = "StartButton"
		start.custom_minimum_size.x = 300
		start.pressed.connect(func() -> void: Net.start_round())
		bottom.add_child(start)
		var hint := "Everyone ready? Start!"
		if players.size() < 2:
			hint = "Waiting for friends... or start now with CPU buddies!" if cpus else "Waiting for friends... or start on your own!"
		var hl := UiKit.label(hint, &"HudLabel")
		hl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bottom.add_child(hl)
		UiKit.focus_later(start)
	else:
		var wait := UiKit.label("Waiting for the host to start the game...", &"HudLabel")
		wait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bottom.add_child(wait)
	bottom.add_child(UiKit.spacer(0, false))
	var leave := UiKit.icon_button("Leave room", &"back", &"PinkButton", 72)
	leave.name = "LeaveButton"
	leave.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	leave.pressed.connect(func() -> void:
		Net.leave_room()
		_show_start())
	bottom.add_child(leave)


# ---------------------------------------------------------------- pieces

func _card() -> PanelContainer:
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(center)
	var card := UiKit.panel(&"CardPanel")
	center.add_child(card)
	UiKit.pop_in(card)
	return card


func _big_choice(title: String, sub: String, icon: StringName, variation: StringName) -> Button:
	var b := Button.new()
	b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(420, 170)
	var col := UiKit.vbox(6, BoxContainer.ALIGNMENT_CENTER)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)
	UiKit.full_rect(col)
	var row := UiKit.hbox(12, BoxContainer.ALIGNMENT_CENTER)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	row.add_child(Icon.new(icon, Color.WHITE, 54))
	var t := UiKit.label(title, &"SubHeaderLabel")
	row.add_child(t)
	col.add_child(UiKit.label(sub, &"SmallLabel", HORIZONTAL_ALIGNMENT_CENTER))
	b.pressed.connect(UiKit._click_sound)
	return b


func _look_chip() -> Control:
	var prof: Dictionary = GameState.profile
	var chip := UiKit.color_panel(Color(0.08, 0.2, 0.17, 0.75), 20, 10)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var row := UiKit.hbox(10)
	chip.add_child(row)
	var portrait := CharacterPortrait.new(StringName(prof.character), 56)
	portrait.hat_id = StringName(prof.hat)
	portrait.paint_id = StringName(prof.paint)
	row.add_child(portrait)
	var l := UiKit.label("You play as %s (change it in the Wardrobe)" % Catalog.character(StringName(prof.character)).name,
			&"SmallLabel")
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	return chip


func _server_chip() -> Control:
	var chip := UiKit.color_panel(Color(0.08, 0.2, 0.17, 0.75), 20, 8)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var row := UiKit.hbox(10)
	chip.add_child(row)
	var l := UiKit.label("Game server: %s" % String(GameState.get_setting("online_server", "127.0.0.1")), &"SmallLabel")
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	var change := UiKit.button("Change (grown-ups)", &"GhostButton", 52)
	change.pressed.connect(_ask_server_address)
	row.add_child(change)
	return chip


func _info_chip(icon: StringName, text: String) -> Control:
	var chip := UiKit.color_panel(Color(0.08, 0.2, 0.17, 0.75), 20, 12)
	chip.custom_minimum_size.y = 64
	var row := UiKit.hbox(10)
	chip.add_child(row)
	row.add_child(Icon.new(icon, Color.WHITE, 40))
	var l := UiKit.label(text, &"HudLabel")
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	return chip


func _player_card(p: Dictionary) -> Control:
	var color_index := clampi(int(p.get("color", 0)), 0, 3)
	var tag: Color = Catalog.PLAYER_TAG_COLORS[color_index]
	var card := UiKit.color_panel(Color(1, 1, 1, 0.94), 22, 12, tag, 5, 3)
	card.custom_minimum_size = Vector2(196, 0)
	var col := UiKit.vbox(4, BoxContainer.ALIGNMENT_CENTER)
	card.add_child(col)
	var look: Dictionary = p.get("look", {})
	var portrait := CharacterPortrait.new(StringName(String(look.get("character", "bloop"))), 84)
	portrait.hat_id = StringName(String(look.get("hat", "none")))
	portrait.paint_id = StringName(String(look.get("paint", "classic")))
	portrait.happy = bool(p.get("connected", true))
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(portrait)
	var name_row := UiKit.hbox(6, BoxContainer.ALIGNMENT_CENTER)
	col.add_child(name_row)
	var label := UiKit.label(String(p.get("label", "P?")), &"DarkHeaderLabel")
	label.add_theme_color_override("font_color", tag.darkened(0.35))
	name_row.add_child(label)
	if bool(p.get("you", false)):
		name_row.add_child(UiKit.label("(you)", &"DarkSmallLabel"))
	var notes := PackedStringArray()
	if bool(p.get("host", false)):
		notes.append("host")
	if not bool(p.get("connected", true)):
		notes.append("reconnecting...")
	if not notes.is_empty():
		col.add_child(UiKit.label(", ".join(notes), &"DarkSmallLabel", HORIZONTAL_ALIGNMENT_CENTER))
	return card


func _empty_seat(cpus: bool) -> Control:
	var card := UiKit.color_panel(Color(1, 1, 1, 0.18), 22, 12, Color(1, 1, 1, 0.5), 3, 0)
	card.custom_minimum_size = Vector2(196, 150)
	var col := UiKit.vbox(6, BoxContainer.ALIGNMENT_CENTER)
	card.add_child(col)
	col.add_child(Icon.new(&"cpu" if cpus else &"person", Color(1, 1, 1, 0.75), 56))
	col.add_child(UiKit.label("CPU buddy" if cpus else "Free seat", &"SmallLabel", HORIZONTAL_ALIGNMENT_CENTER))
	return card


func _build_toast() -> void:
	_toast = UiKit.color_panel(Color("ff8a4c"), 22, 14, Color.WHITE, 4, 4)
	_toast.visible = false
	_toast.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_toast)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast.offset_bottom = -24
	var row := UiKit.hbox(12)
	_toast.add_child(row)
	row.add_child(Icon.new(&"info", Color.WHITE, 40))
	_toast_label = UiKit.wrap_label("", &"HudLabel")
	_toast_label.custom_minimum_size.x = 640
	row.add_child(_toast_label)
	var ok := UiKit.button("OK", &"DarkButton", 60)
	ok.pressed.connect(func() -> void: _toast.visible = false)
	row.add_child(ok)


func _show_error(text: String) -> void:
	_toast_label.text = text
	_toast.visible = true
	UiKit.pop_in(_toast, 0.0, 0.8)
	if Net.status == Net.Status.OFFLINE and _view != "code":
		_refresh()


# ---------------------------------------------------------------- code typing

func _type(ch: String) -> void:
	if _code_typed.length() < NetProtocol.CODE_LENGTH and NetProtocol.CODE_ALPHABET.contains(ch):
		_code_typed += ch
		_update_code_boxes()


func _delete() -> void:
	_code_typed = _code_typed.substr(0, maxi(0, _code_typed.length() - 1))
	_update_code_boxes()


func _update_code_boxes() -> void:
	for i in _code_boxes.size():
		_code_boxes[i].text = _code_typed[i] if i < _code_typed.length() else ""
	if _join_btn:
		_join_btn.disabled = _code_typed.length() != NetProtocol.CODE_LENGTH


func _join() -> void:
	if NetProtocol.is_valid_code(_code_typed):
		_view = "busy"
		Net.join_room(_code_typed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()
		return
	if _view != "code" or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	if key.keycode == KEY_BACKSPACE:
		_delete()
	elif key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		_join()
	elif key.unicode > 0:
		_type(String.chr(key.unicode).to_upper())
	else:
		return
	get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- server address (grown-ups)

func _ask_server_address() -> void:
	var gate := GrownUpGate.new()
	gate.passed.connect(_edit_server_address)
	add_child(gate)


func _edit_server_address() -> void:
	var overlay := Control.new()
	add_child(overlay)
	UiKit.full_rect(overlay)
	overlay.add_child(UiKit.dimmer(0.7))
	# Near the top: a phone's on-screen keyboard covers the lower half.
	var holder := UiKit.margin(0, 24, 0, 0)
	overlay.add_child(holder)
	UiKit.full_rect(holder)
	var top := UiKit.vbox(0, BoxContainer.ALIGNMENT_BEGIN)
	holder.add_child(top)
	var card := UiKit.panel(&"CardPanel")
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	top.add_child(card)
	var col := UiKit.vbox(12)
	col.custom_minimum_size.x = 620
	card.add_child(col)
	col.add_child(UiKit.label("Game server address", &"DarkHeaderLabel"))
	var help := UiKit.wrap_label("The computer running the room server, for example 192.168.1.20 (same Wi-Fi) or a server name. Add :port if it isn't 7777.",
			&"DarkSmallLabel")
	help.custom_minimum_size.x = 600
	col.add_child(help)
	var edit := LineEdit.new()
	edit.text = String(GameState.get_setting("online_server", "127.0.0.1"))
	edit.max_length = 100
	edit.custom_minimum_size = Vector2(600, 64)
	edit.add_theme_font_size_override("font_size", 30)
	col.add_child(edit)
	var note := UiKit.label("", &"DarkSmallLabel")
	col.add_child(note)
	var row := UiKit.hbox(12)
	col.add_child(row)
	var save := UiKit.icon_button("Save", &"check", &"GreenButton", 68)
	save.pressed.connect(func() -> void:
		var text := edit.text.strip_edges()
		if not is_valid_server_address(text):
			note.text = "Use letters, numbers, dots, dashes and an optional :port."
			return
		GameState.set_setting("online_server", text)
		overlay.queue_free()
		_show_start())
	row.add_child(save)
	var cancel := UiKit.button("Cancel", &"PinkButton", 68)
	cancel.pressed.connect(func() -> void: overlay.queue_free())
	row.add_child(cancel)
	UiKit.focus_later(edit)


static func is_valid_server_address(text: String) -> bool:
	if text == "" or text.length() > 100:
		return false
	var re := RegEx.new()
	re.compile("^[A-Za-z0-9.\\-]+(:[0-9]{1,5})?$")
	if re.search(text) == null:
		return false
	if text.contains(":"):
		var port := int(text.get_slice(":", 1))
		return port >= 1 and port <= 65535
	return true


func _back() -> void:
	for c in get_children():
		if c is GrownUpGate:
			c.queue_free()
			return
	match _view:
		"code":
			_show_start()
		"room", "busy":
			Net.leave_room()
			_show_start()
		_:
			Router.go(&"menu")
