class_name Hud
extends Control
## The in-round heads-up display.
##
## Presentation only: it reads the match and listens to its signals. Every
## chaos event is announced here with a big colored card, its name, a one-line
## tip and a countdown BEFORE it starts, and stays listed (with a timer bar)
## while it is active. Reverse Mode also draws a pulsing border.

const CHIP_WIDTH := 132.0

var match_ctl: MatchController

var _layer: Control
var _pause_btn: Button
var _debug_btn: Button
var _chips: Array[Dictionary] = []
var _timer_panel: PanelContainer
var _timer_label: Label
var _timer_style: StyleBoxFlat
var _objective_label: Label
var _objective_slot: VBoxContainer
var _chaos_list: VBoxContainer
var _chaos_rows: Dictionary = {}

var _banner: PanelContainer
var _banner_style: StyleBoxFlat
var _banner_icon: Icon
var _banner_kicker: Label
var _banner_title: Label
var _banner_tagline: Label
var _banner_tip: Label
var _banner_count: Label
var _banner_hide_at := -1.0

var _mission_card: PanelContainer
var _countdown: Label
var _big_message: Label
var _toast: PanelContainer
var _toast_label: Label
var _toast_left := 0.0
var _prompt_hint: Label
var _reverse_border: BorderOverlay
var _reverse_label: PanelContainer
var _flash: ColorRect
var _time := 0.0
var _last_tick_second := -1


class BorderOverlay:
	extends Control
	var color := Color("a64dff")
	var strength := 0.0
	var _t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		if strength > 0.0:
			queue_redraw()

	func _draw() -> void:
		if strength <= 0.0:
			return
		var pulse := 0.55 + 0.45 * sin(_t * 6.0)
		var w := 14.0 + 6.0 * pulse
		var c := Color(color, 0.55 * strength * (0.6 + 0.4 * pulse))
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(Rect2(r.position, Vector2(r.size.x, w)), c)
		draw_rect(Rect2(Vector2(0, r.size.y - w), Vector2(r.size.x, w)), c)
		draw_rect(Rect2(r.position, Vector2(w, r.size.y)), c)
		draw_rect(Rect2(Vector2(r.size.x - w, 0), Vector2(w, r.size.y)), c)


func setup(p_match: MatchController) -> void:
	match_ctl = p_match
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	match_ctl.phase_changed.connect(_on_phase_changed)
	match_ctl.countdown_tick.connect(_on_countdown_tick)
	match_ctl.message_requested.connect(show_toast)
	match_ctl.score.scored.connect(_on_scored)
	var chaos := match_ctl.chaos
	chaos.event_announced.connect(_on_event_announced)
	chaos.countdown_changed.connect(_on_countdown_changed)
	chaos.announcement_cancelled.connect(func(_ev: ChaosEvent) -> void: _hide_banner())
	chaos.event_started.connect(_on_event_started)
	chaos.event_ended.connect(_on_event_ended)
	GameState.settings_changed.connect(_refresh_debug_button)


# ---------------------------------------------------------------- building

func _build() -> void:
	_reverse_border = BorderOverlay.new()
	add_child(_reverse_border)
	UiKit.full_rect(_reverse_border)
	_flash = ColorRect.new()
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 0)
	add_child(_flash)
	UiKit.full_rect(_flash)

	var margin := UiKit.margin(16)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	UiKit.full_rect(margin)
	_apply_safe_area(margin)
	_layer = Control.new()
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(_layer)

	_build_top_left()
	_build_top_center()
	_build_top_right()
	_build_center()
	_build_bottom()


func _apply_safe_area(margin: MarginContainer) -> void:
	var win := Vector2(DisplayServer.window_get_size())
	var safe := DisplayServer.get_display_safe_area()
	if win.x <= 0 or safe.size.x <= 0 or OS.has_feature("headless"):
		return
	var vp := get_viewport_rect().size
	var k := vp / win
	var left := maxf(0.0, safe.position.x) * k.x
	var top := maxf(0.0, safe.position.y) * k.y
	var right := maxf(0.0, win.x - safe.end.x) * k.x
	var bottom := maxf(0.0, win.y - safe.end.y) * k.y
	if left + top + right + bottom > 0.0 and left < vp.x * 0.2 and right < vp.x * 0.2:
		margin.add_theme_constant_override("margin_left", 16 + int(left))
		margin.add_theme_constant_override("margin_top", 16 + int(top))
		margin.add_theme_constant_override("margin_right", 16 + int(right))
		margin.add_theme_constant_override("margin_bottom", 16 + int(bottom))


func _build_top_left() -> void:
	var row := UiKit.hbox(10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_pause_btn = UiKit.icon_button("", &"pause", &"DarkButton", 72)
	_pause_btn.custom_minimum_size = Vector2(72, 72)
	_pause_btn.tooltip_text = "Pause"
	_pause_btn.focus_mode = Control.FOCUS_NONE
	_pause_btn.pressed.connect(func() -> void: match_ctl.set_paused(true))
	row.add_child(_pause_btn)
	_debug_btn = UiKit.icon_button("", &"bug", &"DarkButton", 56, Color("7dffb0"))
	_debug_btn.custom_minimum_size = Vector2(56, 56)
	_debug_btn.focus_mode = Control.FOCUS_NONE
	_debug_btn.pressed.connect(func() -> void: match_ctl.debug_panel.toggle())
	row.add_child(_debug_btn)
	_refresh_debug_button()
	var count := match_ctl.players.size()
	var left_count := ceili(count / 2.0)
	for i in left_count:
		row.add_child(_make_chip(i))
	# Remaining chips go to the top-right corner.
	var right_row := UiKit.hbox(10)
	right_row.name = "RightChips"
	right_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(right_row)
	right_row.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	right_row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	for i in range(left_count, count):
		right_row.add_child(_make_chip(i))


func _refresh_debug_button() -> void:
	if _debug_btn:
		_debug_btn.visible = bool(GameState.get_setting("debug_tools", false))


func _make_chip(index: int) -> Control:
	var p := match_ctl.players[index]
	var slot: MatchSetup.Slot = match_ctl.setup.slots[index]
	var color: Color = Catalog.PLAYER_TAG_COLORS[index % 4]
	var panel := UiKit.color_panel(Color(0.14, 0.12, 0.3, 0.82), 32, 6, color, 0, 3)
	panel.custom_minimum_size = Vector2(CHIP_WIDTH, 60)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := UiKit.hbox(6)
	panel.add_child(row)
	var portrait := CharacterPortrait.new(slot.character_id, 46)
	portrait.paint_id = slot.paint_id
	portrait.hat_id = slot.hat_id
	row.add_child(portrait)
	var col := UiKit.vbox(-6)
	row.add_child(col)
	var tag := UiKit.label(p.display_name, &"SmallLabel")
	tag.add_theme_color_override("font_color", color.lightened(0.3))
	tag.add_theme_font_size_override("font_size", 18)
	col.add_child(tag)
	var points := UiKit.label("0", &"HudLabel")
	points.add_theme_font_size_override("font_size", 26)
	col.add_child(points)
	_chips.append({"panel": panel, "points": points, "index": index})
	return panel


func _build_top_center() -> void:
	var col := UiKit.vbox(6, BoxContainer.ALIGNMENT_BEGIN)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(col)
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_timer_style = UiKit.style(Color(0.14, 0.12, 0.3, 0.88), 34, 10, Color("ffd23f"), 0, 4)
	_timer_panel = PanelContainer.new()
	_timer_panel.add_theme_stylebox_override("panel", _timer_style)
	_timer_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_timer_panel)
	var row := UiKit.hbox(10, BoxContainer.ALIGNMENT_CENTER)
	_timer_panel.add_child(row)
	row.add_child(Icon.new(&"clock", Color("ffd23f"), 40))
	_timer_label = UiKit.label("0:00", &"HudBigLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_timer_label.add_theme_font_size_override("font_size", 48)
	_timer_label.custom_minimum_size.x = 120
	row.add_child(_timer_label)
	_objective_label = UiKit.label("", &"HudLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_objective_label.add_theme_font_size_override("font_size", 24)
	col.add_child(_objective_label)
	_objective_slot = UiKit.vbox(6)
	_objective_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_objective_slot)
	var widget := match_ctl.mode.create_objective_widget()
	if widget:
		_objective_slot.add_child(widget)


func _build_top_right() -> void:
	_chaos_list = UiKit.vbox(8)
	_chaos_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_chaos_list)
	_chaos_list.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_chaos_list.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_chaos_list.position.y = 84
	_chaos_list.offset_top = 84


func _build_center() -> void:
	# Chaos announcement card.
	_banner_style = UiKit.style(Color("7b5cff"), 34, 22, Color(1, 1, 1, 0.9), 10, 5)
	_banner = PanelContainer.new()
	_banner.add_theme_stylebox_override("panel", _banner_style)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	_layer.add_child(_banner)
	var row := UiKit.hbox(20)
	_banner.add_child(row)
	_banner_icon = Icon.new(&"star", Color.WHITE, 110)
	_banner_icon.shadow = true
	row.add_child(_banner_icon)
	var col := UiKit.vbox(0)
	col.custom_minimum_size.x = 430
	row.add_child(col)
	_banner_kicker = UiKit.label("CHAOS SWITCH!", &"HudLabel")
	_banner_kicker.add_theme_font_size_override("font_size", 24)
	_banner_kicker.add_theme_color_override("font_color", Color("fff3a3"))
	col.add_child(_banner_kicker)
	_banner_title = UiKit.label("", &"HudBigLabel")
	_banner_title.add_theme_font_size_override("font_size", 54)
	col.add_child(_banner_title)
	_banner_tagline = UiKit.label("", &"HudLabel")
	_banner_tagline.add_theme_font_size_override("font_size", 28)
	col.add_child(_banner_tagline)
	_banner_tip = UiKit.wrap_label("", &"HudLabel")
	_banner_tip.add_theme_font_size_override("font_size", 22)
	_banner_tip.custom_minimum_size.x = 430
	col.add_child(_banner_tip)
	_banner_count = UiKit.label("3", &"HudHugeLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_banner_count.custom_minimum_size.x = 110
	row.add_child(_banner_count)

	# Mission card shown during the intro.
	_mission_card = UiKit.panel(&"CardPanel")
	_mission_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mission_card.visible = false
	_layer.add_child(_mission_card)
	var mcol := UiKit.vbox(10, BoxContainer.ALIGNMENT_CENTER)
	mcol.custom_minimum_size.x = 620
	_mission_card.add_child(mcol)
	var mode := match_ctl.mode
	var title_row := UiKit.hbox(14, BoxContainer.ALIGNMENT_CENTER)
	mcol.add_child(title_row)
	title_row.add_child(Icon.new(mode.mission_icon, Color(match_ctl.mode_info.get("color", Color("ff5fa8"))), 64))
	title_row.add_child(UiKit.label(mode.mission_title, &"DarkHeaderLabel", HORIZONTAL_ALIGNMENT_CENTER))
	var text := UiKit.wrap_label(mode.mission_text, &"DarkLabel", HORIZONTAL_ALIGNMENT_CENTER)
	text.add_theme_font_size_override("font_size", 28)
	text.custom_minimum_size.x = 600
	mcol.add_child(text)
	var hint := UiKit.wrap_label(_controls_hint(), &"DarkSmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
	hint.custom_minimum_size.x = 600
	mcol.add_child(hint)
	var chaos_note := UiKit.wrap_label("Watch out: the rules will SWITCH! You'll always get a warning first.",
			&"DarkSmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
	chaos_note.add_theme_color_override("font_color", Color("7b5cff"))
	chaos_note.custom_minimum_size.x = 600
	chaos_note.visible = match_ctl.setup.chaos_enabled
	mcol.add_child(chaos_note)

	_countdown = UiKit.label("", &"HudHugeLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_countdown.add_theme_font_size_override("font_size", 150)
	_countdown.visible = false
	_layer.add_child(_countdown)
	_big_message = UiKit.label("", &"HudHugeLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_big_message.add_theme_font_size_override("font_size", 84)
	_big_message.visible = false
	_layer.add_child(_big_message)
	for c: Control in [_banner, _mission_card, _countdown, _big_message]:
		c.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		c.grow_horizontal = Control.GROW_DIRECTION_BOTH
		c.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.offset_top -= 70
	_banner.offset_bottom -= 70


func _controls_hint() -> String:
	if GameState.wants_touch_controls():
		return "Move with the stick on the left. Tap JUMP to hop. The hand button grabs and presses things."
	if match_ctl.setup.human_count() > 1:
		return "P1: WASD + Space (jump) + E (grab)    P2: Arrows + Enter (jump) + / (grab)"
	return "Move: WASD or arrows    Jump: Space    Grab / press: E    Pause: Esc"


func _build_bottom() -> void:
	_toast = UiKit.panel(&"ChipPanel")
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	_layer.add_child(_toast)
	_toast_label = UiKit.label("", &"HudLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_toast.add_child(_toast_label)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast.offset_bottom = -190
	_toast.offset_top = -250

	_reverse_label = UiKit.color_panel(Color("8a3dff"), 30, 10, Color.WHITE, 0, 3)
	_reverse_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reverse_label.visible = false
	var rrow := UiKit.hbox(10)
	_reverse_label.add_child(rrow)
	rrow.add_child(Icon.new(&"reverse", Color.WHITE, 36))
	rrow.add_child(UiKit.label("CONTROLS FLIPPED!", &"HudLabel"))
	rrow.add_child(Icon.new(&"reverse", Color.WHITE, 36))
	_layer.add_child(_reverse_label)
	_reverse_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_reverse_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_reverse_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_reverse_label.offset_bottom = -110
	_reverse_label.offset_top = -170

	_prompt_hint = UiKit.label("", &"HudLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_prompt_hint.visible = false
	_layer.add_child(_prompt_hint)
	_prompt_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_prompt_hint.offset_bottom = -40
	_prompt_hint.offset_top = -90


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	if match_ctl == null:
		return
	_time += delta
	_update_timer()
	_update_chaos_rows()
	_update_reverse()
	_update_prompt()
	if _toast_left > 0.0:
		_toast_left -= delta
		if _toast_left <= 0.0:
			var t := create_tween()
			t.tween_property(_toast, "modulate:a", 0.0, 0.25)
			t.tween_callback(func() -> void: _toast.visible = false)
	if _banner_hide_at > 0.0 and _time >= _banner_hide_at:
		_banner_hide_at = -1.0
		_hide_banner()
	if _flash.color.a > 0.0:
		_flash.color.a = maxf(0.0, _flash.color.a - delta * 2.2)


func _update_timer() -> void:
	var t := match_ctl.time_left
	_timer_label.text = UiKit.format_time(t)
	var urgent := t <= 10.0 and match_ctl.is_playing()
	var warn := t <= 20.0 and match_ctl.is_playing()
	_timer_label.add_theme_color_override("font_color",
			Color("ff7a9c") if urgent else (Color("ffb35c") if warn else Color.WHITE))
	if urgent:
		var s := 1.0 + 0.08 * absf(sin(_time * 6.0))
		_timer_panel.pivot_offset = _timer_panel.size * 0.5
		_timer_panel.scale = Vector2(s, s)
		var sec := ceili(t)
		if sec != _last_tick_second and sec <= 5 and sec > 0:
			_last_tick_second = sec
			AudioManager.play(&"tick", 1.4)
	else:
		_timer_panel.scale = Vector2.ONE
	_objective_label.text = match_ctl.mode.get_objective_text() if match_ctl.is_playing() else ""


func _update_chaos_rows() -> void:
	for entry in match_ctl.chaos.get_active_entries():
		var ev: ChaosEvent = entry.event
		if _chaos_rows.has(ev.id):
			var bar: ProgressBar = _chaos_rows[ev.id].bar
			bar.value = float(entry.left) / maxf(ev.duration, 0.01) * 100.0


func _update_reverse() -> void:
	var reversed := false
	for p in match_ctl.players:
		if p.is_human and p.is_reversed():
			reversed = true
	_reverse_border.strength = move_toward(_reverse_border.strength, 1.0 if reversed else 0.0, 0.08)
	_reverse_border.queue_redraw()
	_reverse_label.visible = reversed and match_ctl.is_playing()


func _update_prompt() -> void:
	# Keyboard players get a text hint; touch players see it on the action button.
	if GameState.wants_touch_controls() or not match_ctl.is_playing():
		_prompt_hint.visible = false
		return
	var parts: PackedStringArray = []
	for p in match_ctl.players:
		if not p.is_human:
			continue
		var prompt := match_ctl.mode.get_interact_prompt(p)
		var local := p.input as LocalInputSource
		if prompt != "" and local != null:
			var key := "E" if local.slot == 1 else "/"
			parts.append(("%s: " % p.display_name if match_ctl.setup.human_count() > 1 else "") + "[%s] %s" % [key, prompt])
	_prompt_hint.text = "     ".join(parts)
	_prompt_hint.visible = not parts.is_empty()


# ---------------------------------------------------------------- reactions to the match

func _on_phase_changed(phase: MatchController.Phase) -> void:
	match phase:
		MatchController.Phase.INTRO:
			_mission_card.visible = true
			UiKit.pop_in(_mission_card)
		MatchController.Phase.COUNTDOWN:
			_mission_card.visible = false
		MatchController.Phase.PLAYING:
			_mission_card.visible = false
			_show_big_count("GO!")
		MatchController.Phase.FINISHED:
			_hide_banner()
			_countdown.visible = false
			_big_message.text = "MISSION COMPLETE!" if match_ctl.success else "TIME'S UP!"
			_big_message.add_theme_color_override("font_color", Color("7dffb0") if match_ctl.success else Color("ffd23f"))
			_big_message.visible = true
			UiKit.pop_in(_big_message)
		MatchController.Phase.RESULTS:
			visible = false


func _on_countdown_tick(value: int) -> void:
	if value > 0:
		_show_big_count(str(value))


func _show_big_count(text: String) -> void:
	_countdown.text = text
	_countdown.visible = true
	_countdown.modulate.a = 1.0
	_countdown.pivot_offset = _countdown.size * 0.5
	_countdown.scale = Vector2(1.6, 1.6)
	var t := create_tween()
	t.tween_property(_countdown, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if text == "GO!":
		t.tween_interval(0.4)
		t.tween_property(_countdown, "modulate:a", 0.0, 0.3)
		t.tween_callback(func() -> void: _countdown.visible = false)


func _on_scored(index: int, _category: StringName, _points: int, _reason: String) -> void:
	for chip in _chips:
		if chip.index == index:
			var label: Label = chip.points
			label.text = _format_points(match_ctl.score.total(index))
			var panel: Control = chip.panel
			panel.pivot_offset = panel.size * 0.5
			var t := create_tween()
			t.tween_property(panel, "scale", Vector2(1.12, 1.12), 0.08)
			t.tween_property(panel, "scale", Vector2.ONE, 0.18)


func _format_points(n: int) -> String:
	var s := str(n)
	if n >= 1000:
		s = "%d,%03d" % [n / 1000, n % 1000]
	return s


func show_toast(text: String, color: Color = Color.WHITE, seconds: float = 2.2) -> void:
	_toast_label.text = text
	_toast_label.add_theme_color_override("font_color", color)
	_toast.visible = true
	_toast.modulate.a = 1.0
	_toast_left = seconds
	UiKit.pop_in(_toast, 0.0, 0.85)


# ---------------------------------------------------------------- chaos presentation

func _set_banner_event(ev: ChaosEvent) -> void:
	_banner_style.bg_color = ev.color.darkened(0.15)
	_banner_style.border_color = ev.color.lightened(0.5)
	_banner_icon.icon = ev.icon
	_banner_title.text = ev.display_name.to_upper()
	_banner_tagline.text = ev.tagline
	_banner_tip.text = ev.tip


func _on_event_announced(ev: ChaosEvent, lead_time: float) -> void:
	_set_banner_event(ev)
	_banner_kicker.text = "CHAOS SWITCH IN..."
	_banner_count.text = str(ceili(lead_time))
	_banner_count.visible = true
	_banner_tip.visible = true
	_banner_hide_at = -1.0
	_banner.visible = true
	_banner.modulate.a = 1.0
	UiKit.pop_in(_banner, 0.0, 0.5)


func _on_countdown_changed(_ev: ChaosEvent, seconds_left: int) -> void:
	if not _banner.visible:
		return
	_banner_count.text = str(maxi(seconds_left, 0))
	_banner_count.pivot_offset = _banner_count.size * 0.5
	_banner_count.scale = Vector2(1.4, 1.4)
	create_tween().tween_property(_banner_count, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)


func _on_event_started(ev: ChaosEvent) -> void:
	_set_banner_event(ev)
	_banner_kicker.text = "THE RULES SWITCHED!"
	_banner_title.text = ev.display_name.to_upper() + "!"
	_banner_count.visible = false
	_banner.visible = true
	_banner.modulate.a = 1.0
	_banner_hide_at = _time + 2.2
	_flash.color = Color(ev.color.lightened(0.4), 0.35 if not GameState.get_setting("reduced_motion", false) else 0.12)
	_add_chaos_row(ev)


func _on_event_ended(ev: ChaosEvent) -> void:
	if _chaos_rows.has(ev.id):
		var row: Control = _chaos_rows[ev.id].row
		_chaos_rows.erase(ev.id)
		var t := create_tween()
		t.tween_property(row, "modulate:a", 0.0, 0.25)
		t.tween_callback(row.queue_free)
	if match_ctl.is_playing():
		show_toast("%s is over!" % ev.display_name, ev.color.lightened(0.5), 1.6)


func _add_chaos_row(ev: ChaosEvent) -> void:
	if _chaos_rows.has(ev.id):
		return
	var panel := UiKit.color_panel(ev.color.darkened(0.2), 24, 8, Color(1, 1, 1, 0.8), 0, 3)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(250, 0)
	var row := UiKit.hbox(8)
	panel.add_child(row)
	row.add_child(Icon.new(ev.icon, Color.WHITE, 44))
	var col := UiKit.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var name_label := UiKit.label(ev.display_name, &"HudLabel")
	name_label.add_theme_font_size_override("font_size", 22)
	col.add_child(name_label)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	bar.value = 100.0
	bar.add_theme_stylebox_override("fill", UiKit.style(Color.WHITE, 8, 0))
	bar.add_theme_stylebox_override("background", UiKit.style(Color(0, 0, 0, 0.25), 8, 0))
	col.add_child(bar)
	_chaos_list.add_child(panel)
	_chaos_rows[ev.id] = {"row": panel, "bar": bar}
	UiKit.pop_in(panel, 0.1)


func _hide_banner() -> void:
	if not _banner.visible:
		return
	var t := create_tween()
	t.tween_property(_banner, "modulate:a", 0.0, 0.25)
	t.tween_callback(func() -> void:
		_banner.visible = false
		_banner.modulate.a = 1.0)


## For tests: is the announcement card showing right now?
func is_banner_visible() -> bool:
	return _banner.visible and _banner.modulate.a > 0.5


func get_banner_title() -> String:
	return _banner_title.text
