extends TestCase
## The Android back button/gesture (Router._notification, simulating the
## NOTIFICATION_WM_GO_BACK_REQUEST the OS sends — Android-only, so nothing
## here can trigger it for real on this desktop test machine, but calling
## the notification handler directly exercises the exact same code the OS
## would call). Checks it reaches the menus, pauses and resumes a match
## instead of doing nothing, and leaves the results screen instead of being
## a dead end.


var gs: Node
var router: Node


func before_each() -> void:
	gs = tree.root.get_node("GameState")
	router = tree.root.get_node("Router")
	gs.reset_to_defaults()


func after_each() -> void:
	gs.reset_to_defaults()
	await end_scene()


func _press_back() -> void:
	router._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frames(3)


func test_back_button_closes_a_menu_screen() -> void:
	router.back_target = &"menu"
	router.busy = false
	router.go(&"settings", false)
	await process_frames(6)
	check_eq(tree.current_scene.scene_file_path, router.SCENES[&"settings"], "settings screen opened")
	await _press_back()
	await process_frames(60)  # Router fades between scenes.
	check_eq(tree.current_scene.scene_file_path, router.SCENES[&"menu"], "back button leaves settings for the menu")


func test_back_button_pauses_and_resumes_a_match_instead_of_doing_nothing() -> void:
	var setup := MatchSetup.quick(&"cake_dash", 1, 3)
	setup.seed = 1
	var m := await start_match(setup)
	check_eq(m.phase, MatchController.Phase.PLAYING, "round is running")
	check(not m.is_paused, "not paused yet")
	await _press_back()
	check(m.is_paused, "back button during play opens the pause menu instead of being ignored")
	check(m.pause_menu.visible, "the pause card is actually on screen")
	await _press_back()
	check(not m.is_paused, "pressing back again (the pause menu's own ui_cancel handling) resumes play")


func test_back_button_leaves_the_results_screen() -> void:
	var setup := MatchSetup.quick(&"cake_dash", 1, 3)
	setup.seed = 1
	var m := await start_match(setup)
	await seconds(1.0)
	m.request_finish(true)
	var frames := 0
	while m.phase != MatchController.Phase.RESULTS and frames < 600:
		await tree.physics_frame
		frames += 1
	check_eq(m.phase, MatchController.Phase.RESULTS, "round reached the results screen")
	check(m.results_screen.visible, "results are actually on screen")
	await _press_back()
	await process_frames(60)  # Router fades between scenes.
	check_eq(tree.current_scene.scene_file_path, router.SCENES[&"menu"], "back button on results leaves for the menu, same as the Menu button")
