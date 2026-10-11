class_name DebugPanel
extends Control
## Developer tools (F1, the ` key, or the bug button when "Debug tools" is on
## in Settings): trigger any chaos event on demand, end events, change round
## time and watch the live rule values.

var match_ctl: MatchController
var _status: Label
var _schedule_btn: Button
var _speed_btn: Button
var _panel: PanelContainer


func setup(p_match: MatchController) -> void:
	match_ctl = p_match
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = UiKit.color_panel(Color(0.08, 0.07, 0.16, 0.92), 20, 12, Color("7dffb0"), 0, 3)
	add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_panel.offset_left = -430
	_panel.offset_top = 90
	_panel.offset_bottom = -20
	_panel.offset_right = -12
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	var col := UiKit.vbox(8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	var head := UiKit.hbox(8)
	col.add_child(head)
	var title := UiKit.label("Debug: Chaos Switch", &"HudLabel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := _small_button("X", func() -> void: toggle())
	head.add_child(close)
	col.add_child(UiKit.label("Warn = announce first. Now = instant.", &"SmallLabel"))
	var i := 0
	for ev in match_ctl.chaos.library:
		i += 1
		var row := UiKit.hbox(6)
		col.add_child(row)
		row.add_child(Icon.new(ev.icon, ev.color.lightened(0.3), 34))
		var name_label := UiKit.label("%d %s" % [i, ev.display_name], &"SmallLabel")
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var id: StringName = ev.id
		row.add_child(_small_button("Warn", func() -> void: match_ctl.chaos.force_event(id, false, 2.0)))
		row.add_child(_small_button("Now", func() -> void: match_ctl.chaos.force_event(id, true)))
		row.add_child(_small_button("End", func() -> void: match_ctl.chaos.end_event(id)))
	var row2 := UiKit.hbox(6)
	col.add_child(row2)
	row2.add_child(_small_button("End all", func() -> void: match_ctl.chaos.end_all_events()))
	_schedule_btn = _small_button("Auto: ON", _toggle_schedule)
	row2.add_child(_schedule_btn)
	row2.add_child(_small_button("Random", func() -> void:
		var ev := match_ctl.chaos.pick_next_event()
		if ev:
			match_ctl.chaos.announce(ev, 2.0)))
	var row3 := UiKit.hbox(6)
	col.add_child(row3)
	row3.add_child(_small_button("+15s", func() -> void: match_ctl.time_left += 15.0))
	row3.add_child(_small_button("Win", func() -> void: match_ctl.request_finish(true)))
	row3.add_child(_small_button("Time up", func() -> void: match_ctl.time_left = 0.05))
	_speed_btn = _small_button("Speed x1", _cycle_speed)
	row3.add_child(_speed_btn)
	_status = UiKit.wrap_label("", &"SmallLabel")
	_status.add_theme_font_size_override("font_size", 18)
	_status.custom_minimum_size.x = 380
	col.add_child(_status)


func _small_button(text: String, cb: Callable) -> Button:
	var b := UiKit.button(text, &"DarkButton", 44)
	b.add_theme_font_size_override("font_size", 18)
	b.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var sb := (b.get_theme_stylebox(state) as StyleBoxFlat).duplicate() as StyleBoxFlat
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 4
		sb.content_margin_bottom = 8
		b.add_theme_stylebox_override(state, sb)
	b.pressed.connect(cb)
	return b


func toggle() -> void:
	visible = not visible
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _toggle_schedule() -> void:
	match_ctl.chaos.auto_schedule = not match_ctl.chaos.auto_schedule
	_schedule_btn.text = "Auto: ON" if match_ctl.chaos.auto_schedule else "Auto: OFF"


func _cycle_speed() -> void:
	var speeds := [1.0, 2.0, 0.5]
	var idx := (speeds.find(Engine.time_scale) + 1) % speeds.size()
	Engine.time_scale = speeds[idx]
	_speed_btn.text = "Speed x%s" % str(speeds[idx])


func _process(_delta: float) -> void:
	if not visible or match_ctl == null:
		return
	var chaos := match_ctl.chaos
	var lines: PackedStringArray = []
	var pending := chaos.get_pending_event()
	if pending:
		lines.append("Coming: %s in %.1fs" % [pending.display_name, chaos.get_pending_time_left()])
	for entry in chaos.get_active_entries():
		lines.append("Active: %s (%.1fs left)" % [(entry.event as ChaosEvent).display_name, entry.left])
	if lines.is_empty():
		lines.append("No chaos right now.")
	lines.append("History: %s" % ", ".join(chaos.get_history().map(func(s): return String(s))))
	for p in match_ctl.players:
		if p.is_human:
			lines.append("%s  gravity x%.2f  speed x%.2f  jump x%.2f  grip x%.2f  size x%.2f%s" % [
				p.display_name, p.stat(&"gravity"), p.stat(&"speed"), p.stat(&"jump"), p.stat(&"traction"),
				p.size_scale, "  REVERSED" if p.is_reversed() else ""])
			break
	lines.append("Round time left: %.1fs   FPS: %d" % [match_ctl.time_left, Engine.get_frames_per_second()])
	_status.text = "\n".join(lines)


func _exit_tree() -> void:
	Engine.time_scale = 1.0
