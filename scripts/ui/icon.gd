@tool
class_name Icon
extends Control
## A vector icon (see IconDraw). Scales with the control's size.

@export var icon: StringName = &"star":
	set(v):
		icon = v
		queue_redraw()
@export var color: Color = Color.WHITE:
	set(v):
		color = v
		queue_redraw()
## Dark outline/shadow drawn behind the icon for readability on busy scenes.
@export var shadow: bool = false:
	set(v):
		shadow = v
		queue_redraw()


func _init(p_icon: StringName = &"star", p_color: Color = Color.WHITE, p_size: float = 48.0) -> void:
	icon = p_icon
	color = p_color
	custom_minimum_size = Vector2(p_size, p_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	if shadow:
		IconDraw.draw(self, icon, o + Vector2(0, s * 0.06), s, Color(0.07, 0.05, 0.16, 0.45))
	IconDraw.draw(self, icon, o, s, color)
