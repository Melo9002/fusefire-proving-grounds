extends SceneTree
## Contract: editable pilot assets use real Move, shared previews and saved replay.
const Catalog = preload("res://systems/generation2/authored_parcel_catalog.gd")
const Content = preload("res://systems/generation2/local_parcel_content.gd")
const BattleScene = preload("res://levels/prototype_map/prototype_map.tscn")
const Sites = preload("res://systems/generation/battlefield_catalog.gd")
const EditorScene = preload("res://tools/parcel_editor/parcel_editor.tscn")
var failures := 0
var checks := 0

func _initialize() -> void:
	if OS.get_environment("FUSEFIRE_TEST_OUTPUT_DIR").is_empty(): OS.set_environment("FUSEFIRE_TEST_OUTPUT_DIR", ProjectSettings.globalize_path("res://.godot/surface-replay-test"))
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	Engine.time_scale = 12.0
	var parcel = Catalog.get_definition(Catalog.SURFACE_FIT_RANGE)
	check(parcel.validate().is_empty(), "The example is an ordinary editable parcel: %s" % [parcel.validate()])
	var editor := EditorScene.instantiate() as ParcelEditor
	root.add_child(editor)
	await process_frame
	editor.select_parcel(Catalog.SURFACE_FIT_RANGE)
	editor.field_panel.preview()
	var preview_map: MapData = editor.field_panel.compiled_preview
	check(preview_map != null and preview_map.surface_placement_enabled, "Editor Preview resolves the pilot's body geometry")
	var preview_signature := SurfaceNavigation.signature(preview_map) if preview_map else ""
	editor.free()
	await process_frame
	var snapshot := Content.archive(parcel.scene)
	check(not snapshot.has("error"), "Archive exact editable example content")
	if snapshot.has("error"): quit(1); return
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(Sites.PARCEL_TEST)
	config.map_size = parcel.size
	config.player_count = 3
	config.enemy_count = 2
	config.battle_seed = 17
	config.content_manifest = {"local_content": snapshot.content}
	var battle := BattleScene.instantiate() as BattleLevel
	battle.configure_battle(config)
	root.add_child(battle)
	current_scene = battle
	await process_frame
	check(battle.battle_initialization_succeeded, "Pilot initializes through normal Generation 2 battle")
	if not battle.battle_initialization_succeeded:
		battle.free(); quit(1); return
	var grid := battle.battle_controller.grid_manager
	var data := grid.map_data
	check(data.surface_placement_enabled and data.content_manifest.has("standing_points_signature"), "Compiler records body-point signature")
	check(preview_signature == data.content_manifest.standing_points_signature, "Editor Preview and battle resolve exactly the same supported points")
	var targets: Array[Vector3i] = [Vector3i(5, 0, 12), Vector3i(13, 0, 12), Vector3i(21, 0, 12)]
	var names := ["container", "truck", "building edge"]
	for index in targets.size():
		var actor: TacticalUnit = battle.turn_manager.player_units[index]
		battle.turn_manager.select_player_unit(actor)
		var target := targets[index]
		var cell := data.get_cell(target)
		check(cell.can_stop and not cell.world_position.is_equal_approx(cell.support_center), "%s has a usable shifted point: %s / %s" % [names[index], cell.world_position, cell.support_center])
		var query := battle.battle_controller.query_move(actor, target)
		check(query.is_legal(), "%s Move preview is legal: %s" % [names[index], query.validation.message])
		if not query.is_legal(): continue
		check(query.path[-1] == cell.world_position and query.presentation_path[-1] == cell.world_position + Vector3.UP * actor.standing_height, "Preview and animation share %s point" % names[index])
		var service := battle.battle_controller.action_service
		var result := await service.submit_move(service.make_move_request(actor, target, TacticalActionRequest.Source.PLAYER), DisplayServer.get_name() == "headless")
		check(result != null and result.presentation_completed, "Real movement commits beside %s" % names[index])
		check((actor.global_position - Vector3.UP * actor.standing_height).is_equal_approx(cell.world_position), "Character finishes at committed %s point" % names[index])
		check(SurfaceNavigation.body_clear(data, cell.world_position), "Body clears %s" % names[index])
		var contact := actor.visual_adapter._cover_context()
		check(contact.get("stand_position", Vector3.INF) == cell.world_position, "Hybrid contact follows committed %s position" % names[index])
		await _capture(battle, actor, names[index].replace(" ", "-"))
	var recording: BattleReplayRecording = battle._replay_recorder.recording
	check(recording.actions.size() == 3, "All three real moves are recorded")
	for action in recording.actions:
		check(action.resolved.get("standing_points", []).size() == action.resolved.path.size(), "Each checkpoint records quantized XYZ")
	var path := OS.get_environment("FUSEFIRE_TEST_OUTPUT_DIR").path_join("surface-fit.replay.json")
	check(recording.save_json(path) == OK, "Save a real partial-cell replay")
	var restored := BattleReplayRecording.load_json(path)
	check(restored.is_playable(), "Saved replay is playable: " + restored.validation_message())
	var omitted := restored.to_dictionary()
	omitted.ordered_records[0].resolved.erase("standing_points")
	check(not BattleReplayRecording.from_dictionary(omitted).is_playable(), "A surface replay cannot omit checkpoint point evidence")
	check(restored.configuration.content_manifest.standing_points_signature == data.content_manifest.standing_points_signature, "JSON preserves standing-point reconstruction evidence")
	var changed: Dictionary = restored.configuration.content_manifest.duplicate(true)
	changed.standing_points_signature = "changed"
	var rejected := Sites.generate(Sites.PARCEL_TEST, parcel.size, 17, 1.0, changed)
	check(rejected.generation_errors.any(func(issue): return issue.code == "CHANGED_STANDING_POINTS"), "Changed standing-point evidence rejects reconstruction")
	battle.free()
	await process_frame
	var replay := BattleScene.instantiate() as BattleLevel
	replay.configure_replay(restored)
	root.add_child(replay)
	current_scene = replay
	await process_frame
	var player := replay.get_node("BattleReplayPlayer") as BattleReplayPlayer
	var deadline := Time.get_ticks_msec() + 20000
	while not player.playback_complete and Time.get_ticks_msec() < deadline: await process_frame
	check(player.playback_complete and player.playback_succeeded and player.verified_actions == 3, "Saved replay reconstructs all three moves: " + player.last_divergence)
	for index in targets.size():
		var actor: TacticalUnit = replay.turn_manager.player_units[index]
		check(actor.grid_position == targets[index], "Replay restores %s logical cell" % names[index])
		check((actor.global_position - Vector3.UP * actor.standing_height).is_equal_approx(replay.battle_controller.grid_manager.grid_to_world(targets[index])), "Replay restores %s physical position" % names[index])
	replay.free()
	for frame in 10: await process_frame
	DirAccess.remove_absolute(path)
	print("Surface battle/replay: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

func _capture(battle: BattleLevel, actor: TacticalUnit, label: String) -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] != "capture" or DisplayServer.get_name() == "headless": return
	var camera := battle.get_node("CameraRig") as TacticalCamera
	camera.focus_position(actor.global_position)
	camera._manual_pitch = true
	camera.rotation = Vector3(deg_to_rad(-45), deg_to_rad(-30), 0)
	camera._set_zoom(18.0)
	battle.battle_controller.cover_visualizer.draw_for_cells([actor.grid_position])
	for frame in 15: await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(args[1])
	check(root.get_texture().get_image().save_png(args[1].path_join(label + ".png")) == OK, "Capture " + label)
