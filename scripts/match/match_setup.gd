class_name MatchSetup
extends RefCounted
## Everything needed to start a round: the mode, who is playing and the rules.
## Built by the setup screens (or by tests) and read by MatchController.

## HUMAN: plays on this device. CPU: a CPU buddy run by this device.
## REMOTE: online only, someone (or a CPU buddy) run by another device.
enum Kind { HUMAN, CPU, REMOTE }


class Slot:
	extends RefCounted
	var kind: int = Kind.HUMAN
	## For HUMAN slots: which local control set drives it (1 = keyboard WASD / touch / pad 0).
	var local_index: int = 1
	var character_id: StringName = &"bloop"
	var hat_id: StringName = &"none"
	var paint_id: StringName = &"classic"
	## For CPU slots: 0.0 (sleepy) .. 1.0 (sharp). Kept modest so kids can win.
	var bot_skill: float = 0.6
	## Development aid: a HUMAN slot steered by the CPU brain (screenshots,
	## soak tests). It still counts as a person for the camera and the HUD.
	var autopilot: bool = false
	## Online phones: this REMOTE slot is a CPU buddy run by the room server.
	var remote_cpu: bool = false

	func duplicate_slot() -> Slot:
		var s := Slot.new()
		s.kind = kind
		s.local_index = local_index
		s.character_id = character_id
		s.hat_id = hat_id
		s.paint_id = paint_id
		s.bot_skill = bot_skill
		s.autopilot = autopilot
		s.remote_cpu = remote_cpu
		return s


var mode_id: StringName = &"cake_dash"
var slots: Array[Slot] = []
var chaos_enabled: bool = true
## Empty means "use the mode's own list of suitable events".
var enabled_events: Array[StringName] = []
## 0 means "use the mode's default round length".
var round_time: float = 0.0
## 0 means "pick a random seed when the round starts".
var seed: int = 0
## Cake Dash: with two or more players the cake is heavy and wants a team.
var team_carry: bool = true
## Tests and demos set this so a round never changes the save file.
var no_progress: bool = false
## Optional list of modes to play in order ("Chaos Party").
var playlist: Array[StringName] = []
var playlist_index: int = 0
## An online room round (seats are labelled P1-P4 the same on every device).
var online: bool = false


func human_count() -> int:
	var n := 0
	for s in slots:
		if s.kind == Kind.HUMAN:
			n += 1
	return n


func player_count() -> int:
	return slots.size()


func duplicate_setup() -> MatchSetup:
	var m := MatchSetup.new()
	m.mode_id = mode_id
	for s in slots:
		m.slots.append(s.duplicate_slot())
	m.chaos_enabled = chaos_enabled
	m.enabled_events = enabled_events.duplicate()
	m.round_time = round_time
	m.seed = seed
	m.team_carry = team_carry
	m.playlist = playlist.duplicate()
	m.playlist_index = playlist_index
	m.no_progress = no_progress
	m.online = online
	return m


## Handy default: one local human plus CPU buddies with distinct characters.
static func quick(p_mode_id: StringName, humans: int = 1, cpus: int = 1,
		first_character: StringName = &"bloop") -> MatchSetup:
	var m := MatchSetup.new()
	m.mode_id = p_mode_id
	var used: Array[StringName] = []
	for i in humans:
		var s := Slot.new()
		s.kind = Kind.HUMAN
		s.local_index = i + 1
		s.character_id = first_character if i == 0 else _next_free_character(used)
		used.append(s.character_id)
		m.slots.append(s)
	for i in cpus:
		var s := Slot.new()
		s.kind = Kind.CPU
		s.character_id = _next_free_character(used)
		used.append(s.character_id)
		m.slots.append(s)
	return m


static func _next_free_character(used: Array[StringName]) -> StringName:
	for c in Catalog.CHARACTERS:
		if not used.has(c.id):
			return c.id
	return Catalog.CHARACTERS[used.size() % Catalog.CHARACTERS.size()].id
