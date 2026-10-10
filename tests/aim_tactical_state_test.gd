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
	await _test_aim_contract_and_attack()
	await _test_cancellation_and_activation()
	await _test_ai_and_hud()
	_test_compatibility_and_fingerprint()
	print("Aim and tactical state: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _test_aim_contract_and_attack() -> void:
	var level := await _create_battle()
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	var target: TacticalUnit = level.turn_manager.enemy_units[0]
	var service := level.battle_controller.action_service
	_prepare_attack(level, actor, target)
	var rng_before := service.get_combat_rng_state()
	var query := service.query_aim(actor.tactical_id)
	check(query.is_legal() and query.actor_ap_before == 2 and query.actor_ap_after == 1, "Aim query exposes its one-AP cost")
	check(not query.aiming_before and query.accuracy_bonus == 15, "Aim query exposes state and +15 bonus")
	check(service.get_combat_rng_state() == rng_before and service.state_revision == 0, "Aim query changes no RNG or revision")
	var stale := service.make_aim_request(actor, TacticalActionRequest.Source.PLAYER)
	stale.expected_revision = -1
	check(await service.submit_aim(stale, true) == null and service.last_rejection.code == &"stale_revision", "Stale Aim is rejected")
	var result := await service.submit_aim(service.make_aim_request(actor, TacticalActionRequest.Source.PLAYER), true)
	check(result != null and result.actor_ap_before == 2 and result.actor_ap_after == 1, "Aim consumes exactly one AP")
	check(result.aiming_after and actor.tactical_state.is_aiming and service.state_revision == 1 and result.transaction_id == 1, "Aim commits one state transition, revision, and transaction")
	check(actor.stats.current_supply_points == 4 and service.get_combat_rng_state() == rng_before, "Aim consumes no SP or RNG")
	check(service.query_aim(actor.tactical_id).validation.code == &"already_aiming", "Aimed actors cannot Aim repeatedly")
	var attack_query := service.query_attack(actor.tactical_id, target.tactical_id)
	check(attack_query.aim_applied and attack_query.hit_chance == mini(100, attack_query.base_hit_chance + 15), "Attack preview applies Aim before the final clamp")
	actor.stats.current_supply_points = 0
	var rejected := await service.submit_attack(service.make_attack_request(actor, target, TacticalActionRequest.Source.PLAYER), true)
	check(rejected == null and actor.tactical_state.is_aiming and actor.stats.current_supply_points == 0, "Rejected Attack preserves Aim and SP")
	actor.stats.current_supply_points = 1
	var attack := await service.submit_attack(service.make_attack_request(actor, target, TacticalActionRequest.Source.PLAYER), true)
	check(attack != null and attack.aim_applied and attack.aim_bonus == 15 and not actor.tactical_state.is_aiming, "Committed Attack consumes Aim on its seeded outcome")
	check(actor.stats.current_supply_points == 0 and attack.supply_points_cost == 1, "Aimed Attack consumes exactly one SP")
	check(attack.to_replay_record().schema_version == 4, "Aimed Attack uses the explicit payload schema extension")
	level.queue_free()
	await process_frame
	await process_frame

func _test_cancellation_and_activation() -> void:
	var level := await _create_battle()
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	var service := level.battle_controller.action_service
	await service.submit_aim(service.make_aim_request(actor, TacticalActionRequest.Source.PLAYER), true)
	actor.stats.current_supply_points = 1
	var stale_reload := service.make_reload_request(actor, TacticalActionRequest.Source.PLAYER)
	stale_reload.expected_revision = -1
	check(await service.submit_reload(stale_reload, true) == null and actor.tactical_state.is_aiming, "Rejected Reload preserves Aim")
	await service.submit_reload(service.make_reload_request(actor, TacticalActionRequest.Source.PLAYER), true)
	check(not actor.tactical_state.is_aiming, "Committed Reload cancels Aim")
	actor.stats.current_ap = 2
	actor.tactical_state.establish_aim()
	var illegal_move := service.make_move_request(actor, Vector3i(-99, -99, -99), TacticalActionRequest.Source.PLAYER)
	check(await service.submit_move(illegal_move, true) == null and actor.tactical_state.is_aiming, "Rejected Move preserves Aim")
	var move_inventory := service.query_move(actor.tactical_id)
	var destination: Vector3i = move_inventory.legal_destination_cells[0]
	if destination == level.battle_controller.grid_manager.get_unit_grid(actor) and move_inventory.legal_destination_cells.size() > 1:
		destination = move_inventory.legal_destination_cells[1]
	check(await service.submit_move(service.make_move_request(actor, destination, TacticalActionRequest.Source.PLAYER), true) != null and not actor.tactical_state.is_aiming, "Committed Move cancels Aim")
	actor.stats.current_ap = 1
	await service.submit_aim(service.make_aim_request(actor, TacticalActionRequest.Source.PLAYER), true)
	await process_frame
	check(actor.tactical_state.is_aiming, "Aim established with the final AP survives exhaustion")
	actor.tactical_state.begin_activation(level.turn_manager.current_round, int(level.turn_manager.current_phase))
	check(actor.tactical_state.is_aiming, "Re-selection in the same faction phase is not a new activation")
	actor.tactical_state.begin_activation(level.turn_manager.current_round + 1, int(level.turn_manager.current_phase))
	check(not actor.tactical_state.is_aiming, "Aim expires before the actor's next activation")
	actor.tactical_state.establish_aim()
	actor.stats.take_damage(actor.stats.max_hp)
	check(not actor.tactical_state.is_aiming, "Defeat clears tactical Aim state")
	level.queue_free()
	await process_frame
	await process_frame

func _test_ai_and_hud() -> void:
	var level := await _create_battle()
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	var target: TacticalUnit = level.turn_manager.enemy_units[0]
	_prepare_attack(level, actor, target)
	var actor_cell := level.battle_controller.grid_manager.get_cell_data(level.battle_controller.grid_manager.get_unit_grid(actor))
	actor_cell.cover_type = MapCellData.CoverType.FULL
	var ai := AIController.new()
	ai.unit = actor
	ai.turn_manager = level.turn_manager
	ai.battle_controller = level.battle_controller
	check(await ai.call("_try_aim_for_attack", target), "AI can submit Aim through the shared authoritative query")
	check(not await ai.call("_try_aim_for_attack", target), "AI does not Aim repeatedly")
	var hud := level.get_node("Visualizers/BattleUI/ActionHUDController") as ActionHUDController
	hud.call("_update_button_states")
	check(hud.tactical_state_label.text == "AIMED +15" and hud.aim_button.disabled, "HUD shows Aim state and disables repeated Aim")
	ai.free()
	level.queue_free()
	await process_frame
	await process_frame

func _test_compatibility_and_fingerprint() -> void:
	var legacy := BattleConfiguration.new()
	legacy.apply_replay({"player_count": 1, "enemy_count": 1, "supply_points_enabled": true})
	check(not legacy.aim_enabled, "Historical replay configuration retains pre-Aim semantics")
	check(BattleConfiguration.new().to_replay().aim_enabled, "New battles record Aim semantics explicitly")
	var valid := ReplayRecordTools.validate_action_record({
		"kind": "aim", "actor": "PlayerUnit1", "expected_state": "x", "record_index": 0,
		"schema_version": 4, "transaction_id": 1, "base_revision": 0, "committed_revision": 1,
		"request": TacticalActionRequest.simple(&"aim", &"PlayerUnit1", 0, TacticalActionRequest.Source.REPLAY).to_dictionary(),
		"resolved": {},
	}, 3)
	check(valid.is_empty(), "Replay schema accepts the versioned Aim payload")

func _create_battle() -> BattleLevel:
	var level := BATTLE_SCENE.instantiate() as BattleLevel
	level.configure(1, 1, false, 5502, 0, Vector2i(32, 24), false, MissionActor.VIPBehavior.PLAYER_CONTROLLED, MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, 1, false))
	root.add_child(level)
	while level.turn_manager.current_round == 0:
		await process_frame
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	return level

func _prepare_attack(level: BattleLevel, actor: TacticalUnit, target: TacticalUnit) -> void:
	var grid := level.battle_controller.grid_manager
	var actor_cell := grid.get_unit_grid(actor)
	var old_target_cell := grid.get_unit_grid(target)
	var target_cell := actor_cell + Vector3i.RIGHT
	var data := grid.get_cell_data(target_cell)
	if data:
		data.cover_type = MapCellData.CoverType.NONE
		data.cover_height = 0.0
		data.blocks_line_of_sight = false
	grid.map_data.rebuild_los_index()
	target.global_position = grid.grid_to_world(target_cell) + Vector3.UP * target.standing_height
	grid.update_unit_position(target, old_target_cell, target_cell)
