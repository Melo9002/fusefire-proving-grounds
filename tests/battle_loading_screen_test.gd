extends SceneTree

const LoadingScreen = preload("res://ui/battle_loading_screen.gd")
const Catalog = preload("res://systems/generation/battlefield_catalog.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var screen := LoadingScreen.new()
	root.add_child(screen)
	await process_frame
	screen.set_stage("Constructing tactical battlefield…", 0.28)
	check(screen._stage.text == "Constructing tactical battlefield…", "Loading screen reports the real preparation stage")
	check(is_equal_approx(screen._progress.value, 0.28), "Loading screen reports bounded progress")
	var layers := screen.find_children("*", "CanvasLayer", true, false)
	check(layers.size() == 1 and layers[0].layer == 100, "Loading content is above the battle's CanvasLayer HUD")
	var key := InputEventKey.new()
	key.keycode = KEY_W
	key.pressed = true
	root.push_input(key)
	check(root.is_input_handled(), "Loading consumes gameplay keys before unhandled battle input")
	screen.show_failure([{"code": "INVALID_MAP", "message": "No legal deployment region"}])
	check(screen._back_button.visible, "Initialization failure offers a return to setup")
	check("INVALID_MAP" in screen._detail.text and "No legal deployment region" in screen._detail.text, "Initialization failure remains actionable")
	screen.queue_free()
	await process_frame
	await _check_real_transition()
	await _check_failed_transition()
	await _check_failed_rewatch()
	print("Battle loading screen: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _check_real_transition() -> void:
	var menu := load("res://ui/match_setup.tscn").instantiate() as MatchSetup
	root.add_child(menu)
	current_scene = menu
	for index in menu.map_size_option.item_count:
		if StringName(menu.map_size_option.get_item_metadata(index)) == Catalog.SERVICE_DEPOT:
			menu.map_size_option.select(index)
			break
	_capture_next_loading("match-loading")
	menu._start_battle()
	check(menu.get_node_or_null("BattleLoadingScreen") != null, "Starting a battle displays the loading screen before construction")
	# Loading is allowed to exceed the former five-second test timeout.
	var deadline := Time.get_ticks_msec() + 30000
	while current_scene == menu and Time.get_ticks_msec() < deadline:
		await process_frame
	check(current_scene is BattleLevel, "Successful initialization transitions from loading screen to battle")
	if current_scene is BattleLevel:
		var battle := current_scene as BattleLevel
		check(battle.battle_initialization_succeeded, "Loading transition only activates a validated battle")
		check(battle.active_generated_map != null and battle.active_generated_map.source_kind == "authored_service_depot", "Loading transition preserves the selected battlefield")
		battle.queue_free()
		await process_frame

func _check_failed_transition() -> void:
	var menu := load("res://ui/match_setup.tscn").instantiate() as MatchSetup
	root.add_child(menu)
	current_scene = menu
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.battlefield_id = &"missing_site_for_loading_test"
	menu._launch_battle(config)
	for frame in 120:
		if menu._loading_screen._back_button.visible: break
		await process_frame
	check(current_scene == menu and menu._loading_screen._back_button.visible, "Rejected content stays on an actionable loading failure instead of activating a battle")
	check("UNKNOWN_BATTLEFIELD" in menu._loading_screen._detail.text, "Loading failure explains the invalid content identity")
	menu._loading_screen._back_button.pressed.emit()
	check(not menu._launch_in_progress and not menu.start_button.disabled, "Failure return restores usable setup controls")
	menu.free()
	await process_frame

func _check_failed_rewatch() -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(Catalog.SERVICE_DEPOT)
	config.battle_seed = 16
	var live := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	live.configure_battle(config)
	root.add_child(live)
	current_scene = live
	check(await live.battle_controller.try_aim(live.turn_manager.active_unit), "Failure recovery starts from a real recorded action")
	var recording := BattleReplayRecording.from_dictionary(live._replay_recorder.recording.to_dictionary())
	recording.configuration["battlefield_id"] = &"missing_site_for_rewatch_test"
	check(recording.is_playable(), "Fixture passes document validation before battlefield reconstruction rejects its identity")
	live.pending_replay = recording
	await live.replay_last_battle()
	check(current_scene == live and is_instance_valid(live._replay_loading), "Failed reconstruction retains the original battle behind the error")
	check(live._replay_loading._back_button.text == "BACK TO BATTLE" and "UNKNOWN_BATTLEFIELD" in live._replay_loading._detail.text, "Replay failure has a specific reason and return route")
	check((live.get_node("CameraRig") as TacticalCamera).camera == root.get_camera_3d(), "Failure restores the original battle camera")
	live._replay_loading._back_button.pressed.emit()
	check(live.process_mode == Node.PROCESS_MODE_INHERIT and live._replay_loading == null, "Failure return restores the original battle controls")
	live.free()
	await process_frame

func _capture_next_loading(name: String) -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] != "capture" or DisplayServer.get_name() == "headless": return
	DirAccess.make_dir_recursive_absolute(args[1])
	RenderingServer.frame_post_draw.connect(func():
		check(root.get_texture().get_image().save_png(args[1].path_join(name + ".png")) == OK, "Capture real loading transition"), CONNECT_ONE_SHOT)
