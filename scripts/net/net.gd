extends Node
## Online multiplayer entry point (proof of concept, see docs/ONLINE_MULTIPLAYER_PLAN.md).
## Local play never touches this node. Filled in during the online phase.

const DEFAULT_PORT := 7777

var is_online := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func start_server(_port: int = DEFAULT_PORT) -> void:
	push_warning("Net: the online room server is not built yet.")
	get_tree().quit(1)
