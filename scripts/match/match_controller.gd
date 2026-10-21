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
##
## Online play (see Net and docs/ONLINE_MULTIPLAYER_PLAN.md) uses the same
## scene in two more roles ([enum NetRole]):
##   SERVER  inside a room on the room server: no screen, no sound. It runs the
##           real rules and tells the room about phases, points, effects and
##           chaos switches, which the room sends to the phones.
##   CLIENT  on each phone: its own creature moves right away on the phone;
##           everybody else, the chaos switches, the timer, the points and the
##           mode's state follow the server.

signal phase_changed(phase: Phase)
signal countdown_tick(value: int)
signal message_requested(text: String, color: Color, seconds: float)
signal round_finished(success: bool)
signal paused_changed(paused: bool)

enum Phase { LOADING, INTRO, COUNTDOWN, PLAYING, FINISHED, RESULTS }
enum NetRole { OFFLINE, SERVER, CLIENT }

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
## How this match takes part in online play. Set before the node enters the tree.
var net_role: NetRole = NetRole.OFFLINE
## SERVER: the room that forwards everything to the phones (see Net.Room).
var net_room: Object = null
## CLIENT: index of the creature this phone controls.
var local_player_index: int = -1
## This round's clock in seconds. Every moving obstacle follows it (MatchClock).
var clock := 0.0

var _finish_requested := false
var _finish_success := false
var _last_countdown := -1
var _last_positions: Dictionary = {}
var _voice_any_at := -10.0
var _voice_last: Dictionary = {}
var _phase_started_at := 0.0
var _server_awards: Array = []


func _ready() -> void:
	if setup == null:
		setup = GameState.current_setup
	if net_role == NetRole.OFFLINE and Net.has_pending_client_match():
		Net.attach_client_match(self)
	if setup == null:
		setup = MatchSetup.quick(&"cake_dash", 1, 3, GameState.profile.character)
		GameState.current_setup = setup
	round_seed = setup.seed if setup.seed != 0 else (randi() % 2000000000) + 1
	_init_clock()
	if net_role != NetRole.SERVER:
		TouchState.reset()
	_load_arena()
	_spawn_players()
	_setup_camera()
	_setup_chaos()
	if net_role == NetRole.SERVER:
		_strip_presentation()
	else:
		hud.setup(self)
		touch_controls.setup(self)
		pause_menu.setup(self)
		results_screen.setup(self)
		debug_panel.setup(self)
		AudioManager.play_music(&"match")
	match net_role:
		NetRole.OFFLINE:
			_set_phase(Phase.INTRO)
			if fast_start or OS.get_cmdline_user_args().has("--fast-start"):
				skip_intro()
		NetRole.SERVER:
			pass  # The room calls begin() once every phone has loaded the arena.
		NetRole.CLIENT:
			Net.client_match_loaded(self)


func is_authority() -> bool:
	return net_role != NetRole.CLIENT


func is_online() -> bool:
	return net_role != NetRole.OFFLINE


func _init_clock() -> void:
	clock = 0.0
	if net_role == NetRole.SERVER:
		MatchClock.per_viewport = true
		get_viewport().set_meta(MatchClock.VIEWPORT_META, 0.0)
	else:
		MatchClock.externally_driven = net_role == NetRole.CLIENT
		MatchClock.reset(0.0)


func _advance_clock(delta: float) -> void:
	match net_role:
		NetRole.SERVER:
			clock += delta
			get_viewport().set_meta(MatchClock.VIEWPORT_META, clock)
		NetRole.CLIENT:
			clock = Net.client_round_clock(clock, delta)
			MatchClock.time = clock
		_:
			MatchClock.advance(delta)
			clock = MatchClock.time


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
	var shows := net_role != NetRole.SERVER
	for i in setup.slots.size():
		var slot: MatchSetup.Slot = setup.slots[i]
		var p: PlayerCharacter = PLAYER_SCENE.instantiate()
		p.name = "Player%d" % (i + 1)
		p.player_index = i
		p.rules = chaos.rules
		p.kill_y = mode.kill_height
		p.is_cpu = slot.kind == MatchSetup.Kind.CPU or slot.remote_cpu
		var label := "CPU" if p.is_cpu else ("P%d" % (i + 1) if setup.online else "P%d" % slot.local_index)
		p.display_name = label
		match net_role:
			NetRole.SERVER:
				# People on phones are proxies; CPU buddies run right here.
				p.is_human = slot.kind == MatchSetup.Kind.REMOTE and not slot.remote_cpu
				if p.is_cpu:
					p.input = BotInputSource.new(mode, slot.bot_skill, round_seed + 97 * (i + 1))
				else:
					p.input = PlayerInputSource.new()
					p.net_mode = PlayerCharacter.NetMode.PROXY
			NetRole.CLIENT:
				# Only this phone's own creature counts as "the person here".
				p.is_human = i == local_player_index
				if p.is_human:
					p.input = BotInputSource.new(mode, 0.8, round_seed + 31 * (i + 1)) if slot.autopilot \
							else LocalInputSource.new(1)
				else:
					p.input = PlayerInputSource.new()
					p.net_mode = PlayerCharacter.NetMode.PUPPET
			_:
				p.is_human = slot.kind == MatchSetup.Kind.HUMAN
				match slot.kind:
					MatchSetup.Kind.HUMAN:
						if slot.autopilot:
							p.input = BotInputSource.new(mode, 0.8, round_seed + 31 * (i + 1))
						else:
							p.input = LocalInputSource.new(slot.local_index)
					MatchSetup.Kind.CPU:
						p.input = BotInputSource.new(mode, slot.bot_skill, round_seed + 97 * (i + 1))
					_:
						p.input = PlayerInputSource.new()
		players_root.add_child(p)
		var xf: Transform3D = spawns[i % spawns.size()]
		var fwd := -xf.basis.z
		p.teleport(xf.origin + Vector3(0, 0.05, 0), Vector3(fwd.x, 0, fwd.z))
		p.respawn_position = xf.origin + Vector3(0, 0.3, 0)
		p.setup_look(slot.character_id, slot.hat_id, slot.paint_id, Catalog.PLAYER_TAG_COLORS[i % 4], label)
		if net_role == NetRole.SERVER and net_room:
			# Hooked up after placing: every phone places its own copy the same way.
			p.net_hook = net_room.player_command.bind(self)
		p.interact_requested.connect(_on_player_interact)
		p.jumped.connect(func() -> void:
			if shows:
				AudioManager.play_varied(&"jump", Catalog.character(slot.character_id).voice_pitch)
			if is_authority():
				score.add_stat(p.player_index, &"jumps"))
		if shows:
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
	if net_role == NetRole.SERVER:
		camera.process_mode = Node.PROCESS_MODE_DISABLED
		return
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
	chaos.event_started.connect(_on_chaos_started)
	chaos.event_ended.connect(_on_chaos_ended)
	match net_role:
		NetRole.SERVER:
			chaos.event_announced.connect(func(ev: ChaosEvent, lead: float) -> void:
				if net_room:
					net_room.match_chaos(self, ev.id, "announce", lead))
			chaos.event_started.connect(func(ev: ChaosEvent) -> void:
				if net_room:
					net_room.match_chaos(self, ev.id, "start", ev.duration))
			chaos.event_ended.connect(func(ev: ChaosEvent) -> void:
				if net_room:
					net_room.match_chaos(self, ev.id, "end", 0.0))
			return
		NetRole.CLIENT:
			# Switches only happen when the room server says so.
			chaos.is_authority = false
	chaos.event_announced.connect(func(ev: ChaosEvent, _lead: float) -> void:
		AudioManager.play(ev.sfx_announce))
	chaos.countdown_changed.connect(func(_ev: ChaosEvent, secs: int) -> void:
		if secs > 0 and is_playing():
			AudioManager.play(&"tick", 1.0 + (3 - secs) * 0.12))


## Room server: nothing here is ever drawn or heard, so drop the screens and
## send effects to the phones instead.
func _strip_presentation() -> void:
	for n: Node in [get_node_or_null("UI"), get_node_or_null("Overlay")]:
		if n:
			remove_child(n)
			n.queue_free()
	if net_room:
		fx.net_forward = func(kind: StringName, args: Array) -> void:
			net_room.match_fx(self, kind, args)


# ---------------------------------------------------------------- phases

func _set_phase(p: Phase) -> void:
	phase = p
	phase_time = 0.0
	_phase_started_at = clock
	var shows := net_role != NetRole.SERVER
	match p:
		Phase.INTRO:
			_set_controls(false)
		Phase.COUNTDOWN:
			_last_countdown = -1
		Phase.PLAYING:
			_set_controls(true)
			if setup.chaos_enabled and is_authority():
				chaos.start(round_seed)
			mode.on_round_started()
			if shows:
				AudioManager.play(&"go")
		Phase.FINISHED:
			_set_controls(false)
			chaos.stop()
			_refresh_chaos_looks()
			mode.on_round_ended(_finish_success)
			success = _finish_success
			if shows:
				for pl in players:
					if success:
						pl.celebrate()
					else:
						pl.react(&"oops")
				AudioManager.play(&"victory" if success else &"round_over")
			round_finished.emit(success)
		Phase.RESULTS:
			result = _build_result()
			if net_role == NetRole.SERVER:
				if net_room:
					net_room.match_results(self, result)
			else:
				results_screen.show_results(result)
	if net_role == NetRole.SERVER and net_room:
		net_room.match_phase(self, p, clock, success)
	phase_changed.emit(p)


func skip_intro() -> void:
	if phase == Phase.INTRO or phase == Phase.COUNTDOWN:
		_set_phase(Phase.PLAYING)


## Room server: everyone has loaded the arena (or waited long enough): go.
func begin() -> void:
	if phase == Phase.LOADING:
		_set_phase(Phase.INTRO)


func _physics_process(delta: float) -> void:
	if phase == Phase.LOADING and net_role != NetRole.CLIENT:
		return
	_advance_clock(delta)
	if net_role == NetRole.CLIENT:
		_client_tick(delta)
		return
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
				if net_role != NetRole.SERVER:
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


## Phone: phases come from the server; this only keeps the countdown, the
## timer and the mode's looks moving between messages.
func _client_tick(delta: float) -> void:
	if phase == Phase.LOADING:
		return
	phase_time = maxf(0.0, clock - _phase_started_at)
	match phase:
		Phase.COUNTDOWN:
			var n := ceili(COUNTDOWN_TIME - phase_time)
			if n != _last_countdown and n > 0:
				_last_countdown = n
				countdown_tick.emit(n)
				AudioManager.play(&"countdown", 1.0)
		Phase.PLAYING:
			elapsed += delta
			time_left = Net.client_time_left(time_left, delta)
			mode.mode_client_process(delta)


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
	if phase != Phase.PLAYING or _finish_requested or not is_authority():
		return
	_finish_requested = true
	_finish_success = p_success


func _set_controls(enabled: bool) -> void:
	for p in players:
		p.controls_enabled = enabled
		if not enabled and p.input:
			p.input.reset()
	if not enabled and net_role != NetRole.SERVER:
		TouchState.reset()


# ---------------------------------------------------------------- scoring & messages

func award(player_index: int, category: StringName, points: int, reason: String = "",
		world_pos: Vector3 = Vector3.INF) -> void:
	if not is_authority():
		return
	if phase != Phase.PLAYING and phase != Phase.FINISHED:
		return
	apply_award(player_index, category, points, reason, world_pos)
	if net_role == NetRole.SERVER and net_room:
		net_room.match_scored(self, player_index, category, points, reason, world_pos)


## Adds points and shows the "+50 Star!" pop. Phones call this for points the
## room server gave.
func apply_award(player_index: int, category: StringName, points: int, reason: String = "",
		world_pos: Vector3 = Vector3.INF) -> void:
	score.add(player_index, category, points, reason)
	if not chaos.get_active_ids().is_empty():
		score.add_stat(player_index, &"chaos_points", points)
	if net_role == NetRole.SERVER:
		return
	if world_pos != Vector3.INF and points > 0:
		var color: Color = Catalog.PLAYER_TAG_COLORS[player_index % 4]
		# With people playing, other creatures' points are shown small and short.
		var quiet := setup.human_count() > 0 and player_index < players.size() and not players[player_index].is_human
		if quiet:
			fx.floating_text("+%d" % points, world_pos, color.lightened(0.2), true)
		else:
			fx.floating_text(("+%d %s" % [points, reason]).strip_edges(), world_pos, color.lightened(0.2))


func _on_scored(_player_index: int, category: StringName, points: int, _reason: String) -> void:
	if points > 0 and net_role != NetRole.SERVER:
		var pitch: float = {ScoreKeeper.STARS: 1.25, ScoreKeeper.TEAMWORK: 1.1, ScoreKeeper.RECOVERY: 1.05}.get(category, 1.0)
		AudioManager.play_varied(&"score", pitch, 0.04, -3.0)


func show_message(text: String, color: Color = Color.WHITE, seconds: float = 2.2) -> void:
	message_requested.emit(text, color, seconds)
	if net_role == NetRole.SERVER and net_room:
		net_room.match_message(self, text, color, seconds)


## Sound for everyone in the round (the room server sends it to the phones).
func play_sfx(id: StringName, pitch: float = 1.0) -> void:
	if net_role == NetRole.SERVER:
		if net_room:
			net_room.match_fx(self, &"sfx", [String(id), pitch])
		return
	AudioManager.play(id, pitch)


func shake_camera(amount: float) -> void:
	if net_role == NetRole.SERVER:
		if net_room:
			net_room.match_fx(self, &"shake", [amount])
		return
	camera.shake(amount)


## Room server: a mode event for every phone (see GameMode.net_event).
func send_mode_event(event_name: StringName, args: Array) -> void:
	if net_role == NetRole.SERVER and net_room:
		net_room.match_mode_event(self, event_name, args)


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
	if net_role == NetRole.SERVER:
		return
	AudioManager.play(ev.sfx_start)
	for p in players:
		p.react(ev.reaction)
	_refresh_chaos_looks()
	camera.shake(0.25)


func _on_chaos_ended(ev: ChaosEvent) -> void:
	if net_role == NetRole.SERVER:
		return
	AudioManager.play(ev.sfx_end)
	_refresh_chaos_looks()


func _refresh_chaos_looks() -> void:
	if net_role == NetRole.SERVER:
		return
	var keys: Array[StringName] = []
	for entry in chaos.get_active_entries():
		var ev: ChaosEvent = entry.event
		if ev.vfx != &"":
			keys.append(ev.vfx)
	for p in players:
		p.visual.set_chaos_looks(keys)


# ---------------------------------------------------------------- input

func _on_player_interact(player: PlayerCharacter) -> void:
	if not is_playing():
		return
	if net_role == NetRole.CLIENT:
		# The server checks the reach and does it (Net.c_interact).
		if player.player_index == local_player_index:
			Net.client_send_interact()
		return
	mode.handle_interact(player)


func _unhandled_input(event: InputEvent) -> void:
	# "ui_cancel" only opens the pause menu here, never closes it — closing
	# (resuming) is the pause menu's own job (it listens for ui_cancel too,
	# but only while visible). That split means this never has to guess
	# whether the pause menu already consumed the same event.
	if event.is_action_pressed(&"pause") or (event.is_action_pressed(&"ui_cancel") and not is_paused):
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
	# Online, only the room server switches the rules.
	if is_playing() and is_authority():
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


## Offline this freezes the round. Online the round can't wait for one phone,
## so the pause card only covers the screen and this phone's controls rest.
func set_paused(value: bool) -> void:
	if value == is_paused or net_role == NetRole.SERVER:
		return
	if value and (phase == Phase.RESULTS):
		return
	is_paused = value
	if net_role == NetRole.CLIENT:
		for p in players:
			if p.is_simulated():
				p.input_muted = value
	else:
		get_tree().paused = value
	TouchState.reset()
	for p in players:
		if p.input:
			p.input.reset()
	pause_menu.visible = value
	if value:
		pause_menu.open()
	paused_changed.emit(value)


# ---------------------------------------------------------------- online (phone side)

## Phone: the server moved the round to [param p] at round clock [param started_at].
func net_set_phase(p: Phase, started_at: float, p_success: bool = false) -> void:
	if net_role != NetRole.CLIENT or p == phase or p == Phase.LOADING:
		return
	if p == Phase.PLAYING and phase < Phase.PLAYING:
		countdown_tick.emit(0)
	if p >= Phase.FINISHED:
		_finish_success = p_success
		if phase < Phase.FINISHED and p == Phase.RESULTS:
			# Joined (or came back) at the very end: run the finish steps too.
			_set_phase(Phase.FINISHED)
	_set_phase(p)
	_phase_started_at = started_at
	phase_time = maxf(0.0, clock - started_at)


## Phone: points the server gave.
func net_apply_scored(player_index: int, category: StringName, points: int, reason: String,
		world_pos: Vector3) -> void:
	if net_role == NetRole.CLIENT and ScoreKeeper.CATEGORIES.has(category):
		apply_award(player_index, category, points, reason, world_pos)


## Phone: an effect the server asked for (sounds, puffs, confetti, shakes).
func net_apply_fx(kind: StringName, args: Array) -> void:
	if net_role != NetRole.CLIENT:
		return
	match kind:
		&"sfx":
			if args.size() == 2 and args[0] is String:
				AudioManager.play(StringName(args[0]), clampf(float(args[1]), 0.25, 4.0))
		&"shake":
			if args.size() == 1:
				camera.shake(clampf(float(args[0]), 0.0, 1.0))
		&"puff":
			if args.size() == 3 and args[0] is Vector3 and args[1] is Color:
				fx.puff(args[0], args[1], clampf(float(args[2]), 0.1, 3.0))
		&"confetti":
			if args.size() == 1 and args[0] is Vector3:
				fx.confetti(args[0])
		&"text":
			if args.size() == 4 and args[0] is String and args[1] is Vector3 and args[2] is Color:
				fx.floating_text(args[0], args[1], args[2], bool(args[3]))


## Phone: the final points, stats and awards decided by the server.
func net_set_results(score_data: Dictionary, awards: Array) -> void:
	if net_role != NetRole.CLIENT:
		return
	score.import_data(score_data)
	_server_awards.clear()
	for a in awards:
		if typeof(a) == TYPE_DICTIONARY and a.get("title") is String and a.get("text") is String:
			_server_awards.append({"title": a.title, "text": a.text})
		else:
			_server_awards.append(FRIENDLY_AWARDS[0])


# ---------------------------------------------------------------- results & flow

func _build_result() -> Dictionary:
	var text := mode.get_result_text(success)
	var awards: Array = _server_awards if (net_role == NetRole.CLIENT and _server_awards.size() == players.size()) \
			else _pick_awards()
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
	if not setup.no_progress and net_role != NetRole.SERVER:
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
		"next_unlock": GameState.next_unlock_hint() if net_role != NetRole.SERVER else {},
		"progress": progress,
		"online": is_online(),
		"awards": awards,
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
	if is_online():
		back_to_room()
		return
	var next := setup.duplicate_setup()
	next.seed = 0
	GameState.current_setup = next
	Router.go(&"match")


## Next game in the party playlist (or the next mode in the list).
func next_round() -> void:
	if is_online():
		back_to_room()
		return
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


## Online: back to the room screen (the host starts the next round there).
func back_to_room() -> void:
	set_paused(false)
	Router.go(&"online")


func quit_to_menu() -> void:
	set_paused(false)
	if net_role == NetRole.CLIENT:
		Net.leave_room()
	Router.go(&"menu")


func _exit_tree() -> void:
	if net_role == NetRole.SERVER:
		return
	get_tree().paused = false
	TouchState.reset()
	MatchClock.externally_driven = false
	if net_role == NetRole.CLIENT:
		Net.detach_client_match(self)
