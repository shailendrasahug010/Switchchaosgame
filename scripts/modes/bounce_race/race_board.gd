class_name RaceBoard
extends Control
## HUD widget for Bounce Race: your place and a mini track showing where
## every racer is, with checkpoint flags. Drawn in code.

var mode: BounceRaceMode
var _font: Font


func _init() -> void:
	custom_minimum_size = Vector2(400, 78)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_font = load("res://assets/fonts/fredoka_bold.tres")


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if mode == null:
		return
	draw_style_box(UiKit.style(Color(0.14, 0.12, 0.3, 0.82), 24, 0), Rect2(Vector2.ZERO, size))
	var humans := mode.human_players()
	var tx := 22.0
	if not humans.is_empty():
		var place := mode.place_of(humans[0])
		draw_string(_font, Vector2(14, 28), "PLACE", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.8))
		var col := Color("ffd23f") if place == 1 else Color.WHITE
		draw_string(_font, Vector2(14, 64), UiKit.ordinal(place), HORIZONTAL_ALIGNMENT_LEFT, -1, 32, col)
		tx = 100.0
	# Mini track.
	var x0 := tx
	var x1 := size.x - 30.0
	var y := size.y * 0.55
	draw_line(Vector2(x0, y), Vector2(x1, y), Color(1, 1, 1, 0.25), 8.0, true)
	for cp in mode.checkpoints:
		var t := clampf((mode.start_z - cp.global_position.z) / maxf(mode.start_z - mode.finish_z, 1.0), 0.0, 1.0)
		var cx := lerpf(x0, x1, t)
		draw_line(Vector2(cx, y - 10), Vector2(cx, y + 10), Color(1, 1, 1, 0.45), 3.0)
	IconDraw.draw(self, &"flag", Vector2(x1 - 4, y - 26), 26, Color("ffd23f"))
	# Racers: CPUs small, people big with a ring. People are drawn last (on top).
	var order: Array[PlayerCharacter] = []
	for p in mode.players:
		if not p.is_human:
			order.append(p)
	for p in mode.players:
		if p.is_human:
			order.append(p)
	for p in order:
		var t := mode.progress_of(p) if not p.is_respawning else mode.best_progress_of(p)
		var c := Vector2(lerpf(x0, x1, t), y)
		var col: Color = Catalog.PLAYER_TAG_COLORS[p.player_index % 4]
		if p.is_human:
			draw_circle(c, 13.0, Color.WHITE)
			draw_circle(c, 10.0, col)
			draw_string(_font, Vector2(c.x - 20, y - 16), p.display_name, HORIZONTAL_ALIGNMENT_CENTER, 40, 16, Color.WHITE)
		else:
			draw_circle(c, 8.0, Color(0.1, 0.08, 0.2, 0.9))
			draw_circle(c, 6.0, col)
