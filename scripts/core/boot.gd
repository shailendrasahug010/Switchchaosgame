extends Node
## Entry point (scenes/main/main.tscn).
##
## Normally opens the main menu. Command-line options (after "--") help with
## testing and automation:
##   --quick=cake_dash      start a round right away (cake_dash, button_mayhem, bounce_race)
##   --humans=1 --cpus=3    who plays in a --quick round
##   --seed=1234            repeatable chaos picks
##   --no-chaos             play without rule switches
##   --no-progress          don't touch the save file
##   --autopilot            people's characters are steered by the CPU (demos, screenshots)
##   --time=45              round length in seconds
##   --server [--port=7777] run the online room server (headless)


func _ready() -> void:
	var args := parse_args()
	if args.has("server"):
		Net.start_server(int(args.get("port", Net.DEFAULT_PORT)))
		return
	if args.has("quick"):
		var setup := MatchSetup.quick(StringName(args.quick), int(args.get("humans", "1")),
				int(args.get("cpus", "3")), GameState.profile.character)
		setup.slots[0].hat_id = GameState.profile.hat
		setup.slots[0].paint_id = GameState.profile.paint
		setup.seed = int(args.get("seed", "0"))
		setup.chaos_enabled = not args.has("no-chaos")
		setup.no_progress = args.has("no-progress")
		if args.has("time"):
			setup.round_time = float(args.time)
		if args.has("autopilot"):
			for s in setup.slots:
				if s.kind == MatchSetup.Kind.HUMAN:
					s.autopilot = true
		Router.start_match.call_deferred(setup)
	else:
		Router.go.call_deferred(&"menu", false)


static func parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var parts := a.trim_prefix("--").split("=", true, 1)
		out[parts[0]] = parts[1] if parts.size() > 1 else "true"
	return out
