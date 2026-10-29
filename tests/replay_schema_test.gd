extends SceneTree

var failures := 0

func _initialize() -> void:
	_run()

func _run() -> void:
	var mission := MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.RESCUE, 2, false)
	var recording := BattleReplayRecording.new()
	recording.configuration = {
		"player_count": 2, "enemy_count": 2, "ally_count": 1,
		"generated_map": true, "seed": 733578405, "map_size": Vector2i(32, 24),
		"include_vip": false, "vip_behavior": MissionActor.VIPBehavior.PLAYER_CONTROLLED,
		"mission": mission, "difficulty": AIDifficultyPolicy.Tier.NORMAL, "refinery": true,
	}
	recording.initial_state_fingerprint = "round=1|phase=0"
	recording.expected_result = TurnManager.BattleResult.VICTORY
	recording.append_action({
		"record_index": 0, "schema_version": 2, "kind": "move",
		"actor": "PlayerUnit1", "transaction_id": 1,
		"base_revision": 0, "committed_revision": 1,
		"request": TacticalActionRequest.move(&"PlayerUnit1", Vector3i(2, 0, 3), 0, TacticalActionRequest.Source.PLAYER).to_dictionary(),
		"resolved": {"from": [1, 0, 3], "to": [2, 0, 3]},
		"expected_state": "round=1|phase=0|active=PlayerUnit1",
	})

	var terminal_recording := BattleReplayRecording.from_dictionary(recording.to_dictionary())
	var terminal_mission := MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.INTERACT_TERMINAL,2,false)
	terminal_mission.terminals[0].grid_position = Vector3i(7,2,11)
	terminal_mission.terminals[0].initially_activated = true
	terminal_recording.configuration.mission = terminal_mission
	var terminal_copy := BattleReplayRecording.from_dictionary(JSON.parse_string(JSON.stringify(terminal_recording.to_dictionary())))
	var restored_terminals: Array = terminal_copy.configuration.mission.terminals
	check(restored_terminals.size() == 1,"Terminal definition survives replay JSON serialization")
	if restored_terminals.size() == 1:
		check(restored_terminals[0].terminal_id == &"main_terminal" and restored_terminals[0].objective_id == &"activate_terminal" and restored_terminals[0].grid_position == Vector3i(7,2,11) and restored_terminals[0].initially_activated,"Replay preserves terminal identity, objective, elevation and initial state")

	var rebuilt := BattleReplayRecording.from_dictionary(recording.to_dictionary())
	check(rebuilt.is_playable(), "Current replay schema round trip is playable")
	check(rebuilt.schema_version == BattleReplayRecording.CURRENT_SCHEMA_VERSION, "Envelope version survives round trip")
	check(rebuilt.configuration.seed == 733578405 and rebuilt.configuration.map_size == Vector2i(32, 24), "Seed and map size survive round trip")
	check(rebuilt.configuration.player_commander == AICommanderPolicy.Profile.DEFAULT and rebuilt.configuration.enemy_commander == AICommanderPolicy.Profile.DEFAULT, "Older replay configurations default both commander teams")
	check(not rebuilt.configuration.industrial_warehouse, "Older replay configurations default away from the industrial preset")
	var industrial_recording_data := recording.to_dictionary()
	var industrial_configuration: Dictionary = industrial_recording_data.get("battle_configuration", {})
	industrial_configuration["industrial_warehouse"] = true
	var industrial_rebuilt := BattleReplayRecording.from_dictionary(industrial_recording_data)
	check(industrial_rebuilt.configuration.industrial_warehouse, "Industrial preset identity survives replay envelope serialization")
	var cautious_recording_data := recording.to_dictionary()
	var cautious_configuration: Dictionary = cautious_recording_data.get("battle_configuration", {})
	cautious_configuration["player_commander"] = AICommanderPolicy.Profile.CAUTIOUS
	var cautious_rebuilt := BattleReplayRecording.from_dictionary(cautious_recording_data)
	check(cautious_rebuilt.configuration.player_commander == AICommanderPolicy.Profile.CAUTIOUS, "Non-default commander identity survives replay envelope serialization")
	var aggressive_recording_data := recording.to_dictionary()
	var aggressive_configuration: Dictionary = aggressive_recording_data.get("battle_configuration", {})
	aggressive_configuration["enemy_commander"] = AICommanderPolicy.Profile.AGGRESSIVE
	var aggressive_rebuilt := BattleReplayRecording.from_dictionary(aggressive_recording_data)
	check(aggressive_rebuilt.configuration.enemy_commander == AICommanderPolicy.Profile.AGGRESSIVE, "Aggressive commander identity survives replay envelope serialization")
	check(not rebuilt.configuration.supply_points_enabled, "A replay configuration without an SP rules flag remains explicitly historical after round trip")
	check(not rebuilt.configuration.tactical_tempo_enabled, "A replay configuration without a tactical-tempo flag retains its historical fingerprint shape")
	check(rebuilt.configuration.mission is MissionDefinition and rebuilt.configuration.mission.objectives.size() == mission.objectives.size(), "Mission definition survives round trip")
	check(rebuilt.actions[0].request.actor_id == "PlayerUnit1", "Stable tactical actor ID remains human-readable")

	var path := "res://tests/.replay_schema_test.tmp.json"
	check(recording.save_json(path) == OK, "Replay saves as readable JSON")
	var loaded := BattleReplayRecording.load_json(path)
	check(loaded.is_playable() and loaded.actions.size() == 1, "Saved JSON replay loads and validates")
	check(ReplayRecordTools.compare_fields(recording.actions[0].resolved, loaded.actions[0].resolved).is_empty(), "Replay comparison treats persistence-normalized integer coordinates as equivalent")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	var unsupported := BattleReplayRecording.from_dictionary(recording.to_dictionary())
	unsupported.schema_version = 999
	check(unsupported.validation_message().contains("Unsupported replay schema"), "Unsupported schemas fail with an actionable error")

	var broken_recording := BattleReplayRecording.from_dictionary(recording.to_dictionary())
	broken_recording.actions[0].erase("committed_revision")
	check(broken_recording.validation_message().contains("committed_revision"), "Current records reject missing revision contracts")

	var legacy := BattleReplayRecording.new()
	legacy.schema_version = BattleReplayRecording.LEGACY_SCHEMA_VERSION
	legacy.configuration = recording.configuration.duplicate(true)
	legacy.append_action({"kind": "defend", "actor": "PlayerUnit1", "expected_state": "legacy"})
	check(legacy.is_playable(), "Schema 2 remains an explicit supported compatibility boundary")

	var field_difference := ReplayRecordTools.compare_fields(
		{"resolved": {"damage": 25, "did_hit": true}},
		{"resolved": {"damage": 0, "did_hit": true}}
	)
	check(field_difference == "resolved.damage differs: expected 25, got 0", "Divergence reports the earliest field path and values")

	var request := TacticalActionRequest.attack(&"PlayerUnit1", &"EnemyUnit1", 7, TacticalActionRequest.Source.AI)
	var request_copy := TacticalActionRequest.from_dictionary(request.to_dictionary())
	check(request_copy.actor_id == request.actor_id and request_copy.target_id == request.target_id and request_copy.expected_revision == 7, "Action request round trip preserves IDs and revision")

	for result in [_move_result(request), _simple_result(request), _mission_result(request)]:
		var record: Dictionary = result.to_replay_record()
		check(record.base_revision == 7 and record.committed_revision == 8, "Every action result records base and committed revisions")

	print("Replay schema: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _move_result(request: TacticalActionRequest) -> MoveActionResult:
	var result := MoveActionResult.new()
	result.request = TacticalActionRequest.move(request.actor_id, Vector3i.ZERO, 7, request.source)
	result.transaction_id = 1; result.base_revision = 7; result.committed_revision = 8
	return result

func _simple_result(request: TacticalActionRequest) -> SimpleActionResult:
	var result := SimpleActionResult.new()
	result.request = TacticalActionRequest.simple(&"wait", request.actor_id, 7, request.source)
	result.transaction_id = 1; result.base_revision = 7; result.committed_revision = 8
	return result

func _mission_result(request: TacticalActionRequest) -> MissionActionResult:
	var result := MissionActionResult.new()
	result.request = TacticalActionRequest.mission(&"extract", request.actor_id, &"", 7, request.source)
	result.transaction_id = 1; result.base_revision = 7; result.committed_revision = 8
	return result

func check(condition: bool, message: String) -> void:
	if condition: return
	failures += 1
	push_error(message)
