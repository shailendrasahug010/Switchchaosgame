class_name LicensesOverlay
extends Control
## Full license texts for everything the game ships with (Grown-ups page >
## Software licenses): the Fredoka font (SIL OFL 1.1), the Godot Engine (MIT)
## and the third-party parts inside the engine. Shipping these notices with
## the app is what those licenses ask for.

const FONT_LICENSE := "res://assets/fonts/Fredoka-OFL.txt"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(UiKit.dimmer(0.94))
	var margin := UiKit.margin(28, 18, 28, 18)
	add_child(margin)
	UiKit.full_rect(margin)
	var col := UiKit.vbox(12)
	margin.add_child(col)
	var head := UiKit.hbox(14)
	col.add_child(head)
	var close := UiKit.icon_button("Close", &"back", &"DarkButton", 68)
	close.name = "CloseLicenses"
	close.pressed.connect(queue_free)
	head.add_child(close)
	var title := UiKit.label("Software licenses", &"HeaderLabel")
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	# A TextEdit only lays out the lines on screen, so the long text stays quick.
	var text := TextEdit.new()
	text.name = "LicenseText"
	text.editable = false
	text.context_menu_enabled = false
	text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("font_size", 18)
	text.add_theme_color_override("font_readonly_color", Color("f4f1ff"))
	var bg := UiKit.style(Color("1d1840"), 18, 16)
	for state in ["normal", "focus", "read_only"]:
		text.add_theme_stylebox_override(state, bg)
	text.text = build_text()
	col.add_child(text)
	UiKit.focus_later(close)


static func build_text() -> String:
	var out := PackedStringArray()
	out.append("THE CHAOS SWITCH uses the following software and fonts.\n")
	out.append("== Fredoka font ==")
	var ofl := FileAccess.get_file_as_string(FONT_LICENSE)
	out.append(ofl if ofl != "" else "Fredoka, Copyright 2016 The Fredoka Project Authors. SIL Open Font License 1.1 (https://openfontlicense.org).")
	out.append("\n== Godot Engine ==")
	out.append(Engine.get_license_text())
	out.append("\n== Parts of the Godot Engine made by others ==")
	for info in Engine.get_copyright_info():
		out.append("\n" + String(info.get("name", "")))
		for part in info.get("parts", []):
			for line in part.get("copyright", []):
				out.append("  (c) " + String(line))
			out.append("  License: " + String(part.get("license", "")))
	out.append("\n== License texts ==")
	var licenses := Engine.get_license_info()
	var names := licenses.keys()
	names.sort()
	for name in names:
		out.append("\n-- " + String(name) + " --")
		out.append(String(licenses[name]))
	return "\n".join(out)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		queue_free()
		get_viewport().set_input_as_handled()
