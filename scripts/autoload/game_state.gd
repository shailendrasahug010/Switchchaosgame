extends Node
## Local save data, settings, progression and the setup of the next match.
##
## Saved to user:// as JSON. No account, no network, no personal data —
## only settings, play statistics and which cosmetics have been earned.

signal settings_changed
signal progress_changed
signal cosmetics_unlocked(items: Array)

const SAVE_VERSION := 1
const DEFAULT_SAVE_PATH := "user://chaos_switch_save.json"

## Tests point this somewhere else so they never touch a real save.
var save_path: String = DEFAULT_SAVE_PATH
var persist_enabled: bool = true

var settings: Dictionary = {}
var stats: Dictionary = {}
var unlocked: Array[StringName] = []
## The local player's look (first human slot).
var profile: Dictionary = {}

## Filled by the setup screen right before a match starts.
var current_setup: MatchSetup = null
## Last few setups' choices, so "Play again" keeps the same party.
var last_player_count: int = 4
var last_human_count: int = 1
## The party setup screen's last choices (mode, players, rules).
var party: Dictionary = {}


func _ready() -> void:
	reset_to_defaults()
	load_game()
	_apply_runtime_settings()


func reset_to_defaults() -> void:
	settings = {
		"sfx_volume": 0.8,
		"music_volume": 0.55,
		"muted": false,
		"touch_controls": "auto",   # auto | on | off
		"simple_controls": false,   # one big action button + floating stick
		"button_scale": 1.0,        # 1.0 normal, 1.25 large
		"left_handed": false,       # swap stick and buttons
		"shadows": true,
		"reduced_motion": false,    # no camera shake, gentler flashes
		"debug_tools": OS.is_debug_build(),
		"show_tips": true,
		"online_allowed": false,    # a grown-up switches this on (Grown-ups page)
	}
	stats = {
		"rounds_played": 0,
		"stars": 0,
		"party_points": 0,
		"cakes_delivered": 0,
		"buttons_pressed": 0,
		"races_finished": 0,
		"best_times": {},
	}
	unlocked = []
	for item in Catalog.all_cosmetics():
		if (item.unlock as Dictionary).is_empty():
			unlocked.append(item.id)
	profile = {"character": &"bloop", "hat": &"none", "paint": &"classic"}
	party = {
		"mode": "cake_dash",
		"count": 4,
		"kinds": ["human", "cpu", "cpu", "cpu"],
		"characters": ["bloop", "jelly", "mossy", "sunny"],
		"chaos": true,
		"events": [],
		"quick": false,
		"skill": 1,
		"playlist": false,
	}


# ---------------------------------------------------------------- settings

func get_setting(key: String, fallback: Variant = null) -> Variant:
	return settings.get(key, fallback)


func set_setting(key: String, value: Variant) -> void:
	if settings.get(key) == value:
		return
	settings[key] = value
	_apply_runtime_settings()
	settings_changed.emit()
	save_game()


func wants_touch_controls() -> bool:
	match String(settings.get("touch_controls", "auto")):
		"on":
			return true
		"off":
			return false
	return DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")


func _apply_runtime_settings() -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("apply_settings"):
		audio.apply_settings()


# ---------------------------------------------------------------- progression

func is_unlocked(id: StringName) -> bool:
	return unlocked.has(id)


## 0..1 progress toward a cosmetic's unlock rule (1.0 when unlocked).
func unlock_progress(item: Dictionary) -> float:
	if is_unlocked(item.id):
		return 1.0
	var rule: Dictionary = item.unlock
	if rule.is_empty():
		return 1.0
	var total := 0.0
	for key in rule:
		total += clampf(float(stats.get(key, 0)) / maxf(1.0, float(rule[key])), 0.0, 1.0)
	return total / float(rule.size())


func unlock_rule_text(item: Dictionary) -> String:
	var rule: Dictionary = item.unlock
	if rule.is_empty():
		return "Unlocked from the start"
	var parts: Array[String] = []
	for key in rule:
		var need := int(rule[key])
		var have := mini(int(stats.get(key, 0)), need)
		var label: String = {
			"rounds_played": "Play %d rounds",
			"stars": "Collect %d stars",
			"party_points": "Earn %d party points",
			"cakes_delivered": "Deliver %d cakes",
			"buttons_pressed": "Press %d right buttons",
			"races_finished": "Finish %d races",
		}.get(key, key + " %d") % need
		parts.append("%s (%d/%d)" % [label, have, need])
	return ", ".join(parts)


## Adds a finished round's numbers to the lifetime stats and returns any
## cosmetics that just unlocked (as catalog dictionaries).
func record_round(round_stats: Dictionary) -> Array:
	stats.rounds_played = int(stats.rounds_played) + 1
	for key in ["stars", "party_points", "cakes_delivered", "buttons_pressed", "races_finished"]:
		stats[key] = int(stats.get(key, 0)) + int(round_stats.get(key, 0))
	if round_stats.has("best_time") and round_stats.has("mode_id"):
		var mode_key := String(round_stats.mode_id)
		var t := float(round_stats.best_time)
		var best: Dictionary = stats.best_times
		if not best.has(mode_key) or t < float(best[mode_key]):
			best[mode_key] = snappedf(t, 0.01)
	var newly: Array = []
	for item in Catalog.all_cosmetics():
		if is_unlocked(item.id):
			continue
		if _rule_met(item.unlock):
			unlocked.append(item.id)
			newly.append(item)
	save_game()
	progress_changed.emit()
	if not newly.is_empty():
		cosmetics_unlocked.emit(newly)
	return newly


func _rule_met(rule: Dictionary) -> bool:
	for key in rule:
		if int(stats.get(key, 0)) < int(rule[key]):
			return false
	return true


## Next cosmetic the player is closest to earning (for the results screen).
func next_unlock_hint() -> Dictionary:
	var best: Dictionary = {}
	var best_progress := -1.0
	for item in Catalog.all_cosmetics():
		if is_unlocked(item.id):
			continue
		var p := unlock_progress(item)
		if p > best_progress:
			best_progress = p
			best = item
	return best


func set_profile(character_id: StringName, hat_id: StringName, paint_id: StringName) -> void:
	profile.character = character_id
	if is_unlocked(hat_id):
		profile.hat = hat_id
	if is_unlocked(paint_id):
		profile.paint = paint_id
	save_game()
	progress_changed.emit()


# ---------------------------------------------------------------- save / load

func save_game() -> void:
	if not persist_enabled:
		return
	var data := {
		"version": SAVE_VERSION,
		"settings": settings,
		"stats": stats,
		"unlocked": unlocked.map(func(s): return String(s)),
		"profile": {
			"character": String(profile.character),
			"hat": String(profile.hat),
			"paint": String(profile.paint),
		},
		"last_player_count": last_player_count,
		"last_human_count": last_human_count,
		"party": party,
	}
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		push_warning("GameState: could not write save (%s)" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify(data, "\t"))


func load_game() -> void:
	if not persist_enabled or not FileAccess.file_exists(save_path):
		return
	var text := FileAccess.get_file_as_string(save_path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("GameState: save file unreadable, starting fresh.")
		return
	var data: Dictionary = parsed
	# Merge so new settings/stats added in later versions get their defaults.
	for key in (data.get("settings", {}) as Dictionary):
		if settings.has(key):
			settings[key] = data.settings[key]
	for key in (data.get("stats", {}) as Dictionary):
		stats[key] = data.stats[key]
	for id in (data.get("unlocked", []) as Array):
		var sid := StringName(String(id))
		if not unlocked.has(sid):
			unlocked.append(sid)
	var p: Dictionary = data.get("profile", {})
	if p.has("character"):
		profile.character = StringName(String(p.character))
	if p.has("hat") and is_unlocked(StringName(String(p.hat))):
		profile.hat = StringName(String(p.hat))
	if p.has("paint") and is_unlocked(StringName(String(p.paint))):
		profile.paint = StringName(String(p.paint))
	last_player_count = clampi(int(data.get("last_player_count", 4)), 1, 4)
	last_human_count = clampi(int(data.get("last_human_count", 1)), 1, 4)
	var saved_party: Variant = data.get("party", {})
	if saved_party is Dictionary:
		for key in (saved_party as Dictionary):
			if party.has(key):
				party[key] = saved_party[key]


## Wipes progress but keeps settings (offered on the settings screen).
func reset_progress() -> void:
	var keep := settings.duplicate(true)
	reset_to_defaults()
	settings = keep
	save_game()
	progress_changed.emit()
