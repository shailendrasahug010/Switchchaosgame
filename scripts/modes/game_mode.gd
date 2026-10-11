class_name GameMode
extends Node3D
## Base class for a game mode. The root node of every arena scene uses a
## subclass of this script.
##
## The match calls, in order:
##   setup_mode(match) -> players are spawned -> on_players_spawned(players)
##   -> on_round_started() -> mode_physics_process(delta) every physics tick
##   while playing -> on_round_ended(success)
## A mode never touches the UI directly. It reports through the match
## (award points, show messages, finish the round) and exposes data that the
## HUD and the results screen read.

## Ask the HUD to refresh the objective widget.
signal objective_changed

@export var mode_id: StringName = &""
@export var mission_title: String = ""
@export_multiline var mission_text: String = ""
@export var mission_icon: StringName = &"star"
@export_range(30.0, 180.0, 1.0) var round_time: float = 75.0
## Chaos events that suit this arena. Empty = every event.
@export var suitable_events: Array[StringName] = []
## Cooperative (shared win) instead of competitive.
@export var team_mode: bool = true
@export var kill_height: float = -12.0
@export_group("Camera")
@export var camera_yaw: float = 0.0
@export var camera_pitch: float = -38.0
@export var camera_distance: float = 13.0
@export var camera_min_distance: float = 10.0
@export var camera_max_distance: float = 22.0
@export var camera_look_ahead: Vector3 = Vector3(0, 0, -3)
@export var camera_bounds: AABB = AABB()

var match_node: MatchController = null
var players: Array[PlayerCharacter] = []
var rng := RandomNumberGenerator.new()
var round_active := false

var _bot_waypoint: Dictionary = {}   # player_index -> int
var _bot_ride: Dictionary = {}       # player_index -> bool (riding a platform)


# ---------------------------------------------------------------- lifecycle

func setup_mode(p_match: MatchController) -> void:
	match_node = p_match
	rng.seed = p_match.round_seed


## Spawn transforms in the order players are placed (group "spawn", sorted by name).
func get_spawn_transforms() -> Array[Transform3D]:
	var markers: Array[Node] = find_children("*", "Marker3D", true, false).filter(
			func(n: Node) -> bool: return n.is_in_group(&"spawn"))
	markers.sort_custom(func(a: Node, b: Node) -> bool: return String(a.name) < String(b.name))
	var out: Array[Transform3D] = []
	for m: Marker3D in markers:
		out.append(m.global_transform)
	if out.is_empty():
		for i in 4:
			out.append(Transform3D(Basis(), Vector3((i - 1.5) * 2.0, 0.5, 0)))
	return out


func on_players_spawned(p_players: Array[PlayerCharacter]) -> void:
	players = p_players


func on_round_started() -> void:
	round_active = true


func mode_physics_process(_delta: float) -> void:
	pass


func on_round_ended(_success: bool) -> void:
	round_active = false


# ---------------------------------------------------------------- helpers for subclasses

func award(player: PlayerCharacter, category: StringName, points: int, reason: String = "",
		at: Vector3 = Vector3.INF) -> void:
	if match_node and player:
		match_node.award(player.player_index, category, points, reason,
				player.global_position + Vector3(0, 2.4, 0) if at == Vector3.INF else at)


func award_everyone(category: StringName, points: int, reason: String = "") -> void:
	for p in players:
		award(p, category, points, reason)


func message(text: String, color: Color = Color.WHITE, seconds: float = 2.2) -> void:
	if match_node:
		match_node.show_message(text, color, seconds)


func finish(success: bool) -> void:
	if match_node:
		match_node.request_finish(success)


func stat(player: PlayerCharacter, key: StringName, amount: float = 1.0) -> void:
	if match_node and player:
		match_node.score.add_stat(player.player_index, key, amount)


func is_playing() -> bool:
	return match_node != null and match_node.is_playing()


func time_left() -> float:
	return match_node.time_left if match_node else 0.0


func human_players() -> Array[PlayerCharacter]:
	var out: Array[PlayerCharacter] = []
	for p in players:
		if p.is_human:
			out.append(p)
	return out


# ---------------------------------------------------------------- camera

## Who the camera keeps in view. Humans matter most; CPU buddies a little.
func get_camera_targets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var humans := human_players()
	for p in players:
		var w := 1.0 if p.is_human else (0.0 if humans.size() > 0 else 1.0)
		if w > 0.0:
			out.append({"node": p, "weight": w})
	return out


# ---------------------------------------------------------------- interacting

## Text for the contextual action button ("" when there is nothing to do).
func get_interact_prompt(player: PlayerCharacter) -> String:
	var it := find_interactable(player)
	return it.get_prompt(player) if it else ""


func get_interact_icon(player: PlayerCharacter) -> StringName:
	var it := find_interactable(player)
	return it.prompt_icon if it else &"hand"


func handle_interact(player: PlayerCharacter) -> void:
	var it := find_interactable(player)
	if it:
		it.interact(player)


func find_interactable(player: PlayerCharacter) -> Interactable:
	var best: Interactable = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group(&"interactable"):
		var it := n as Interactable
		if it == null or not is_ancestor_of(it) or not it.can_interact(player):
			continue
		var d := it.get_interact_position().distance_to(player.global_position)
		if d <= it.interact_radius and d < best_d:
			best = it
			best_d = d
	return best


# ---------------------------------------------------------------- HUD and results

## Optional mode-specific widget for the HUD (cake meter, button board...).
func create_objective_widget() -> Control:
	return null


## Short line under the timer ("Deliver the cake!").
func get_objective_text() -> String:
	return mission_text


## {headline, subline} for the results screen.
func get_result_text(success: bool) -> Dictionary:
	return {"headline": "Well played!" if success else "Time's up!", "subline": ""}


## Fun titles handed out on the results screen, best first:
## [{stat, title, text}] — the player with the highest [stat] gets the title.
func get_award_candidates() -> Array[Dictionary]:
	return []


## Lifetime progress numbers from this round for the local human players
## (cakes_delivered, buttons_pressed, races_finished, best_time...).
func get_progress_stats(_success: bool) -> Dictionary:
	return {}


# ---------------------------------------------------------------- bots

## Where a CPU buddy should go now. See BotInputSource for the keys.
func get_bot_goal(_player: PlayerCharacter) -> Dictionary:
	return {}


## Ordered waypoints for bots (Marker3D nodes in group "bot_path", sorted by name).
func get_bot_path() -> Array[Node3D]:
	var markers: Array[Node] = find_children("*", "Marker3D", true, false).filter(
			func(n: Node) -> bool: return n.is_in_group(&"bot_path"))
	markers.sort_custom(func(a: Node, b: Node) -> bool: return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
	var out: Array[Node3D] = []
	for m in markers:
		out.append(m as Node3D)
	return out


## Follows a course whose finish lies toward -Z. Waypoint metadata:
##   jump (bool)      jump when getting close to this point
##   ride (NodePath)  board the MovingPlatform when it is here, ride it to the next point
func path_goal(player: PlayerCharacter, path: Array[Node3D], arrive_radius: float = 1.4) -> Dictionary:
	if path.is_empty():
		return {}
	var idx: int = _bot_waypoint.get(player.player_index, -1)
	var pos := player.global_position
	if idx < 0 or idx >= path.size() or player.is_respawning:
		idx = 0
		# Start from the first waypoint that is still ahead of us.
		for i in path.size():
			if path[i].global_position.z < pos.z - 0.5:
				idx = i
				break
		_bot_ride[player.player_index] = false
	var wp := path[idx]
	# Ride handling: wait for the platform, hop on, stay on until the far end.
	if wp.has_meta(&"ride"):
		var platform := wp.get_node_or_null(wp.get_meta(&"ride")) as MovingPlatform
		if platform:
			var riding: bool = _bot_ride.get(player.player_index, false)
			var plat_pos := platform.global_position
			var next_wp := path[mini(idx + 1, path.size() - 1)]
			if not riding:
				var on_top := _is_above(pos, plat_pos, platform.size) and player.is_on_floor()
				if on_top:
					_bot_ride[player.player_index] = true
				elif plat_pos.distance_to(wp.global_position) < 1.6:
					return {"position": plat_pos, "stop_distance": 0.4, "jump": absf(plat_pos.y - pos.y) > 0.6,
							"jump_distance": 3.0}
				else:
					return {"position": wp.global_position - (next_wp.global_position - wp.global_position).normalized() * 1.6,
							"stop_distance": 0.6}
			if _bot_ride.get(player.player_index, false):
				if plat_pos.distance_to(next_wp.global_position) < 2.2 or not _is_above(pos, plat_pos, platform.size * 1.3):
					_bot_ride[player.player_index] = false
					idx += 1
					_bot_waypoint[player.player_index] = idx
					return {"position": next_wp.global_position, "jump": true, "jump_distance": 2.5}
				return {"position": plat_pos, "stop_distance": 0.5}
	var flat := Vector2(wp.global_position.x - pos.x, wp.global_position.z - pos.z).length()
	var passed := pos.z < wp.global_position.z - 0.3
	if (flat < arrive_radius and absf(wp.global_position.y - pos.y) < 2.0) or passed:
		idx = mini(idx + 1, path.size() - 1)
		wp = path[idx]
	_bot_waypoint[player.player_index] = idx
	return {
		"position": wp.global_position,
		"stop_distance": 0.5,
		"jump": bool(wp.get_meta(&"jump", false)),
		"jump_distance": float(wp.get_meta(&"jump_distance", 2.6)),
	}


func _is_above(pos: Vector3, center: Vector3, box: Vector3) -> bool:
	return absf(pos.x - center.x) < box.x * 0.5 + 0.2 and absf(pos.z - center.z) < box.z * 0.5 + 0.2 \
			and pos.y > center.y - 0.5


func reset_bot_path(player: PlayerCharacter) -> void:
	_bot_waypoint.erase(player.player_index)
	_bot_ride.erase(player.player_index)
