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
	var revision_before := service.state_revision
	var ap_before := attacker.stats.current_ap
	var hp_before := target.stats.current_hp
	var state_before := BattleStateFingerprint.capture(first.turn_manager, first.battle_controller.grid_manager, first.objective_manager)
	var query := first.battle_controller.query_attack(attacker, target)
	_check(query.is_legal() and query.state_revision == 0, "Attack query returns a revision-stamped legal preview")
	_check(query.cost.ap == 1 and query.actor_ap_before == 2 and query.actor_ap_after == 1, "Attack prediction exposes authoritative AP cost and remaining AP")
	_check(query.damage_on_hit == 25 and query.minimum_damage == 0 and query.maximum_damage == 25, "Attack prediction exposes the current damage contract")
	_check(is_equal_approx(query.expected_damage, float(query.hit_chance) * 0.25), "Expected damage is derived from the authoritative hit chance")
	_check(query.distance <= attacker.attack_range and query.visibility_fraction > 0.0, "Attack prediction exposes range and visibility facts")
	var inventory := first.battle_controller.query_attack(attacker)
	var inventory_target := inventory.get_candidate(target.tactical_id)
	_check(inventory.is_legal() and inventory.has_legal_targets() and inventory.legal_target_ids.has(target.tactical_id), "Targetless query inventories legal targets")
	_check(inventory_target != null and inventory_target.hit_chance == query.hit_chance and inventory_target.expected_damage == query.expected_damage, "Inventory, UI-style hover, and AI-style candidate lookup agree")
	var action_hud := first.get_node("Visualizers/BattleUI/ActionHUDController") as ActionHUDController
	action_hud.call("_update_button_states")
	_check(not action_hud.attack_button.disabled and action_hud.attack_button.tooltip_text.is_empty(), "Player Attack availability consumes the shared legal-target inventory")
	var self_query := first.battle_controller.query_attack(attacker, attacker)
	_check(not self_query.is_legal() and self_query.validation.code == &"target_not_hostile", "Invalid target returns a structured eligibility reason")
	var missing_query := service.query_attack(attacker.tactical_id, &"missing-target")
	_check(not missing_query.is_legal() and missing_query.validation.code == &"target_missing", "Missing target is rejected without an unstructured failure")
	var missing_actor := service.query_attack(&"missing-actor", target.tactical_id)
	_check(not missing_actor.is_legal() and missing_actor.validation.code == &"actor_missing", "Missing actor is rejected through the shared contract")
	target.stats.current_hp = 0
	target.stats.is_defeated = true
	var defeated_target := first.battle_controller.query_attack(attacker, target)
	_check(not defeated_target.is_legal() and defeated_target.validation.code == &"unit_defeated", "Defeated target is ineligible through the shared contract")
	target.stats.current_hp = hp_before
	target.stats.is_defeated = false
	var repeated := first.battle_controller.query_attack(attacker, target)
	_check(repeated.hit_chance == query.hit_chance and repeated.cover_type == query.cover_type and repeated.obstruction == query.obstruction, "Repeated unchanged queries return equivalent predictions")
	_check(service.get_combat_rng_state() == rng_before, "Attack query does not consume combat RNG")
	_check(service.state_revision == revision_before and attacker.stats.current_ap == ap_before and target.stats.current_hp == hp_before, "Attack queries do not mutate revision, AP, or HP")
	_check(BattleStateFingerprint.capture(first.turn_manager, first.battle_controller.grid_manager, first.objective_manager) == state_before, "Attack queries leave the complete authoritative fingerprint unchanged")
	attacker.stats.current_ap = 0
	var no_ap := first.battle_controller.query_attack(attacker, target)
	_check(not no_ap.is_legal() and no_ap.validation.code == &"insufficient_ap", "Insufficient AP uses the shared structured validation")
	action_hud.call("_update_button_states")
	_check(action_hud.attack_button.disabled and action_hud.attack_button.tooltip_text == no_ap.reason, "Player Attack tooltip presents the shared rejection reason")
	attacker.stats.current_ap = ap_before
	action_hud.call("_update_button_states")
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
	_check(result.hit_chance == query.hit_chance, "Committed attack uses the same hit-chance rules as its prediction")
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
