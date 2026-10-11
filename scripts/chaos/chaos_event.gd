class_name ChaosEvent
extends Resource
## One "rule switch" (Moon Mode, Penguin Mode, ...), stored as a .tres file in
## res://data/chaos_events/ so it can be tuned in the Inspector.
##
## The default behaviour is purely data driven: while the event is active its
## [member modifiers] are registered on the match's rule stack under the
## event's id, and on expiry that source is removed again. Because effective
## values are always recomputed from the base values (see ModifierStack),
## cleanup can never leave a player stuck with stale gravity, speed or
## reversed controls. Subclasses can override the _on_* hooks for extra logic.
##
## Stats understood by PlayerCharacter (numbers are multipliers unless noted):
##   gravity, speed, jump, traction, size, push, air_control
##   floor_bounce (strongest wins), min_bounce (strongest wins),
##   waddle (strongest wins, 0..1), reverse (flag)

@export var id: StringName = &""
@export var display_name: String = "Chaos!"
## Big funny subtitle on the announcement card.
@export var tagline: String = ""
## One short sentence telling kids what changes and how to deal with it.
@export var tip: String = ""
@export_range(2.0, 60.0, 0.5) var duration: float = 12.0
## Relative chance of being picked by the random selector.
@export_range(0.0, 10.0, 0.1) var weight: float = 1.0
@export var color: Color = Color.WHITE
## Key for the UI icon painter (see ChaosIcon).
@export var icon: StringName = &"star"
## Events sharing a non-empty group never run at the same time (e.g. giant/tiny).
@export var exclusive_group: StringName = &""
@export var incompatible_with: Array[StringName] = []
@export var modifiers: Dictionary = {}
## True when the event changes what the controls do (Reverse Mode). The HUD
## then keeps a warning on screen for the whole duration.
@export var changes_controls: bool = false

@export_group("Presentation hooks")
@export var sfx_announce: StringName = &"chaos_announce"
@export var sfx_start: StringName = &"chaos_start"
@export var sfx_end: StringName = &"chaos_end"
## Key the presentation layer uses for screen and character effects.
@export var vfx: StringName = &""
## How characters react when the event begins.
@export var reaction: StringName = &"surprised"


func can_coexist_with(other: ChaosEvent) -> bool:
	if other == null:
		return true
	if other.id == id:
		return false
	if exclusive_group != &"" and exclusive_group == other.exclusive_group:
		return false
	if incompatible_with.has(other.id) or other.incompatible_with.has(id):
		return false
	return true


## Switches the event on. Called by ChaosManager only.
func activate(ctx: ChaosContext) -> void:
	ctx.rules.set_source(id, modifiers)
	_on_activate(ctx)


func tick(ctx: ChaosContext, delta: float) -> void:
	_on_tick(ctx, delta)


## Switches the event off and removes everything it changed.
func deactivate(ctx: ChaosContext) -> void:
	_on_deactivate(ctx)
	ctx.rules.remove_source(id)


# Override these in a subclass for behaviour that modifiers can't express.
func _on_activate(_ctx: ChaosContext) -> void:
	pass


func _on_tick(_ctx: ChaosContext, _delta: float) -> void:
	pass


func _on_deactivate(_ctx: ChaosContext) -> void:
	pass
