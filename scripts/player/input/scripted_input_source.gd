class_name ScriptedInputSource
extends PlayerInputSource
## Input driven by code: automated tests, attract-mode demos and replays.
## Set [member move] / [member jump_held] directly and call press_jump().


func get_kind_label() -> String:
	return "TEST"
