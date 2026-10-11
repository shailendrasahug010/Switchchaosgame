extends Node
## Title screen: the creatures hop around on their island while the big
## buttons lead to playing, the wardrobe, settings, grown-up info and the
## online beta.

var _play: Button


func _ready() -> void:
	AudioManager.play_music(&"menu")
	add_child(MenuBackdrop.new())
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	layer.add_child(root)
	UiKit.full_rect(root)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var margin := UiKit.margin(36, 28, 36, 28)
	root.add_child(margin)
	UiKit.full_rect(margin)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := UiKit.vbox(14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)

	var title_box := UiKit.vbox(-18)
	col.add_child(title_box)
	var t1 := UiKit.label("THE CHAOS", &"TitleLabel")
	t1.add_theme_font_size_override("font_size", 92)
	title_box.add_child(t1)
	var t2 := UiKit.label("SWITCH!", &"TitleLabel")
	t2.add_theme_font_size_override("font_size", 112)
	t2.add_theme_color_override("font_color", Color("ff7eb6"))
	t2.add_theme_color_override("font_outline_color", Color("ffffff"))
	title_box.add_child(t2)
	var sub := UiKit.label("Silly challenges. Switching rules. Big laughs.", &"HudLabel")
	sub.add_theme_font_size_override("font_size", 26)
	col.add_child(sub)
	col.add_child(UiKit.spacer(8))

	_play = UiKit.icon_button("PLAY!", &"play", &"BigButton", 116)
	_play.custom_minimum_size.x = 420
	_play.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_play.pressed.connect(func() -> void: Router.go(&"setup"))
	col.add_child(_play)

	var row := UiKit.hbox(12)
	col.add_child(row)
	var wardrobe := UiKit.icon_button("Wardrobe", &"shirt", &"BlueButton", 84)
	wardrobe.pressed.connect(func() -> void: Router.go(&"wardrobe"))
	row.add_child(wardrobe)
	var settings := UiKit.icon_button("", &"gear", &"DarkButton", 84)
	settings.tooltip_text = "Settings"
	settings.pressed.connect(func() -> void:
		Router.back_target = &"menu"
		Router.go(&"settings"))
	row.add_child(settings)
	var row2 := UiKit.hbox(12)
	col.add_child(row2)
	var online := UiKit.icon_button("Online (beta)", &"globe", &"GreenButton", 72)
	online.pressed.connect(func() -> void: Router.go(&"online"))
	row2.add_child(online)
	var parents := UiKit.icon_button("Grown-ups", &"info", &"DarkButton", 72, Color("ffd23f"))
	parents.pressed.connect(func() -> void: Router.go(&"parents"))
	row2.add_child(parents)

	col.add_child(UiKit.spacer())
	var stats := GameState.stats
	var info := UiKit.label("Rounds played: %d   Stars: %d   v%s" % [int(stats.rounds_played), int(stats.stars),
			ProjectSettings.get_setting("application/config/version", "0.1")], &"SmallLabel")
	col.add_child(info)
	UiKit.pop_in(_play, 0.2)
	_play.grab_focus.call_deferred()
