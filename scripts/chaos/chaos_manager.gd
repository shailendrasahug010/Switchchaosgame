class_name ChaosManager
extends Node
## The Chaos Switch: schedules, announces, starts and ends rule-changing events.
##
## Flow for every event: pick -> ANNOUNCE (countdown, banner, sound) -> START
## (modifiers applied) -> END after its duration (modifiers removed).
## No event ever starts without being announced first, unless a debug/test
## call explicitly asks for an instant switch.
##
## Game logic only: this node never touches UI. The HUD, sounds and character
## effects listen to the signals below.

signal event_announced(event: ChaosEvent, lead_time: float)
signal countdown_changed(event: ChaosEvent, seconds_left: int)
signal announcement_cancelled(event: ChaosEvent)
signal event_started(event: ChaosEvent)
signal event_ended(event: ChaosEvent)
signal active_events_changed

@export var library: Array[ChaosEvent] = []
## Ids allowed to be picked. Empty means every event in the library.
@export var enabled_ids: Array[StringName] = []
@export_range(0.0, 60.0, 0.5) var first_event_delay: float = 6.0
@export_range(1.0, 60.0, 0.5) var interval_min: float = 11.0
@export_range(1.0, 60.0, 0.5) var interval_max: float = 15.0
@export_range(0.5, 10.0, 0.5) var announce_time: float = 3.0
@export_range(1, 4) var max_active: int = 2
## Never pick any of the last N events again (when other choices exist).
@export_range(0, 6) var avoid_repeat: int = 2
## When false (online client) events only start/end on remote commands.
@export var is_authority: bool = true
## When false no new events are picked automatically (debug panel, tests);
## events can still be forced and running ones still expire.
@export var auto_schedule: bool = true

var context: ChaosContext = ChaosContext.new()
var rules: ModifierStack:
	get:
		return context.rules
var running: bool = false

var _time_to_next: float = 0.0
var _pending: ChaosEvent = null
var _pending_left: float = 0.0
var _last_countdown: int = -1
var _active: Dictionary = {}  # StringName -> {"event": ChaosEvent, "left": float}
var _history: Array[StringName] = []


func _ready() -> void:
	if library.is_empty():
		library = Catalog.load_chaos_library()


## Starts the schedule for a new round. [param seed_value] makes picks repeatable.
func start(seed_value: int) -> void:
	stop()
	context.rng.seed = seed_value
	_history.clear()
	running = true
	_time_to_next = first_event_delay


## Ends everything immediately and restores every rule to normal.
func stop() -> void:
	running = false
	if _pending != null:
		var cancelled := _pending
		_pending = null
		announcement_cancelled.emit(cancelled)
	for id: StringName in _active.keys():
		_end_event(id)
	context.rules.clear()


func _physics_process(delta: float) -> void:
	if not running:
		return
	_tick_active(delta)
	if _pending != null:
		_tick_pending(delta)
		return
	if not is_authority or not auto_schedule:
		return
	_time_to_next -= delta
	if _time_to_next > 0.0:
		return
	if _active.size() >= max_active:
		_time_to_next = 1.0  # wait for a free slot
		return
	var next := pick_next_event()
	if next == null:
		_time_to_next = 2.0
		return
	announce(next, announce_time)
	_time_to_next = context.rng.randf_range(interval_min, maxf(interval_min, interval_max))


func _tick_active(delta: float) -> void:
	for id: StringName in _active.keys():
		var entry: Dictionary = _active[id]
		entry.left = float(entry.left) - delta
		(entry.event as ChaosEvent).tick(context, delta)
		# Online clients wait for the server's "end", with a small safety margin.
		var limit := 0.0 if is_authority else -1.5
		if entry.left <= limit:
			_end_event(id)


func _tick_pending(delta: float) -> void:
	_pending_left -= delta
	var secs := maxi(0, ceili(_pending_left))
	if secs != _last_countdown:
		_last_countdown = secs
		countdown_changed.emit(_pending, secs)
	if _pending_left <= 0.0 and is_authority:
		var ev := _pending
		_pending = null
		_begin_event(ev)


## Weighted random pick that respects enabled ids, recent history,
## event compatibility and what is already running. Returns null if none fit.
func pick_next_event() -> ChaosEvent:
	var pool := get_enabled_events()
	var candidates: Array[ChaosEvent] = []
	var recent := _history.slice(maxi(0, _history.size() - avoid_repeat))
	for ev in pool:
		if _active.has(ev.id) or recent.has(ev.id):
			continue
		if not _fits_with_active(ev):
			continue
		candidates.append(ev)
	if candidates.is_empty():
		# Only repeats are left: allow them, but never the very last one.
		var last: StringName = _history[-1] if not _history.is_empty() else &""
		for ev in pool:
			if not _active.has(ev.id) and ev.id != last and _fits_with_active(ev):
				candidates.append(ev)
	if candidates.is_empty():
		return null
	var total := 0.0
	for ev in candidates:
		total += maxf(0.0, ev.weight)
	if total <= 0.0:
		return candidates[context.rng.randi() % candidates.size()]
	var roll := context.rng.randf() * total
	for ev in candidates:
		roll -= maxf(0.0, ev.weight)
		if roll <= 0.0:
			return ev
	return candidates[-1]


func _fits_with_active(ev: ChaosEvent) -> bool:
	for entry: Dictionary in _active.values():
		if not ev.can_coexist_with(entry.event):
			return false
	return true


func get_enabled_events() -> Array[ChaosEvent]:
	var out: Array[ChaosEvent] = []
	for ev in library:
		if enabled_ids.is_empty() or enabled_ids.has(ev.id):
			out.append(ev)
	return out


func find_event(id: StringName) -> ChaosEvent:
	for ev in library:
		if ev.id == id:
			return ev
	return null


## Shows the warning for [param ev]; it starts when the countdown reaches zero.
func announce(ev: ChaosEvent, lead_time: float = -1.0) -> void:
	if ev == null:
		return
	if lead_time < 0.0:
		lead_time = announce_time
	if _pending != null:
		announcement_cancelled.emit(_pending)
	_pending = ev
	_pending_left = lead_time
	_last_countdown = -1
	event_announced.emit(ev, lead_time)


## Debug / test entry point. With [param instant] the event switches on right
## away (still emitting all signals); otherwise it gets a short announcement.
func force_event(id: StringName, instant: bool = false, lead_time: float = 1.5) -> bool:
	var ev := find_event(id)
	if ev == null:
		push_warning("ChaosManager: unknown event '%s'" % id)
		return false
	if not running:
		running = true
		_time_to_next = interval_min
	if instant:
		if _pending == ev:
			_pending = null
		_begin_event(ev)
	else:
		announce(ev, lead_time)
	return true


## Ends one active event early (debug panel, network command, tests).
func end_event(id: StringName) -> void:
	if _active.has(id):
		_end_event(id)


func end_all_events() -> void:
	for id: StringName in _active.keys():
		_end_event(id)


func _begin_event(ev: ChaosEvent) -> void:
	if _active.has(ev.id):
		# Already running: just refresh its timer.
		_active[ev.id].left = ev.duration
		return
	# Make room: end anything this event cannot share the stage with...
	for id: StringName in _active.keys():
		if not ev.can_coexist_with(_active[id].event):
			_end_event(id)
	# ...and the event closest to finishing if we are still at the limit.
	while _active.size() >= max_active:
		var soonest: StringName = &""
		var soonest_left := INF
		for id: StringName in _active.keys():
			if float(_active[id].left) < soonest_left:
				soonest_left = float(_active[id].left)
				soonest = id
		_end_event(soonest)
	ev.activate(context)
	_active[ev.id] = {"event": ev, "left": ev.duration}
	_history.append(ev.id)
	if _history.size() > 12:
		_history.remove_at(0)
	event_started.emit(ev)
	active_events_changed.emit()


func _end_event(id: StringName) -> void:
	if not _active.has(id):
		return
	var ev: ChaosEvent = _active[id].event
	_active.erase(id)
	ev.deactivate(context)
	event_ended.emit(ev)
	active_events_changed.emit()


# ---------------------------------------------------------------- queries

func is_active(id: StringName) -> bool:
	return _active.has(id)


func get_active_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _active.keys():
		out.append(id)
	return out


## [{event, left}] for every running event, for HUD timers.
func get_active_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in _active.values():
		out.append({"event": entry.event, "left": maxf(0.0, float(entry.left))})
	return out


func get_pending_event() -> ChaosEvent:
	return _pending


func get_pending_time_left() -> float:
	return maxf(0.0, _pending_left)


func get_history() -> Array[StringName]:
	return _history.duplicate()


# ---------------------------------------------------------------- online clients

## Applies a command received from the authoritative server.
## [param phase] is "announce", "start" or "end".
func apply_remote(id: StringName, phase: String, value: float = 0.0) -> void:
	var ev := find_event(id)
	if ev == null:
		return
	running = true
	match phase:
		"announce":
			announce(ev, value)
		"start":
			if _pending == ev:
				_pending = null
			_begin_event(ev)
			if value > 0.0 and _active.has(id):
				_active[id].left = value
		"end":
			_end_event(id)
