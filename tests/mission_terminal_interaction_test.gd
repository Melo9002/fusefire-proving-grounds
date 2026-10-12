extends SceneTree

const BATTLE_SCENE := preload("res://levels/prototype_map/prototype_map.tscn")

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	await _test_terminal_action()
	await _test_generated_terminal_placement()
	_test_replay_schema_policy()
	print("Mission terminal interaction: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _test_terminal_action() -> void:
	var config := BattleConfiguration.new()
	config.player_count = 1
	config.enemy_count = 1
	config.battle_seed = 1160
	config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.INTERACT_TERMINAL, 1, false)
	config.mission.terminals[0].grid_position = Vector3i(2, 0, 8)
	var level := BATTLE_SCENE.instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	while level.turn_manager.current_round == 0: await process_frame
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	var service := level.battle_controller.action_service
	var manager := level.objective_manager
	var terminal := manager.get_terminal_state(&"main_terminal")
	check(terminal != null, "Terminal mission creates authoritative runtime terminal state")
	check(level.get_node_or_null("Visualizers/MissionTerminalPresenter/main_terminal") != null, "Terminal visual is generated from authoritative mission state")
	var terminal_cell := terminal.definition.grid_position
	check(CombatRules.can_reach_adjacent(level.battle_controller.grid_manager.get_unit_grid(actor), terminal_cell, level.battle_controller.grid_manager), "Authored terminal is legally adjacent to the player spawn")
	var rng_before := service.get_combat_rng_state()
	check(manager.can_activate_terminal(level.turn_manager.enemy_units[0], &"main_terminal").code == &"wrong_faction", "Terminal interaction enforces objective faction ownership")
	check(manager.can_activate_terminal(actor, &"missing").code == &"terminal_missing", "Unknown terminal IDs reject clearly")
	var query := level.battle_controller.query_terminal(actor, &"main_terminal")
	check(query.is_legal() and query.cost.ap == 0, "Adjacent terminal query exposes the free objective-interaction cost")
	check(query.terminal_position == terminal_cell and query.objective_id == &"activate_terminal", "Query exposes stable terminal and objective identity")
	check(service.get_combat_rng_state() == rng_before and service.state_revision == 0, "Terminal queries consume no RNG or revision")
	var inventory := level.battle_controller.query_terminal(actor)
	check(inventory.legal_target_ids == [&"main_terminal"], "Targetless query discovers the legal mission terminal")
	service.call("_set_busy", true)
	check(level.battle_controller.query_terminal(actor, &"main_terminal").validation.code == &"action_busy", "Terminal interaction rejects while the action service is busy")
	service.call("_set_busy", false)
	actor.stats.is_defeated = true
	check(level.battle_controller.query_terminal(actor, &"main_terminal").validation.code == &"actor_defeated", "Defeated actors cannot interact")
	actor.stats.is_defeated = false
	var diagonal := terminal_cell + Vector3i(-1, 0, -1)
	var side := terminal_cell + Vector3i(-1, 0, 0)
	var diagonal_data := level.battle_controller.grid_manager.get_cell_data(diagonal)
	var side_data := level.battle_controller.grid_manager.get_cell_data(side)
	if diagonal_data and side_data:
		check(CombatRules.can_reach_adjacent(diagonal, terminal_cell, level.battle_controller.grid_manager), "Legal diagonal adjacency is accepted")
		var previous_stop := side_data.can_stop
		side_data.can_stop = false
		check(not CombatRules.can_reach_adjacent(diagonal, terminal_cell, level.battle_controller.grid_manager), "Diagonal interaction through a sealed corner is rejected")
		side_data.can_stop = previous_stop
	actor.stats.current_ap = 0
	check(level.battle_controller.query_terminal(actor, &"main_terminal").is_legal(), "An active unit may interact with zero AP, matching Rescue and Extract")
	await process_frame
	await process_frame
	check(level.turn_manager.active_unit == actor, "Selection waits when an exhausted unit can still perform a free terminal interaction")
	actor.stats.current_ap = actor.stats.max_ap
	var ap_before := actor.stats.current_ap
	var stale := service.make_terminal_request(actor, &"main_terminal", TacticalActionRequest.Source.PLAYER)
	stale.expected_revision = -1
	check(await service.submit_mission(stale, true) == null and actor.stats.current_ap == ap_before and not terminal.is_activated, "Stale terminal request changes no state")
	actor.tactical_state.establish_aim()
	var sp_before := actor.stats.current_supply_points
	var result := await service.submit_mission(service.make_terminal_request(actor, &"main_terminal", TacticalActionRequest.Source.PLAYER), true)
	check(result != null and result.actor_ap_before == ap_before and result.actor_ap_after == ap_before, "Committed terminal interaction consumes no AP")
	check(actor.stats.current_supply_points == sp_before and service.get_combat_rng_state() == rng_before, "Terminal interaction consumes no SP or combat RNG")
	check(terminal.is_activated and result.terminal_activated_after, "Terminal activation commits exactly once")
	check(not actor.tactical_state.is_aiming, "Committed terminal interaction cancels Aim")
	var objective := manager.get_objective(&"activate_terminal")
	check(objective != null and objective.is_completed() and objective.progress == 1, "Terminal advances only its configured objective")
	check(service.state_revision == 1 and result.transaction_id == 1, "Terminal interaction produces one transaction and revision")
	check(manager.can_activate_terminal(actor, &"main_terminal").code == &"terminal_activated", "Activated terminal cannot be used repeatedly")
	var record := result.to_replay_record()
	check(record.schema_version == 8 and ReplayRecordTools.validate_action_record(record.merged({"expected_state": "x", "record_index": 0}), 3).is_empty(), "Replay accepts the typed terminal payload")
	check(record.resolved.terminal_position == [terminal_cell.x, terminal_cell.y, terminal_cell.z], "Replay records terminal position and state evidence")
	var fingerprint := BattleStateFingerprint.capture(level.turn_manager, level.battle_controller.grid_manager, manager)
	check(fingerprint.contains("terminal=main_terminal,%d,%d,%d,1" % [terminal_cell.x, terminal_cell.y, terminal_cell.z]), "New state fingerprints include authoritative terminal activation")
	var recording = level.get("_replay_recorder").recording
	level.queue_free()
	await process_frame
	await process_frame
	var replay := BATTLE_SCENE.instantiate() as BattleLevel
	replay.configure_replay(recording)
	root.add_child(replay)
	while replay.turn_manager.current_round == 0: await process_frame
	var player = replay.get_node("BattleReplayPlayer")
	var deadline := Time.get_ticks_msec() + 5000
	while not player.playback_complete and Time.get_ticks_msec() < deadline: await process_frame
	check(player.playback_succeeded and player.verified_actions == 1, "Terminal interaction reconstructs through the ordinary authoritative replay path")
	replay.queue_free()
	await process_frame
	await process_frame

func _test_generated_terminal_placement() -> void:
	var config := BattleConfiguration.new()
	config.player_count = 1
	config.enemy_count = 1
	config.generated_map = true
	config.map_size = Vector2i(24, 20)
	config.battle_seed = 1161
	config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.INTERACT_TERMINAL, 1, false)
	var level := BATTLE_SCENE.instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	while level.turn_manager.current_round == 0: await process_frame
	var terminal := level.objective_manager.get_terminal_state(&"main_terminal")
	var data = level.battle_controller.grid_manager.get_cell_data(terminal.definition.grid_position) if terminal else null
	check(terminal != null and data != null and not data.walkable and not data.can_stop, "Generated Terminal missions choose a deterministic blocked objective cell")
	check(level.get_node_or_null("Visualizers/MissionTerminalPresenter/main_terminal") != null, "Generated Terminal missions create their visual representation")
	level.queue_free()
	await process_frame
	await process_frame

func _test_replay_schema_policy() -> void:
	var old_mission_record := {"kind": "rescue", "actor": "A", "target": "B", "expected_state": "x", "record_index": 0, "schema_version": 2, "transaction_id": 1, "base_revision": 0, "committed_revision": 1, "request": TacticalActionRequest.mission(&"rescue", &"A", &"B", 0, TacticalActionRequest.Source.REPLAY).to_dictionary(), "resolved": {}}
	check(ReplayRecordTools.validate_action_record(old_mission_record, 3).is_empty(), "Historical schema-2 mission payloads remain supported")
	var bad_terminal := old_mission_record.duplicate(true)
	bad_terminal.kind = "interact_terminal"
	check(ReplayRecordTools.validate_action_record(bad_terminal, 3).contains("expected 8"), "Terminal payloads reject unsupported versions clearly")
