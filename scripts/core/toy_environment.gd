@tool
class_name ToyEnvironment
extends Node3D
## Sky, sun and ambient light for an arena, tuned for the bright toy look and
## for the GL Compatibility renderer used on Android. Shadows follow the
## player's "Shadows" setting.

enum Style { CANDY, TOYBOX, MEADOW }

@export var style: Style = Style.CANDY:
	set(v):
		style = v
		_changed()
@export_range(-89.0, 0.0, 1.0) var sun_pitch: float = -52.0:
	set(v):
		sun_pitch = v
		_changed()
@export_range(-180.0, 180.0, 1.0) var sun_yaw: float = 35.0:
	set(v):
		sun_yaw = v
		_changed()
@export var shadow_distance: float = 45.0
@export_range(0.0, 3.0, 0.05) var sun_energy: float = 0.85
@export_range(0.0, 3.0, 0.05) var ambient_energy: float = 0.42
@export_range(0.1, 3.0, 0.05) var exposure: float = 1.0
@export var tonemap: Environment.ToneMapper = Environment.TONE_MAPPER_LINEAR

var sun: DirectionalLight3D
var world_environment: WorldEnvironment
var _queued := false


func _ready() -> void:
	_rebuild()
	if Gen.in_game():
		var gs := get_node_or_null("/root/GameState")
		if gs:
			gs.settings_changed.connect(_apply_shadow_setting)


func _changed() -> void:
	if not is_inside_tree() or _queued:
		return
	_queued = true
	_rebuild.call_deferred()


func _palette() -> Dictionary:
	match style:
		Style.TOYBOX:
			return {"top": Color("8fb8ff"), "horizon": Color("ffe9d6"), "ground": Color("b9a6e8"),
					"ambient": Color("d9cfff"), "fog": Color("ffe9f3"), "sun": Color(1.0, 0.95, 0.88)}
		Style.MEADOW:
			return {"top": Color("5fb4ff"), "horizon": Color("dff4ff"), "ground": Color("9fd98a"),
					"ambient": Color("d6f0ff"), "fog": Color("e8f6ff"), "sun": Color(1.0, 0.97, 0.9)}
	return {"top": Color("6ec3ff"), "horizon": Color("ffe3f1"), "ground": Color("d9b8ff"),
			"ambient": Color("e6d9ff"), "fog": Color("ffe6f2"), "sun": Color(1.0, 0.96, 0.9)}


func _rebuild() -> void:
	_queued = false
	Gen.clear(self)
	var pal := _palette()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = pal.top
	sky_mat.sky_horizon_color = pal.horizon
	sky_mat.ground_horizon_color = pal.horizon
	sky_mat.ground_bottom_color = pal.ground
	sky_mat.sky_curve = 0.12
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = pal.ambient
	env.ambient_light_energy = ambient_energy
	env.tonemap_mode = tonemap
	env.tonemap_exposure = exposure
	env.tonemap_white = 1.0
	env.fog_enabled = true
	env.fog_light_color = pal.fog
	env.fog_density = 0.0035
	env.fog_sky_affect = 0.0
	world_environment = WorldEnvironment.new()
	world_environment.environment = env
	Gen.add(self, world_environment)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(sun_pitch, sun_yaw, 0)
	sun.light_color = pal.sun
	sun.light_energy = sun_energy
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = shadow_distance
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_opacity = 0.75
	Gen.add(self, sun)
	_apply_shadow_setting()


func _apply_shadow_setting() -> void:
	if sun == null:
		return
	var on := true
	if Gen.in_game():
		var gs := get_node_or_null("/root/GameState")
		if gs:
			on = bool(gs.get_setting("shadows", true))
	sun.shadow_enabled = on
