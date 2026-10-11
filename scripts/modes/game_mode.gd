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
##
## Online (see docs/ONLINE_MULTIPLAYER_PLAN.md) the room server runs the real
## rules ([method is_authority] is true there). On the phones the same arena is
## loaded, but the rules don't run: [method mode_physics_process] is replaced
## by [method mode_client_process], and the state the HUD needs arrives through
## [method apply_net_state] and [method apply_net_event]. Sounds and effects
## go through [method sfx] and the match's MatchFx so the server can forward
## them to every phone.

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
var _nav_paths: Dictionary = {}      # player_index -> {target, path, index, time}
var _nav_region: NavigationRegion3D = null
var _stars_cache: Array[StarPickup] = []


# ---------------------------------------------------------------- lifecycle

func setup_mode(p_match: MatchController) -> void:
	match_node = p_match
	rng.seed = p_match.round_seed
	for n in find_children("*", "NavigationRegion3D", true, false):
		_nav_region = n as NavigationRegion3D


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

## False on an online phone: the room server runs the rules and decides
## points, finishes and pickups. Local play and the server return true.
func is_authority() -> bool:
	return match_node == null or match_node.is_authority()


func award(player: PlayerCharacter, category: StringName, points: int, reason: String = "",
		at: Vector3 = Vector3.INF) -> void:
	if match_node and player and is_authority():
		match_node.award(player.player_index, category, points, reason,
				player.global_position + Vector3(0, 2.4, 0) if at == Vector3.INF else at)


func award_everyone(category: StringName, points: int, reason: String = "") -> void:
	for p in players:
		award(p, category, points, reason)


func message(text: String, color: Color = Color.WHITE, seconds: float = 2.2) -> void:
	if match_node:
		match_node.show_message(text, color, seconds)


func finish(success: bool) -> void:
	if match_node and is_authority():
		match_node.request_finish(success)


func stat(player: PlayerCharacter, key: StringName, amount: float = 1.0) -> void:
	if match_node and player and is_authority():
		match_node.score.add_stat(player.player_index, key, amount)


## Plays a sound for everyone (the room server sends it to the phones).
func sfx(id: StringName, pitch: float = 1.0) -> void:
	if match_node:
		match_node.play_sfx(id, pitch)


## A short camera shake for everyone.
func shake(amount: float) -> void:
	if match_node:
		match_node.shake_camera(amount)


# ---------------------------------------------------------------- online

## Room server: what the phones need to show this mode (sent several times a
## second). Keep it small: numbers, strings and short arrays.
func get_net_state() -> Dictionary:
	return {}


## Phone: applies [method get_net_state] from the server.
func apply_net_state(_state: Dictionary) -> void:
	pass


## Room server: a one-off event for every phone (a star popped, a button buzzed).
func net_event(event_name: StringName, args: Array = []) -> void:
	if match_node:
		match_node.send_mode_event(event_name, args)


## Phone: handles [method net_event].
func apply_net_event(_event_name: StringName, _args: Array) -> void:
	pass


## Phone: runs every physics tick while playing, instead of
## [method mode_physics_process] (for looks only: hints, arrows...).
func mode_client_process(_delta: float) -> void:
	pass


## Room server: the player behind [param _player] lost the connection.
func on_player_away(_player: PlayerCharacter) -> void:
	pass


## Index of [param star] among the mode's stars (for net events), -1 if none.
func star_index(star: StarPickup) -> int:
	return _star_list().find(star)


## Every star in the arena, in scene order (the same on the server and phones).
func _star_list() -> Array[StarPickup]:
	if _stars_cache.is_empty():
		for n in find_children("*", "StarPickup", true, false):
			_stars_cache.append(n as StarPickup)
	return _stars_cache


## Stars as a compact "taken by" list for [method get_net_state]
## (-1 = still there, else the collector's player index).
func stars_net_state() -> PackedInt32Array:
	var out := PackedInt32Array()
	for s in _star_list():
		out.append(s.collected_by if s.taken else -1)
	return out


func apply_stars_net_state(state: Variant) -> void:
	if typeof(state) != TYPE_PACKED_INT32_ARRAY:
		return
	var stars := _star_list()
	for i in mini(stars.size(), (state as PackedInt32Array).size()):
		var by: int = state[i]
		if by >= 0 and not stars[i].taken:
			stars[i].collect(_player_by_index(by))


## Room server: [param player] picked up [param star] (shared star rules).
func collect_star(player: PlayerCharacter, star: StarPickup) -> void:
	star.collect(player)
	award(player, ScoreKeeper.STARS, star.points, "Star!")
	stat(player, &"stars")
	sfx(&"star")
	net_event(&"star", [star_index(star), player.player_index])


func _player_by_index(index: int) -> PlayerCharacter:
	for p in players:
		if p.player_index == index:
			return p
	return null


## Handles the shared events (stars). Subclasses call super() first.
func _apply_common_event(event_name: StringName, args: Array) -> bool:
	if event_name == &"star" and args.size() == 2:
		var stars := _star_list()
		var i := int(args[0])
		if i >= 0 and i < stars.size() and not stars[i].taken:
			stars[i].collect(_player_by_index(int(args[1])))
		return true
	return false


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

## Who the camera keeps in view (see PartyCamera): people on this device are
## never lost off-screen; CPU buddies are only followed in an all-CPU demo.
## Modes add their objective (the cake...) with PartyCamera.Priority.SHOULD.
func get_camera_targets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var any_human := not human_players().is_empty()
	for p in players:
		var prio := PartyCamera.Priority.MUST if (p.is_human or not any_human) else PartyCamera.Priority.NICE
		out.append({"node": p, "priority": prio, "height": 2.0})
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


## Nearest usable Interactable in reach. Giant players have longer arms.
func find_interactable(player: PlayerCharacter) -> Interactable:
	var best: Interactable = null
	var best_d := INF
	var arm := maxf(1.0, player.size_scale)
	for n in get_tree().get_nodes_in_group(&"interactable"):
		var it := n as Interactable
		if it == null or not is_ancestor_of(it) or not it.can_interact(player):
			continue
		var d := it.get_interact_position().distance_to(player.global_position)
		if d <= it.interact_radius * arm and d < best_d:
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


## Big word shown the moment the round ends.
func get_finish_banner(success: bool) -> String:
	return "MISSION COMPLETE!" if success else "TIME'S UP!"


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
##   jump_distance    how close "close" is (default 2.6)
##   no_pass (bool)   must really be reached (a bounce pad), not just passed
##   arrive_radius    how close counts as "reached" (default 1.4)
##   no_brake (bool)  run straight through it at full speed (trampolines)
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
	var passed: bool = pos.z < wp.global_position.z - 0.3 and not wp.get_meta(&"no_pass", false) \
			and pos.y > wp.global_position.y - 1.0
	var arrive := float(wp.get_meta(&"arrive_radius", arrive_radius))
	if (flat < arrive and absf(wp.global_position.y - pos.y) < 2.0) or passed:
		idx = mini(idx + 1, path.size() - 1)
		wp = path[idx]
	_bot_waypoint[player.player_index] = idx
	var no_brake: bool = wp.get_meta(&"no_brake", false)
	return {
		"position": wp.global_position,
		"stop_distance": 0.0 if no_brake else 0.5,
		"no_brake": no_brake,
		"jump": bool(wp.get_meta(&"jump", false)),
		"jump_distance": float(wp.get_meta(&"jump_distance", 2.6)),
	}


func _is_above(pos: Vector3, center: Vector3, box: Vector3) -> bool:
	return absf(pos.x - center.x) < box.x * 0.5 + 0.2 and absf(pos.z - center.z) < box.z * 0.5 + 0.2 \
			and pos.y > center.y - 0.5


func reset_bot_path(player: PlayerCharacter) -> void:
	_bot_waypoint.erase(player.player_index)
	_bot_ride.erase(player.player_index)
	_nav_paths.erase(player.player_index)


# ---------------------------------------------------------------- navigation

func has_navigation() -> bool:
	return _nav_region != null and _nav_region.navigation_mesh != null


## A bot goal toward [param target] that walks around walls and up ramps using
## the arena's navigation mesh (baked by tools/build_arenas.gd). Intermediate
## corners use a small stop distance; [param stop_distance] applies at the end.
## [param extra] keys (interact, interact_at...) are copied into the goal.
func nav_goal(player: PlayerCharacter, target: Vector3, stop_distance: float = 0.6,
		extra: Dictionary = {}) -> Dictionary:
	var g := extra.duplicate()
	var step := nav_next_point(player, target)
	g["position"] = step.point
	g["stop_distance"] = stop_distance if step.final else 0.25
	if g.get("interact", false) and not g.has("interact_at"):
		g["interact_at"] = target
	return g


## Next corner on the navigation path from [param player] to [param target].
## Returns {point: Vector3, final: bool}. Without a navigation mesh (or before
## the navigation map is ready) it simply heads straight for the target.
func nav_next_point(player: PlayerCharacter, target: Vector3) -> Dictionary:
	if not has_navigation() or not is_inside_tree():
		return {"point": target, "final": true}
	var now := MatchClock.now(self)
	var pos := player.global_position
	var st: Dictionary = _nav_paths.get(player.player_index, {})
	if st.is_empty() or (st.target as Vector3).distance_to(target) > 0.8 or now - float(st.time) > 0.75:
		var map := get_world_3d().navigation_map
		var path := NavigationServer3D.map_get_path(map, pos, target, true)
		st = {"target": target, "path": path, "index": 0, "time": now}
		_nav_paths[player.player_index] = st
	var path: PackedVector3Array = st.path
	if path.size() < 2:
		return {"point": target, "final": true}
	var i: int = st.index
	while i < path.size() - 1:
		var d := path[i] - pos
		if Vector2(d.x, d.z).length() > 0.7:
			break
		i += 1
	st.index = i
	if i >= path.size() - 1:
		# Past the last corner: aim at the real target (it may be just off the
		# navigation mesh, like a button on a moving platform).
		return {"point": target, "final": true}
	return {"point": path[i], "final": false}
