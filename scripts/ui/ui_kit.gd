class_name UiKit
extends RefCounted
## Small helpers so every screen is built the same way with the shared theme.

const INK := Color("1c1a33")
const NIGHT := Color("241e4c")
const VIOLET := Color("7b5cff")
const PINK := Color("ff5fa8")
const SKY := Color("3f9dff")
const SUN := Color("ffd23f")
const MINT := Color("2fc97a")
const ORANGE := Color("ff8a4c")
const CREAM := Color("fff8ee")


static func label(text: String, variation: StringName = &"", align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	if variation != &"":
		l.theme_type_variation = variation
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func wrap_label(text: String, variation: StringName = &"", align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := label(text, variation, align)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 120
	return l


static func button(text: String, variation: StringName = &"", min_height: float = 78.0) -> Button:
	var b := Button.new()
	b.text = text
	if variation != &"":
		b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(0, min_height)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(func() -> void: _click_sound())
	return b


## A button showing a vector icon next to (or instead of) its text.
static func icon_button(text: String, icon: StringName, variation: StringName = &"", min_height: float = 78.0,
		icon_color: Color = Color.WHITE) -> Button:
	var b := button("", variation, min_height)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 12)
	var ic := Icon.new(icon, icon_color, min_height * 0.46)
	row.add_child(ic)
	if text != "":
		var l := label(text)
		var font_size := b.get_theme_font_size("font_size")
		l.add_theme_font_size_override("font_size", font_size)
		var col := b.get_theme_color("font_color")
		l.add_theme_color_override("font_color", col)
		l.add_theme_font_override("font", b.get_theme_font("font"))
		l.name = "Text"
		row.add_child(l)
		b.custom_minimum_size.x = maxf(b.custom_minimum_size.x, min_height * 0.5 + 60 + text.length() * font_size * 0.55)
	else:
		b.custom_minimum_size.x = maxf(b.custom_minimum_size.x, min_height)
	b.add_child(row)
	return b


static func set_icon_button_text(b: Button, text: String) -> void:
	var l := b.find_child("Text", true, false) as Label
	if l:
		l.text = text


static func panel(variation: StringName = &"") -> PanelContainer:
	var p := PanelContainer.new()
	if variation != &"":
		p.theme_type_variation = variation
	return p


## A rounded panel with its own colors.
static func color_panel(bg: Color, radius: int = 26, margin: int = 18, border: Color = Color(0, 0, 0, 0),
		border_bottom: int = 0, border_all: int = 0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", style(bg, radius, margin, border, border_bottom, border_all))
	return p


static func style(bg: Color, radius: int = 26, margin: int = 18, border: Color = Color(0, 0, 0, 0),
		border_bottom: int = 0, border_all: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 8
	sb.set_content_margin_all(margin)
	if border.a > 0.0:
		sb.border_color = border
		if border_all > 0:
			sb.set_border_width_all(border_all)
		sb.border_width_bottom = maxi(border_bottom, border_all)
		sb.content_margin_bottom = margin + maxi(border_bottom, border_all)
	return sb


static func vbox(separation: int = 14, align: BoxContainer.AlignmentMode = BoxContainer.ALIGNMENT_BEGIN) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", separation)
	b.alignment = align
	return b


static func hbox(separation: int = 14, align: BoxContainer.AlignmentMode = BoxContainer.ALIGNMENT_BEGIN) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", separation)
	b.alignment = align
	return b


static func margin(left: int, top: int = -1, right: int = -1, bottom: int = -1) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", left)
	m.add_theme_constant_override("margin_top", left if top < 0 else top)
	m.add_theme_constant_override("margin_right", left if right < 0 else right)
	m.add_theme_constant_override("margin_bottom", (left if top < 0 else top) if bottom < 0 else bottom)
	return m


static func spacer(min_size: float = 0.0, vertical: bool = true) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if vertical:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
		c.custom_minimum_size.y = min_size
	else:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.custom_minimum_size.x = min_size
	return c


static func full_rect(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c


## A dimmed backdrop that blocks clicks to whatever is behind it.
static func dimmer(alpha: float = 0.55) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.08, 0.06, 0.18, alpha)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	full_rect(r)
	return r


## Springy entrance animation. Respects the "reduced motion" setting.
static func pop_in(c: Control, delay: float = 0.0, from_scale: float = 0.6) -> void:
	if not c.is_inside_tree():
		await c.tree_entered
	if _reduced_motion():
		c.modulate.a = 1.0
		return
	var tree := c.get_tree()
	await tree.process_frame
	# The screen may have closed during that frame.
	if not is_instance_valid(c) or not c.is_inside_tree():
		return
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2.ONE * from_scale
	c.modulate.a = 0.0
	var t := c.create_tween().set_parallel(true)
	t.tween_property(c, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(delay)
	t.tween_property(c, "modulate:a", 1.0, 0.2).set_delay(delay)


## Gives [param c] keyboard/gamepad focus at the end of this frame, if it is
## still on screen by then.
static func focus_later(c: Control) -> void:
	(func() -> void:
		if is_instance_valid(c) and c.is_inside_tree() and c.is_visible_in_tree():
			c.grab_focus()).call_deferred()


static func _reduced_motion() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	var gs := tree.root.get_node_or_null("GameState")
	return gs != null and bool(gs.get_setting("reduced_motion", false))


static func _click_sound() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var audio := tree.root.get_node_or_null("AudioManager")
	if audio:
		audio.play(&"ui_click")


static func format_time(seconds: float) -> String:
	var s := maxi(0, ceili(seconds))
	return "%d:%02d" % [s / 60, s % 60]


static func ordinal(n: int) -> String:
	match n:
		1:
			return "1st"
		2:
			return "2nd"
		3:
			return "3rd"
	return "%dth" % n
