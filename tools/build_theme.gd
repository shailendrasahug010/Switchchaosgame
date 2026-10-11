extends SceneTree
## Generates res://assets/ui/theme.tres — the shared chunky "toy" look used by
## every menu and the HUD.
##
## Run from the project folder:
##   godot --headless --path . -s tools/build_theme.gd
##
## Re-running overwrites theme.tres. Tweak colors and sizes here rather than in
## the generated file so the look stays consistent.

const OUT := "res://assets/ui/theme.tres"
const FONT_PATH := "res://assets/fonts/Fredoka-Variable.ttf"

const INK := Color("1c1a33")
const NIGHT := Color("241e4c")
const VIOLET := Color("7b5cff")
const PINK := Color("ff5fa8")
const SKY := Color("3f9dff")
const SUN := Color("ffd23f")
const MINT := Color("2fc97a")
const ORANGE := Color("ff8a4c")
const CREAM := Color("fff8ee")
const GREY := Color("8d89a6")


func _init() -> void:
	var theme := Theme.new()
	var base_font: Font = load(FONT_PATH)
	# Font weights are saved as their own files so Label3D signs and name tags
	# can use them too.
	var regular := _save_variation(_variation(base_font, 500), "res://assets/fonts/fredoka_regular.tres")
	var semibold := _save_variation(_variation(base_font, 600), "res://assets/fonts/fredoka_semibold.tres")
	var bold := _save_variation(_variation(base_font, 700), "res://assets/fonts/fredoka_bold.tres")
	theme.default_font = semibold
	theme.default_font_size = 26

	_buttons(theme, semibold, bold)
	_labels(theme, regular, semibold, bold)
	_panels(theme)
	_bars_and_sliders(theme)
	_misc(theme, regular)

	var err := ResourceSaver.save(theme, OUT)
	if err != OK:
		push_error("Could not save theme: %s" % error_string(err))
	else:
		print("Saved ", OUT)
	quit()


func _variation(base: Font, weight: int) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = base
	var ts := TextServerManager.get_primary_interface()
	fv.variation_opentype = {ts.name_to_tag("wght"): weight}
	return fv


func _save_variation(fv: FontVariation, path: String) -> FontVariation:
	var err := ResourceSaver.save(fv, path)
	if err != OK:
		push_error("Could not save %s: %s" % [path, error_string(err)])
		return fv
	# Reload so the theme stores a reference to the file instead of a copy.
	return load(path) as FontVariation


# ---------------------------------------------------------------- buttons

func _box(bg: Color, radius: int = 22) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 10
	sb.anti_aliasing = true
	return sb


## A chunky button face with a darker "lip" underneath, like a toy key.
func _button_face(bg: Color, state: String) -> StyleBoxFlat:
	var sb := _box(bg)
	sb.border_color = bg.darkened(0.32)
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	match state:
		"pressed":
			sb.border_width_bottom = 2
			sb.expand_margin_top = -6
			sb.content_margin_top = 12
			sb.content_margin_bottom = 8
		_:
			sb.border_width_bottom = 8
			sb.content_margin_top = 10
			sb.content_margin_bottom = 16
	return sb


func _set_button_styles(theme: Theme, type_name: String, bg: Color, text: Color) -> void:
	theme.set_stylebox("normal", type_name, _button_face(bg, "normal"))
	theme.set_stylebox("hover", type_name, _button_face(bg.lightened(0.12), "normal"))
	theme.set_stylebox("hover_pressed", type_name, _button_face(bg.darkened(0.06), "pressed"))
	theme.set_stylebox("pressed", type_name, _button_face(bg.darkened(0.06), "pressed"))
	var disabled := _button_face(GREY, "normal")
	disabled.bg_color.a = 0.6
	theme.set_stylebox("disabled", type_name, disabled)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.set_border_width_all(5)
	focus.border_color = SUN
	focus.set_corner_radius_all(26)
	focus.set_expand_margin_all(5)
	theme.set_stylebox("focus", type_name, focus)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		theme.set_color(c, type_name, text)
	theme.set_color("font_disabled_color", type_name, Color(1, 1, 1, 0.55))


func _buttons(theme: Theme, semibold: Font, bold: Font) -> void:
	_set_button_styles(theme, "Button", VIOLET, Color.WHITE)
	theme.set_font("font", "Button", semibold)
	theme.set_font_size("font_size", "Button", 30)
	theme.set_constant("h_separation", "Button", 12)
	theme.set_constant("icon_max_width", "Button", 56)

	var variants := {
		"PinkButton": [PINK, Color.WHITE],
		"BlueButton": [SKY, Color.WHITE],
		"GreenButton": [MINT, Color.WHITE],
		"OrangeButton": [ORANGE, Color.WHITE],
		"YellowButton": [SUN, INK],
		"DarkButton": [NIGHT.lightened(0.12), Color.WHITE],
	}
	for type_name: String in variants:
		theme.set_type_variation(type_name, "Button")
		_set_button_styles(theme, type_name, variants[type_name][0], variants[type_name][1])

	theme.set_type_variation("BigButton", "Button")
	_set_button_styles(theme, "BigButton", PINK, Color.WHITE)
	theme.set_font("font", "BigButton", bold)
	theme.set_font_size("font_size", "BigButton", 46)

	# Flat, borderless button for list rows and small round icon buttons.
	theme.set_type_variation("GhostButton", "Button")
	var ghost := _box(Color(1, 1, 1, 0.12), 18)
	ghost.set_content_margin_all(12)
	theme.set_stylebox("normal", "GhostButton", ghost)
	var ghost_hover := ghost.duplicate() as StyleBoxFlat
	ghost_hover.bg_color = Color(1, 1, 1, 0.22)
	theme.set_stylebox("hover", "GhostButton", ghost_hover)
	theme.set_stylebox("pressed", "GhostButton", ghost_hover)
	theme.set_stylebox("hover_pressed", "GhostButton", ghost_hover)
	theme.set_stylebox("disabled", "GhostButton", ghost)
	theme.set_stylebox("focus", "GhostButton", theme.get_stylebox("focus", "Button"))


# ---------------------------------------------------------------- labels

func _label_variant(theme: Theme, type_name: String, font: Font, size: int, color: Color,
		outline: int, outline_color: Color = NIGHT) -> void:
	theme.set_type_variation(type_name, "Label")
	theme.set_font("font", type_name, font)
	theme.set_font_size("font_size", type_name, size)
	theme.set_color("font_color", type_name, color)
	theme.set_constant("outline_size", type_name, outline)
	theme.set_color("font_outline_color", type_name, outline_color)


func _labels(theme: Theme, regular: Font, semibold: Font, bold: Font) -> void:
	theme.set_color("font_color", "Label", Color.WHITE)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	theme.set_font_size("font_size", "Label", 26)
	theme.set_constant("line_spacing", "Label", 2)
	_label_variant(theme, "TitleLabel", bold, 84, SUN, 18)
	_label_variant(theme, "HeaderLabel", bold, 48, Color.WHITE, 12)
	_label_variant(theme, "SubHeaderLabel", bold, 34, Color.WHITE, 9)
	_label_variant(theme, "BodyLabel", regular, 26, Color.WHITE, 0)
	_label_variant(theme, "SmallLabel", regular, 21, Color(1, 1, 1, 0.85), 0)
	_label_variant(theme, "HudLabel", semibold, 30, Color.WHITE, 10)
	_label_variant(theme, "HudBigLabel", bold, 60, Color.WHITE, 14)
	_label_variant(theme, "HudHugeLabel", bold, 120, SUN, 24)
	_label_variant(theme, "DarkLabel", semibold, 26, INK, 0)
	_label_variant(theme, "DarkSmallLabel", regular, 21, INK.lightened(0.15), 0)
	_label_variant(theme, "DarkHeaderLabel", bold, 40, INK, 0)


# ---------------------------------------------------------------- panels

func _panels(theme: Theme) -> void:
	var dark := _box(Color(NIGHT, 0.92), 30)
	dark.border_color = VIOLET.lightened(0.15)
	dark.set_border_width_all(4)
	dark.set_content_margin_all(26)
	dark.shadow_color = Color(0, 0, 0, 0.25)
	dark.shadow_size = 10
	dark.shadow_offset = Vector2(0, 6)
	theme.set_stylebox("panel", "PanelContainer", dark)
	theme.set_stylebox("panel", "Panel", dark)

	theme.set_type_variation("CardPanel", "PanelContainer")
	var card := _box(CREAM, 28)
	card.border_color = Color("e8d9f2")
	card.border_width_bottom = 8
	card.set_content_margin_all(22)
	card.content_margin_bottom = 28
	theme.set_stylebox("panel", "CardPanel", card)

	theme.set_type_variation("ChipPanel", "PanelContainer")
	var chip := _box(Color(NIGHT, 0.78), 40)
	chip.content_margin_left = 18
	chip.content_margin_right = 18
	chip.content_margin_top = 6
	chip.content_margin_bottom = 8
	theme.set_stylebox("panel", "ChipPanel", chip)

	theme.set_type_variation("ClearPanel", "PanelContainer")
	var clear := StyleBoxEmpty.new()
	theme.set_stylebox("panel", "ClearPanel", clear)


# ---------------------------------------------------------------- bars & sliders

func _circle_texture(diameter: int, fill: Color, rim: Color) -> ImageTexture:
	var img := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	var r := diameter * 0.5
	for y in diameter:
		for x in diameter:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var a := clampf(r - d, 0.0, 1.0)
			var c := fill if d < r - 5.0 else rim
			img.set_pixel(x, y, Color(c, c.a * a))
	return ImageTexture.create_from_image(img)


func _bars_and_sliders(theme: Theme) -> void:
	var bg := _box(Color(NIGHT, 0.55), 14)
	bg.set_content_margin_all(0)
	var fill := _box(MINT, 14)
	theme.set_stylebox("background", "ProgressBar", bg)
	theme.set_stylebox("fill", "ProgressBar", fill)
	theme.set_font_size("font_size", "ProgressBar", 18)
	theme.set_color("font_color", "ProgressBar", Color.WHITE)

	var track := _box(Color(NIGHT, 0.6), 12)
	track.content_margin_top = 10
	track.content_margin_bottom = 10
	var filled := _box(PINK, 12)
	filled.content_margin_top = 10
	filled.content_margin_bottom = 10
	theme.set_stylebox("slider", "HSlider", track)
	theme.set_stylebox("grabber_area", "HSlider", filled)
	theme.set_stylebox("grabber_area_highlight", "HSlider", filled)
	var grab := _circle_texture(44, Color.WHITE, PINK.darkened(0.2))
	theme.set_icon("grabber", "HSlider", grab)
	theme.set_icon("grabber_highlight", "HSlider", grab)
	theme.set_constant("center_grabber", "HSlider", 1)


func _misc(theme: Theme, regular: Font) -> void:
	# Big friendly scroll bars for touch.
	var scroll_bg := _box(Color(1, 1, 1, 0.08), 10)
	scroll_bg.content_margin_left = 6
	scroll_bg.content_margin_right = 6
	var grab := _box(Color(1, 1, 1, 0.45), 10)
	grab.content_margin_left = 6
	grab.content_margin_right = 6
	theme.set_stylebox("scroll", "VScrollBar", scroll_bg)
	theme.set_stylebox("grabber", "VScrollBar", grab)
	theme.set_stylebox("grabber_highlight", "VScrollBar", grab)
	theme.set_stylebox("grabber_pressed", "VScrollBar", grab)

	var edit := _box(CREAM, 16)
	edit.set_content_margin_all(14)
	edit.border_color = VIOLET
	edit.set_border_width_all(3)
	theme.set_stylebox("normal", "LineEdit", edit)
	var edit_focus := edit.duplicate() as StyleBoxFlat
	edit_focus.border_color = SUN
	theme.set_stylebox("focus", "LineEdit", edit_focus)
	theme.set_color("font_color", "LineEdit", INK)
	theme.set_color("caret_color", "LineEdit", INK)
	theme.set_color("font_placeholder_color", "LineEdit", Color(INK, 0.45))
	theme.set_font("font", "LineEdit", regular)
	theme.set_font_size("font_size", "LineEdit", 28)

	theme.set_constant("separation", "VBoxContainer", 14)
	theme.set_constant("separation", "HBoxContainer", 14)
	theme.set_constant("h_separation", "GridContainer", 14)
	theme.set_constant("v_separation", "GridContainer", 14)
