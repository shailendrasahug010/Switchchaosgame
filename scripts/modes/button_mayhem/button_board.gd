class_name ButtonBoard
extends Control
## HUD widget for Button Mayhem: which wave this is and the button sequence.
## Each button is a colored badge with its own symbol; the one to press now is
## big and bouncing, finished ones get a check mark. Drawn in code.

const BADGE := 46.0
const GAP := 10.0

var mode: ButtonMayhemMode
var _font: Font
var _time := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(380, 84)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_font = load("res://assets/fonts/fredoka_bold.tres")


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if mode == null:
		return
	draw_style_box(UiKit.style(Color(0.14, 0.12, 0.3, 0.82), 24, 0), Rect2(Vector2.ZERO, size))
	var waves := ButtonMayhemMode.WAVES.size()
	var wave_no := mini(mode.wave + 1, waves)
	draw_string(_font, Vector2(14, 30), "WAVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.8))
	draw_string(_font, Vector2(14, 62), "%d/%d" % [wave_no, waves], HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color.WHITE)
	var seq := mode.sequence
	if seq.is_empty():
		return
	var x0 := 92.0
	var avail := size.x - x0 - 12.0
	var step_w := minf(BADGE + GAP, avail / float(seq.size()))
	var cy := size.y * 0.5
	for i in seq.size():
		var info := Catalog.button_color(seq[i])
		var col: Color = info.color
		var c := Vector2(x0 + step_w * (i + 0.5), cy)
		var r := BADGE * 0.5
		var done := mode.completed or i < mode.step
		var current := not mode.completed and i == mode.step
		if current:
			r *= 1.12 + 0.06 * sin(_time * 6.0)
			draw_circle(c, r + 5.0, Color.WHITE)
		var fill := col if not done else col.darkened(0.35)
		draw_circle(c + Vector2(0, 3), r, Color(0, 0, 0, 0.3))
		draw_circle(c, r, fill)
		var s := r * 1.05
		IconDraw.draw(self, StringName(info.symbol), c - Vector2(s, s) * 0.5, s, Color(1, 1, 1, 0.55 if done else 1.0))
		if done:
			IconDraw.draw(self, &"check", c - Vector2(r, r) * 0.5 + Vector2(r * 0.35, r * 0.3), r, Color("7dffb0"))
		# Little order number under each badge.
		draw_string(_font, Vector2(c.x - 10, size.y - 2), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, 20, 14,
				Color(1, 1, 1, 0.75))
