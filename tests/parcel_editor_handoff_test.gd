extends SceneTree
const EditorScene = preload("res://tools/parcel_editor/parcel_editor.tscn")
const Catalog = preload("res://systems/generation2/authored_parcel_catalog.gd")
var failures := 0

func _initialize() -> void:
	if OS.get_environment("FUSEFIRE_TEST_OUTPUT_DIR").is_empty(): OS.set_environment("FUSEFIRE_TEST_OUTPUT_DIR", ProjectSettings.globalize_path("res://.godot/handoff-test-output"))
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var editor := EditorScene.instantiate() as ParcelEditor
	root.add_child(editor)
	await process_frame
	editor.select_parcel(Catalog.LOADING_YARD_A)
	var box := editor.PlacementLibrary.create("factory_kit/box-small")
	box.position = Vector3(7, 0, 17)
	editor.draft.add_fixed(box)
	box.free()
	editor._apply_draft()
	var field = editor.field_panel
	field.session.add("ground", "containers", Rect2i(7, 25, 3, 5))
	field.density.value = 100
	field.refresh()
	var path := "res://.godot/parcel_handoff_test.parcel.json"
	check(editor._save_session_to(path), "Save the complete fixed-object and population edit")
	var fingerprint := editor._session_fingerprint()
	editor._translate_selected(Vector3.RIGHT)
	field.session.add("ground", "protected", Rect2i(1, 1, 1, 1))
	check(editor._apply_session(path) and editor._session_fingerprint() == fingerprint, "Open restores both drafts and their settings together")
	check(editor.active_session_path == path and not editor.draft.dirty and not field.has_unsaved_changes(), "The active complete file is visible and both drafts are saved")
	field.preview()
	check(is_instance_valid(field._runtime_preview), "The exact current draft has a runtime-rule preview: %s" % field.preview_context.text)
	var choices: Array = field.preview_manifest.get("placements", []).duplicate(true)
	check(choices.size() == 1 and choices[0].population.size() == 1, "100% preview uses the single fitted container position")
	await _capture("editor-preview")
	var objects: Array = editor.draft.placements.duplicate(true)
	var fields: Array = field.session.fields.duplicate(true)
	await editor.test_in_battle()
	check(is_instance_valid(editor.test_battle) and editor.test_battle.battle_initialization_succeeded, "Test battle starts without manual registration")
	if is_instance_valid(editor.test_battle):
		check(editor.test_battle.active_generated_map.content_manifest.placements == choices, "Battle uses the same exact parcel and population choices as Preview")
		check(not editor.displayed_parcel.is_inside_tree(), "Editor physics and hazards are absent from the battle's world")
		check(editor.test_battle.return_button_text() == "RETURN TO PARCEL EDITOR", "The test battle exposes its return route clearly")
		await _capture("local-battle")
		var live := editor.test_battle
		check(await live.battle_controller.try_aim(live.turn_manager.active_unit), "Commit a real action in the local test")
		var recording = live._replay_recorder.recording
		var replay_path := "res://.godot/local_parcel_handoff.replay.json"
		check(recording.save_json(replay_path) == OK, "Save a local-content replay")
		var loaded := BattleReplayRecording.load_json(replay_path)
		check(loaded.is_playable(), "The local replay reloads with its exact archived content: " + loaded.validation_message())
		BattleReplaySession.store(loaded)
		live.replay_last_battle()
		await process_frame
		var replay := current_scene as BattleLevel
		var player := replay.get_node("BattleReplayPlayer") as BattleReplayPlayer
		for frame in 600:
			if player.playback_complete: break
			await process_frame
		check(player.playback_complete and player.playback_succeeded and player.verified_actions == loaded.actions.size(), "Saved local content replays the committed action without divergence: " + player.last_divergence)
		check(replay.return_button_text() == "RETURN TO PARCEL EDITOR", "Rewatch preserves the editor return route")
		var pause := replay.get_node("Visualizers/BattleUI/BattlePauseMenu") as BattlePauseMenu
		pause.set_open(true)
		await _capture("return-to-editor")
		pause._return_to_setup()
		await process_frame
		DirAccess.remove_absolute(replay_path)
	check(editor.visible and editor.displayed_parcel.is_inside_tree() and editor.draft.placements == objects and field.session.fields == fields, "Returning restores the editor without losing either edit")
	check(editor._session_fingerprint() == fingerprint, "A local playtest does not mutate the saved editing session")
	await _capture("editor-restored")
	editor.free()
	DirAccess.remove_absolute(path)
	print("Parcel editor handoff: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _capture(name: String) -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] != "capture" or DisplayServer.get_name() == "headless": return
	DirAccess.make_dir_recursive_absolute(args[1])
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(args[1].path_join(name + ".png")) == OK, "Capture " + name)
