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
	await _check_registration_and_multiple_watchers()
	await _check_lethal_interruption()
	await _check_reactive_move_camera_release(false)
	await _check_reactive_move_camera_release(true)
	await _check_direct_attack_retaliation()
	await _check_defeated_watcher_cannot_retaliate()
	await _check_player_overwatch_hands_off_turn_and_draws_range()
	await _check_ai_acts_after_player_overwatch()
	_check_hypothetical_occupancy()
	var legacy := BattleConfiguration.new()
	legacy.apply_replay({"player_count": 1, "enemy_count": 1, "supply_points_enabled": true, "aim_enabled": true, "shield_enabled": true})
	check(not legacy.overwatch_enabled, "Historical replay configuration retains pre-Overwatch semantics")
	check(BattleConfiguration.new().to_replay().overwatch_enabled, "New battles record Overwatch semantics explicitly")
	print("Overwatch reactions: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _check_registration_and_multiple_watchers() -> void:
	var level := await _create_battle(2)
	var service := level.battle_controller.action_service
	var first: TacticalUnit = level.turn_manager.player_units[0]
	var second: TacticalUnit = level.turn_manager.player_units[1]
	var mover: TacticalUnit = level.turn_manager.enemy_units[0]
	_clear_shot_geometry(level)
	first.attack_range = 100
	second.attack_range = 100
	var rng_before := service.get_combat_rng_state()
	var query := service.query_overwatch(first.tactical_id)
	check(query.is_legal() and query.cost.spend_all_remaining_ap and query.actor_ap_after == 0, "Overwatch query exposes all-remaining-AP cost")
	check(query.supply_points_before == 4 and service.get_combat_rng_state() == rng_before, "Overwatch query is read-only and requires available SP")
	first.stats.current_supply_points = 0
	check(service.query_overwatch(first.tactical_id).validation.code == &"insufficient_supply_points", "Overwatch requires one available SP without consuming it")
	first.stats.current_supply_points = 4
	service._set_busy(true)
	check(service.query_overwatch(first.tactical_id).validation.code == &"action_busy", "Busy action service rejects Overwatch")
	service._set_busy(false)
	var stale := service.make_overwatch_request(first, TacticalActionRequest.Source.PLAYER)
	stale.expected_revision = -1
	check(await service.submit_overwatch(stale, true) == null and service.last_rejection.code == &"stale_revision", "Stale Overwatch is rejected without mutation")
	first.tactical_state.establish_shield(Vector2.RIGHT)
	check(service.query_overwatch(first.tactical_id).validation.code == &"shield_stance_restriction", "Shield and Overwatch cannot stack")
	first.tactical_state.clear_shield()
	first.tactical_state.establish_aim()
	var armed_first := await service.submit_overwatch(service.make_overwatch_request(first, TacticalActionRequest.Source.PLAYER), true)
	check(armed_first != null and first.stats.current_ap == 0 and first.stats.spent_ap == first.stats.activation_capacity_ap and first.stats.current_supply_points == 4 and first.tactical_state.is_overwatching and not first.tactical_state.is_aiming, "Registration records all remaining AP as expenditure, preserves SP, cancels Aim, and arms one reaction")
	first.stats.set_available_ap_for_setup(1)
	check(service.query_overwatch(first.tactical_id).validation.code == &"already_overwatching", "Duplicate Overwatch registration is rejected")
	first.stats.set_available_ap_for_setup(0)
	level.turn_manager.call("_set_active_unit", second)
	second.stats.is_defeated = true
	check(service.query_overwatch(second.tactical_id).validation.code == &"actor_defeated", "Defeated actor cannot register Overwatch")
	second.stats.is_defeated = false
	var armed_second := await service.submit_overwatch(service.make_overwatch_request(second, TacticalActionRequest.Source.PLAYER), true)
	check(armed_second != null and second.tactical_state.is_overwatching, "A second watcher registers through the same action path")
	level.turn_manager.current_phase = TurnManager.TurnPhase.ENEMY_TURN
	level.turn_manager.call("_set_active_unit", mover)
	var move_query := service.query_move(mover.tactical_id)
	var destination := _destination_with_path(service, mover, move_query.legal_destination_cells)
	check(destination.x >= 0, "Reaction fixture finds a multi-cell legal move")
	var revision_before := service.state_revision
	var move := await service.submit_move(service.make_move_request(mover, destination, TacticalActionRequest.Source.AI), true)
	check(move != null and move.reaction_events.size() == 2, "One Move resolves both eligible watchers as nested events")
	if move and move.reaction_events.size() == 2:
		check(move.reaction_events[0].watcher_id == first.tactical_id and move.reaction_events[1].watcher_id == second.tactical_id, "Multiple reactions use stable tactical actor ordering")
	check(first.stats.current_supply_points == 3 and second.stats.current_supply_points == 3, "Each committed reaction consumes exactly one SP")
	check(not first.tactical_state.is_overwatching and not second.tactical_state.is_overwatching, "Each registration is consumed after one shot")
	check(service.state_revision == revision_before + 1 and move.committed_revision == service.state_revision, "Nested reactions retain one parent Move revision")
	check(level.battle_controller.grid_manager.get_unit_at(move.target_cell) == mover, "Surviving mover commits final occupancy exactly once")
	var move_record: Dictionary = level._replay_recorder.recording.actions[-1]
	check(move_record.get("kind") == "move" and move_record.get("schema_version") == MoveActionResult.SCHEMA_VERSION, "Replay records the reactive movement as one typed parent action")
	check(move_record.get("resolved", {}).get("reaction_events", []).size() == 2, "Replay keeps ordered reaction outcomes inside the parent Move payload")
	check(ReplayRecordTools.validate_action_record(move_record, BattleReplayRecording.CURRENT_SCHEMA_VERSION).is_empty(), "Reactive Move payload passes replay schema validation")
	level.queue_free()
	await process_frame
	await process_frame

func _check_lethal_interruption() -> void:
	var level := await _create_battle(1)
	var service := level.battle_controller.action_service
	var watcher: TacticalUnit = level.turn_manager.player_units[0]
	var mover: TacticalUnit = level.turn_manager.enemy_units[0]
	_clear_shot_geometry(level)
	watcher.attack_range = 100
	check(await service.submit_overwatch(service.make_overwatch_request(watcher, TacticalActionRequest.Source.PLAYER), true) != null, "Lethal fixture registers Overwatch")
	level.turn_manager.current_phase = TurnManager.TurnPhase.ENEMY_TURN
	level.turn_manager.call("_set_active_unit", mover)
	var inventory := service.query_move(mover.tactical_id)
	var destination := _destination_with_path(service, mover, inventory.legal_destination_cells)
	var preview := service.query_move(mover.tactical_id, destination)
	mover.shield_capability = preload("res://units/capabilities/physical_shield.tres")
	var checkpoint := preview.path_cells[1]
	var watcher_cell := level.battle_controller.grid_manager.get_unit_grid(watcher)
	mover.tactical_state.establish_shield(Vector2(watcher_cell.x - checkpoint.x, watcher_cell.z - checkpoint.z))
	mover.stats.current_hp = 9
	service._combat_rng.seed = _seed_for_hit(85)
	var move := await service.submit_move(service.make_move_request(mover, destination, TacticalActionRequest.Source.AI), true)
	check(move != null and move.movement_interrupted and move.reaction_events.size() == 1 and move.reaction_events[0].target_defeated, "Lethal reaction interrupts movement at its checkpoint")
	if move:
		check(move.reaction_events[0].shield_applied and move.reaction_events[0].damage == 9, "Reaction fire uses ordinary directional shield protection and damage rounding")
		check(move.target_cell == move.reaction_events[0].checkpoint_cell and move.path_cells.size() < preview.path_cells.size(), "Interrupted Move shortens its authoritative path to the lethal checkpoint")
		check(level.battle_controller.grid_manager.get_unit_at(move.start_cell) == null and level.battle_controller.grid_manager.get_unit_at(move.target_cell) == null, "Defeated mover leaves no ghost occupancy at origin or checkpoint")
	check(watcher.stats.current_supply_points == 3 and not watcher.tactical_state.is_overwatching, "Lethal reaction consumes its SP and registration once")
	level.queue_free()
	await process_frame

func _check_direct_attack_retaliation() -> void:
	var level := await _create_battle(1)
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.COMBAT_ONLY
	var service := level.battle_controller.action_service
	var watcher: TacticalUnit = level.turn_manager.player_units[0]
	var attacker: TacticalUnit = level.turn_manager.enemy_units[0]
	_clear_shot_geometry(level)
	watcher.attack_range = 100
	attacker.attack_range = 100
	check(await service.submit_overwatch(service.make_overwatch_request(watcher, TacticalActionRequest.Source.PLAYER), true) != null, "Return-fire fixture registers Overwatch")
	level.turn_manager.current_phase = TurnManager.TurnPhase.ENEMY_TURN
	level.turn_manager.call("_set_active_unit", attacker)
	var watcher_hp_before := watcher.stats.current_hp
	var watcher_sp_before := watcher.stats.current_supply_points
	var revision_before := service.state_revision
	var attack := await service.submit_attack(service.make_attack_request(attacker, watcher, TacticalActionRequest.Source.AI))
	check(attack != null and attack.reaction_events.size() == 1, "A direct attack against a surviving watcher triggers one retaliation")
	check(watcher.stats.current_hp <= watcher_hp_before and watcher.stats.current_supply_points == watcher_sp_before - 1, "The original attack resolves first and retaliation consumes one SP")
	check(not watcher.tactical_state.is_overwatching and service.state_revision == revision_before + 1, "Attack retaliation consumes the reservation inside one parent revision")
	var camera_rig := level.get_node("CameraRig") as TacticalCamera
	check(not camera_rig._cinematic_active and not camera_rig.is_camera_transitioning() and not service.is_busy, "Direct-attack Guard releases cinematic ownership and the action barrier")
	if attack and not attack.reaction_events.is_empty():
		check(attack.reaction_events[0].watcher_id == watcher.tactical_id, "Nested retaliation preserves the watching actor identity")
	var attack_record: Dictionary = level._replay_recorder.recording.actions[-1]
	check(attack_record.get("kind") == "attack" and attack_record.get("resolved", {}).get("reaction_events", []).size() == 1, "Replay nests retaliation inside the initiating Attack record")
	check(ReplayRecordTools.validate_action_record(attack_record, BattleReplayRecording.CURRENT_SCHEMA_VERSION).is_empty(), "Retaliating Attack payload passes replay schema validation")
	level.queue_free()
	await process_frame
	await process_frame
	await process_frame

func _check_reactive_move_camera_release(lethal: bool) -> void:
	var level := await _create_battle(2)
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.COMBAT_ONLY
	var service := level.battle_controller.action_service
	var watcher: TacticalUnit = level.turn_manager.player_units[0]
	var next_player: TacticalUnit = level.turn_manager.player_units[1]
	var mover: TacticalUnit = level.turn_manager.enemy_units[0]
	var camera_rig := level.get_node("CameraRig") as TacticalCamera
	_clear_shot_geometry(level)
	watcher.attack_range = 100
	check(await service.submit_overwatch(service.make_overwatch_request(watcher, TacticalActionRequest.Source.PLAYER), true) != null, "%s camera fixture registers Guard" % ("Lethal" if lethal else "Nonlethal"))
	level.turn_manager.current_phase = TurnManager.TurnPhase.ENEMY_TURN
	level.turn_manager.call("_set_active_unit", mover)
	var move_query := service.query_move(mover.tactical_id)
	var destination := _destination_with_path(service, mover, move_query.legal_destination_cells)
	if lethal:
		mover.stats.current_hp = 1
	service._combat_rng.seed = _seed_for_hit(100)
	var move := await service.submit_move(service.make_move_request(mover, destination, TacticalActionRequest.Source.AI))
	var label := "Lethal" if lethal else "Nonlethal"
	check(move != null and move.reaction_events.size() == 1, "%s movement triggers one presented Guard reaction" % label)
	if move and not move.reaction_events.is_empty():
		check(move.reaction_events[0].target_defeated == lethal, "%s camera fixture resolves the intended survival result" % label)
	check(not camera_rig._cinematic_active, "%s movement-triggered Guard releases cinematic camera ownership" % label)
	check(not camera_rig.is_camera_transitioning(), "%s movement-triggered Guard completes the tactical-camera return" % label)
	check(not service.is_busy, "%s movement-triggered Guard releases the action-service barrier" % label)
	if lethal:
		check(level.turn_manager.battle_result == TurnManager.BattleResult.VICTORY, "Lethal movement-triggered Guard permits normal battle-result progression")
	else:
		level.turn_manager.current_phase = TurnManager.TurnPhase.PLAYER_TURN
		next_player.stats.refresh_activation()
		check(level.turn_manager.select_player_unit(next_player), "Nonlethal movement-triggered Guard leaves normal player selection operable")
		check(level.turn_manager.active_unit == next_player, "Nonlethal movement-triggered Guard permits normal phase selection progression")
	var camera_before_pan := camera_rig.global_position
	camera_rig._pan(Vector2.RIGHT, 0.1)
	check(not camera_rig.global_position.is_equal_approx(camera_before_pan), "%s movement-triggered Guard restores manual camera control" % label)
	level.queue_free()
	await process_frame
	await process_frame

func _check_defeated_watcher_cannot_retaliate() -> void:
	var level := await _create_battle(1)
	var service := level.battle_controller.action_service
	var watcher: TacticalUnit = level.turn_manager.player_units[0]
	var attacker: TacticalUnit = level.turn_manager.enemy_units[0]
	_clear_shot_geometry(level)
	watcher.attack_range = 100
	attacker.attack_range = 100
	check(await service.submit_overwatch(service.make_overwatch_request(watcher, TacticalActionRequest.Source.PLAYER), true) != null, "Defeated-watcher fixture registers Overwatch")
	level.turn_manager.current_phase = TurnManager.TurnPhase.ENEMY_TURN
	level.turn_manager.call("_set_active_unit", attacker)
	watcher.stats.current_hp = 1
	var watcher_sp_before := watcher.stats.current_supply_points
	service._combat_rng.seed = _seed_for_hit(100)
	var attack := await service.submit_attack(service.make_attack_request(attacker, watcher, TacticalActionRequest.Source.AI), true)
	check(attack != null and attack.target_defeated, "The initiating attack defeats the watcher before retaliation eligibility is checked")
	check(attack != null and attack.reaction_events.is_empty(), "A watcher defeated by the initiating attack cannot retaliate")
	check(watcher.stats.current_supply_points == watcher_sp_before and not watcher.tactical_state.is_overwatching, "A defeated watcher spends no SP and clears its unused reaction state")
	level.queue_free()
	await process_frame
	await process_frame

func _check_player_overwatch_hands_off_turn_and_draws_range() -> void:
	var level := await _create_battle(1)
	var controller := level.battle_controller
	var watcher: TacticalUnit = level.turn_manager.player_units[0]
	_clear_shot_geometry(level)
	watcher.attack_range = 100
	# Keep the enemy phase under manual debug control so this test observes the
	# handoff without racing the asynchronous AI activation.
	controller.set_debug_enemy_control(true)
	var ap_before := watcher.stats.current_ap
	controller.toggle_overwatch_mode()
	var range_visualizer := level.get_node("Visualizers/OverwatchRangeVisualizer") as OverwatchRangeVisualizer
	check(controller.is_overwatch_mode_active and watcher.stats.current_ap == ap_before, "First Overwatch press previews without committing or spending AP")
	check(range_visualizer != null and range_visualizer.displayed_cells == controller.call("_legal_shot_cells", watcher), "Overwatch preview reuses the exact Attack range and line-of-sight cells")
	check(range_visualizer != null and not range_visualizer.preview_cells.is_empty() and range_visualizer.committed_cells.is_empty(), "Pending Guard coverage uses the bright preview layer")
	check(await controller.try_overwatch(watcher), "Player can register Overwatch through the ordinary controller entry point")
	check(not controller.is_overwatch_mode_active, "Confirming Overwatch leaves preview mode")
	check(level.turn_manager.current_phase == TurnManager.TurnPhase.ENEMY_TURN, "Final-unit Overwatch hands control to the enemy phase instead of waiting at zero AP")
	check(range_visualizer != null and not range_visualizer.displayed_cells.is_empty(), "Active friendly Overwatch draws a visible guarded range")
	check(range_visualizer != null and range_visualizer.preview_cells.is_empty() and not range_visualizer.committed_cells.is_empty(), "Confirmed Guard coverage switches to the darker committed layer")
	watcher.tactical_state.clear_overwatch()
	controller.call("_refresh_overwatch_range")
	check(range_visualizer.displayed_cells.is_empty(), "Guard range clears when the reservation is removed")
	level.queue_free()
	await process_frame

func _check_ai_acts_after_player_overwatch() -> void:
	var level := await _create_battle(1)
	var controller := level.battle_controller
	var watcher: TacticalUnit = level.turn_manager.player_units[0]
	_clear_shot_geometry(level)
	watcher.attack_range = 100
	var transaction_before := controller.action_service.last_transaction_id
	check(await controller.try_overwatch(watcher), "AI handoff fixture registers player Overwatch")
	var deadline := Time.get_ticks_msec() + 4000
	while controller.action_service.last_transaction_id <= transaction_before + 1 \
	and level.turn_manager.battle_result == TurnManager.BattleResult.ONGOING \
	and Time.get_ticks_msec() < deadline:
		await process_frame
	check(controller.action_service.last_transaction_id > transaction_before + 1 \
		or level.turn_manager.battle_result != TurnManager.BattleResult.ONGOING,
		"Enemy AI performs an authoritative action after player Overwatch hands off the phase")
	while controller.action_service.is_busy and Time.get_ticks_msec() < deadline:
		await process_frame
	var feedback = level.get_node("Visualizers/ShotResultFeedback")
	check(feedback.last_result_text in ["HIT", "MISS"], "Overwatch reaction uses the ordinary visible Attack hit/miss feedback")
	level.queue_free()
	await process_frame

func _check_hypothetical_occupancy() -> void:
	var pathfinder := Pathfinder.new()
	for x in 3: pathfinder.add_walkable_cell(Vector3i(x, 0, 0), Vector3(x, 0, 0))
	var grid := GridManager.new()
	var actor := TacticalUnit.new()
	var blocker := TacticalUnit.new()
	grid.occupancy_map[Vector3i(1, 0, 0)] = actor
	var before := grid.occupancy_map.duplicate()
	var path := pathfinder.calculate_path_with_occupancy(Vector3i(2, 0, 0), Vector3i(0, 0, 0), grid, actor)
	check(path.size() == 3 and grid.occupancy_map == before, "Hypothetical path treats the planning actor's origin as vacated without mutation")
	grid.occupancy_map[Vector3i(1, 0, 0)] = blocker
	check(pathfinder.calculate_path_with_occupancy(Vector3i(2, 0, 0), Vector3i(0, 0, 0), grid, actor).is_empty(), "Other actors still block hypothetical paths")
	actor.free()
	blocker.free()
	grid.free()
	var state := TacticalState.new()
	state.begin_activation(1, 0)
	state.establish_overwatch()
	check(not state.begin_activation(1, 0) and state.is_overwatching, "Reselecting within one activation preserves Overwatch")
	state.begin_activation(2, 0)
	check(not state.is_overwatching, "Unused Overwatch expires at the next activation")
	state.free()

func _destination_with_path(service: TacticalActionService, mover: TacticalUnit, destinations: Array[Vector3i]) -> Vector3i:
	for cell in destinations:
		var query := service.query_move(mover.tactical_id, cell)
		if query.is_legal() and query.path_cells.size() >= 3: return cell
	return destinations[0] if not destinations.is_empty() else Vector3i(-1, -1, -1)

func _seed_for_hit(chance: int) -> int:
	for seed in range(1000):
		var candidate := RandomNumberGenerator.new()
		candidate.seed = seed
		if candidate.randf() * 100.0 < chance: return seed
	return 0

func _clear_shot_geometry(level: BattleLevel) -> void:
	for data: MapCellData in level.battle_controller.grid_manager.map_data.cells.values():
		data.cover_type = MapCellData.CoverType.NONE
		data.cover_height = 0.0
		data.blocks_line_of_sight = false
	level.battle_controller.grid_manager.map_data.rebuild_los_index()

func _create_battle(player_count: int) -> BattleLevel:
	var config := BattleConfiguration.new()
	config.player_count = player_count
	config.enemy_count = 1
	config.battle_seed = 11505 + player_count
	config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, 1, false)
	var level := BATTLE_SCENE.instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	while level.turn_manager.current_round == 0: await process_frame
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	return level
