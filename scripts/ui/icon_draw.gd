class_name IconDraw
extends RefCounted
## Vector icons drawn with CanvasItem calls, so the UI needs no image files.
## Every icon fits a square of side [param s] at [param o] (top-left corner).

const INK := Color("1c1a33")


static func draw(ci: CanvasItem, icon: StringName, o: Vector2, s: float, color: Color) -> void:
	var c := o + Vector2(s, s) * 0.5
	var r := s * 0.5
	match icon:
		&"star":
			_star(ci, c, r * 0.95, r * 0.42, color)
		&"heart":
			_heart(ci, c, r * 0.9, color)
		&"circle":
			ci.draw_circle(c, r * 0.8, color)
		&"square":
			ci.draw_rect(Rect2(c - Vector2(r, r) * 0.72, Vector2(r, r) * 1.44), color)
		&"triangle":
			_poly(ci, [c + Vector2(0, -r * 0.85), c + Vector2(r * 0.9, r * 0.7), c + Vector2(-r * 0.9, r * 0.7)], color)
		&"plus":
			ci.draw_rect(Rect2(c - Vector2(r * 0.28, r * 0.85), Vector2(r * 0.56, r * 1.7)), color)
			ci.draw_rect(Rect2(c - Vector2(r * 0.85, r * 0.28), Vector2(r * 1.7, r * 0.56)), color)
		&"diamond":
			_poly(ci, [c + Vector2(0, -r * 0.9), c + Vector2(r * 0.75, 0), c + Vector2(0, r * 0.9), c + Vector2(-r * 0.75, 0)], color)
		&"buttons":
			var cols: Array[Color] = [Color("ff5f6d"), Color("3f9dff"), Color("ffd23f")]
			for i in 3:
				var bc := c + Vector2((i - 1) * r * 0.62, (r * 0.25 if i == 1 else -r * 0.2))
				ci.draw_circle(bc + Vector2(0, r * 0.08), r * 0.34, Color(0, 0, 0, 0.25 * color.a))
				ci.draw_circle(bc, r * 0.34, Color(cols[i], color.a))
				ci.draw_circle(bc + Vector2(-r * 0.1, -r * 0.1), r * 0.09, Color(1, 1, 1, 0.6 * color.a))
		&"pause":
			ci.draw_rect(Rect2(c + Vector2(-r * 0.55, -r * 0.6), Vector2(r * 0.38, r * 1.2)), color)
			ci.draw_rect(Rect2(c + Vector2(r * 0.17, -r * 0.6), Vector2(r * 0.38, r * 1.2)), color)
		&"play":
			_poly(ci, [c + Vector2(-r * 0.45, -r * 0.65), c + Vector2(r * 0.7, 0), c + Vector2(-r * 0.45, r * 0.65)], color)
		&"back":
			_arrow(ci, c, r, Vector2.LEFT, color)
		&"next":
			_arrow(ci, c, r, Vector2.RIGHT, color)
		&"up":
			_arrow(ci, c, r, Vector2.UP, color)
		&"down":
			_arrow(ci, c, r, Vector2.DOWN, color)
		&"restart":
			ci.draw_arc(c, r * 0.62, deg_to_rad(-60), deg_to_rad(240), 24, color, r * 0.24, true)
			_poly(ci, [c + Vector2(r * 0.25, -r * 0.95), c + Vector2(r * 0.75, -r * 0.45), c + Vector2(r * 0.12, -r * 0.3)], color)
		&"gear":
			for i in 8:
				var a := TAU * i / 8.0
				var d := Vector2(cos(a), sin(a))
				ci.draw_line(c + d * r * 0.45, c + d * r * 0.92, color, r * 0.32)
			ci.draw_circle(c, r * 0.62, color)
			ci.draw_circle(c, r * 0.26, color.darkened(0.55))
		&"lock":
			ci.draw_arc(c + Vector2(0, -r * 0.15), r * 0.42, PI, TAU, 16, color, r * 0.18, true)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.62, -r * 0.12), Vector2(r * 1.24, r * 0.95)), color)
		&"check":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.6, 0), c + Vector2(-r * 0.15, r * 0.45),
					c + Vector2(r * 0.65, -r * 0.5)]), color, r * 0.28, true)
		&"cross":
			ci.draw_line(c + Vector2(-r, -r) * 0.55, c + Vector2(r, r) * 0.55, color, r * 0.28, true)
			ci.draw_line(c + Vector2(r, -r) * 0.55, c + Vector2(-r, r) * 0.55, color, r * 0.28, true)
		&"clock":
			ci.draw_circle(c, r * 0.85, color)
			ci.draw_circle(c, r * 0.65, Color.WHITE)
			ci.draw_line(c, c + Vector2(0, -r * 0.45), INK, r * 0.14, true)
			ci.draw_line(c, c + Vector2(r * 0.32, 0), INK, r * 0.14, true)
		&"trophy":
			_poly(ci, [c + Vector2(-r * 0.6, -r * 0.75), c + Vector2(r * 0.6, -r * 0.75), c + Vector2(r * 0.4, r * 0.05),
					c + Vector2(-r * 0.4, r * 0.05)], color)
			ci.draw_arc(c + Vector2(-r * 0.62, -r * 0.4), r * 0.26, PI * 0.5, PI * 1.5, 10, color, r * 0.13)
			ci.draw_arc(c + Vector2(r * 0.62, -r * 0.4), r * 0.26, -PI * 0.5, PI * 0.5, 10, color, r * 0.13)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.12, 0), Vector2(r * 0.24, r * 0.5)), color)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.5, r * 0.5), Vector2(r * 1.0, r * 0.3)), color)
		&"cake":
			ci.draw_rect(Rect2(c + Vector2(-r * 0.8, -r * 0.05), Vector2(r * 1.6, r * 0.75)), color)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.55, -r * 0.5), Vector2(r * 1.1, r * 0.5)), color.lightened(0.3))
			for i in 3:
				var x := -r * 0.35 + i * r * 0.35
				ci.draw_rect(Rect2(c + Vector2(x - r * 0.05, -r * 0.85), Vector2(r * 0.1, r * 0.35)), Color.WHITE)
				ci.draw_circle(c + Vector2(x, -r * 0.92), r * 0.09, Color("ffb13b"))
		&"flag":
			ci.draw_rect(Rect2(c + Vector2(-r * 0.6, -r * 0.85), Vector2(r * 0.16, r * 1.7)), color.darkened(0.3))
			_poly(ci, [c + Vector2(-r * 0.44, -r * 0.85), c + Vector2(r * 0.75, -r * 0.5), c + Vector2(-r * 0.44, -r * 0.1)], color)
		&"hand":
			ci.draw_circle(c + Vector2(0, r * 0.15), r * 0.55, color)
			for i in 4:
				ci.draw_rect(Rect2(c + Vector2(-r * 0.5 + i * r * 0.27, -r * 0.8), Vector2(r * 0.2, r * 0.8)), color)
			ci.draw_rect(Rect2(c + Vector2(r * 0.4, -r * 0.1), Vector2(r * 0.42, r * 0.2)), color)
		&"bell":
			_poly(ci, [c + Vector2(-r * 0.7, r * 0.45), c + Vector2(-r * 0.45, -r * 0.4), c + Vector2(0, -r * 0.7),
					c + Vector2(r * 0.45, -r * 0.4), c + Vector2(r * 0.7, r * 0.45)], color)
			ci.draw_circle(c + Vector2(0, r * 0.6), r * 0.18, color)
		&"lever":
			ci.draw_line(c + Vector2(0, r * 0.6), c + Vector2(r * 0.45, -r * 0.6), color, r * 0.2, true)
			ci.draw_circle(c + Vector2(r * 0.45, -r * 0.65), r * 0.25, color)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.6, r * 0.5), Vector2(r * 1.2, r * 0.3)), color.darkened(0.3))
		&"person":
			ci.draw_circle(c + Vector2(0, -r * 0.35), r * 0.38, color)
			ci.draw_circle(c + Vector2(0, r * 0.65), r * 0.62, color)
		&"cpu":
			ci.draw_rect(Rect2(c - Vector2(r, r) * 0.6, Vector2(r, r) * 1.2), color)
			ci.draw_circle(c + Vector2(-r * 0.25, -r * 0.1), r * 0.14, INK)
			ci.draw_circle(c + Vector2(r * 0.25, -r * 0.1), r * 0.14, INK)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.3, r * 0.2), Vector2(r * 0.6, r * 0.1)), INK)
		&"globe":
			ci.draw_circle(c, r * 0.85, color)
			ci.draw_arc(c, r * 0.85, 0, TAU, 24, color.darkened(0.4), r * 0.1, true)
			ci.draw_line(c + Vector2(-r * 0.85, 0), c + Vector2(r * 0.85, 0), color.darkened(0.4), r * 0.08)
			ci.draw_arc(c, r * 0.42, -PI * 0.5, PI * 0.5, 12, color.darkened(0.4), r * 0.08)
			ci.draw_arc(c, r * 0.42, PI * 0.5, PI * 1.5, 12, color.darkened(0.4), r * 0.08)
		&"shirt":
			_poly(ci, [c + Vector2(-r * 0.35, -r * 0.75), c + Vector2(-r * 0.9, -r * 0.4), c + Vector2(-r * 0.65, 0),
					c + Vector2(-r * 0.45, -r * 0.1), c + Vector2(-r * 0.45, r * 0.8), c + Vector2(r * 0.45, r * 0.8),
					c + Vector2(r * 0.45, -r * 0.1), c + Vector2(r * 0.65, 0), c + Vector2(r * 0.9, -r * 0.4),
					c + Vector2(r * 0.35, -r * 0.75), c + Vector2(0, -r * 0.5)], color)
		&"info":
			ci.draw_circle(c, r * 0.85, color)
			ci.draw_circle(c + Vector2(0, -r * 0.4), r * 0.13, INK)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.1, -r * 0.15), Vector2(r * 0.2, r * 0.65)), INK)
		&"bug":
			ci.draw_circle(c + Vector2(0, r * 0.1), r * 0.55, color)
			ci.draw_circle(c + Vector2(0, -r * 0.5), r * 0.3, color)
			for side: float in [-1.0, 1.0]:
				for i in 3:
					ci.draw_line(c + Vector2(side * r * 0.4, -r * 0.2 + i * r * 0.35),
							c + Vector2(side * r * 0.9, -r * 0.35 + i * r * 0.4), color, r * 0.1)
		&"sound":
			_poly(ci, [c + Vector2(-r * 0.8, -r * 0.25), c + Vector2(-r * 0.4, -r * 0.25), c + Vector2(0, -r * 0.65),
					c + Vector2(0, r * 0.65), c + Vector2(-r * 0.4, r * 0.25), c + Vector2(-r * 0.8, r * 0.25)], color)
			ci.draw_arc(c + Vector2(r * 0.1, 0), r * 0.4, -PI * 0.3, PI * 0.3, 8, color, r * 0.12)
			ci.draw_arc(c + Vector2(r * 0.1, 0), r * 0.7, -PI * 0.3, PI * 0.3, 8, color, r * 0.12)
		# ---- chaos events
		&"moon":
			_crescent(ci, c, r * 0.85, color)
		&"penguin":
			ci.draw_circle(c + Vector2(0, r * 0.1), r * 0.75, INK)
			ci.draw_circle(c + Vector2(0, r * 0.25), r * 0.5, Color.WHITE)
			ci.draw_circle(c + Vector2(-r * 0.2, -r * 0.25), r * 0.1, Color.WHITE)
			ci.draw_circle(c + Vector2(r * 0.2, -r * 0.25), r * 0.1, Color.WHITE)
			_poly(ci, [c + Vector2(-r * 0.15, -r * 0.05), c + Vector2(r * 0.15, -r * 0.05), c + Vector2(0, r * 0.15)], Color("ff9a1f"))
		&"ice":
			for i in 3:
				var a := PI * i / 3.0
				var d := Vector2(cos(a), sin(a)) * r * 0.85
				ci.draw_line(c - d, c + d, color, r * 0.16, true)
			ci.draw_circle(c, r * 0.2, color)
		&"giant":
			_arrow(ci, c + Vector2(0, -r * 0.05), r, Vector2.UP, color)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.85, r * 0.7), Vector2(r * 1.7, r * 0.18)), color)
		&"tiny":
			ci.draw_circle(c + Vector2(0, r * 0.35), r * 0.32, color)
			_arrow(ci, c + Vector2(0, -r * 0.35), r * 0.55, Vector2.DOWN, color)
		&"bounce":
			for i in 4:
				var y := r * 0.55 - i * r * 0.32
				ci.draw_line(c + Vector2(-r * 0.5, y), c + Vector2(r * 0.5, y - r * 0.16), color, r * 0.13, true)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.7, -r * 0.85), Vector2(r * 1.4, r * 0.22)), color)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.7, r * 0.65), Vector2(r * 1.4, r * 0.22)), color)
		&"reverse":
			_arrow(ci, c + Vector2(0, -r * 0.35), r * 0.6, Vector2.RIGHT, color)
			_arrow(ci, c + Vector2(0, r * 0.35), r * 0.6, Vector2.LEFT, color)
		&"sticky":
			_poly(ci, [c + Vector2(0, -r * 0.9), c + Vector2(r * 0.6, r * 0.1), c + Vector2(-r * 0.6, r * 0.1)], color)
			ci.draw_circle(c + Vector2(0, r * 0.25), r * 0.6, color)
		_:
			_star(ci, c, r * 0.95, r * 0.42, color)


static func _poly(ci: CanvasItem, pts: Array, color: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array(pts), color)


static func _star(ci: CanvasItem, c: Vector2, outer: float, inner: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + TAU * i / 10.0
		var rr := outer if i % 2 == 0 else inner
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	ci.draw_colored_polygon(pts, color)


static func _heart(ci: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	ci.draw_circle(c + Vector2(-r * 0.42, -r * 0.25), r * 0.48, color)
	ci.draw_circle(c + Vector2(r * 0.42, -r * 0.25), r * 0.48, color)
	_poly(ci, [c + Vector2(-r * 0.88, -r * 0.1), c + Vector2(r * 0.88, -r * 0.1), c + Vector2(0, r * 0.9)], color)


static func _arrow(ci: CanvasItem, c: Vector2, r: float, dir: Vector2, color: Color) -> void:
	var side := Vector2(-dir.y, dir.x)
	var tip := c + dir * r * 0.85
	var base := c + dir * r * 0.05
	_poly(ci, [tip, base + side * r * 0.6, base - side * r * 0.6], color)
	ci.draw_line(c - dir * r * 0.75, base, color, r * 0.36)


static func _crescent(ci: CanvasItem, c: Vector2, big_r: float, color: Color) -> void:
	# Outer circle minus an offset "bite" circle, traced as one polygon.
	var bite := c + Vector2(big_r * 0.42, -big_r * 0.32)
	var bite_r := big_r * 0.8
	var n := 48
	var outside: Array[bool] = []
	for i in n:
		var p := c + Vector2.from_angle(TAU * i / n) * big_r
		outside.append((p - bite).length() > bite_r)
	var start := -1
	for i in n:
		if outside[i] and not outside[(i - 1 + n) % n]:
			start = i
			break
	if start == -1:
		ci.draw_circle(c, big_r, color)
		return
	var pts := PackedVector2Array()
	var i := start
	while outside[i % n] and pts.size() < n:
		pts.append(c + Vector2.from_angle(TAU * i / n) * big_r)
		i += 1
	var a_end := (pts[pts.size() - 1] - bite).angle()
	var a_start := (pts[0] - bite).angle()
	var delta := wrapf(a_start - a_end, -PI, PI)
	var mid := bite + Vector2.from_angle(a_end + delta * 0.5) * bite_r
	if (mid - c).length() > big_r:
		delta -= signf(delta) * TAU
	for k in range(1, 16):
		pts.append(bite + Vector2.from_angle(a_end + delta * k / 16.0) * bite_r)
	if pts.size() >= 3:
		ci.draw_colored_polygon(pts, color)
