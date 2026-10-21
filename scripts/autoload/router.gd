extends Node
## Moves between screens with a short fade. Screens are referenced by id so
## file paths live in one place.
##
## Also bridges the Android back button/gesture to the rest of the game.
## Android sends that as NOTIFICATION_WM_GO_BACK_REQUEST, not as an input
## event, so without this every "ui_cancel" handler in the menus (and the
## pause menu, and the results screen) would never see it and back would do
## nothing. config/quit_on_go_back is off (project.godot) specifically so we
## can turn it into an ordinary ui_cancel press instead of an instant,
## unconditional quit from wherever the player happens to be.

signal scene_changed(id: StringName)

const SCENES := {
	&"menu": "res://scenes/menus/main_menu.tscn",
	&"setup": "res://scenes/menus/party_setup.tscn",
	&"wardrobe": "res://scenes/menus/wardrobe.tscn",
	&"settings": "res://scenes/menus/settings_screen.tscn",
	&"parents": "res://scenes/menus/parents_info.tscn",
	&"online": "res://scenes/menus/online_lobby.tscn",
	&"match": "res://scenes/match/match.tscn",
}

const FADE_TIME := 0.22

var current_id: StringName = &""
var busy := false
## Screen to return to when the player taps "Back" (settings can open from pause or menu).
var back_target: StringName = &"menu"

var _layer: CanvasLayer
var _fade: ColorRect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.141, 0.118, 0.298, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_fade)


## Android only: the back button/gesture. Hand it to everyone already
## listening for "ui_cancel" (menus, the pause menu, the results screen)
## instead of guessing here what "back" should do on whatever screen is
## current.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		var ev := InputEventAction.new()
		ev.action = &"ui_cancel"
		ev.pressed = true
		Input.parse_input_event(ev)


func go(id: StringName, fade: bool = true) -> void:
	if busy or not SCENES.has(id):
		if not SCENES.has(id):
			push_error("Router: unknown screen '%s'" % id)
		return
	busy = true
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	if fade:
		var t := create_tween()
		t.tween_property(_fade, "color:a", 1.0, FADE_TIME)
		await t.finished
	get_tree().paused = false
	var err := get_tree().change_scene_to_file(SCENES[id])
	if err != OK:
		push_error("Router: could not open %s (%s)" % [SCENES[id], error_string(err)])
	current_id = id
	# Wait for the new scene to enter the tree before fading back in.
	await get_tree().process_frame
	await get_tree().process_frame
	if fade:
		var t2 := create_tween()
		t2.tween_property(_fade, "color:a", 0.0, FADE_TIME)
		await t2.finished
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	busy = false
	scene_changed.emit(id)


func start_match(setup: MatchSetup) -> void:
	GameState.current_setup = setup
	InputSetup.configure_local_players(maxi(1, setup.human_count()))
	go(&"match")
