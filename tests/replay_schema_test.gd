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

	var rebuilt := BattleReplayRecording.from_dictionary(recording.to_dictionary())
	check(rebuilt.is_playable(), "Current replay schema round trip is playable")
	check(rebuilt.schema_version == BattleReplayRecording.CURRENT_SCHEMA_VERSION, "Envelope version survives round trip")
	check(rebuilt.configuration.seed == 733578405 and rebuilt.configuration.map_size == Vector2i(32, 24), "Seed and map size survive round trip")
	check(not rebuilt.configuration.supply_points_enabled, "A replay configuration without an SP rules flag remains explicitly historical after round trip")
	check(rebuilt.configuration.mission is MissionDefinition and rebuilt.configuration.mission.objectives.size() == mission.objectives.size(), "Mission definition survives round trip")
	check(rebuilt.actions[0].request.actor_id == "PlayerUnit1", "Stable tactical actor ID remains human-readable")

	var path := "res://tests/.replay_schema_test.tmp.json"
	check(recording.save_json(path) == OK, "Replay saves as readable JSON")
	var loaded := BattleReplayRecording.load_json(path)
	check(loaded.is_playable() and loaded.actions.size() == 1, "Saved JSON replay loads and validates")
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
