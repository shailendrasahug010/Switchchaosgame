extends Control
## "Grown-ups" page: what the game does with data, how online play works,
## fair-play and healthy-play notes, and credits. The online switch lives here
## behind a grown-up check.

const SECTIONS: Array[Dictionary] = [
	{
		"title": "What this game is",
		"icon": &"star",
		"text": "The Chaos Switch is a silly party game for ages 9 to 12. Up to four players share one device (keyboard, gamepads or touch for player 1), with friendly CPU buddies filling empty seats. Rounds last about a minute and the rules keep switching in funny ways, always with a warning first.",
	},
	{
		"title": "No accounts, no ads, nothing to buy",
		"icon": &"heart",
		"text": "There is no sign-up, no advertising, no in-app purchases and no loot boxes. Hats and colors are earned by playing; the exact goal for each one is always shown, and they never change how a character plays.",
	},
	{
		"title": "What is saved, and where",
		"icon": &"lock",
		"text": "Only on this device, in the game's private storage: settings, play totals (rounds played, stars, points, cakes delivered, buttons pressed, races finished, best times), which hats and colors are earned, the chosen character, and the last party setup. No names, photos, contacts or location. Nothing of this is sent anywhere. To erase it: Settings > Reset progress, or uninstall the game.",
	},
	{
		"title": "Online play (beta)",
		"icon": &"globe",
		"text": "Online play is off until a grown-up switches it on below. It uses private rooms only: one device creates a room and gets a short code, and friends type that code to join, so share it in person or with people you know. There is no text chat, no voice chat, no player names (players show up as P1 to P4 with their chosen creature), no friend lists and no location. While playing online the game sends the room code, the chosen creature, hat and color, controller presses and game events to the game server. Like any internet connection, the server can see the device's network (IP) address while connected. The test server keeps rooms in memory only and forgets them when the room closes. This is an early test feature: it will be reviewed again before any public release.",
	},
	{
		"title": "Fair and friendly play",
		"icon": &"trophy",
		"text": "Points only come from good things: finishing goals, collecting stars, helping teammates, bouncing back after a mistake and finishing in time. Players pass through each other, so nobody can score by pushing or blocking others, and losing a round is played for laughs.",
	},
	{
		"title": "Comfort",
		"icon": &"info",
		"text": "Settings has a Calm camera option (no shaking, softer flashes), Simple controls with one big button, Big buttons and a Left-handed layout. Every rule switch is shown with words, a picture and a countdown, so the game can be played with the sound off. Short breaks between rounds are a good idea.",
	},
	{
		"title": "Credits",
		"icon": &"bell",
		"text": "Game code, 3D shapes, icons, sound effects and music were made for this project. Font: Fredoka (SIL Open Font License 1.1). Made with the Godot Engine (MIT license). The full license texts are below.",
	},
]

var _online_btn: Button


func _ready() -> void:
	AudioManager.play_music(&"menu")
	var bg := MenuBackground.new()
	bg.top_color = Color("3b2f8f")
	bg.bottom_color = Color("7b5cff")
	add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	UiKit.full_rect(scroll)
	var margin := UiKit.margin(28, 18, 28, 24)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)
	var col := UiKit.vbox(14)
	margin.add_child(col)
	var head := UiKit.hbox(16)
	col.add_child(head)
	var back := UiKit.icon_button("", &"back", &"DarkButton", 72)
	back.pressed.connect(_back)
	head.add_child(back)
	head.add_child(Icon.new(&"info", Color("ffd23f"), 52))
	head.add_child(UiKit.label("For grown-ups", &"HeaderLabel"))

	for s in SECTIONS:
		var panel := UiKit.color_panel(Color(0.12, 0.1, 0.26, 0.8), 22, 16)
		col.add_child(panel)
		var inner := UiKit.vbox(6)
		panel.add_child(inner)
		var row := UiKit.hbox(10)
		row.add_child(Icon.new(s.icon, Color("ffd23f"), 34))
		row.add_child(UiKit.label(s.title, &"HudLabel"))
		inner.add_child(row)
		var text := UiKit.wrap_label(s.text, &"BodyLabel")
		text.add_theme_font_size_override("font_size", 22)
		text.custom_minimum_size.x = 1100
		inner.add_child(text)
		if s.title.begins_with("Online"):
			_online_btn = UiKit.icon_button("", &"globe", &"GreenButton", 68)
			_online_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			_online_btn.pressed.connect(_toggle_online)
			inner.add_child(_online_btn)
		elif s.title == "Credits":
			var lic := UiKit.icon_button("Software licenses", &"info", &"DarkButton", 64)
			lic.name = "LicensesButton"
			lic.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			lic.pressed.connect(func() -> void: add_child(LicensesOverlay.new()))
			inner.add_child(lic)
	_refresh()


func _refresh() -> void:
	var on := bool(GameState.get_setting("online_allowed", false))
	UiKit.set_icon_button_text(_online_btn, "Online play: ON (tap to switch off)" if on else "Online play: OFF (grown-up check to switch on)")
	_online_btn.theme_type_variation = &"GreenButton" if on else &"DarkButton"


func _toggle_online() -> void:
	if bool(GameState.get_setting("online_allowed", false)):
		GameState.set_setting("online_allowed", false)
		_refresh()
		return
	var gate := GrownUpGate.new()
	gate.passed.connect(func() -> void:
		GameState.set_setting("online_allowed", true)
		_refresh())
	add_child(gate)


func _back() -> void:
	Router.go(&"menu")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		for c in get_children():
			if c is GrownUpGate or c is LicensesOverlay:
				c.queue_free()
				return
		_back()
