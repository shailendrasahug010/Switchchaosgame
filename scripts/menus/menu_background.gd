class_name MenuBackground
extends Control
## A cheerful animated 2D backdrop for menu screens: a soft gradient with
## slowly drifting stars and bubbles. Drawn in code (no image files).

@export var top_color: Color = Color("7b5cff")
@export var bottom_color: Color = Color("ff7eb6")

var _time := 0.0
var _items: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 26:
		_items.append({
			"x": rng.randf(), "y": rng.randf(), "s": rng.randf_range(10.0, 34.0),
			"speed": rng.randf_range(0.01, 0.035), "kind": [&"star", &"circle", &"heart", &"triangle"][i % 4],
			"phase": rng.randf() * TAU,
			"color": [Color(1, 1, 1, 0.16), Color("ffd23f", 0.22), Color("7dffb0", 0.18), Color("8fd3ff", 0.2)][i % 4],
		})


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var steps := 24
	for i in steps:
		var t := float(i) / steps
		draw_rect(Rect2(0, size.y * t, size.x, size.y / steps + 1.0), top_color.lerp(bottom_color, t))
	for it in _items:
		var y := fposmod(float(it.y) - _time * float(it.speed), 1.0) * (size.y + 80.0) - 40.0
		var x := float(it.x) * size.x + sin(_time * 0.7 + float(it.phase)) * 18.0
		var s: float = it.s
		IconDraw.draw(self, it.kind, Vector2(x - s * 0.5, y - s * 0.5), s, it.color)
