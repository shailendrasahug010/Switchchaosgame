class_name MatchFx
extends Node3D
## Pooled, cheap effects: floating "+100" texts and little puffs/confetti.
## Everything is created once and reused, so effects never allocate mid-round.

const TEXT_POOL := 14
const PUFF_POOL := 8
const TEXT_LIFE := 1.3

var _texts: Array[Label3D] = []
var _text_age: Array[float] = []
var _text_origin: Array[Vector3] = []
var _next_text := 0
var _puffs: Array[CPUParticles3D] = []
var _next_puff := 0
## Room server: effects are sent to the phones instead of being shown here.
## Called as (kind: StringName, args: Array).
var net_forward: Callable = Callable()


func _ready() -> void:
	var font: Font = load("res://assets/fonts/fredoka_bold.tres")
	for i in TEXT_POOL:
		var l := Label3D.new()
		l.font = font
		l.font_size = 56
		l.pixel_size = 0.0075
		l.outline_size = 16
		l.outline_modulate = Color(0.1, 0.07, 0.22)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.render_priority = 5
		l.outline_render_priority = 4
		l.visible = false
		add_child(l)
		_texts.append(l)
		_text_age.append(99.0)
		_text_origin.append(Vector3.ZERO)
	for i in PUFF_POOL:
		var p := CPUParticles3D.new()
		p.emitting = false
		p.one_shot = true
		p.amount = 14
		p.lifetime = 0.7
		p.explosiveness = 1.0
		p.direction = Vector3.UP
		p.spread = 180.0
		p.initial_velocity_min = 2.0
		p.initial_velocity_max = 4.5
		p.gravity = Vector3(0, -6, 0)
		p.scale_amount_min = 0.5
		p.scale_amount_max = 1.0
		p.mesh = MeshFactory.sphere(0.14, 0.28, 6, 3)
		p.material_override = ToyMaterials.flat(Color.WHITE)
		add_child(p)
		_puffs.append(p)


## [param small] texts are for less important news (CPU buddies' points).
## Texts popping up at the same moment and place stack upward instead of
## piling on top of each other.
func floating_text(text: String, world_pos: Vector3, color: Color = Color.WHITE, small: bool = false) -> void:
	if net_forward.is_valid():
		net_forward.call(&"text", [text, world_pos, color, small])
		return
	var pos := world_pos
	for k in 6:
		var blocked := false
		for j in TEXT_POOL:
			if _text_age[j] < 0.6 and _texts[j].visible:
				var d := _text_origin[j] - pos
				if Vector2(d.x, d.z).length() < 3.0 and absf(d.y) < 0.5:
					blocked = true
					break
		if not blocked:
			break
		pos.y += 0.6
	var i := _next_text
	_next_text = (_next_text + 1) % TEXT_POOL
	var l := _texts[i]
	l.text = text
	l.modulate = color
	l.font_size = 40 if small else 56
	l.global_position = pos
	l.visible = true
	_text_age[i] = 0.0
	_text_origin[i] = pos


func puff(world_pos: Vector3, color: Color = Color.WHITE, amount_scale: float = 1.0) -> void:
	if net_forward.is_valid():
		net_forward.call(&"puff", [world_pos, color, amount_scale])
		return
	var p := _puffs[_next_puff]
	_next_puff = (_next_puff + 1) % PUFF_POOL
	p.global_position = world_pos
	p.color = color
	p.amount = int(14 * amount_scale)
	p.restart()


## A colorful confetti burst (deliveries, finishes, correct sequences).
func confetti(world_pos: Vector3) -> void:
	if net_forward.is_valid():
		net_forward.call(&"confetti", [world_pos])
		return
	for c: Color in [Color("ff5fa8"), Color("ffd23f"), Color("3f9dff"), Color("2fc97a")]:
		puff(world_pos + Vector3(randf_range(-0.6, 0.6), randf_range(0.0, 0.6), randf_range(-0.6, 0.6)), c, 1.2)


func _process(delta: float) -> void:
	for i in TEXT_POOL:
		if _text_age[i] > TEXT_LIFE:
			continue
		_text_age[i] += delta
		var t := _text_age[i] / TEXT_LIFE
		var l := _texts[i]
		l.global_position = _text_origin[i] + Vector3(0, t * 1.6, 0)
		var pop := 1.0 + 0.5 * maxf(0.0, 1.0 - t * 6.0)
		l.scale = Vector3.ONE * pop
		l.modulate.a = 1.0 - maxf(0.0, (t - 0.6) / 0.4)
		if _text_age[i] > TEXT_LIFE:
			l.visible = false
