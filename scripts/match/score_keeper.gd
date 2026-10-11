class_name ScoreKeeper
extends RefCounted
## Points for one round, per player and per category.
##
## Only positive, constructive things score: finishing objectives, stars,
## helping teammates, bouncing back after a mistake and finishing in time.
## Nothing here rewards pushing, blocking or bothering other players.

signal scored(player_index: int, category: StringName, points: int, reason: String)

const OBJECTIVE := &"objective"
const STARS := &"stars"
const TEAMWORK := &"teamwork"
const RECOVERY := &"recovery"
const TIME := &"time"
const CATEGORIES: Array[StringName] = [OBJECTIVE, STARS, TEAMWORK, RECOVERY, TIME]
const CATEGORY_NAMES := {
	OBJECTIVE: "Mission",
	STARS: "Stars",
	TEAMWORK: "Teamwork",
	RECOVERY: "Comebacks",
	TIME: "Speedy bonus",
}

var _points: Array[Dictionary] = []   # per player: category -> int
var _stats: Array[Dictionary] = []    # per player: stat name -> float
var _log: Array[Dictionary] = []      # every award, in order (for tests / replays)


func reset(player_count: int) -> void:
	_points.clear()
	_stats.clear()
	_log.clear()
	for i in player_count:
		var p := {}
		for c in CATEGORIES:
			p[c] = 0
		_points.append(p)
		_stats.append({})


func player_count() -> int:
	return _points.size()


func add(player_index: int, category: StringName, points: int, reason: String = "") -> void:
	if player_index < 0 or player_index >= _points.size() or points == 0:
		return
	if not CATEGORIES.has(category):
		push_warning("ScoreKeeper: unknown category %s" % category)
		category = OBJECTIVE
	# Scores never go below zero in any category.
	_points[player_index][category] = maxi(0, int(_points[player_index][category]) + points)
	_log.append({"player": player_index, "category": category, "points": points, "reason": reason})
	scored.emit(player_index, category, points, reason)


func add_all(category: StringName, points: int, reason: String = "") -> void:
	for i in _points.size():
		add(i, category, points, reason)


func total(player_index: int) -> int:
	if player_index < 0 or player_index >= _points.size():
		return 0
	var sum := 0
	for c in CATEGORIES:
		sum += int(_points[player_index][c])
	return sum


func category_points(player_index: int, category: StringName) -> int:
	if player_index < 0 or player_index >= _points.size():
		return 0
	return int(_points[player_index].get(category, 0))


func breakdown(player_index: int) -> Dictionary:
	if player_index < 0 or player_index >= _points.size():
		return {}
	return _points[player_index].duplicate()


func team_total() -> int:
	var sum := 0
	for i in _points.size():
		sum += total(i)
	return sum


## Player indices from highest to lowest total (ties keep player order).
func ranking() -> Array[int]:
	var order: Array[int] = []
	for i in _points.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		var ta := total(a)
		var tb := total(b)
		return ta > tb if ta != tb else a < b)
	return order


# ---------------------------------------------------------------- stats (for awards)

func add_stat(player_index: int, key: StringName, amount: float = 1.0) -> void:
	if player_index < 0 or player_index >= _stats.size():
		return
	_stats[player_index][key] = float(_stats[player_index].get(key, 0.0)) + amount


func set_stat(player_index: int, key: StringName, value: float) -> void:
	if player_index >= 0 and player_index < _stats.size():
		_stats[player_index][key] = value


func get_stat(player_index: int, key: StringName) -> float:
	if player_index < 0 or player_index >= _stats.size():
		return 0.0
	return float(_stats[player_index].get(key, 0.0))


func get_log() -> Array[Dictionary]:
	return _log.duplicate()
