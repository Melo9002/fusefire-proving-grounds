extends SceneTree

const BattleScene := preload("res://levels/prototype_map/prototype_map.tscn")
const SetupScene := preload("res://ui/match_setup.tscn")
const Catalog := preload("res://systems/generation/battlefield_catalog.gd")
var failures := 0
var capture_directory := ""

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2 and args[0] == "capture" and DisplayServer.get_name() != "headless":
		capture_directory = args[1]
		DirAccess.make_dir_recursive_absolute(capture_directory)
	Engine.time_scale = 12.0
	var test_id := str(Time.get_ticks_usec())
	var saved_path := "res://artifacts/replay-file-%s.replay.json" % test_id
	var exported_path := "res://artifacts/replay-file-%s-export.replay.json" % test_id
	var partial_path := "res://artifacts/replay-file-%s-partial.replay.json" % test_id
	var malformed_path := "res://artifacts/replay-file-%s-malformed.json" % test_id
	var stale_path := "res://artifacts/replay-file-%s-stale.json" % test_id
	var retired_path := "res://artifacts/replay-file-%s-retired.json" % test_id
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(Catalog.SERVICE_DEPOT)
	config.battle_seed = 17
	config.player_count = 3
	config.enemy_count = 3
	config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.REACH, 3)
	var original := BattleScene.instantiate() as BattleLevel
	original.configure_battle(config)
	root.add_child(original)
	current_scene = original
	var hud := original.get_node("Visualizers/BattleUI/TurnHUDController") as TurnHUDController
	_check(original.battle_initialization_succeeded and not hud.save_replay_button.visible, "Save appears only at battle end")
	_check(hud.round_label.visible and hud.round_label.text == "Round 1", "The battle HUD starts at round one")
	var live_pause := original.get_node("Visualizers/BattleUI/BattlePauseMenu") as BattlePauseMenu
	live_pause.set_open(true)
	_check(live_pause._save_replay_button.disabled, "Pause menu waits for the first recorded action")
	live_pause.set_open(false)
	original.battle_controller.set_debug_player_ai(true)
	var deadline := Time.get_ticks_msec() + 30000
	var live_recording := original.get_replay_recording()
	while live_recording.actions.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	live_pause.set_open(true)
	_check(not live_pause._save_replay_button.disabled, "Pause menu can save the in-progress match")
	live_pause._save_replay_button.pressed.emit()
	if hud._save_dialog:
		hud._save_dialog.hide()
		hud._save_dialog.file_selected.emit(partial_path)
		_check(paused and live_pause._replay_save_status.text == "Replay saved.", "Saving from Esc leaves the pause menu open and confirms the save")
	live_pause.set_open(false)
	var partial := BattleReplayRecording.load_json(partial_path)
	_check(partial.is_playable() and partial.expected_result == TurnManager.BattleResult.ONGOING, "In-progress save is a playable recording of committed actions")
	while original.turn_manager.battle_result == TurnManager.BattleResult.ONGOING and Time.get_ticks_msec() < deadline:
		await process_frame
	var recording: BattleReplayRecording = BattleReplaySession.last_recording
	if not recording or not recording.is_playable() or original.turn_manager.battle_result == TurnManager.BattleResult.ONGOING:
		push_error("The real depot battle did not produce a complete replay")
		quit(1)
		return
	_check(hud.save_replay_button.visible, "Completed depot battle shows Save Replay")
	_check(original.turn_manager.current_round > 1 and hud.round_label.text == "Round %d" % original.turn_manager.current_round, "The HUD tracks authoritative round progression through the battle result")
	await _capture("battle-result")
	hud.save_replay_button.pressed.emit()
	_check(hud._save_dialog.visible and hud._save_dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE, "Save button opens a Save As picker")
	var live_camera := original.get_node("CameraRig") as TacticalCamera
	_check(hud._save_dialog.exclusive and paused and not live_camera.can_process() and hud._save_dialog.can_process(), "Save As owns input and keeps the battle camera from polling keys")
	hud._save_dialog.hide()
	_check(not paused and live_camera.can_process(), "Closing Save As restores battle input")
	hud._save_dialog.file_selected.emit("res://artifacts/missing-%s/test.replay.json" % test_id)
	_check("Save failed" in hud._save_status.text and recording.is_playable(), "A failed write shows the error and preserves the recording for retry")
	hud._save_dialog.file_selected.emit(saved_path)
	_check(FileAccess.file_exists(saved_path) and hud._save_status.text == "Replay saved.", "The save callback writes the recording and confirms it")
	original.queue_free()
	await process_frame

	var menu := SetupScene.instantiate() as MatchSetup
	root.add_child(menu)
	current_scene = menu
	var open_button := menu.get_node("%OpenReplayButton") as Button
	await _capture("match-setup")
	open_button.pressed.emit()
	_check(menu._replay_dialog.visible and menu._replay_dialog.file_mode == FileDialog.FILE_MODE_OPEN_FILE, "Match Setup can pick a replay file")
	menu._replay_dialog.hide()
	var malformed := recording.to_dictionary()
	malformed.battle_configuration.content_manifest.placements = ["bad placement"]
	var file := FileAccess.open(malformed_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(malformed))
	file.close()
	menu._replay_dialog.file_selected.emit(malformed_path)
	_check(current_scene == menu and menu._replay_error.visible and "placement" in menu._replay_error.dialog_text, "Malformed content opens an actionable error and preserves Match Setup")
	_check(BattleReplaySession.last_recording == recording, "Opening a malformed file preserves the last completed recording")
	menu._replay_error.hide()
	var retired := BattleReplayRecording.from_dictionary(recording.to_dictionary())
	retired.configuration.battlefield_id = Catalog.GENERATED_COVER
	retired.configuration.content_manifest = {}
	_check(retired.save_json(retired_path) == OK, "Retired battlefield replay fixture saves")
	menu._replay_dialog.file_selected.emit(retired_path)
	_check(current_scene == menu and menu._replay_error.visible and "retired battlefield" in menu._replay_error.dialog_text, "The file picker cannot launch the old cover generator")
	menu._replay_error.hide()

	var stale := BattleReplayRecording.from_dictionary(recording.to_dictionary())
	stale.configuration.content_manifest.plot_revision += 1
	_check(stale.save_json(stale_path) == OK, "Stale replay fixture saves")
	menu._replay_dialog.file_selected.emit(stale_path)
	await process_frame
	await process_frame
	if menu._loading_screen == null:
		_check(false, "Stale supported content must reach the loading screen, not an earlier selection rejection")
		quit(1)
		return
	_check(current_scene == menu and menu._loading_screen._back_button.visible and "STALE_PLOT_REVISION" in menu._loading_screen._detail.text, "Incompatible content fails through the loading screen")
	_check(BattleReplaySession.last_recording == recording, "Stale file does not replace the last completed recording")
	menu._loading_screen._back_button.pressed.emit()
	_check(not open_button.disabled and not menu.start_button.disabled, "Dismissal restores both Match Setup entry points")
	await process_frame

	# Opening and rewatching a file must also work after restarting the game.
	BattleReplaySession.last_recording = null
	menu._replay_dialog.file_selected.emit(saved_path)
	deadline = Time.get_ticks_msec() + 10000
	while current_scene == menu and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(current_scene is BattleLevel, "Valid file launches the normal replay battle")
	if current_scene is BattleLevel:
		var replay := current_scene as BattleLevel
		_check((replay.get_node("Environment/WorldEnvironment") as WorldEnvironment).environment.fog_enabled, "Saved Depot replay configures its own atmosphere")
		var player := replay.get_node_or_null("BattleReplayPlayer") as BattleReplayPlayer
		var replay_hud := replay.get_node("Visualizers/BattleUI/TurnHUDController") as TurnHUDController
		_check(player != null and replay.active_generated_map.content_manifest == recording.configuration.content_manifest, "Playback reconstructs the exact saved depot and occupants")
		if player:
			player.set_camera_mode(BattleReplayPlayer.CameraMode.CINEMATIC)
			var replay_pause := replay.get_node("Visualizers/BattleUI/BattlePauseMenu") as BattlePauseMenu
			var escape := InputEventKey.new()
			escape.keycode = KEY_ESCAPE
			escape.pressed = true
			replay_pause._unhandled_key_input(escape)
			_check(replay_pause.is_open and not replay_pause._save_replay_button.disabled, "Esc offers Save Replay during playback")
			if not replay_pause._save_replay_button.disabled:
				BattleReplaySession.last_recording = null
				replay_pause._save_replay_button.pressed.emit()
				var completed_before_export := player.verified_actions
				var revision_before_export := replay.battle_controller.action_service.state_revision
				_check(replay_hud._save_dialog.visible and paused, "Replay export opens a modal and pauses playback")
				await create_timer(1.0, true).timeout
				_check(not player.playback_complete and player.verified_actions == completed_before_export
					and replay.battle_controller.action_service.state_revision == revision_before_export, "Playback commits no new action while Save As is open")
				replay_hud._save_dialog.hide()
				_check(paused, "Closing Save As leaves the Esc menu paused")
				replay_hud._save_dialog.file_selected.emit(exported_path)
				var exported := BattleReplayRecording.load_json(exported_path)
				_check(exported.is_playable() and exported.to_dictionary() == player.recording.to_dictionary(), "Export writes the active recording even when no last recording is stored")
				await _capture("replay-paused-export")
				replay_pause.set_open(false)
				_check(not paused and not player.playback_paused, "Leaving Esc resumes a previously running replay")
				player.set_playback_paused(true)
				replay_pause.set_open(true)
				replay_pause.set_open(false)
				_check(paused and player.playback_paused, "Leaving Esc preserves manual replay pause")
				player.set_playback_paused(false)
			player.set_camera_mode(BattleReplayPlayer.CameraMode.SELECTION_FOCUS)
			player.set_playback_speed(4.0)
			deadline = Time.get_ticks_msec() + 30000
			while not player.playback_complete and Time.get_ticks_msec() < deadline:
				await process_frame
			_check(player.playback_succeeded and player.verified_actions == recording.actions.size(), "Replay verifies every action loaded from the user-selected file")
		_check(not replay_hud.save_replay_button.visible, "Playback offers export through the pause menu")
		_check(replay_hud.round_label.visible and replay_hud.round_label.text == "Round %d" % replay.turn_manager.current_round, "The replay HUD shows the recorded battle's round")
		if player and player.playback_succeeded:
			var opened_recording = player.recording
			replay_hud.replay_button.pressed.emit()
			_check(current_scene == replay and is_instance_valid(replay._replay_loading), "Rewatch displays loading before replacing the battle")
			deadline = Time.get_ticks_msec() + 30000
			while current_scene == replay and Time.get_ticks_msec() < deadline:
				await process_frame
			_check(current_scene != replay and current_scene is BattleLevel and current_scene.pending_replay == opened_recording, "Rewatch uses the opened file rather than a previous in-memory battle")
			var reopened := current_scene as BattleLevel
			_check((reopened.get_node("Environment/WorldEnvironment") as WorldEnvironment).environment.fog_enabled, "Rewatch atmosphere belongs to the replacement scene even while the original still exists")
			var reopened_player := reopened.get_node("BattleReplayPlayer") as BattleReplayPlayer
			reopened_player.set_playback_paused(true)
			await process_frame
			if not capture_directory.is_empty():
				reopened.get_node("Visualizers/GridVisualizer").hide()
				reopened.get_node("Visualizers/GridCursor").hide()
			await _capture("replay-rewatch")
			var return_button := reopened.find_child("ReplaySetupButton", true, false) as Button
			return_button.pressed.emit()
			await process_frame
			await process_frame
			_check(current_scene is MatchSetup and not paused, "Returning to setup while replay is paused cancels playback and unpauses the game")
	if partial.is_playable() and current_scene is MatchSetup:
		var partial_menu := current_scene as MatchSetup
		partial_menu._open_replay_file(partial_path)
		deadline = Time.get_ticks_msec() + 10000
		while current_scene == partial_menu and Time.get_ticks_msec() < deadline:
			await process_frame
		var partial_player := current_scene.get_node_or_null("BattleReplayPlayer") as BattleReplayPlayer
		if partial_player:
			while not partial_player.playback_complete and Time.get_ticks_msec() < deadline:
				await process_frame
		_check(partial_player != null and partial_player.playback_succeeded
			and partial_player.verified_actions == partial.actions.size(), "A saved in-progress match reopens and verifies every exported action")
	for path in [saved_path, exported_path, partial_path, stale_path, malformed_path, retired_path]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("Replay file workflow: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _capture(name: String) -> void:
	if capture_directory.is_empty():
		return
	await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(capture_directory.path_join("%s.png" % name)) == OK, "Captured %s" % name)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
