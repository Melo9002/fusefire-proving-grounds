extends SceneTree

const BATTLE_SCENE := preload("res://levels/prototype_map/prototype_map.tscn")
const LayoutStore := preload("res://tools/map_editor_layout_store.gd")
const ReplaySession := preload("res://systems/replay/battle_replay_session.gd")
const TEMP_LAYOUT := "res://tests/.generation_2_edited_replay_test.layout.json"
const TEMP_REPLAY := "res://tests/.generation_2_edited_replay_test.replay.json"

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var previous_time_scale := Engine.time_scale
	Engine.time_scale = 24.0
	ReplaySession.last_recording = null
	var config := _configuration()
	var first := Generation2BattlefieldBuilder.build(config)
	var repeated := Generation2BattlefieldBuilder.build(config)
	check(first.ok and repeated.ok, "identical Generation 2.0 inputs build successfully")
	if not first.ok or not repeated.ok:
		_finish(previous_time_scale)
		return
	check(first.document.signature() == repeated.document.signature(), "identical seed, configuration, and dependencies reproduce the accepted layout document")
	check(_map_signature(first.data) == _map_signature(repeated.data), "repeated tactical compilation reproduces cells, placements, zones, and traversal links")

	var edited := _add_optional_furniture(first.document, config)
	check(edited != null and edited.provenance.get("origin", "") == "edited" and edited.provenance.get("generation_seed", -1) == 17, "a meaningful optional-furniture edit preserves generated provenance")
	var edited_result := Generation2BattlefieldBuilder.compile_document(edited, config) if edited else {"ok": false, "errors": []}
	check(edited_result.ok, "the edited document revalidates through the shared runtime compiler: %s" % _describe(edited_result.errors))
	if not edited_result.ok:
		_finish(previous_time_scale)
		return
	var save_error := LayoutStore.save(edited_result.document, TEMP_LAYOUT)
	check(save_error.is_empty(), "edited layout saves through versioned persistence: %s" % save_error)
	var loaded := LayoutStore.load(IndustrialModuleCatalog.create(), TEMP_LAYOUT)
	check(loaded.ok and _document_semantics(loaded.document) == _document_semantics(edited_result.document), "saved edited layout reloads without losing construction intent")
	if not loaded.ok:
		_finish(previous_time_scale)
		return

	_test_document_failures(loaded.document, config)
	var original := await _start_document_battle(config, loaded.document)
	if original == null:
		_finish(previous_time_scale)
		return
	original.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	original.battle_controller.set_debug_player_ai(true)
	await _wait_for_battle(original, 120.0)
	check(original.turn_manager.battle_result != TurnManager.BattleResult.ONGOING, "edited-map battle reaches a legitimate mission result")
	check(ReplaySession.has_recording(), "edited-map gameplay publishes a playable replay")
	var recording: BattleReplayRecording = ReplaySession.last_recording
	if recording:
		check(recording.configuration.get("battlefield_preset", -1) == BattleConfiguration.BattlefieldPreset.GENERATION_2_INDUSTRIAL, "replay preserves the Generation 2.0 preset")
		check(recording.battlefield_document_signature == BattleReplayRecording.stable_battlefield_document_signature(recording.battlefield_document), "replay records the exact accepted edited battlefield document")
		check(recording.actions.any(func(action): return action.get("kind", "") == "move"), "recording contains authoritative movement")
		check(recording.actions.any(func(action): return action.get("kind", "") == "attack"), "recording contains cover/LOS-dependent combat")
		check(recording.save_json(TEMP_REPLAY) == OK, "document-bearing replay saves as JSON")
	var expected_result := original.turn_manager.battle_result
	var expected_document_signature := recording.battlefield_document_signature if recording else ""
	var expected_presentation := _presentation_signature(original)
	original.queue_free()
	await process_frame
	await process_frame

	if recording:
		var persisted := BattleReplayRecording.load_json(TEMP_REPLAY)
		check(persisted.is_playable(), "saved Generation 2.0 replay reloads with valid dependencies")
		check(persisted.battlefield_document_signature == expected_document_signature, "replay persistence retains edited battlefield identity")
		var replay := await _start_replay(persisted)
		if replay:
			check(BattleReplayRecording.stable_battlefield_document_signature(replay.active_battlefield_document.to_dictionary()) == expected_document_signature, "playback compiles the recorded document instead of regenerating from its seed")
			check(_presentation_signature(replay) == expected_presentation, "replay presentation reconstructs the same component transforms")
			var player := replay.get_node("BattleReplayPlayer") as BattleReplayPlayer
			player.action_delay = 0.001
			player.continuous_actor_delay = 0.001
			player.set_playback_speed(4.0)
			player.set_camera_mode(BattleReplayPlayer.CameraMode.CINEMATIC)
			await _wait_for_replay(player, 120.0)
			check(player.playback_succeeded and player.verified_actions == persisted.actions.size(), "recorded and replayed tactical state agree after every action")
			check(replay.turn_manager.battle_result == expected_result, "replay reaches the recorded mission result")
			check(replay.action_camera_director != null and replay.get_node_or_null("CameraRig") != null, "existing action-camera presentation remains active on the reconstructed environment")
			replay.queue_free()
			await process_frame
	_finish(previous_time_scale)

func _configuration() -> BattleConfiguration:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.battlefield_preset = BattleConfiguration.BattlefieldPreset.GENERATION_2_INDUSTRIAL
	config.map_size = BattleConfiguration.GENERATION_2_MAP_SIZE
	config.battle_seed = 17
	config.player_count = 2
	config.enemy_count = 1
	config.player_commander = AICommanderPolicy.Profile.AGGRESSIVE
	config.enemy_commander = AICommanderPolicy.Profile.DEFAULT
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
	level.battle_initialization_finished.connect(func(success: bool, errors: Array): completed.append({"success": success, "errors": errors.duplicate(true)}), CONNECT_ONE_SHOT)
	root.add_child(level)
	await _wait_for_initialization(completed)
	var ok: bool = not completed.is_empty() and bool(completed[0].success)
	check(ok, "saved edited document initializes a normal battle: %s" % str(completed[0].errors if not completed.is_empty() else "timeout"))
	if ok: return level
	level.queue_free()
	await process_frame
	return null

func _start_replay(recording: BattleReplayRecording) -> BattleLevel:
	var level := BATTLE_SCENE.instantiate() as BattleLevel
	level.configure_replay(recording)
	var completed: Array = []
	level.battle_initialization_finished.connect(func(success: bool, errors: Array): completed.append({"success": success, "errors": errors.duplicate(true)}), CONNECT_ONE_SHOT)
	root.add_child(level)
	await _wait_for_initialization(completed)
	var ok: bool = not completed.is_empty() and bool(completed[0].success)
	check(ok, "replay initializes through document validation and tactical compilation: %s" % str(completed[0].errors if not completed.is_empty() else "timeout"))
	if ok: return level
	level.queue_free()
	await process_frame
	return null

func _wait_for_initialization(completed: Array) -> void:
	var deadline := Time.get_ticks_msec() + 60000
	while completed.is_empty() and Time.get_ticks_msec() < deadline: await process_frame

func _wait_for_battle(level: BattleLevel, timeout_seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while is_instance_valid(level) and level.turn_manager.battle_result == TurnManager.BattleResult.ONGOING and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout

func _wait_for_replay(player: BattleReplayPlayer, timeout_seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while is_instance_valid(player) and not player.playback_complete and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout

func _test_document_failures(source: BattlefieldLayoutDocument, config: BattleConfiguration) -> void:
	var missing_asset := BattlefieldLayoutDocument.from_dictionary(source.to_dictionary())
	missing_asset.spatial_layout.placements[0]["component_id"] = "missing_task_6_3_asset"
	check(_has_code(Generation2BattlefieldBuilder.compile_document(missing_asset, config).errors, "MISSING_PLACEMENT_REFERENCE"), "missing required asset rejects edited battle initialization")
	var stale := BattlefieldLayoutDocument.from_dictionary(source.to_dictionary())
	for dependency in stale.dependencies:
		if dependency.get("required", true) and dependency.get("kind", "") == "asset":
			dependency["geometry_sha256"] = "stale-task-6-3"
			break
	check(Generation2BattlefieldBuilder.compile_document(stale, config).errors.any(func(error): return String(error.get("code", "")).begins_with("STALE_")), "stale geometry, calibration, or assembly dependency is explicit")
	var broken_relationship := BattlefieldLayoutDocument.from_dictionary(source.to_dictionary())
	var required_index := broken_relationship.relationships.find_custom(func(value): return bool(value.get("required", false)))
	if required_index >= 0: broken_relationship.relationships[required_index]["subject_ref"] = "placement:missing_task_6_3"
	check(required_index >= 0 and not Generation2BattlefieldBuilder.compile_document(broken_relationship, config).ok, "invalid required relationship endpoint rejects compilation")
	var unsupported := BattlefieldLayoutDocument.from_dictionary(source.to_dictionary())
	unsupported.environment_id = "unsupported_task_6_3_world"
	check(_has_code(Generation2BattlefieldBuilder.compile_document(unsupported, config).errors, "UNSUPPORTED_ENVIRONMENT"), "unsupported environment identity is explicit")
	var invalid_deployment := BattlefieldLayoutDocument.from_dictionary(source.to_dictionary())
	for zone in invalid_deployment.mission_context.get("zones", []):
		if int(zone.get("kind", -1)) == MapZoneData.Kind.DEPLOYMENT and int(zone.get("faction", -1)) == TacticalUnit.Faction.PLAYER:
			zone["cells"] = zone.get("cells", []).slice(0, 1)
			break
	check(_has_code(Generation2BattlefieldBuilder.compile_document(invalid_deployment, config).errors, "INSUFFICIENT_DEPLOYMENT"), "deployment-invalid edit cannot start a battle")
	var mismatched := config
	var wrong_size := BattlefieldLayoutDocument.from_dictionary(source.to_dictionary())
	wrong_size.spatial_layout["map_size"] = [40, 30]
	check(_has_code(Generation2BattlefieldBuilder.compile_document(wrong_size, mismatched).errors, "DOCUMENT_MAP_SIZE_MISMATCH"), "unsupported mission/map document dimensions are rejected")
	check(LayoutStore.decode("{ malformed", IndustrialModuleCatalog.create()).code == "MALFORMED_JSON", "malformed saved layout fails before replacing runtime state")
	var replay_without_document := BattleReplayRecording.new()
	replay_without_document.configuration = config.to_replay()
	replay_without_document.append_action({"record_index": 0, "schema_version": 1, "kind": "wait", "actor": "PlayerUnit1", "transaction_id": "test", "base_revision": 0, "committed_revision": 1, "request": TacticalActionRequest.simple(&"wait", &"PlayerUnit1", 0, TacticalActionRequest.Source.PLAYER).to_dictionary(), "resolved": {}, "expected_state": "test"})
	check(replay_without_document.validation_message().contains("no battlefield_layout_document"), "Generation 2.0 replay without its environment document is rejected explicitly")

func _map_signature(data: MapData) -> String:
	var parts: Array[String] = [str(data.map_size)]
	var positions: Array[Vector3i] = []
	for value: MapCellData in data.cells.values(): positions.append(value.grid_position)
	positions.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and (a.z < b.z or (a.z == b.z and a.x < b.x))))
	for position in positions:
		var cell := data.get_cell(position)
		parts.append("c:%s:%s:%s:%s:%s" % [position, cell.walkable, cell.can_stop, cell.cover_type, cell.blocks_line_of_sight])
	for placement: EnvironmentModulePlacement in data.environment_modules:
		parts.append("p:%s:%s:%d:%d:%d" % [placement.component_id, placement.origin, placement.rotation, placement.variation, placement.elevation])
	for zone_id in data.zones:
		parts.append("z:%s:%s" % [zone_id, data.get_objective_zone(zone_id)])
	for link in data.traversal_links: parts.append("l:%s" % str(link))
	return "|".join(parts).sha256_text()

func _presentation_signature(level: BattleLevel) -> String:
	var modular := level.get_node_or_null("GeneratedTerrain/ModularEnvironment")
	if modular == null: return "missing"
	var parts: Array[String] = [String(modular.get_meta("environment_identity", ""))]
	for node in modular.get_children():
		parts.append("%s:%s:%s:%s" % [node.get_meta("placement_index", -1), node.get_meta("component_id", ""), node.get_meta("origin", Vector2i.ZERO), node.get_meta("rotation", -1)])
	return "|".join(parts)

func _document_semantics(document: BattlefieldLayoutDocument) -> String:
	if document == null: return "missing"
	var placements: Array[String] = []
	for value in document.spatial_layout.get("placements", []):
		var origin: Array = value.get("origin", [])
		placements.append("%s:%s:%d,%d:%d:%d:%d" % [value.get("placement_id", ""), value.get("component_id", ""), int(origin[0]), int(origin[1]), int(value.get("rotation", -1)), int(value.get("variation", -1)), int(value.get("elevation", -1))])
	return "%s|%s|%s|%d|%s" % [document.document_id, document.environment_id, document.provenance.get("origin", ""), int(document.provenance.get("generation_seed", -1)), "|".join(placements)]

func _has_code(errors: Array, code: String) -> bool:
	return errors.any(func(error): return error.get("code", "") == code)

func _describe(errors: Array) -> String:
	return "; ".join(errors.map(func(error): return "%s:%s" % [error.get("code", ""), error.get("message", "")]))

func _finish(previous_time_scale: float) -> void:
	Engine.time_scale = previous_time_scale
	for path in [TEMP_LAYOUT, TEMP_REPLAY]:
		var absolute := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(absolute): DirAccess.remove_absolute(absolute)
	print("Generation 2.0 replay and edited-map lifecycle: %d failure(s)" % failures)
	quit(1 if failures else 0)

func check(condition: bool, message: String) -> void:
	if condition: print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)
