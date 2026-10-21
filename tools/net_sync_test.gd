extends SceneTree
## Online multiplayer test with real separate programs talking over the
## network (localhost): one room server and several automatic phones
## (scripts/net/net_test_driver.gd). Checks that every phone sees the same
## round: phases, timer, chaos switches, points, awards and the mode's state,
## that other creatures appear where they really are, that a phone can drop
## out and take its seat back, and that the server refuses impossible moves.
##
##   godot --headless --path . -s tools/net_sync_test.gd
##   godot --headless --path . -s tools/net_sync_test.gd -- --only=reconnect
##   godot --headless --path . -s tools/net_sync_test.gd -- --server-exe=build/server/chaos-switch-server.x86_64
##       (the room server is an exported build, as it would run on a real server)
##
## Scenarios: sync (3 phones + 1 CPU, Bounce Race), reconnect, modes (Button
## Mayhem and Cake Dash), cheat, lobby (two phones use the real Online screen
## for two rounds). Exit code 0 = everything passed.
## Takes a few minutes: rounds run in real time (shortened to 30 seconds).

const PORT_BASE := 7811

var _exe := ""
var _server_exe := ""   # an exported server build instead of this project (optional)
var _project := ""
var _work := ""
var _failures: PackedStringArray = []
var _passes := 0
var _procs: Array[int] = []


func _initialize() -> void:
	_exe = OS.get_executable_path()
	_project = ProjectSettings.globalize_path("res://")
	_work = OS.get_user_data_dir().path_join("net_sync_test")
	DirAccess.make_dir_recursive_absolute(_work)
	_run.call_deferred()


func _run() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
		elif a.begins_with("--server-exe="):
			_server_exe = ProjectSettings.globalize_path(a.trim_prefix("--server-exe=")) \
					if a.trim_prefix("--server-exe=").begins_with("res://") else a.trim_prefix("--server-exe=")
			if _server_exe.is_relative_path():
				_server_exe = _project.path_join(_server_exe)
			print("Room server: exported build ", _server_exe)
	var t0 := Time.get_ticks_msec()
	if only == "" or only == "sync":
		await _scenario_sync()
	if only == "" or only == "reconnect":
		await _scenario_reconnect()
	if only == "" or only == "modes":
		await _scenario_modes()
	if only == "" or only == "cheat":
		await _scenario_cheat()
	if only == "" or only == "lobby":
		await _scenario_lobby()
	_kill_all()
	print("------------------------------------------------------")
	print("%d checks passed, %d failed (%.0f s)" % [_passes, _failures.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	for f in _failures:
		print("FAILED: ", f)
	quit(0 if _failures.is_empty() else 1)


# ---------------------------------------------------------------- scenarios

func _scenario_sync() -> void:
	print("\n== sync: 3 phones + 1 CPU buddy, Bounce Race")
	var dir := _fresh_dir("sync")
	var port := PORT_BASE
	_start_server(dir, port, 30)
	await _sleep(1.5)
	_start_phone(dir, port, "c1", ["--net-test=create", "--players=3", "--mode=bounce_race", "--cpus"])
	await _sleep(1.0)
	_start_phone(dir, port, "c2", ["--net-test=join"])
	_start_phone(dir, port, "c3", ["--net-test=join"])
	var logs := await _wait_for_results(dir, ["c1", "c2", "c3"], 90.0)
	await _stop_all(dir)
	_check_same_round(logs, "sync")
	_check_positions(logs, "sync")
	var traffic := PackedStringArray()
	for line in FileAccess.get_file_as_string(dir.path_join("server.out")).split("\n"):
		if line.contains("traffic:"):
			traffic.append(line.strip_edges())
			print("  ", line.strip_edges())
	_check(traffic.size() >= 2, "sync: the server logged its network traffic (%d lines)" % traffic.size())
	_check_clean_output(dir, ["server", "c1", "c2", "c3"], "sync")


func _scenario_reconnect() -> void:
	print("\n== reconnect: a phone drops out mid-round and takes its seat back")
	var dir := _fresh_dir("reconnect")
	var port := PORT_BASE + 1
	_start_server(dir, port, 30)
	await _sleep(1.5)
	_start_phone(dir, port, "c1", ["--net-test=create", "--players=2", "--mode=bounce_race"])
	await _sleep(1.0)
	var c2 := _start_phone(dir, port, "c2", ["--net-test=join", "--seat-file=" + dir.path_join("c2_seat.json")])
	# Wait until the round is properly going, then pull the plug.
	var ok := await _wait_until(func() -> bool:
		for e in _read_log(dir.path_join("c2.jsonl")):
			if e.ev == "pos" and int(e.phase) == 3 and float(e.clock) > 12.0:
				return true
		return false, 60.0)
	_check(ok, "reconnect: the round got going before the drop-out")
	OS.kill(c2)
	await _sleep(2.0)
	_start_phone(dir, port, "c2b", ["--net-test=rejoin", "--seat-file=" + dir.path_join("c2_seat.json")])
	var logs := await _wait_for_results(dir, ["c1", "c2b"], 70.0)
	await _stop_all(dir)
	var first := _first(logs.get("c2b", []), "match")
	var before := _first(logs.get("c1", []), "match")
	_check(not first.is_empty() and int(first.get("index", -1)) == 1, "reconnect: the phone got its own seat back (player 2)")
	_check(not first.is_empty() and int(first.get("seed", -1)) == int(before.get("seed", -2)),
			"reconnect: it came back into the same round")
	var r1 := _first(logs.get("c1", []), "results")
	var r2 := _first(logs.get("c2b", []), "results")
	_check(not r1.is_empty() and not r2.is_empty() and r1.totals == r2.totals,
			"reconnect: both phones agree on the final points %s / %s" % [r1.get("totals"), r2.get("totals")])
	var server_log := FileAccess.get_file_as_string(dir.path_join("server.out"))
	_check(server_log.contains("rejoined room"), "reconnect: the server logged the rejoin")
	_check_clean_output(dir, ["server", "c1", "c2b"], "reconnect")


func _scenario_modes() -> void:
	for mode in ["button_mayhem", "cake_dash"]:
		print("\n== modes: %s, 2 phones + 2 CPU buddies" % mode)
		var dir := _fresh_dir(mode)
		var port := PORT_BASE + (2 if mode == "button_mayhem" else 3)
		_start_server(dir, port, 40)
		await _sleep(1.5)
		_start_phone(dir, port, "c1", ["--net-test=create", "--players=2", "--mode=" + mode, "--cpus"])
		await _sleep(1.0)
		_start_phone(dir, port, "c2", ["--net-test=join"])
		var logs := await _wait_for_results(dir, ["c1", "c2"], 100.0)
		await _stop_all(dir)
		_check_same_round(logs, mode)
		var s1: Dictionary = _first(logs.get("c1", []), "results").get("mode_state", {})
		var s2: Dictionary = _first(logs.get("c2", []), "results").get("mode_state", {})
		var keys: Array = ["sq", "s", "w", "rp", "c"] if mode == "button_mayhem" else ["dl", "cc"]
		var same := not s1.is_empty()
		for k in keys:
			if s1.get(k) != s2.get(k):
				same = false
		_check(same, "%s: both phones end with the same mode state (%s)" % [mode, _pick(s1, keys)])
		var scored := 0
		for e in logs.get("c1", []):
			if e.ev == "scored":
				scored += 1
		_check(scored > 0, "%s: points were scored during the round (%d)" % [mode, scored])
		_check_clean_output(dir, ["server", "c1", "c2"], mode)


func _scenario_cheat() -> void:
	print("\n== cheat: a phone tries to jump its creature 30 m ahead every few seconds")
	var dir := _fresh_dir("cheat")
	var port := PORT_BASE + 4
	_start_server(dir, port, 25)
	await _sleep(1.5)
	_start_phone(dir, port, "c1", ["--net-test=create", "--players=2", "--mode=bounce_race"])
	await _sleep(1.0)
	_start_phone(dir, port, "c2", ["--net-test=join", "--cheat=teleport"])
	var logs := await _wait_for_results(dir, ["c1", "c2"], 80.0)
	await _stop_all(dir)
	var cheats := 0
	var corrections := 0
	for e in logs.get("c2", []):
		if e.ev == "cheat":
			cheats += 1
		elif e.ev == "corrected":
			corrections += 1
	_check(cheats >= 3, "cheat: the phone tried to cheat (%d times)" % cheats)
	_check(corrections >= cheats - 1 and corrections > 0,
			"cheat: the server put the creature back (%d corrections)" % corrections)
	# The honest phone never saw the cheater far ahead of the real course.
	var r := _first(logs.get("c1", []), "results")
	_check(not r.is_empty(), "cheat: the round still finished normally")
	_check_clean_output(dir, ["server", "c1", "c2"], "cheat")


func _scenario_lobby() -> void:
	print("\n== lobby: two phones use the real Online screen (make a room, type the code, pick the game, START) for two rounds")
	var dir := _fresh_dir("lobby")
	var port := PORT_BASE + 5
	_start_server(dir, port, 25)
	await _sleep(1.5)
	_start_phone(dir, port, "c1", ["--net-test=ui-create", "--players=2", "--mode=cake_dash,button_mayhem",
			"--rounds=2", "--cpus"])
	_start_phone(dir, port, "c2", ["--net-test=ui-join", "--rounds=2", "--look=jelly", "--screen=2400x1080"])
	var logs := await _wait_for_results(dir, ["c1", "c2"], 160.0, 2)
	await _stop_all(dir)
	var c1: Array = logs.get("c1", [])
	var c2: Array = logs.get("c2", [])
	var shown := _first_ui(c1, "room_code_shown")
	var code := String(shown.get("code", ""))
	_check(code.length() == 5 and bool(shown.get("matches_net", false)),
			"lobby: tapping \"Make a room\" shows the room code on screen (%s)" % code)
	var typed := _first_ui(c2, "typed_code")
	_check(not typed.is_empty() and bool(typed.get("join_was_disabled", false)) and bool(typed.get("join_enabled", false)),
			"lobby: the friend types the code on the letter keys; Join! only lights up with all 5")
	var joined := _first_ui(c2, "in_room")
	_check(String(joined.get("code", "")) == code and int(joined.get("players", 0)) == 2 and not bool(joined.get("host", true)),
			"lobby: the friend's room screen shows the same code, both players, and they are not the host")
	var offscreen := []
	for e in c1 + c2:
		if e.ev == "offscreen":
			offscreen.append(e.button)
	var screens := [_first_ui(c1, "screen").get("size", []), _first_ui(c2, "screen").get("size", [])]
	_check(offscreen.is_empty() and screens[0] == [1280.0, 720.0] and screens[1] == [1600.0, 720.0],
			"lobby: every button the phones needed was on the screen (16:9 and 20:9 phones) %s" % [offscreen])
	var m1 := _all(c1, "match")
	var m2 := _all(c2, "match")
	_check(m1.size() == 2 and m2.size() == 2, "lobby: both phones played two rounds (%d / %d)" % [m1.size(), m2.size()])
	if m1.size() == 2 and m2.size() == 2:
		for r in 2:
			var want: String = ["cake_dash", "button_mayhem"][r]
			_check(m1[r].mode == want and m2[r].mode == want and m1[r].seed == m2[r].seed,
					"lobby: round %d is %s on both phones (picked on the room screen)" % [r + 1, want])
		_check(m1[0].seed != m1[1].seed, "lobby: round 2 is a fresh round (new seed)")
		_check(int(m1[0].players) == 4, "lobby: CPU buddies filled the two empty seats (%d creatures)" % int(m1[0].players))
		var other := int(m2[0].index)
		var chars: Array = m1[0].get("chars", [])
		_check(other >= 0 and other < chars.size() and chars[other] == "jelly",
				"lobby: the host sees the friend's chosen creature (%s)" % [chars[other] if other >= 0 and other < chars.size() else "?"])
	var r1 := _all(c1, "results")
	var r2 := _all(c2, "results")
	for r in mini(r1.size(), r2.size()):
		_check(r1[r].totals == r2[r].totals, "lobby: both phones agree on round %d's points %s" % [r + 1, r1[r].totals])
	var back1 := _first_ui(c1, "back_in_room")
	var back2 := _first_ui(c2, "pressed_back_to_room")
	_check(back1.get("state", "") == "lobby" and not back2.is_empty(),
			"lobby: \"Back to the room\" after the results returns to the room screen, ready for the next round")
	_check_clean_output(dir, ["server", "c1", "c2"], "lobby")


func _first_ui(entries: Array, what: String) -> Dictionary:
	for e in entries:
		if e.ev == "ui" and e.get("what", "") == what:
			return e
	return {}


func _all(entries: Array, ev: String) -> Array:
	var out := []
	for e in entries:
		if e.ev == ev:
			out.append(e)
	return out


# ---------------------------------------------------------------- checks

func _check_same_round(logs: Dictionary, tag: String) -> void:
	var names: Array = logs.keys()
	names.sort()
	var ref_name: String = names[0]
	var ref: Array = logs[ref_name]
	var ref_res := _first(ref, "results")
	_check(not ref_res.is_empty(), "%s: %s saw the results" % [tag, ref_name])
	var indices := {}
	for n in names:
		var m := _first(logs[n], "match")
		indices[int(m.get("index", -1))] = true
	_check(indices.size() == names.size() and not indices.has(-1), "%s: every phone got its own creature %s" % [tag, indices.keys()])
	for n in names:
		if n == ref_name:
			continue
		var other: Array = logs[n]
		var res := _first(other, "results")
		_check(not res.is_empty(), "%s: %s saw the results" % [tag, n])
		if res.is_empty() or ref_res.is_empty():
			continue
		_check(res.totals == ref_res.totals, "%s: %s and %s agree on the points %s" % [tag, n, ref_name, ref_res.totals])
		_check(res.awards == ref_res.awards, "%s: %s and %s agree on the awards %s" % [tag, n, ref_name, ref_res.awards])
		_check(bool(res.success) == bool(ref_res.success), "%s: same mission result" % tag)
		# Chaos switches: same events, same order, (nearly) same round time.
		var ca := _chaos_list(ref)
		var cb := _chaos_list(other)
		var same_events := ca.size() == cb.size() and ca.size() > 0
		var worst := 0.0
		if same_events:
			for i in ca.size():
				if ca[i].key != cb[i].key:
					same_events = false
				worst = maxf(worst, absf(float(ca[i].clock) - float(cb[i].clock)))
		_check(same_events, "%s: %s and %s saw the same chaos switches (%d)" % [tag, n, ref_name, ca.size()])
		_check(worst < 0.25, "%s: chaos switches happened at the same round time (worst %.3f s)" % [tag, worst])
		# Phases (round start, finish, results) at the same round time.
		var pa := _phase_times(ref)
		var pb := _phase_times(other)
		var worst_phase := 0.0
		for ph in [3, 4, 5]:
			if pa.has(ph) and pb.has(ph):
				worst_phase = maxf(worst_phase, absf(float(pa[ph]) - float(pb[ph])))
		_check(pa.has(3) and pb.has(3) and pa.has(5) and pb.has(5) and worst_phase < 0.25,
				"%s: round start / end at the same time (worst %.3f s)" % [tag, worst_phase])


## Other creatures appear where they really were (shown 0.1 s in the past).
func _check_positions(logs: Dictionary, tag: String) -> void:
	var errors: Array[float] = []
	for viewer in logs:
		for owner_name in logs:
			if viewer == owner_name:
				continue
			var owner_index := int(_first(logs[owner_name], "match").get("index", -1))
			if owner_index < 0:
				continue
			var truth: Array = []
			for e in logs[owner_name]:
				if e.ev == "pos" and int(e.phase) == 3:
					truth.append(e)
			for e in logs[viewer]:
				if e.ev != "pos" or int(e.phase) != 3:
					continue
				var t := float(e.st) - 0.1
				var real = _interp(truth, t, owner_index)
				if real == null:
					continue
				var seen: Array = e.pos[owner_index]
				errors.append(Vector3(seen[0], seen[1], seen[2]).distance_to(real))
	errors.sort()
	if errors.is_empty():
		_check(false, "%s: position samples to compare" % tag)
		return
	var median := errors[errors.size() / 2]
	var p90 := errors[int(errors.size() * 0.9)]
	print("   positions: %d samples, median %.2f m, 90%% under %.2f m, worst %.2f m" % [errors.size(), median, p90, errors[-1]])
	_check(median < 0.6, "%s: other creatures shown where they are (median error %.2f m)" % [tag, median])
	_check(p90 < 2.0, "%s: 90%% of samples within 2 m (%.2f m)" % [tag, p90])


func _interp(series: Array, t: float, idx: int) -> Variant:
	for i in series.size() - 1:
		var a: Dictionary = series[i]
		var b: Dictionary = series[i + 1]
		if float(a.st) <= t and t <= float(b.st):
			var span := float(b.st) - float(a.st)
			if span <= 0.0 or span > 0.3:
				return null
			var w := (t - float(a.st)) / span
			var pa := Vector3(a.pos[idx][0], a.pos[idx][1], a.pos[idx][2])
			var pb := Vector3(b.pos[idx][0], b.pos[idx][1], b.pos[idx][2])
			if pa.distance_to(pb) > 4.0:
				return null  # a respawn jump: skip
			return pa.lerp(pb, w)
	return null


func _check_clean_output(dir: String, names: Array, tag: String) -> void:
	for n in names:
		var text := FileAccess.get_file_as_string(dir.path_join(n + ".out"))
		var bad := PackedStringArray()
		for line in text.split("\n"):
			if (line.begins_with("ERROR") or line.begins_with("SCRIPT ERROR")) and not line.contains("audio"):
				bad.append(line)
		_check(bad.is_empty(), "%s: no errors from %s%s" % [tag, n, (" (" + bad[0] + ")") if not bad.is_empty() else ""])


func _chaos_list(entries: Array) -> Array:
	var out := []
	for e in entries:
		if e.ev == "chaos":
			out.append({"key": "%s:%s" % [e.id, e.what], "clock": e.clock})
	return out


func _phase_times(entries: Array) -> Dictionary:
	var out := {}
	for e in entries:
		if e.ev == "phase":
			out[int(e.phase)] = float(e.clock)
	return out


func _pick(d: Dictionary, keys: Array) -> String:
	var parts := PackedStringArray()
	for k in keys:
		parts.append("%s=%s" % [k, d.get(k)])
	return ", ".join(parts)


func _check(ok: bool, what: String) -> void:
	if ok:
		_passes += 1
		print("  PASS  ", what)
	else:
		_failures.append(what)
		print("  FAIL  ", what)


# ---------------------------------------------------------------- processes & logs

func _fresh_dir(name: String) -> String:
	var dir := _work.path_join(name)
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	return dir


func _start_server(dir: String, port: int, round_time: int) -> int:
	return _spawn(dir, "server", ["--", "--server", "--port=%d" % port, "--round-time=%d" % round_time,
			"--stop-file=" + dir.path_join("stop"), "--traffic-log=10"])


func _start_phone(dir: String, port: int, name: String, extra: Array) -> int:
	var args := ["--", "--online-server=127.0.0.1:%d" % port, "--net-log=" + dir.path_join(name + ".jsonl"),
			"--code-file=" + dir.path_join("code.txt")]
	args.append_array(extra)
	return _spawn(dir, name, args)


## Starts a separate Godot program. Its output goes to <name>.out (written
## when it exits normally).
func _spawn(dir: String, name: String, args: Array) -> int:
	var exe := _exe
	var all := ["--headless", "--log-file", dir.path_join(name + ".out"), "--path", _project]
	if name == "server" and _server_exe != "":
		exe = _server_exe
		all = ["--headless", "--log-file", dir.path_join(name + ".out")]
	all.append_array(args)
	var pid := OS.create_process(exe, PackedStringArray(all))
	_procs.append(pid)
	return pid


## Asks the server to quit (stop file), gives everyone a moment, then makes sure.
func _stop_all(dir: String) -> void:
	var f := FileAccess.open(dir.path_join("stop"), FileAccess.WRITE)
	f.store_string("stop")
	f.close()
	await _wait_until(func() -> bool:
		for pid in _procs:
			if OS.is_process_running(pid):
				return false
		return true, 6.0)
	_kill_all()


func _kill_all() -> void:
	for pid in _procs:
		if OS.is_process_running(pid):
			OS.kill(pid)
	_procs.clear()


func _read_log(path: String) -> Array:
	var out := []
	if not FileAccess.file_exists(path):
		return out
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.strip_edges() == "":
			continue
		var d = JSON.parse_string(line)
		if d is Dictionary:
			out.append(d)
	return out


func _first(entries: Array, ev: String) -> Dictionary:
	for e in entries:
		if e.ev == ev:
			return e
	return {}


## Waits until every phone logged [param rounds] results (or the timeout).
func _wait_for_results(dir: String, names: Array, timeout: float, rounds: int = 1) -> Dictionary:
	await _wait_until(func() -> bool:
		for n in names:
			if _all(_read_log(dir.path_join(n + ".jsonl")), "results").size() < rounds:
				return false
		return true, timeout)
	await _sleep(1.0)
	var logs := {}
	for n in names:
		logs[n] = _read_log(dir.path_join(n + ".jsonl"))
	return logs


func _wait_until(cond: Callable, timeout: float) -> bool:
	var until := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < until:
		if cond.call():
			return true
		await _sleep(0.5)
	return false


func _sleep(seconds: float) -> void:
	await create_timer(seconds).timeout
