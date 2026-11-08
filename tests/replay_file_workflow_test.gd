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
	if args.size() == 2 and args[0] == "capture" and DisplayServer.get_name() != "headless":
		capture_directory = args[1]
		DirAccess.make_dir_recursive_absolute(capture_directory)
	Engine.time_scale = 12.0
	var test_id := str(Time.get_ticks_usec())
	var saved_path := "res://artifacts/replay-file-%s.replay.json" % test_id
	var malformed_path := "res://artifacts/replay-file-%s-malformed.json" % test_id
	var stale_path := "res://artifacts/replay-file-%s-stale.json" % test_id
	var retired_path := "res://artifacts/replay-file-%s-retired.json" % test_id
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(Catalog.PARKING_GARAGE)
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
	original.battle_controller.set_debug_player_ai(true)
	var deadline := Time.get_ticks_msec() + 30000
	while original.turn_manager.battle_result == TurnManager.BattleResult.ONGOING and Time.get_ticks_msec() < deadline:
		await process_frame
	var recording: BattleReplayRecording = BattleReplaySession.last_recording
	if not recording or not recording.is_playable() or original.turn_manager.battle_result == TurnManager.BattleResult.ONGOING:
		push_error("The real garage battle did not produce a complete replay")
		quit(1)
		return
	_check(hud.save_replay_button.visible, "Completed garage battle shows Save Replay")
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
		var player := replay.get_node_or_null("BattleReplayPlayer") as BattleReplayPlayer
		_check(player != null and replay.active_generated_map.content_manifest == recording.configuration.content_manifest, "Playback reconstructs the exact saved garage and occupants")
		if player:
			player.set_playback_speed(4.0)
			deadline = Time.get_ticks_msec() + 30000
			while not player.playback_complete and Time.get_ticks_msec() < deadline:
				await process_frame
			_check(player.playback_succeeded and player.verified_actions == recording.actions.size(), "Replay verifies every action loaded from the user-selected file")
		_check(not (replay.get_node("Visualizers/BattleUI/TurnHUDController") as TurnHUDController).save_replay_button.visible, "Playback keeps Save Replay hidden")
		if player and player.playback_succeeded:
			var replay_hud := replay.get_node("Visualizers/BattleUI/TurnHUDController") as TurnHUDController
			replay_hud.replay_button.pressed.emit()
			_check(current_scene != replay and current_scene is BattleLevel and current_scene.pending_replay == player.recording, "Rewatch uses the opened file rather than a previous in-memory battle")
			var reopened := current_scene as BattleLevel
			var reopened_player := reopened.get_node("BattleReplayPlayer") as BattleReplayPlayer
			reopened_player.set_playback_paused(true)
			await process_frame
			var return_button := reopened.find_child("ReplaySetupButton", true, false) as Button
			return_button.pressed.emit()
			await process_frame
			await process_frame
			_check(current_scene is MatchSetup and not paused, "Returning to setup while replay is paused cancels playback and unpauses the game")
	for path in [saved_path, stale_path, malformed_path, retired_path]:
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
