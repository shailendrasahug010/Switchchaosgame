@tool
class_name CharacterPortrait
extends Control
## A flat 2D portrait of a toy creature for menus, score chips and results.
## Drawn in code so it always matches the character's shape and colors.

@export var character_id: StringName = &"bloop":
	set(v):
		character_id = v
		queue_redraw()
@export var paint_id: StringName = &"classic":
	set(v):
		paint_id = v
		queue_redraw()
@export var hat_id: StringName = &"none":
	set(v):
		hat_id = v
		queue_redraw()
@export var happy: bool = false:
	set(v):
		happy = v
		queue_redraw()
## Draw a soft circular backdrop.
@export var backdrop: Color = Color(0, 0, 0, 0):
	set(v):
		backdrop = v
		queue_redraw()


func _init(p_character: StringName = &"bloop", p_size: float = 64.0) -> void:
	character_id = p_character
	custom_minimum_size = Vector2(p_size, p_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var c := o + Vector2(s * 0.5, s * 0.56)
	if backdrop.a > 0.0:
		draw_circle(o + Vector2(s, s) * 0.5, s * 0.5, backdrop)
	var info := Catalog.character(character_id)
	var body := Catalog.body_color(character_id, paint_id)
	var dark := body.darkened(0.25)
	var shape: StringName = info.shape
	var top_y := c.y
	match shape:
		&"ball":
			draw_circle(c + Vector2(0, s * 0.02), s * 0.35, dark)
			draw_circle(c, s * 0.34, body)
			top_y = c.y - s * 0.34
		&"bean":
			var w := s * 0.27
			draw_rect(Rect2(c + Vector2(-w, -s * 0.2), Vector2(w * 2.0, s * 0.42)), body)
			draw_circle(c + Vector2(0, -s * 0.2), w, body)
			draw_circle(c + Vector2(0, s * 0.22), w, body)
			top_y = c.y - s * 0.2 - w
		&"gumdrop":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.36, s * 0.3), c + Vector2(-s * 0.27, -s * 0.12),
					c + Vector2(s * 0.27, -s * 0.12), c + Vector2(s * 0.36, s * 0.3)]), body)
			draw_circle(c + Vector2(0, -s * 0.12), s * 0.27, body)
			draw_rect(Rect2(c + Vector2(-s * 0.36, s * 0.22), Vector2(s * 0.72, s * 0.1)), dark)
			top_y = c.y - s * 0.39
		_:
			var pts := PackedVector2Array()
			for i in 32:
				var a := TAU * i / 32.0
				var ry := s * (0.38 if sin(a) < 0.0 else 0.32)
				pts.append(c + Vector2(cos(a) * s * 0.3, sin(a) * ry + s * 0.02))
			draw_colored_polygon(pts, body)
			top_y = c.y - s * 0.36
	# Belly
	draw_circle(c + Vector2(0, s * 0.12), s * 0.14, body.lightened(0.35))
	# Eyes
	var eye_y := c.y - s * 0.06
	for side: float in [-1.0, 1.0]:
		var e := Vector2(c.x + side * s * 0.11, eye_y)
		if happy:
			draw_arc(e + Vector2(0, s * 0.02), s * 0.06, PI, TAU, 10, Color("1c1a33"), s * 0.03, true)
		else:
			draw_circle(e, s * 0.085, Color.WHITE)
			draw_circle(e + Vector2(side * -s * 0.01, s * 0.015), s * 0.048, Color("1c1a33"))
			draw_circle(e + Vector2(-s * 0.02, -s * 0.02), s * 0.017, Color.WHITE)
		draw_circle(Vector2(c.x + side * s * 0.21, eye_y + s * 0.08), s * 0.035, Color(1.0, 0.56, 0.76, 0.8))
	# Accessory hint
	var acc_col: Color = info.accent
	match info.accessory:
		&"antenna":
			draw_line(Vector2(c.x + s * 0.03, top_y + s * 0.02), Vector2(c.x + s * 0.08, top_y - s * 0.1), body.darkened(0.2), s * 0.025)
			draw_circle(Vector2(c.x + s * 0.09, top_y - s * 0.12), s * 0.045, acc_col)
		&"bunny_ears":
			for side: float in [-1.0, 1.0]:
				var base := Vector2(c.x + side * s * 0.1, top_y + s * 0.03)
				draw_colored_polygon(PackedVector2Array([base + Vector2(-s * 0.05, 0), base + Vector2(side * s * 0.05, -s * 0.24),
						base + Vector2(s * 0.05, 0)]), body)
		&"sprout":
			draw_line(Vector2(c.x, top_y + s * 0.01), Vector2(c.x, top_y - s * 0.07), Color(0.24, 0.55, 0.22), s * 0.02)
			draw_circle(Vector2(c.x - s * 0.05, top_y - s * 0.08), s * 0.04, acc_col)
			draw_circle(Vector2(c.x + s * 0.05, top_y - s * 0.08), s * 0.04, Color(0.45, 0.85, 0.3))
		&"propeller":
			draw_rect(Rect2(Vector2(c.x - s * 0.12, top_y - s * 0.02), Vector2(s * 0.24, s * 0.05)), acc_col)
			draw_line(Vector2(c.x - s * 0.15, top_y - s * 0.06), Vector2(c.x + s * 0.15, top_y - s * 0.06), Color(0.36, 0.72, 1.0), s * 0.025)
	# Hat hint
	match hat_id:
		&"party_hat":
			draw_colored_polygon(PackedVector2Array([Vector2(c.x - s * 0.12, top_y + s * 0.03), Vector2(c.x + s * 0.02, top_y - s * 0.2),
					Vector2(c.x + s * 0.12, top_y + s * 0.03)]), Color(1.0, 0.36, 0.55))
		&"crown":
			draw_colored_polygon(PackedVector2Array([Vector2(c.x - s * 0.13, top_y + s * 0.03), Vector2(c.x - s * 0.13, top_y - s * 0.08),
					Vector2(c.x - s * 0.06, top_y - s * 0.02), Vector2(c.x, top_y - s * 0.1), Vector2(c.x + s * 0.06, top_y - s * 0.02),
					Vector2(c.x + s * 0.13, top_y - s * 0.08), Vector2(c.x + s * 0.13, top_y + s * 0.03)]), Color(1.0, 0.8, 0.2))
		&"top_hat":
			draw_rect(Rect2(Vector2(c.x - s * 0.14, top_y - s * 0.01), Vector2(s * 0.28, s * 0.04)), Color(0.15, 0.13, 0.2))
			draw_rect(Rect2(Vector2(c.x - s * 0.09, top_y - s * 0.16), Vector2(s * 0.18, s * 0.16)), Color(0.15, 0.13, 0.2))
		&"chef_hat":
			draw_rect(Rect2(Vector2(c.x - s * 0.1, top_y - s * 0.06), Vector2(s * 0.2, s * 0.08)), Color.WHITE)
			draw_circle(Vector2(c.x, top_y - s * 0.1), s * 0.11, Color.WHITE)
		&"bow":
			draw_colored_polygon(PackedVector2Array([Vector2(c.x + s * 0.12, top_y + s * 0.04), Vector2(c.x + s * 0.02, top_y - s * 0.04),
					Vector2(c.x + s * 0.02, top_y + s * 0.1)]), Color(1.0, 0.33, 0.55))
			draw_colored_polygon(PackedVector2Array([Vector2(c.x + s * 0.12, top_y + s * 0.04), Vector2(c.x + s * 0.22, top_y - s * 0.04),
					Vector2(c.x + s * 0.22, top_y + s * 0.1)]), Color(1.0, 0.33, 0.55))
		&"flower":
			for i in 5:
				var a := TAU * i / 5.0
				draw_circle(Vector2(c.x + s * 0.16, top_y + s * 0.04) + Vector2(cos(a), sin(a)) * s * 0.035, s * 0.03, Color(1.0, 0.55, 0.8))
			draw_circle(Vector2(c.x + s * 0.16, top_y + s * 0.04), s * 0.022, Color(1.0, 0.86, 0.25))
		&"shades":
			for side: float in [-1.0, 1.0]:
				draw_circle(Vector2(c.x + side * s * 0.11, eye_y), s * 0.075, Color(0.12, 0.12, 0.18))
			draw_line(Vector2(c.x - s * 0.04, eye_y - s * 0.02), Vector2(c.x + s * 0.04, eye_y - s * 0.02), Color(0.12, 0.12, 0.18), s * 0.02)
		&"headphones":
			draw_arc(Vector2(c.x, eye_y), s * 0.3, PI * 1.05, TAU * 0.98, 16, Color(0.3, 0.3, 0.4), s * 0.03)
			for side: float in [-1.0, 1.0]:
				draw_circle(Vector2(c.x + side * s * 0.3, eye_y + s * 0.02), s * 0.06, acc_col)
