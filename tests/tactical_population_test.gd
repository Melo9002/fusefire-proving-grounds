extends "res://tests/generation_2_replay_edited_map_test.gd"
## Reuse the existing document battle/replay oracle; only the source strategy changes.
func _run() -> void:
	var previous_time_scale := Engine.time_scale
	Engine.time_scale = 24.0
	ReplaySession.last_recording = null
	var context := EnvironmentResolutionContext.new()
	var loaded_base := LayoutStore.load(context.catalog, FixedEnvironmentPopulation.BASE_PATH)
	check(loaded_base.ok, "fixed authored base loads")
	if not loaded_base.ok: _finish(previous_time_scale); return
	var base: BattlefieldLayoutDocument = loaded_base.document
	var signature := base.signature()
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FixedEnvironmentPopulation.RULES_PATH))
	var results: Array = []
	for population_seed in [17, 42, 17]:
		var result := TacticalPopulationPass.populate(base, rules, population_seed, context)
		check(result.ok, "population seed %d compiles: %s" % [population_seed, str(result.errors)])
		check(base.signature() == signature, "authored base signature remains immutable")
		if not result.ok: _finish(previous_time_scale); return
		check(TacticalPopulationPass.canonical(result.document.provenance.population.base_placements) == TacticalPopulationPass.canonical(base.spatial_layout.placements), "fixed placement identities/transforms/variants preserved")
		check(result.repairs.is_empty(), "population never repairs away authored mission positions")
		check(result.document.provenance.population.attempts <= 512, "candidate search bounded")
		check(TacticalPopulationPass.verify(result.document, result.data, context).is_empty(), "declared regions, protected routes and mission reservations hold")
		results.append(result)
		check(LayoutStore.save(result.document, "res://artifacts/t08-seed%d.layout.json" % population_seed).is_empty(), "save exact accepted population")
	check(results[0].document.signature() == results[2].document.signature() and _map_signature(results[0].data) == _map_signature(results[2].data), "same seed reproduces accepted document and tactical state")
	check(_map_signature(results[0].data) != _map_signature(results[1].data), "different seeds change tactical cover, not merely visual variants")
	_population_negatives(base, rules, results[0].document, context)
	var config := FixedEnvironmentPopulation.configuration(17)
	config.enemy_count = 1
	config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, 1, false)
	config.player_commander = AICommanderPolicy.Profile.AGGRESSIVE
	var loaded := LayoutStore.load(context.catalog, "res://artifacts/t08-seed17.layout.json")
	check(loaded.ok, "accepted population round-trips through shared store")
	if not loaded.ok: _finish(previous_time_scale); return
	var round_trip := Generation2BattlefieldBuilder.compile_document(loaded.document, config)
	check(round_trip.ok and _map_signature(round_trip.data) == _map_signature(results[0].data), "saved choices compile unchanged without rerunning population")
	var original := await _start_document_battle(config, loaded.document)
	if original == null: _finish(previous_time_scale); return
	original.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	original.battle_controller.set_debug_player_ai(true)
	await _wait_for_battle(original, 120.0)
	check(original.turn_manager.battle_result != TurnManager.BattleResult.ONGOING, "fixed populated battlefield completes real combat")
	var recording: BattleReplayRecording = ReplaySession.last_recording
	check(recording != null and not recording.actions.is_empty(), "population gameplay creates a recording")
	var expected_result := original.turn_manager.battle_result
	original.queue_free()
	await process_frame
	await process_frame
	if recording:
		check(recording.actions.any(func(a): return a.get("kind") == "move") and recording.actions.any(func(a): return a.get("kind") == "attack"), "real movement and combat exercised")
		check(recording.save_json(TEMP_REPLAY) == OK, "population replay saves")
		var persisted := BattleReplayRecording.load_json(TEMP_REPLAY)
		check(persisted.is_playable(), "population replay reloads")
		var replay := await _start_replay(persisted)
		if replay:
			var player: BattleReplayPlayer = replay.get_node("BattleReplayPlayer") as BattleReplayPlayer
			player.action_delay = 0.001
			player.continuous_actor_delay = 0.001
			player.set_playback_speed(4.0)
			await _wait_for_replay(player,120.0)
			check(player.playback_succeeded and player.verified_actions == persisted.actions.size(), "population replay verifies all %d actions" % persisted.actions.size())
			check(replay.turn_manager.battle_result == expected_result, "population replay outcome agrees")
			replay.queue_free()
			await process_frame
	var terminal_config := FixedEnvironmentPopulation.configuration(17, MissionObjectiveDefinition.Kind.INTERACT_TERMINAL)
	var terminal := await _start_document_battle(terminal_config, loaded.document)
	if terminal:
		check(not terminal.active_generated_map.get_objective_zone(&"terminal").is_empty(), "active Terminal mission retains its protected objective")
		terminal.queue_free()
		await process_frame
	print("T08 population failures: ",failures)
	_finish(previous_time_scale)


func _population_negatives(base: BattlefieldLayoutDocument, rules: Dictionary, accepted: BattlefieldLayoutDocument, context: EnvironmentResolutionContext) -> void:
	var signature := base.signature()
	var bad := rules.duplicate(true)
	bad.regions[0].anchors = [[0,0]]
	check(not TacticalPopulationPass.populate(base, bad, 17, context).ok, "out-of-region candidates reject")
	bad = rules.duplicate(true)
	bad.regions[0].elevation = 7
	bad.regions[0].anchors = [bad.regions[0].anchors[0]]
	bad.regions[0].choices = [bad.regions[0].choices[0]]
	check(not TacticalPopulationPass.populate(base, bad, 17, context).ok, "unsupported floor exhausts explicitly; no floating population")
	bad = rules.duplicate(true)
	bad.regions[0].bounds = [0,20,60,10]
	bad.regions[0].anchors = [[12,24]]
	bad.regions[0].choices = [bad.regions[0].choices[0]]
	check(not TacticalPopulationPass.populate(base, bad, 17, context).ok, "candidate across protected route rejects")
	var changed := BattlefieldLayoutDocument.from_dictionary(accepted.to_dictionary())
	changed.spatial_layout.placements[0].variation += 1
	check(not BattlefieldLayoutDocumentCompiler.compile(changed).ok, "changed immutable base rejects on compile")
	changed = BattlefieldLayoutDocument.from_dictionary(accepted.to_dictionary())
	changed.spatial_layout.placements.pop_back()
	check(not BattlefieldLayoutDocumentCompiler.compile(changed).ok, "missing accepted addition rejects on load/play compilation")
	changed = BattlefieldLayoutDocument.from_dictionary(accepted.to_dictionary())
	changed.provenance.population.base_placements = [null]
	check(not BattlefieldLayoutDocumentCompiler.compile(changed).ok, "malformed population snapshot rejects without crashing")
	check(base.signature() == signature, "rejected population leaves original source intact")
	bad = rules.duplicate(true)
	bad.regions = [{"id": "mission_intrusion", "bounds": [0,0,60,50], "elevation": 0, "count": 1, "anchors": [[45,36]], "choices": [{"component_id": "service_dumpster", "rotation": 0, "variation": 0}]}]
	bad.routes = []
	check(not TacticalPopulationPass.populate(base, bad, 17, context).ok, "mission reservation rejects population independently of protected routes")
