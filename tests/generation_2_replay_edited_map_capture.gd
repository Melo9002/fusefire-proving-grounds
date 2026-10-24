extends SceneTree
## Explicit GPU evidence for Task 6.3. The automated lifecycle and state
## comparisons live in generation_2_replay_edited_map_test.gd.

const BATTLE_SCENE := preload("res://levels/prototype_map/prototype_map.tscn")
const CAPTURE_SIZE := Vector2i(1600, 900)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless":
		push_error("A rendered window and output directory are required.")
		quit(1)
		return
	var output: String = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size = CAPTURE_SIZE
	var config := _configuration()
	var built := Generation2BattlefieldBuilder.build(config)
	if not built.ok:
		push_error("Could not build capture document: %s" % str(built.errors))
		quit(1)
		return
	var edited := _add_optional_furniture(built.document, config)
	var level := await _start_document_battle(config, edited)
	if level == null: return
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	_frame(level)
	await process_frame
	await RenderingServer.frame_post_draw
	if not _save(output.path_join("generation-2-edited-battle.png")): return
	var actor: TacticalUnit = level.turn_manager.active_unit
	await level.battle_controller.action_service.submit_simple(level.battle_controller.action_service.make_simple_request(&"wait", actor, TacticalActionRequest.Source.PLAYER), true)
	await process_frame
	var recording: BattleReplayRecording = level._replay_recorder.recording
	level.queue_free()
	await process_frame
	await process_frame
	var replay := BATTLE_SCENE.instantiate() as BattleLevel
	replay.configure_replay(recording)
	var completed: Array = []
	replay.battle_initialization_finished.connect(func(success: bool, errors: Array): completed.append({"success": success, "errors": errors}), CONNECT_ONE_SHOT)
	root.add_child(replay)
	await _wait(completed)
	if completed.is_empty() or not completed[0].success:
		push_error("Could not reconstruct replay capture: %s" % str(completed))
		quit(1)
		return
	var player := replay.get_node_or_null("BattleReplayPlayer") as BattleReplayPlayer
	if player: player.set_playback_paused(true)
	_frame(replay)
	await process_frame
	await RenderingServer.frame_post_draw
	if not _save(output.path_join("generation-2-edited-replay.png")): return
	print("Generation 2.0 edited battle/replay captures saved to " + output)
	quit()

func _configuration() -> BattleConfiguration:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.battlefield_preset = BattleConfiguration.BattlefieldPreset.GENERATION_2_INDUSTRIAL
	config.map_size = BattleConfiguration.GENERATION_2_MAP_SIZE
	config.battle_seed = 17
	config.player_count = 2
	config.enemy_count = 1
	config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, 1, false)
	return config

func _add_optional_furniture(source: BattlefieldLayoutDocument, config: BattleConfiguration) -> BattlefieldLayoutDocument:
	var catalog := IndustrialModuleCatalog.create()
	for z in range(1, config.map_size.y - 1):
		for x in range(1, config.map_size.x - 1):
			var document := source.editable_copy()
			var layout := document.to_module_layout(catalog)
			if not layout.try_add(catalog[&"street_light"], EnvironmentModulePlacement.new(&"street_light", Vector2i(x, z)), config.map_size): continue
			document.apply_edited_layout(layout)
			if Generation2BattlefieldBuilder.compile_document(document, config).ok: return document
	return null

func _start_document_battle(config: BattleConfiguration, document: BattlefieldLayoutDocument) -> BattleLevel:
	var level := BATTLE_SCENE.instantiate() as BattleLevel
	level.configure_layout_document(config, document)
	var completed: Array = []
	level.battle_initialization_finished.connect(func(success: bool, errors: Array): completed.append({"success": success, "errors": errors}), CONNECT_ONE_SHOT)
	root.add_child(level)
	await _wait(completed)
	if not completed.is_empty() and completed[0].success: return level
	push_error("Could not initialize edited battle capture: %s" % str(completed))
	quit(1)
	return null

func _wait(completed: Array) -> void:
	var deadline := Time.get_ticks_msec() + 60000
	while completed.is_empty() and Time.get_ticks_msec() < deadline: await process_frame

func _frame(level: BattleLevel) -> void:
	var rig := level.get_node("CameraRig") as TacticalCamera
	rig.focus_position(Vector3.ZERO)
	rig._set_zoom(56.0)

func _save(path: String) -> bool:
	var error := root.get_texture().get_image().save_png(path)
	if error == OK: return true
	push_error("Generation 2.0 replay capture failed: %s" % error)
	quit(1)
	return false
