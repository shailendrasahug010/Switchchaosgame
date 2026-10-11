class_name ModifierStack
extends RefCounted
## A set of named modifier "sources" — for example one source per active chaos event.
##
## Every effective value is recomputed from the untouched base value and all
## sources that are active *right now*. Nothing ever writes into a base value,
## so removing any source restores the correct result no matter which other
## sources are still active. (Moon Mode ending while Giant Mode is running
## gives back normal gravity and keeps the giant size.)
##
## Conventions for a source's dictionary (stat name -> value):
##   * numbers are multipliers by default, read with [method mul]
##   * some stats are "strongest wins" values, read with [method max_of]
##   * booleans are flags, read with [method any]
## The reader decides which rule applies to a stat; the stack stays generic.

signal changed

var _sources: Dictionary = {}  # StringName -> Dictionary
var version: int = 0           # bumps on every change; handy for caches


func set_source(source: StringName, modifiers: Dictionary) -> void:
	# Normalise keys so "gravity" and &"gravity" mean the same stat.
	var clean: Dictionary = {}
	for key in modifiers:
		clean[StringName(str(key))] = modifiers[key]
	_sources[source] = clean
	version += 1
	changed.emit()


func remove_source(source: StringName) -> bool:
	if not _sources.has(source):
		return false
	_sources.erase(source)
	version += 1
	changed.emit()
	return true


func has_source(source: StringName) -> bool:
	return _sources.has(source)


func get_source_ids() -> Array:
	return _sources.keys()


func is_empty() -> bool:
	return _sources.is_empty()


func clear() -> void:
	if _sources.is_empty():
		return
	_sources.clear()
	version += 1
	changed.emit()


## Product of every multiplier registered for [param stat] (1.0 when none).
func mul(stat: StringName) -> float:
	var result := 1.0
	for mods: Dictionary in _sources.values():
		if mods.has(stat):
			result *= float(mods[stat])
	return result


## Largest value registered for [param stat], or [param fallback] when none.
func max_of(stat: StringName, fallback: float = 0.0) -> float:
	var found := false
	var best := fallback
	for mods: Dictionary in _sources.values():
		if mods.has(stat):
			var v := float(mods[stat])
			if not found or v > best:
				best = v
				found = true
	return best


## True when any source sets [param stat] to a truthy value.
func any(stat: StringName) -> bool:
	for mods: Dictionary in _sources.values():
		if mods.has(stat) and bool(mods[stat]):
			return true
	return false
