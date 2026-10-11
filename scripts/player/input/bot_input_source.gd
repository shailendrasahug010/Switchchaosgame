class_name BotInputSource
extends PlayerInputSource
## A friendly CPU buddy. It asks the current game mode where to go
## ([code]get_bot_goal(player)[/code]) and turns that into stick and button
## presses — exactly like a person would. It is deliberately a little sloppy
## (aim wobble, hesitation, a moment of confusion when controls reverse) so
## kids can beat it.
##
## Goal dictionary keys (all optional except position):
##   position: Vector3      where to go
##   stop_distance: float   arrival radius (default 0.7)
##   jump: bool             this spot needs a jump when close
##   jump_distance: float   how close before jumping (default 2.2)
##   interact: bool         press interact when within interact_distance
##   interact_distance: float
##   wait: bool             stand still

var provider: Object = null
var skill: float = 0.6
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _last_pos: Vector3 = Vector3.ZERO
var _stuck_check: float = 0.7
var _jump_cooldown: float = 0.0
var _jump_hold: float = 0.0
var _interact_cooldown: float = 0.0
var _confusion: float = 0.0
var _was_reversed: bool = false
var _wobble_phase: float = 0.0
var _side_step: float = 0.0
var _side_step_time: float = 0.0
var _hesitate: float = 0.0
var _smooth_stick: Vector2 = Vector2.ZERO


func _init(p_provider: Object = null, p_skill: float = 0.6, p_seed: int = 0) -> void:
	provider = p_provider
	skill = clampf(p_skill, 0.0, 1.0)
	rng.seed = p_seed if p_seed != 0 else randi()
	_wobble_phase = rng.randf() * TAU


func get_kind_label() -> String:
	return "CPU"


func update(delta: float, player: Node) -> void:
	move = Vector2.ZERO
	if provider == null or not is_instance_valid(provider) or not provider.has_method("get_bot_goal"):
		jump_held = false
		return
	var goal: Dictionary = provider.get_bot_goal(player)
	if goal.is_empty() or goal.get("wait", false) or not goal.has("position"):
		jump_held = false
		return
	var body := player as PlayerCharacter
	var target: Vector3 = goal.position
	var pos: Vector3 = body.global_position
	var to := target - pos
	var flat := Vector3(to.x, 0.0, to.z)
	var dist := flat.length()
	var stop_distance: float = goal.get("stop_distance", 0.7)

	# --- steering
	var desired := Vector3.ZERO
	if dist > stop_distance:
		desired = flat / dist
		_wobble_phase += delta * 2.0
		var wobble := sin(_wobble_phase * 1.7) * deg_to_rad(16.0) * (1.0 - skill)
		desired = desired.rotated(Vector3.UP, wobble)
	if _side_step_time > 0.0:
		_side_step_time -= delta
		desired = (desired + desired.cross(Vector3.UP) * _side_step).normalized()
	# Occasional tiny hesitation keeps bots from feeling robotic.
	if _hesitate > 0.0:
		_hesitate -= delta
		desired *= 0.3
	elif rng.randf() < delta * 0.25 * (1.0 - skill):
		_hesitate = rng.randf_range(0.2, 0.5)

	var throttle := 0.0
	if dist > stop_distance:
		throttle = clampf(dist / 2.0, 0.4, 1.0) * lerpf(0.85, 1.0, skill)
		# On ice, ease off so we don't slide past the goal.
		if body.stat(&"traction") < 0.5:
			throttle *= clampf(dist / 4.0, 0.3, 1.0)
	var local := desired.rotated(Vector3.UP, -body.camera_yaw)
	var stick := Vector2(local.x, local.z) * throttle

	# --- reversed controls: a moment of "huh?" then compensate
	var reversed := body.is_reversed()
	if reversed and not _was_reversed:
		_confusion = lerpf(1.3, 0.4, skill)
	_was_reversed = reversed
	if reversed:
		if _confusion > 0.0:
			_confusion -= delta
		else:
			stick = -stick
	# "careful" goals (carrying the cake) steer smoothly instead of snapping.
	var careful: bool = goal.get("careful", false)
	if careful:
		_smooth_stick = _smooth_stick.lerp(stick, 1.0 - exp(-4.0 * delta))
		stick = _smooth_stick
	else:
		_smooth_stick = stick
	move = stick.limit_length(1.0)

	# --- jumping
	_jump_cooldown -= delta
	_jump_hold -= delta
	var want_jump := false
	if goal.get("jump", false) and dist < float(goal.get("jump_distance", 2.2)):
		want_jump = true
	if to.y > 0.9 and dist < 3.2 and not careful:
		want_jump = true
	_stuck_check -= delta
	if _stuck_check <= 0.0:
		_stuck_check = 0.7
		var moved := Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length()
		if dist > stop_distance + 0.3 and moved < 0.35:
			want_jump = not careful or rng.randf() < 0.3
			_side_step = -1.0 if rng.randf() < 0.5 else 1.0
			_side_step_time = 0.6
		_last_pos = pos
	if want_jump and _jump_cooldown <= 0.0 and body.is_on_floor():
		press_jump()
		_jump_cooldown = 0.45
		_jump_hold = 0.4
	jump_held = _jump_hold > 0.0

	# --- interacting
	_interact_cooldown -= delta
	if goal.get("interact", false) and _interact_cooldown <= 0.0:
		var reach: float = goal.get("interact_distance", 1.6)
		if dist <= reach and absf(to.y) < 2.5:
			press_interact()
			_interact_cooldown = 0.9
