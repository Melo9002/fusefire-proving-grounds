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
	await _test_attack_supply_contract()
	await _test_reload_contract()
	await _test_ai_reload_policy()
	await _test_historical_attack_semantics()
	await _test_presentation_and_hud()
	_test_legacy_configuration_policy()
	print("Supply Points and Reload: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _test_attack_supply_contract() -> void:
	var level := await _create_battle()
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	var target: TacticalUnit = level.turn_manager.enemy_units[0]
	var service := level.battle_controller.action_service
	_prepare_attack(level, actor, target)
	check(actor.stats.max_supply_points == 4 and actor.stats.current_supply_points == 4, "Combatants start with four Supply Points")
	var rng_before := service.get_combat_rng_state()
	var revision_before := service.state_revision
	var first_query := service.query_attack(actor.tactical_id, target.tactical_id)
	check(first_query.is_legal() and first_query.supply_points_before == 4 and first_query.supply_points_cost == 1 and first_query.supply_points_after == 3, "Attack query exposes its read-only SP prediction")
	check(service.get_combat_rng_state() == rng_before and service.state_revision == revision_before and actor.stats.current_supply_points == 4, "Attack query changes neither RNG, revision, nor SP")
	service._combat_rng.seed = _seed_for_outcome(first_query.hit_chance, true)
	var hit := await service.submit_attack(service.make_attack_request(actor, target, TacticalActionRequest.Source.PLAYER), true)
	check(hit != null and hit.did_hit and hit.supply_points_before == 4 and hit.supply_points_after == 3, "A committed hit consumes exactly one SP")
	actor.stats.current_ap = 1
	actor.stats.current_supply_points = 1
	target.stats.current_hp = target.stats.max_hp
	var actor_cell_data := level.battle_controller.grid_manager.get_cell_data(level.battle_controller.grid_manager.get_unit_grid(actor))
	actor_cell_data.cover_type = MapCellData.CoverType.FULL
	var miss_query := service.query_attack(actor.tactical_id, target.tactical_id)
	service._combat_rng.seed = _seed_for_outcome(miss_query.hit_chance, false)
	var miss := await service.submit_attack(service.make_attack_request(actor, target, TacticalActionRequest.Source.PLAYER), true)
	check(miss != null and not miss.did_hit and miss.supply_points_before == 1 and miss.supply_points_after == 0, "A committed miss consumes the final SP")
	actor.stats.current_ap = 1
	var exhausted_rng := service.get_combat_rng_state()
	var exhausted_revision := service.state_revision
	var exhausted := service.query_attack(actor.tactical_id, target.tactical_id)
	check(not exhausted.is_legal() and exhausted.validation.code == &"insufficient_supply_points", "Attack at zero SP has a stable rejection reason")
	check(await service.submit_attack(service.make_attack_request(actor, target, TacticalActionRequest.Source.PLAYER), true) == null, "Attack submission revalidates zero SP")
	check(actor.stats.current_supply_points == 0 and service.state_revision == exhausted_revision and service.get_combat_rng_state() == exhausted_rng, "Rejected zero-SP Attack changes no state or RNG")
	level.queue_free()
	await process_frame
	await process_frame

func _test_reload_contract() -> void:
	var level := await _create_battle()
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	var service := level.battle_controller.action_service
	var full := service.query_reload(actor.tactical_id)
	check(not full.is_legal() and full.validation.code == &"resource_full", "Reload rejects a full SP reserve")
	actor.stats.current_supply_points = 0
	var query := service.query_reload(actor.tactical_id)
	var rng_before := service.get_combat_rng_state()
	check(query.is_legal() and query.actor_ap_before == 2 and query.actor_ap_after == 1, "Reload query exposes its one-AP cost")
	check(query.supply_points_before == 0 and query.supply_points_after == 4 and query.supply_points_restored == 4, "Reload query predicts a full refill")
	var stale := service.make_reload_request(actor, TacticalActionRequest.Source.PLAYER)
	stale.expected_revision = -1
	check(await service.submit_reload(stale, true) == null and service.last_rejection.code == &"stale_revision", "Stale Reload is rejected")
	check(actor.stats.current_ap == 2 and actor.stats.current_supply_points == 0 and service.get_combat_rng_state() == rng_before, "Rejected Reload changes no AP, SP, or RNG")
	service._set_busy(true)
	check(not service.query_reload(actor.tactical_id).is_legal() and service.query_reload(actor.tactical_id).validation.code == &"action_busy", "Reload query respects the action barrier")
	service._set_busy(false)
	var commit_count := [0]
	var reentrant_code := [&""]
	service.action_committed.connect(func(_result): commit_count[0] += 1)
	service.action_committed.connect(func(_result):
		Callable(service, "submit_reload").call(service.make_reload_request(actor, TacticalActionRequest.Source.SYSTEM), true)
		reentrant_code[0] = service.last_rejection.code
	, CONNECT_ONE_SHOT)
	var request := service.make_reload_request(actor, TacticalActionRequest.Source.PLAYER)
	var result := await service.submit_reload(request, true)
	check(result != null and result.actor_ap_before == 2 and result.actor_ap_after == 1, "Reload spends exactly one AP")
	check(result.supply_points_before == 0 and result.supply_points_after == 4 and result.supply_points_restored == 4, "Reload restores SP to capacity")
	check(result.transaction_id == 1 and result.base_revision == 0 and result.committed_revision == 1 and commit_count[0] == 1, "Reload creates exactly one transaction, revision, and committed result")
	check(reentrant_code[0] == &"action_busy", "Reload rejects synchronous reentrant submission")
	check(service.get_combat_rng_state() == rng_before, "Successful Reload consumes no combat RNG")
	check(result.to_replay_record().schema_version == 3 and result.to_replay_record().kind == "reload", "Reload produces a versioned human-readable replay record")
	check(await service.submit_reload(request, true) == null and service.last_rejection.code == &"stale_revision", "Repeated Reload request cannot commit twice")
	actor.stats.current_supply_points = 1
	actor.stats.current_ap = 0
	check(service.query_reload(actor.tactical_id).validation.code == &"insufficient_ap", "Reload rejects insufficient AP")
	actor.stats.current_ap = 1
	actor.stats.is_defeated = true
	check(service.query_reload(actor.tactical_id).validation.code == &"actor_defeated", "Reload rejects defeated actors")
	level.queue_free()
	await process_frame
	await process_frame

func _test_presentation_and_hud() -> void:
	var suppressed := await _create_battle()
	var first: TacticalUnit = suppressed.turn_manager.player_units[0]
	first.stats.current_supply_points = 1
	var suppressed_result := await suppressed.battle_controller.action_service.submit_reload(
		suppressed.battle_controller.action_service.make_reload_request(first, TacticalActionRequest.Source.PLAYER), true)
	var suppressed_fingerprint := BattleStateFingerprint.capture(suppressed.turn_manager, suppressed.battle_controller.grid_manager, suppressed.objective_manager)
	check(suppressed_result.presentation_suppressed and suppressed_result.presentation_completed, "Suppressed Reload completes its lifecycle")
	suppressed.queue_free()
	await process_frame
	await process_frame

	var presented := await _create_battle()
	var second: TacticalUnit = presented.turn_manager.player_units[0]
	second.stats.current_supply_points = 1
	presented.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	var presented_result := await presented.battle_controller.action_service.submit_reload(
		presented.battle_controller.action_service.make_reload_request(second, TacticalActionRequest.Source.PLAYER), false)
	var presented_fingerprint := BattleStateFingerprint.capture(presented.turn_manager, presented.battle_controller.grid_manager, presented.objective_manager)
	check(presented_result.presentation_completed and presented_result.presentation_error.is_empty(), "Normal Reload presentation completes without owning gameplay state")
	check(presented_fingerprint == suppressed_fingerprint, "Presented and suppressed Reload produce identical authoritative state")
	var hud := presented.get_node("Visualizers/BattleUI/ActionHUDController") as ActionHUDController
	hud.call("_update_button_states")
	check(hud.supply_points_label.text == "SP 4/4" and hud.reload_button.disabled, "HUD shows SP and disables Reload while full")
	second.stats.current_supply_points = 0
	hud.call("_update_button_states")
	check(hud.supply_points_label.text == "SP 0/4" and hud.attack_button.disabled, "HUD exposes depleted SP and disables Attack")
	check(hud.attack_button.tooltip_text == "Not enough Supply Points", "HUD displays the authoritative Attack rejection")
	presented.queue_free()
	await process_frame
	await process_frame

func _test_ai_reload_policy() -> void:
	var level := await _create_battle()
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	var ai := AIController.new()
	ai.unit = actor
	ai.turn_manager = level.turn_manager
	ai.battle_controller = level.battle_controller
	actor.stats.current_supply_points = 0
	actor.stats.current_ap = 2
	check(await ai.call("_try_reload_if_useful"), "AI Reload policy submits the shared authoritative Reload when depleted")
	check(actor.stats.current_supply_points == 4 and actor.stats.current_ap == 1, "AI Reload receives the same committed SP and AP result as the player")
	check(not await ai.call("_try_reload_if_useful"), "AI never attempts Reload while SP is full")
	actor.stats.current_supply_points = 2
	check(not await ai.call("_try_reload_if_useful"), "Basic AI preserves a useful partial reserve instead of reloading repeatedly")
	ai.free()
	level.queue_free()
	await process_frame
	await process_frame

func _test_historical_attack_semantics() -> void:
	var level := await _create_battle()
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	var target: TacticalUnit = level.turn_manager.enemy_units[0]
	var service := level.battle_controller.action_service
	_prepare_attack(level, actor, target)
	service.supply_points_enabled = false
	actor.stats.current_supply_points = 0
	var legacy_query := service.query_attack(actor.tactical_id, target.tactical_id)
	check(legacy_query.is_legal(), "A historical replay can reproduce a pre-SP Attack with an empty runtime reserve")
	var request := service.make_attack_request(actor, target, TacticalActionRequest.Source.REPLAY)
	var result := await service.submit_attack(request, true)
	check(result != null and actor.stats.current_supply_points == 0, "Historical Attack playback preserves its original no-SP semantics")
	var recorded := result.to_replay_record()
	var changed := recorded.duplicate(true)
	changed.resolved.supply_points_after = 99
	check(ReplayRecordTools.compare_fields(recorded.resolved, changed.resolved).contains("supply_points_after"), "New replay diagnostics identify an SP result divergence by field")
	level.queue_free()
	await process_frame
	await process_frame

func _test_legacy_configuration_policy() -> void:
	var legacy := BattleConfiguration.new()
	legacy.apply_replay({"player_count": 1, "enemy_count": 1})
	check(not legacy.supply_points_enabled, "Historical replay configuration retains pre-SP semantics")
	var current := BattleConfiguration.new()
	check(current.to_replay().supply_points_enabled, "New battle configuration records SP semantics explicitly")

func _create_battle() -> BattleLevel:
	var level := BATTLE_SCENE.instantiate() as BattleLevel
	level.configure(1, 1, false, 4401, 0, Vector2i(32, 24), false, MissionActor.VIPBehavior.PLAYER_CONTROLLED, MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, 1, false))
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
	var target_data := grid.get_cell_data(target_cell)
	if target_data:
		target_data.cover_type = MapCellData.CoverType.NONE
		target_data.cover_height = 0.0
		target_data.blocks_line_of_sight = false
	grid.map_data.rebuild_los_index()
	target.global_position = grid.grid_to_world(target_cell) + Vector3.UP * target.standing_height
	grid.update_unit_position(target, old_target_cell, target_cell)
	target.stats.current_hp = target.stats.max_hp

func _seed_for_outcome(hit_chance: int, should_hit: bool) -> int:
	for candidate in 10000:
		var rng := RandomNumberGenerator.new()
		rng.seed = candidate
		if (rng.randf() * 100.0 < hit_chance) == should_hit:
			return candidate
	return 1
