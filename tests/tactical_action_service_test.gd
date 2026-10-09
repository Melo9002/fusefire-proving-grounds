extends SceneTree

const BATTLE_SCENE := preload("res://levels/prototype_map/prototype_map.tscn")

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await _check_move_and_wait_pipeline()
	var first := await _create_battle()
	var first_setup := _prepare_attack(first)
	var service: TacticalActionService = first.battle_controller.action_service
	var attacker: TacticalUnit = first_setup.attacker
	var target: TacticalUnit = first_setup.target
	var stable_ids := service.actor_registry.get_ids()
	_check(stable_ids == [&"EnemyUnit1", &"PlayerUnit1"], "Battle actors receive deterministic stable IDs")

	var rng_before := service.get_combat_rng_state()
	var query := first.battle_controller.query_attack(attacker, target)
	_check(query.is_legal() and query.state_revision == 0, "Attack query returns a revision-stamped legal preview")
	_check(service.get_combat_rng_state() == rng_before, "Attack query does not consume combat RNG")
	var stale := service.make_attack_request(attacker, target, TacticalActionRequest.Source.PLAYER)
	stale.expected_revision = -1
	var stale_result := await service.submit_attack(stale, true)
	_check(stale_result == null and service.last_rejection.code == &"stale_revision", "Stale request is rejected explicitly")
	_check(service.get_combat_rng_state() == rng_before, "Rejected request does not consume combat RNG")

	var commits := [0]
	var reentrant_codes: Array[StringName] = []
	service.action_committed.connect(func(_result): commits[0] += 1)
	service.action_committed.connect(func(_result):
		var nested := service.make_simple_request(&"wait", attacker, TacticalActionRequest.Source.SYSTEM)
		Callable(service, "submit_simple").call(nested, true)
		reentrant_codes.append(service.last_rejection.code)
	, CONNECT_ONE_SHOT)
	var request := service.make_attack_request(attacker, target, TacticalActionRequest.Source.PLAYER)
	var result := await service.submit_attack(request, true)
	_check(result != null and result.presentation_suppressed and result.presentation_completed, "Suppressed presentation still completes the action lifecycle")
	_check(commits[0] == 1 and service.state_revision == 1 and result.transaction_id == 1, "Attack commits exactly once with one revision and transaction")
	_check(reentrant_codes == [&"action_busy"], "Synchronous commit observers cannot submit a reentrant action")
	_check(result.did_hit and result.target_defeated, "Deterministic attack fixture resolves hit and defeat")
	_check(first.turn_manager.enemy_units.is_empty(), "Defeat consequence removes target from the roster")
	_check(first.objective_manager.get_objective(&"eliminate").progress == 1, "Defeat consequence advances the objective once")
	var hp_after := result.target_hp_after
	var second_submit := await service.submit_attack(request, true)
	_check(second_submit == null and service.last_rejection.code == &"stale_revision", "Submitting the same request cannot double commit")
	_check(result.target_hp_after == hp_after and commits[0] == 1, "Rejected duplicate creates no second damage or commit")
	var first_roll := result.roll
	var first_fingerprint := BattleStateFingerprint.capture(first.turn_manager, first.battle_controller.grid_manager, first.objective_manager)
	first.queue_free()
	await process_frame
	await process_frame

	var second := await _create_battle()
	var second_setup := _prepare_attack(second)
	var second_service: TacticalActionService = second.battle_controller.action_service
	_check(second_service.actor_registry.get_ids() == stable_ids, "Stable IDs survive deterministic battle reconstruction")
	var second_result := await second_service.submit_attack(
		second_service.make_attack_request(second_setup.attacker, second_setup.target, TacticalActionRequest.Source.AI), true
	)
	_check(second_result != null and is_equal_approx(second_result.roll, first_roll), "Same battle seed produces the same combat roll")
	var second_fingerprint := BattleStateFingerprint.capture(second.turn_manager, second.battle_controller.grid_manager, second.objective_manager)
	_check(second_fingerprint == first_fingerprint, "Repeated suppressed execution produces the same authoritative outcome")
	second.queue_free()
	await process_frame
	await process_frame

	var presented := await _create_battle()
	presented.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	var presented_setup := _prepare_attack(presented)
	var presented_service: TacticalActionService = presented.battle_controller.action_service
	var presented_result := await presented_service.submit_attack(
		presented_service.make_attack_request(presented_setup.attacker, presented_setup.target, TacticalActionRequest.Source.PLAYER), false
	)
	var presented_fingerprint := BattleStateFingerprint.capture(presented.turn_manager, presented.battle_controller.grid_manager, presented.objective_manager)
	_check(presented_result != null and presented_result.presentation_completed, "Normal result-driven presentation completes")
	_check(presented_fingerprint == first_fingerprint, "Normal and suppressed presentation have identical authoritative outcomes")
	presented.queue_free()
	await process_frame

	print("Tactical action service: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _check_move_and_wait_pipeline() -> void:
	var level := await _create_battle()
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	var service: TacticalActionService = level.battle_controller.action_service
	var grid := level.battle_controller.grid_manager
	var start := grid.get_unit_grid(actor)
	var destination := Vector3i(-1, -1, -1)
	for candidate: Vector3i in level.battle_controller.pathfinder.get_reachable_cells(start, actor.stats.speed):
		if candidate != start and grid.can_unit_occupy_cell(actor, candidate):
			destination = candidate
			break
	_check(destination.x >= 0, "Movement fixture finds a legal destination")
	var query := service.query_move(actor.tactical_id, destination)
	_check(query.is_legal() and query.state_revision == 0, "Move query is read-only and revision stamped")
	var stale := service.make_move_request(actor, destination, TacticalActionRequest.Source.PLAYER)
	stale.expected_revision = -1
	_check(await service.submit_move(stale, true) == null and service.last_rejection.code == &"stale_revision", "Stale movement is rejected before occupancy changes")
	_check(grid.get_unit_at(start) == actor and grid.get_unit_at(destination) == null, "Rejected movement preserves occupancy")
	var move := await service.submit_move(service.make_move_request(actor, destination, TacticalActionRequest.Source.PLAYER), true)
	_check(move != null and grid.get_unit_at(start) == null and grid.get_unit_at(destination) == actor, "Move commits occupancy before suppressed presentation completes")
	_check(actor.stats.current_ap == 1 and service.state_revision == 1, "Move spends one AP and advances one shared revision")
	var duplicate := await service.submit_move(move.request, true)
	_check(duplicate == null and grid.get_unit_at(destination) == actor and actor.stats.current_ap == 1, "Duplicate Move cannot spend AP or move twice")
	var wait := await service.submit_simple(service.make_simple_request(&"wait", actor, TacticalActionRequest.Source.PLAYER), true)
	_check(wait != null and actor.stats.current_ap == 0 and service.state_revision == 2, "Wait exhausts AP and advances the shared revision")
	_check(wait.presentation_suppressed and wait.presentation_completed, "Suppressed Wait still completes its lifecycle")
	level.queue_free()
	await process_frame
	await process_frame

func _create_battle() -> BattleLevel:
	var level := BATTLE_SCENE.instantiate() as BattleLevel
	level.configure(
		1, 1, false, 1, 0, Vector2i(32, 24), false,
		MissionActor.VIPBehavior.PLAYER_CONTROLLED,
		MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, 1, false)
	)
	root.add_child(level)
	while level.turn_manager.current_round == 0:
		await process_frame
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	return level

func _prepare_attack(level: BattleLevel) -> Dictionary:
	var attacker := level.turn_manager.player_units[0]
	var target := level.turn_manager.enemy_units[0]
	var grid := level.battle_controller.grid_manager
	var attacker_cell := grid.get_unit_grid(attacker)
	var old_target_cell := grid.get_unit_grid(target)
	var target_cell := attacker_cell + Vector3i.RIGHT
	var target_data := grid.get_cell_data(target_cell)
	if target_data:
		target_data.cover_type = MapCellData.CoverType.NONE
		target_data.cover_height = 0.0
		target_data.blocks_line_of_sight = false
	grid.map_data.rebuild_los_index()
	target.global_position = grid.grid_to_world(target_cell) + Vector3.UP * target.standing_height
	grid.update_unit_position(target, old_target_cell, target_cell)
	target.stats.current_hp = 25
	return {"attacker": attacker, "target": target}

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
