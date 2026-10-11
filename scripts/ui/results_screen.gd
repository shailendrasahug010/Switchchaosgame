class_name ResultsScreen
extends Control
## End-of-round results: a funny headline, one card per player with a
## friendly award (everyone gets one), new cosmetic unlocks and buttons to
## play again right away.

var match_ctl: MatchController
var _buttons: Array[Button] = []


func setup(p_match: MatchController) -> void:
	match_ctl = p_match
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func show_results(r: Dictionary) -> void:
	for c in get_children():
		c.queue_free()
	_buttons.clear()
	visible = true
	add_child(UiKit.dimmer(0.45))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	UiKit.full_rect(scroll)
	var outer := UiKit.margin(18)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(outer)
	var col := UiKit.vbox(12, BoxContainer.ALIGNMENT_CENTER)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(col)

	# Headline
	var success: bool = r.success
	var head := UiKit.color_panel(Color("2fc97a") if success else Color("ff8a4c"), 34, 14, Color.WHITE, 8, 4)
	head.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(head)
	var hcol := UiKit.vbox(0, BoxContainer.ALIGNMENT_CENTER)
	head.add_child(hcol)
	var hrow := UiKit.hbox(14, BoxContainer.ALIGNMENT_CENTER)
	hcol.add_child(hrow)
	hrow.add_child(Icon.new(&"trophy" if success else &"clock", Color("fff3a3"), 56))
	var title := UiKit.label(String(r.headline), &"HeaderLabel", HORIZONTAL_ALIGNMENT_CENTER)
	hrow.add_child(title)
	if String(r.subline) != "":
		hcol.add_child(UiKit.label(String(r.subline), &"BodyLabel", HORIZONTAL_ALIGNMENT_CENTER))
	UiKit.pop_in(head)
	if r.team:
		var team := UiKit.label("Team score: %s" % _fmt(int(r.team_total)), &"SubHeaderLabel", HORIZONTAL_ALIGNMENT_CENTER)
		col.add_child(team)

	# Player cards
	var cards := UiKit.hbox(14, BoxContainer.ALIGNMENT_CENTER)
	col.add_child(cards)
	var order: Array = r.ranking if not r.team else range((r.players as Array).size())
	var rank := 0
	for idx in order:
		rank += 1
		var info: Dictionary = (r.players as Array)[idx]
		var card := _player_card(info, rank, r.team, success)
		cards.add_child(card)
		UiKit.pop_in(card, 0.15 + rank * 0.12)

	# Unlocks
	for item in (r.unlocked as Array):
		var u := UiKit.color_panel(Color("7b5cff"), 26, 10, Color("ffd23f"), 0, 4)
		u.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var urow := UiKit.hbox(10)
		u.add_child(urow)
		urow.add_child(Icon.new(&"star", Color("ffd23f"), 40))
		urow.add_child(UiKit.label("NEW! You unlocked the %s! Try it in the Wardrobe." % item.name, &"HudLabel"))
		col.add_child(u)
		UiKit.pop_in(u, 0.8)
	var hint: Dictionary = r.next_unlock
	if not hint.is_empty():
		var hrow2 := UiKit.hbox(10, BoxContainer.ALIGNMENT_CENTER)
		col.add_child(hrow2)
		hrow2.add_child(Icon.new(&"lock", Color("d6d3e8"), 30))
		hrow2.add_child(UiKit.label("Next prize: %s - %s" % [hint.name, GameState.unlock_rule_text(hint)], &"SmallLabel"))
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(160, 16)
		bar.value = GameState.unlock_progress(hint) * 100.0
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hrow2.add_child(bar)

	# Buttons
	var brow := UiKit.hbox(16, BoxContainer.ALIGNMENT_CENTER)
	col.add_child(brow)
	if bool(r.get("online", false)):
		# Online the host starts the next round from the room screen.
		var room := UiKit.icon_button("Back to the room", &"next", &"GreenButton", 84)
		room.pressed.connect(func() -> void: match_ctl.back_to_room())
		brow.add_child(room)
		var leave := UiKit.icon_button("Leave room", &"back", &"PinkButton", 84)
		leave.pressed.connect(func() -> void: match_ctl.quit_to_menu())
		brow.add_child(leave)
		_buttons = [room, leave]
		UiKit.focus_later(room)
		return
	var again := UiKit.icon_button("Play again", &"restart", &"GreenButton", 84)
	again.pressed.connect(func() -> void: match_ctl.restart_round())
	brow.add_child(again)
	var next := UiKit.icon_button("Next game", &"next", &"BlueButton", 84)
	next.pressed.connect(func() -> void: match_ctl.next_round())
	brow.add_child(next)
	var menu := UiKit.icon_button("Menu", &"back", &"PinkButton", 84)
	menu.pressed.connect(func() -> void: match_ctl.quit_to_menu())
	brow.add_child(menu)
	_buttons = [again, next, menu]
	UiKit.focus_later(again)


func _player_card(info: Dictionary, rank: int, team: bool, success: bool) -> Control:
	var color: Color = info.color
	var card := UiKit.color_panel(Color("fff8ee"), 26, 14, color, 8, 4)
	card.custom_minimum_size = Vector2(260, 0)
	var col := UiKit.vbox(4, BoxContainer.ALIGNMENT_CENTER)
	card.add_child(col)
	var top := UiKit.hbox(8, BoxContainer.ALIGNMENT_CENTER)
	col.add_child(top)
	if not team:
		var medal_colors := [Color("ffc93c"), Color("c9d2e3"), Color("e3a06a")]
		var badge := UiKit.color_panel(medal_colors[rank - 1] if rank <= 3 else Color("b9b3d6"), 20, 4)
		badge.add_child(UiKit.label(UiKit.ordinal(rank), &"DarkLabel", HORIZONTAL_ALIGNMENT_CENTER))
		top.add_child(badge)
	var portrait := CharacterPortrait.new(info.character, 84)
	portrait.paint_id = info.paint
	portrait.hat_id = info.hat
	portrait.happy = success or rank == 1
	portrait.backdrop = Color(color, 0.25)
	top.add_child(portrait)
	var name_label := UiKit.label("%s  %s" % [info.label, info.character_name], &"DarkLabel", HORIZONTAL_ALIGNMENT_CENTER)
	name_label.add_theme_color_override("font_color", color.darkened(0.35))
	col.add_child(name_label)
	var total := UiKit.label(_fmt(int(info.total)), &"DarkHeaderLabel", HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(total)
	var award: Dictionary = info.award
	var award_box := UiKit.color_panel(Color(color, 0.2), 16, 8)
	col.add_child(award_box)
	var acol := UiKit.vbox(0, BoxContainer.ALIGNMENT_CENTER)
	award_box.add_child(acol)
	var at := UiKit.label(String(award.title), &"DarkLabel", HORIZONTAL_ALIGNMENT_CENTER)
	at.add_theme_color_override("font_color", Color("7b5cff"))
	acol.add_child(at)
	var ad := UiKit.wrap_label(String(award.text), &"DarkSmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
	ad.custom_minimum_size.x = 220
	acol.add_child(ad)
	var breakdown: Dictionary = info.breakdown
	for cat in ScoreKeeper.CATEGORIES:
		var pts := int(breakdown.get(cat, 0))
		if pts <= 0:
			continue
		var row := UiKit.hbox(6)
		col.add_child(row)
		var l := UiKit.label(String(ScoreKeeper.CATEGORY_NAMES[cat]), &"DarkSmallLabel")
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(UiKit.label(_fmt(pts), &"DarkSmallLabel"))
	return card


func _fmt(n: int) -> String:
	if n >= 1000:
		return "%d,%03d" % [n / 1000, n % 1000]
	return str(n)


func get_button_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for b in _buttons:
		var l := b.find_child("Text", true, false) as Label
		out.append(l.text if l else b.text)
	return out
