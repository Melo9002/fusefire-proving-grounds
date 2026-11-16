extends SceneTree
var failures := 0

func _initialize() -> void:
	if OS.get_environment("FUSEFIRE_TEST_OUTPUT_DIR").is_empty(): OS.set_environment("FUSEFIRE_TEST_OUTPUT_DIR", ProjectSettings.globalize_path("res://.godot/local-completion-output"))
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var editor := load("res://tools/parcel_editor/parcel_editor.tscn").instantiate() as ParcelEditor
	root.add_child(editor)
	current_scene = editor
	await process_frame
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		check(editor._apply_session(args[0]), "Open the reported parcel without modifying its saved file")
	else:
		editor.select_parcel(AuthoredParcelCatalog.LOADING_YARD_A)
		var ambulance := editor.PlacementLibrary.create("car_kit/ambulance")
		ambulance.position = Vector3(5.5, 0, 25)
		editor.draft.add_fixed(ambulance)
		ambulance.free()
		editor._apply_draft()
	var fingerprint := editor._session_fingerprint()
	await editor.test_in_battle()
	var live := editor.test_battle
	check(is_instance_valid(live) and live.battle_initialization_succeeded, "The ambulance parcel starts a valid local battle")
	if not is_instance_valid(live) or not live.battle_initialization_succeeded:
		editor.free()
		quit(1)
		return
	var ambulances := live.find_children("*", "Node3D", true, false).filter(func(node): return node.get_meta("asset_id", "") == "car_kit/ambulance" and node.has_meta("mesh_boundary_version"))
	check(ambulances.size() == 1, "The new ambulance and its automatic boundaries reach battle exactly once")
	if ambulances.size() == 1:
		var part: Node3D = ambulances[0].get_node("MeshBoundaries").get_child(0)
		var size: Vector3 = part.get_meta("solid_size")
		var bounds := part.global_transform * AABB(-size * 0.5, size)
		var grid := live.battle_controller.grid_manager
		var body := grid.world_to_grid(bounds.get_center())
		body.y = 0
		check(not grid.map_data.get_cell(body).can_stop, "The ambulance body blocks standing in the live battle")
		var from := bounds.get_center() - Vector3.RIGHT * (bounds.size.x * 0.5 + 0.1)
		var to := bounds.get_center() + Vector3.RIGHT * (bounds.size.x * 0.5 + 0.1)
		check(CombatRules.get_blocking_cell(from, to, grid) != null, "The ambulance's visible body participates in authoritative shot blocking")
		check(not live.battle_controller.pathfinder.calculate_3d_path(Vector3i(2, 0, 25), Vector3i(9, 0, 25)).is_empty(), "Live movement retains a route around the placed ambulance")
	Engine.time_scale = 12
	live.battle_controller.set_debug_player_ai(true)
	var deadline := Time.get_ticks_msec() + 30000
	while live.turn_manager.battle_result == TurnManager.BattleResult.ONGOING and Time.get_ticks_msec() < deadline:
		await process_frame
	live.battle_controller.set_debug_player_ai(false)
	await process_frame
	var recording: BattleReplayRecording = live._replay_recorder.recording
	check(live.turn_manager.battle_result != TurnManager.BattleResult.ONGOING and recording.is_playable(), "The local Eliminate battle reaches a recorded final result")
	check(recording.actions.any(func(action): return action.kind == "move") and recording.actions.any(func(action): return action.kind == "attack"), "The complete battle exercises real movement and shooting")
	var path := "res://.godot/ambulance-complete-test.replay.json"
	check(recording.save_json(path) == OK, "Save the complete local battle to a replay file")
	var loaded := BattleReplayRecording.load_json(path)
	check(loaded.is_playable(), "The saved local replay validates its snapshot and dependencies")
	BattleReplaySession.store(loaded)
	await live.replay_last_battle()
	await process_frame
	var replay := current_scene as BattleLevel
	var player := replay.get_node("BattleReplayPlayer") as BattleReplayPlayer
	player.set_playback_speed(4)
	deadline = Time.get_ticks_msec() + 30000
	while not player.playback_complete and Time.get_ticks_msec() < deadline:
		await process_frame
	check(player.playback_complete and player.playback_succeeded and player.verified_actions == loaded.actions.size(), "Saved-file replay verifies every action: " + player.last_divergence)
	check(replay.turn_manager.battle_result == loaded.expected_result and loaded.expected_result != TurnManager.BattleResult.ONGOING, "Replay reaches the same completed result")
	print("Local completion evidence: %d actions, %s" % [loaded.actions.size(), TurnManager.BattleResult.keys()[loaded.expected_result]])
	replay.return_to_match_setup()
	await process_frame
	check(editor.visible and editor._session_fingerprint() == fingerprint, "Return after the complete replay preserves the original editor session")
	editor.free()
	DirAccess.remove_absolute(path)
	Engine.time_scale = 1
	print("Local battle completion: %d failure(s)" % failures)
	quit(1 if failures else 0)
