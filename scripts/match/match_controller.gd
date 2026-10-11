class_name MatchController
extends Node
## Runs one round from start to finish.
##
## Loads the arena (a GameMode scene), spawns the players with their input
## sources, drives the round timer and the Chaos Switch, keeps score and
## shows the results. Phases: INTRO (mission card) -> COUNTDOWN (3-2-1) ->
## PLAYING -> FINISHED (short celebration) -> RESULTS.
##
## Restarting always reloads this scene, so nothing from the previous round
## can leak into the next one.

signal phase_changed(phase: Phase)
signal countdown_tick(value: int)
signal message_requested(text: String, color: Color, seconds: float)
signal round_finished(success: bool)
signal paused_changed(paused: bool)

enum Phase { LOADING, INTRO, COUNTDOWN, PLAYING, FINISHED, RESULTS }

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const INTRO_TIME := 3.4
const COUNTDOWN_TIME := 3.0
const FINISH_TIME := 3.0
const VOICE_GAP_ANY := 0.15
const VOICE_GAP_SAME := 0.6

const COMMON_AWARDS: Array[Dictionary] = [
	{"stat": &"stars", "title": "Star Catcher", "text": "Grabbed the most stars"},
	{"stat": &"chaos_points", "title": "Chaos Surfer", "text": "Scored big while the rules kept switching"},
	{"stat": &"recoveries", "title": "Never Gives Up", "text": "Bounced back after every oopsie"},
	{"stat": &"jumps", "title": "Super Hopper", "text": "Did the most jumps"},
	{"stat": &"distance", "title": "Zoomy Feet", "text": "Ran the farthest"},
]
const FRIENDLY_AWARDS: Array[Dictionary] = [
	{"title": "Party Pal", "text": "Brought the fun to the party"},
	{"title": "Good Sport", "text": "Smiled through all the chaos"},
	{"title": "Giggle Champion", "text": "Made everyone laugh"},
	{"title": "Chaos Explorer", "text": "Tried every silly rule"},
]

@onready var world: Node3D = $World
@onready var players_root: Node3D = $World/Players
@onready var camera: PartyCamera = $World/Camera
@onready var fx: MatchFx = $World/Fx
@onready var chaos: ChaosManager = $ChaosManager
@onready var hud: Hud = $UI/Hud
@onready var touch_controls: TouchControls = $UI/TouchControls
@onready var pause_menu: PauseMenu = $Overlay/PauseMenu
@onready var results_screen: ResultsScreen = $Overlay/ResultsScreen
@onready var debug_panel: DebugPanel = $Overlay/DebugPanel

var setup: MatchSetup
var mode: GameMode
var mode_info: Dictionary = {}
var players: Array[PlayerCharacter] = []
var score := ScoreKeeper.new()
var phase: Phase = Phase.LOADING
var phase_time := 0.0
var time_left := 0.0
var round_length := 60.0
## Seconds of actual play so far.
var elapsed := 0.0
var round_seed := 0
var success := false
var result: Dictionary = {}
var is_paused := false
## Set by tests/tools to skip the intro and countdown.
var fast_start := false

var _finish_requested := false
var _finish_success := false
var _last_countdown := -1
var _last_positions: Dictionary = {}
var _voice_any_at := -10.0
var _voice_last: Dictionary = {}


func _ready() -> void:
	setup = GameState.current_setup
	if setup == null:
		setup = MatchSetup.quick(&"cake_dash", 1, 3, GameState.profile.character)
		GameState.current_setup = setup
	round_seed = setup.seed if setup.seed != 0 else (randi() % 2000000000) + 1
	MatchClock.externally_driven = false
	MatchClock.reset(0.0)
	TouchState.reset()
	_load_arena()
	_spawn_players()
	_setup_camera()
	_setup_chaos()
	hud.setup(self)
	touch_controls.setup(self)
	pause_menu.setup(self)
	results_screen.setup(self)
	debug_panel.setup(self)
	AudioManager.play_music(&"match")
	_set_phase(Phase.INTRO)
	if fast_start or OS.get_cmdline_user_args().has("--fast-start"):
		skip_intro()


func _load_arena() -> void:
	mode_info = Catalog.mode(setup.mode_id)
	var packed := load(String(mode_info.scene)) as PackedScene
	if packed == null:
		push_error("MatchController: cannot load arena %s" % mode_info.scene)
		return
	mode = packed.instantiate() as GameMode
	if mode == null:
		push_error("MatchController: arena root must use a GameMode script")
		return
	world.add_child(mode)
	world.move_child(mode, 0)
	mode.setup_mode(self)
	round_length = setup.round_time if setup.round_time > 0.0 else mode.round_time
	time_left = round_length
	score.reset(setup.slots.size())
	score.scored.connect(_on_scored)


func _spawn_players() -> void:
	var spawns := mode.get_spawn_transforms()
	var cpu_count := 0
	for i in setup.slots.size():
		var slot: MatchSetup.Slot = setup.slots[i]
		var p: PlayerCharacter = PLAYER_SCENE.instantiate()
		p.name = "Player%d" % (i + 1)
		p.player_index = i
		p.is_human = slot.kind == MatchSetup.Kind.HUMAN
		p.rules = chaos.rules
		p.kill_y = mode.kill_height
		var label := "P%d" % slot.local_index if p.is_human else "CPU"
		if slot.kind == MatchSetup.Kind.REMOTE:
			label = "P%d" % (i + 1)
		p.display_name = label
		match slot.kind:
			MatchSetup.Kind.HUMAN:
				if slot.autopilot:
					p.input = BotInputSource.new(mode, 0.8, round_seed + 31 * (i + 1))
				else:
					p.input = LocalInputSource.new(slot.local_index)
			MatchSetup.Kind.CPU:
				cpu_count += 1
				p.input = BotInputSource.new(mode, slot.bot_skill, round_seed + 97 * (i + 1))
			_:
				p.input = PlayerInputSource.new()
		players_root.add_child(p)
		var xf: Transform3D = spawns[i % spawns.size()]
		var fwd := -xf.basis.z
		p.teleport(xf.origin + Vector3(0, 0.05, 0), Vector3(fwd.x, 0, fwd.z))
		p.respawn_position = xf.origin + Vector3(0, 0.3, 0)
		p.setup_look(slot.character_id, slot.hat_id, slot.paint_id, Catalog.PLAYER_TAG_COLORS[i % 4], label)
		p.interact_requested.connect(_on_player_interact)
		p.jumped.connect(func() -> void:
			AudioManager.play_varied(&"jump", Catalog.character(slot.character_id).voice_pitch)
			score.add_stat(p.player_index, &"jumps"))
		p.landed.connect(func(impact: float) -> void:
			if impact > 7.0:
				AudioManager.play_varied(&"land", 1.0, 0.1, -4.0))
		p.bounced.connect(func(_s: float) -> void: AudioManager.play_varied(&"bounce"))
		p.knocked.connect(func(_d: Vector3) -> void:
			AudioManager.play_varied(&"bonk")
			camera.shake(0.15))
		p.fell_out.connect(func() -> void:
			AudioManager.play_varied(&"fall_whoosh")
			fx.puff(p.global_position + Vector3(0, 1, 0), Color("ff9ccf")))
		p.respawned.connect(func() -> void:
			AudioManager.play_varied(&"respawn_pop")
			fx.puff(p.global_position + Vector3(0, 0.6, 0), Color.WHITE))
		p.reacted.connect(_on_player_reacted.bind(p))
		players.append(p)
		_last_positions[i] = p.global_position
	mode.on_players_spawned(players)


func _setup_camera() -> void:
	camera.yaw_degrees = mode.camera_yaw
	camera.pitch_degrees = mode.camera_pitch
	camera.base_distance = mode.camera_distance
	camera.min_distance = mode.camera_min_distance
	camera.max_distance = mode.camera_max_distance
	camera.look_ahead = mode.camera_look_ahead
	camera.bounds = mode.camera_bounds
	camera.reduced_motion = bool(GameState.get_setting("reduced_motion", false))
	camera.set_targets(mode.get_camera_targets())
	camera.current = true
	for p in players:
		p.camera_yaw = camera.get_control_yaw()
	camera.snap()


func _setup_chaos() -> void:
	chaos.context.match_node = self
	chaos.enabled_ids = setup.enabled_events.duplicate() if not setup.enabled_events.is_empty() \
			else mode.suitable_events.duplicate()
	chaos.event_announced.connect(func(ev: ChaosEvent, _lead: float) -> void:
		AudioManager.play(ev.sfx_announce))
	chaos.countdown_changed.connect(func(_ev: ChaosEvent, secs: int) -> void:
		if secs > 0 and is_playing():
			AudioManager.play(&"tick", 1.0 + (3 - secs) * 0.12))
	chaos.event_started.connect(_on_chaos_started)
	chaos.event_ended.connect(_on_chaos_ended)


# ---------------------------------------------------------------- phases

func _set_phase(p: Phase) -> void:
	phase = p
	phase_time = 0.0
	match p:
		Phase.INTRO:
			_set_controls(false)
		Phase.COUNTDOWN:
			_last_countdown = -1
		Phase.PLAYING:
			_set_controls(true)
			if setup.chaos_enabled:
				chaos.start(round_seed)
			mode.on_round_started()
			AudioManager.play(&"go")
		Phase.FINISHED:
			_set_controls(false)
			chaos.stop()
			_refresh_chaos_looks()
			mode.on_round_ended(_finish_success)
			success = _finish_success
			for pl in players:
				if success:
					pl.celebrate()
				else:
					pl.react(&"oops")
			AudioManager.play(&"victory" if success else &"round_over")
			round_finished.emit(success)
		Phase.RESULTS:
			result = _build_result()
			results_screen.show_results(result)
	phase_changed.emit(p)


func skip_intro() -> void:
	if phase == Phase.INTRO or phase == Phase.COUNTDOWN:
		_set_phase(Phase.PLAYING)


func _physics_process(delta: float) -> void:
	MatchClock.advance(delta)
	phase_time += delta
	match phase:
		Phase.INTRO:
			if phase_time >= INTRO_TIME:
				_set_phase(Phase.COUNTDOWN)
		Phase.COUNTDOWN:
			var n := ceili(COUNTDOWN_TIME - phase_time)
			if n != _last_countdown and n > 0:
				_last_countdown = n
				countdown_tick.emit(n)
				AudioManager.play(&"countdown", 1.0)
			if phase_time >= COUNTDOWN_TIME:
				countdown_tick.emit(0)
				_set_phase(Phase.PLAYING)
		Phase.PLAYING:
			elapsed += delta
			time_left = maxf(0.0, time_left - delta)
			mode.mode_physics_process(delta)
			_track_stats()
			if _finish_requested:
				_set_phase(Phase.FINISHED)
			elif time_left <= 0.0:
				_finish_success = false
				mode_time_up()
				_set_phase(Phase.FINISHED)
		Phase.FINISHED:
			if phase_time >= FINISH_TIME:
				_set_phase(Phase.RESULTS)


func mode_time_up() -> void:
	if mode.has_method("on_time_up"):
		mode.call("on_time_up")


func _track_stats() -> void:
	for p in players:
		var last: Vector3 = _last_positions.get(p.player_index, p.global_position)
		var moved := Vector2(p.global_position.x - last.x, p.global_position.z - last.z).length()
		if moved < 2.0 and not p.is_respawning:
			score.add_stat(p.player_index, &"distance", moved)
		_last_positions[p.player_index] = p.global_position


func is_playing() -> bool:
	return phase == Phase.PLAYING


## Ends the round early (objective completed, or everyone finished).
func request_finish(p_success: bool) -> void:
	if phase != Phase.PLAYING or _finish_requested:
		return
	_finish_requested = true
	_finish_success = p_success


func _set_controls(enabled: bool) -> void:
	for p in players:
		p.controls_enabled = enabled
		if not enabled and p.input:
			p.input.reset()
	if not enabled:
		TouchState.reset()


# ---------------------------------------------------------------- scoring & messages

func award(player_index: int, category: StringName, points: int, reason: String = "",
		world_pos: Vector3 = Vector3.INF) -> void:
	if phase != Phase.PLAYING and phase != Phase.FINISHED:
		return
	score.add(player_index, category, points, reason)
	if not chaos.get_active_ids().is_empty():
		score.add_stat(player_index, &"chaos_points", points)
	if world_pos != Vector3.INF and points > 0:
		var color: Color = Catalog.PLAYER_TAG_COLORS[player_index % 4]
		# With people playing, CPU buddies' points are shown small and short.
		var quiet := setup.human_count() > 0 and player_index < players.size() and not players[player_index].is_human
		if quiet:
			fx.floating_text("+%d" % points, world_pos, color.lightened(0.2), true)
		else:
			fx.floating_text(("+%d %s" % [points, reason]).strip_edges(), world_pos, color.lightened(0.2))


func _on_scored(_player_index: int, category: StringName, points: int, _reason: String) -> void:
	if points > 0:
		var pitch: float = {ScoreKeeper.STARS: 1.25, ScoreKeeper.TEAMWORK: 1.1, ScoreKeeper.RECOVERY: 1.05}.get(category, 1.0)
		AudioManager.play_varied(&"score", pitch, 0.04, -3.0)


func show_message(text: String, color: Color = Color.WHITE, seconds: float = 2.2) -> void:
	message_requested.emit(text, color, seconds)


## Character voices ("wee-hee!", "uh-oh"). When several creatures react at
## once (everyone gasps at a chaos switch) only one voice plays.
func _on_player_reacted(kind: StringName, p: PlayerCharacter) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _voice_any_at < VOICE_GAP_ANY or now - float(_voice_last.get(kind, -10.0)) < VOICE_GAP_SAME:
		return
	_voice_any_at = now
	_voice_last[kind] = now
	var pitch: float = Catalog.character(p.character_id).voice_pitch
	AudioManager.play_varied(StringName("voice_%s" % kind), pitch, 0.05, -3.0)


# ---------------------------------------------------------------- chaos presentation

func _on_chaos_started(ev: ChaosEvent) -> void:
	AudioManager.play(ev.sfx_start)
	for p in players:
		p.react(ev.reaction)
	_refresh_chaos_looks()
	camera.shake(0.25)


func _on_chaos_ended(ev: ChaosEvent) -> void:
	AudioManager.play(ev.sfx_end)
	_refresh_chaos_looks()


func _refresh_chaos_looks() -> void:
	var keys: Array[StringName] = []
	for entry in chaos.get_active_entries():
		var ev: ChaosEvent = entry.event
		if ev.vfx != &"":
			keys.append(ev.vfx)
	for p in players:
		p.visual.set_chaos_looks(keys)


# ---------------------------------------------------------------- input

func _on_player_interact(player: PlayerCharacter) -> void:
	if is_playing():
		mode.handle_interact(player)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		if phase == Phase.RESULTS:
			return
		set_paused(not is_paused)
		get_viewport().set_input_as_handled()
		return
	if not GameState.get_setting("debug_tools", false):
		return
	if event.is_action_pressed(&"debug_panel"):
		debug_panel.toggle()
		get_viewport().set_input_as_handled()
		return
	if is_playing():
		var lib := chaos.library
		for i in range(1, 10):
			if event.is_action_pressed(StringName("debug_event_%d" % i)) and i <= lib.size():
				chaos.force_event(lib[i - 1].id, false, 1.5)
				get_viewport().set_input_as_handled()
				return
		if event.is_action_pressed(&"debug_clear_events"):
			chaos.end_all_events()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if phase == Phase.PLAYING or phase == Phase.COUNTDOWN or phase == Phase.INTRO:
			set_paused(true)


func set_paused(value: bool) -> void:
	if value == is_paused:
		return
	if value and (phase == Phase.RESULTS):
		return
	is_paused = value
	get_tree().paused = value
	TouchState.reset()
	for p in players:
		if p.input:
			p.input.reset()
	pause_menu.visible = value
	if value:
		pause_menu.open()
	paused_changed.emit(value)


# ---------------------------------------------------------------- results & flow

func _build_result() -> Dictionary:
	var text := mode.get_result_text(success)
	var awards := _pick_awards()
	var list: Array[Dictionary] = []
	for p in players:
		var slot: MatchSetup.Slot = setup.slots[p.player_index]
		list.append({
			"index": p.player_index,
			"label": p.display_name,
			"character": slot.character_id,
			"hat": slot.hat_id,
			"paint": slot.paint_id,
			"character_name": Catalog.character(slot.character_id).name,
			"color": Catalog.PLAYER_TAG_COLORS[p.player_index % 4],
			"total": score.total(p.player_index),
			"breakdown": score.breakdown(p.player_index),
			"award": awards[p.player_index],
			"is_human": p.is_human,
		})
	var progress := {"mode_id": setup.mode_id}
	var human_stars := 0
	var human_points := 0
	for p in players:
		if p.is_human:
			human_stars += int(score.get_stat(p.player_index, &"stars"))
			human_points += score.total(p.player_index)
	progress.stars = human_stars
	progress.party_points = human_points
	progress.merge(mode.get_progress_stats(success), true)
	var unlocked: Array = []
	if not setup.no_progress:
		unlocked = GameState.record_round(progress)
	return {
		"mode_id": setup.mode_id,
		"mode_name": mode_info.get("name", "Round"),
		"success": success,
		"headline": text.get("headline", ""),
		"subline": text.get("subline", ""),
		"team": mode.team_mode,
		"players": list,
		"ranking": score.ranking(),
		"team_total": score.team_total(),
		"duration": elapsed,
		"unlocked": unlocked,
		"next_unlock": GameState.next_unlock_hint(),
		"progress": progress,
	}


func _pick_awards() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.resize(players.size())
	var given := {}
	var candidates: Array[Dictionary] = []
	candidates.append_array(mode.get_award_candidates())
	candidates.append_array(COMMON_AWARDS)
	for c in candidates:
		var best := -1
		var best_v := 0.0
		for i in players.size():
			if given.has(i):
				continue
			var v := score.get_stat(i, c.stat)
			if v > best_v + 0.001:
				best_v = v
				best = i
		if best >= 0:
			out[best] = {"title": c.title, "text": c.text}
			given[best] = true
	var f := 0
	for i in players.size():
		if not given.has(i):
			out[i] = FRIENDLY_AWARDS[(i + f) % FRIENDLY_AWARDS.size()]
			f += 1
	return out


## Same party, same mode, fresh round.
func restart_round() -> void:
	var next := setup.duplicate_setup()
	next.seed = 0
	GameState.current_setup = next
	Router.go(&"match")


## Next game in the party playlist (or the next mode in the list).
func next_round() -> void:
	var next := setup.duplicate_setup()
	next.seed = 0
	if not next.playlist.is_empty():
		next.playlist_index = (next.playlist_index + 1) % next.playlist.size()
		next.mode_id = next.playlist[next.playlist_index]
	else:
		var idx := (Catalog.mode_index(setup.mode_id) + 1) % Catalog.MODES.size()
		next.mode_id = Catalog.MODES[idx].id
	GameState.current_setup = next
	Router.go(&"match")


func quit_to_menu() -> void:
	set_paused(false)
	Router.go(&"menu")


func _exit_tree() -> void:
	get_tree().paused = false
	TouchState.reset()
	MatchClock.externally_driven = false
