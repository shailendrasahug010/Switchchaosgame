class_name GrownUpGate
extends Control
## A simple "ask a grown-up" check before settings that grown-ups should
## decide (like switching on online play): type the answer to a sum written
## in words, on a big number pad. It is a speed bump for young children, not
## real security, and the docs say so.

signal passed
signal cancelled

const WORDS := {
	3: "three", 4: "four", 6: "six", 7: "seven", 8: "eight", 9: "nine",
	12: "twelve", 13: "thirteen", 14: "fourteen", 16: "sixteen", 17: "seventeen", 18: "eighteen",
}

var answer := 0
var _entry: Label
var _typed := ""
var _note: Label


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	UiKit.full_rect(self)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var a: int = [12, 13, 14, 16, 17, 18][rng.randi() % 6]
	var b: int = [3, 4, 6, 7, 8, 9][rng.randi() % 6]
	answer = a * b
	add_child(UiKit.dimmer(0.7))
	var center := CenterContainer.new()
	add_child(center)
	UiKit.full_rect(center)
	var card := UiKit.panel(&"CardPanel")
	center.add_child(card)
	var col := UiKit.vbox(10, BoxContainer.ALIGNMENT_CENTER)
	col.custom_minimum_size.x = 520
	card.add_child(col)
	col.add_child(UiKit.label("Grown-ups only", &"DarkHeaderLabel", HORIZONTAL_ALIGNMENT_CENTER))
	var q := UiKit.wrap_label("To continue, type the answer to: %s times %s" % [WORDS[a], WORDS[b]], &"DarkLabel",
			HORIZONTAL_ALIGNMENT_CENTER)
	q.custom_minimum_size.x = 500
	col.add_child(q)
	_entry = UiKit.label("_", &"DarkHeaderLabel", HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_entry)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	col.add_child(grid)
	for n in [1, 2, 3, 4, 5, 6, 7, 8, 9, 0]:
		var key := UiKit.button(str(n), &"BlueButton", 64)
		key.custom_minimum_size.x = 88
		key.pressed.connect(func() -> void: _type(str(n)))
		grid.add_child(key)
	var row := UiKit.hbox(10, BoxContainer.ALIGNMENT_CENTER)
	col.add_child(row)
	var del := UiKit.icon_button("", &"back", &"DarkButton", 64)
	del.pressed.connect(func() -> void:
		_typed = _typed.substr(0, maxi(0, _typed.length() - 1))
		_entry.text = _typed if _typed != "" else "_")
	row.add_child(del)
	var cancel := UiKit.button("Cancel", &"PinkButton", 64)
	cancel.pressed.connect(func() -> void:
		cancelled.emit()
		queue_free())
	row.add_child(cancel)
	var ok := UiKit.button("OK", &"GreenButton", 64)
	ok.custom_minimum_size.x = 120
	ok.pressed.connect(_check)
	row.add_child(ok)
	_note = UiKit.label("", &"DarkSmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_note)
	UiKit.pop_in(card)


func _type(digit: String) -> void:
	if _typed.length() < 4:
		_typed += digit
	_entry.text = _typed


func _check() -> void:
	if _typed != "" and int(_typed) == answer:
		passed.emit()
		queue_free()
	else:
		_typed = ""
		_entry.text = "_"
		_note.text = "That's not it. Please ask a grown-up."
