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
##            [--max-rooms=200] [--round-time=SECONDS] (shorter rounds for tests)
##            [--stop-file=PATH] (tests: quit cleanly once that file exists)
##            [--traffic-log=60] (log network traffic every N seconds)


func _ready() -> void:
	var args := parse_args()
	if args.has("server"):
		Net.round_time_override = float(args.get("round-time", "0"))
		Net.stop_file = String(args.get("stop-file", ""))
		Net.traffic_log_seconds = maxf(5.0, float(args.get("traffic-log", "60")))
		var err := Net.start_server(int(args.get("port", Net.DEFAULT_PORT)), int(args.get("max-rooms", "200")))
		if err != OK:
			get_tree().quit(1)
		return
	if args.has("net-test"):
		# Development: an automatic online phone (see tools/net_sync_test.gd).
		var driver: Node = load("res://scripts/net/net_test_driver.gd").new()
		driver.set("args", args)
		get_tree().root.add_child.call_deferred(driver)
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
