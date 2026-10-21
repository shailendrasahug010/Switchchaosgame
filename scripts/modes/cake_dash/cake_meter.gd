class_name CakeMeter
extends Control
## HUD widget for Cake Dash: candles left, how wobbly the cake is and how far
## it has come. Drawn in code; reads the mode every frame.

var mode: CakeDashMode
var _font: Font


func _init() -> void:
	custom_minimum_size = Vector2(380, 74)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_font = load("res://assets/fonts/fredoka_bold.tres")


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if mode == null or mode.cake == null:
		return
	var w := size.x
	var bg := Rect2(Vector2.ZERO, size)
	draw_style_box(UiKit.style(Color(0.14, 0.12, 0.3, 0.82), 24, 0), bg)
	# Cake icon + candles.
	IconDraw.draw(self, &"cake", Vector2(10, 10), 54, Color("ff8fc0"))
	for i in GiantCake.MAX_CANDLES:
		var x := 74.0 + i * 20.0
		var lit := i < mode.cake.candles
		draw_rect(Rect2(x, 34, 9, 28), Color("3f9dff") if lit else Color(1, 1, 1, 0.3))
		if lit:
			draw_circle(Vector2(x + 4.5, 27), 6, Color("ffb13b"))
	# Wobble meter.
	var wob := mode.cake.wobble_amount() if mode.cake.state == GiantCake.State.CARRIED else 0.0
	var mx := 180.0
	var mw := w - mx - 14.0
	draw_string(_font, Vector2(mx, 26), "WOBBLE", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.85))
	draw_rect(Rect2(mx, 32, mw, 12), Color(0, 0, 0, 0.35))
	var col := Color("2fc97a").lerp(Color("ffd23f"), clampf(wob * 2.0, 0.0, 1.0)).lerp(Color("ff5f6d"), clampf(wob * 2.0 - 1.0, 0.0, 1.0))
	draw_rect(Rect2(mx, 32, mw * wob, 12), col)
	# Progress toward the party.
	draw_string(_font, Vector2(mx, 64), "PARTY", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.85))
	var px := mx + 62.0
	var pw := mw - 62.0
	draw_rect(Rect2(px, 54, pw, 8), Color(0, 0, 0, 0.35))
	var prog := mode.progress() if not mode.delivered else 1.0
	draw_rect(Rect2(px, 54, pw * prog, 8), Color("ff8fc0"))
	draw_circle(Vector2(px + pw * prog, 58), 8, Color.WHITE)
	IconDraw.draw(self, &"flag", Vector2(px + pw - 8, 40), 20, Color("ffd23f"))
