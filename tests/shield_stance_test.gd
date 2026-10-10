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
	await _test_capability_action_and_combat()
	_test_arc_boundary()
	_test_compatibility()
	print("Shield stance: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _test_capability_action_and_combat() -> void:
	var config := BattleConfiguration.new()
	config.player_count = 1
	config.enemy_count = 1
	config.player_archetypes = [&"shieldbearer"]
	config.enemy_archetypes = [&"generic"]
	config.battle_seed = 6114
	config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, 1, false)
	var level := BATTLE_SCENE.instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	while level.turn_manager.current_round == 0: await process_frame
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	var threat: TacticalUnit = level.turn_manager.enemy_units[0]
	var service := level.battle_controller.action_service
	_prepare_adjacent(level, actor, threat)
	check(actor.shield_capability != null and threat.shield_capability == null, "Only Shieldbearer receives the Inspector-authored capability")
	check(not service.query_shield(threat.tactical_id, actor.tactical_id).is_legal(), "A unit without the capability cannot activate Shield Stance")
	var rng_before := service.get_combat_rng_state()
	var inventory := service.query_shield(actor.tactical_id)
	var query := service.query_shield(actor.tactical_id, threat.tactical_id)
	check(inventory.is_legal() and inventory.has_legal_threats(), "Targetless Shield query exposes legal hostile choices")
	check(query.is_legal() and query.cost.ap == 1 and query.actor_ap_after == 1, "Shield query exposes its one-AP cost")
	check(is_equal_approx(query.protected_arc_degrees, 120.0) and query.accuracy_modifier == -20 and is_equal_approx(query.damage_multiplier, 0.35), "Shield query exposes capability tuning")
	check(service.get_combat_rng_state() == rng_before and service.state_revision == 0, "Shield queries consume no RNG or revision")
	service.call("_set_busy", true)
	check(service.query_shield(actor.tactical_id, threat.tactical_id).validation.code == &"action_busy", "Shield query rejects while the service is busy")
	service.call("_set_busy", false)
	actor.stats.current_ap = 0
	check(service.query_shield(actor.tactical_id, threat.tactical_id).validation.code == &"insufficient_ap", "Shield query rejects insufficient AP")
	actor.stats.current_ap = 2
	var stale := service.make_shield_request(actor, threat, TacticalActionRequest.Source.PLAYER)
	stale.expected_revision = -1
	check(await service.submit_shield(stale, true) == null and actor.stats.current_ap == 2, "Stale Shield request spends no AP")
	var result := await service.submit_shield(service.make_shield_request(actor, threat, TacticalActionRequest.Source.PLAYER), true)
	check(result != null and result.actor_ap_before == 2 and result.actor_ap_after == 1, "Shield Stance consumes exactly one AP")
	check(actor.tactical_state.is_shielding and service.state_revision == 1 and result.transaction_id == 1, "Shield Stance commits one state transition")
	check(service.get_combat_rng_state() == rng_before, "Shield activation consumes no combat RNG")
	check(service.query_attack(actor.tactical_id, threat.tactical_id).validation.code == &"shield_stance_restriction", "Shield Stance prevents Attack")
	actor.stats.current_supply_points = 3
	check(service.query_reload(actor.tactical_id).validation.code == &"shield_stance_restriction", "Shield Stance prevents Reload")
	check(service.query_shield(actor.tactical_id, threat.tactical_id).validation.code == &"already_shielding", "Duplicate Shield Stance is rejected")
	actor.tactical_state.begin_activation(level.turn_manager.current_round, int(level.turn_manager.current_phase))
	check(actor.tactical_state.is_shielding, "Re-selection in the same activation preserves Shield Stance")
	var incoming := service.query_attack(threat.tactical_id, actor.tactical_id)
	check(incoming.shield_applied and incoming.shield_accuracy_modifier == -20, "Incoming attack inside the arc receives the accuracy penalty")
	check(incoming.damage_on_hit == 9 and is_equal_approx(incoming.shield_damage_multiplier, 0.35), "Incoming shield damage rounds 25 x 0.35 to 9")
	var grid := level.battle_controller.grid_manager
	var actor_cell := grid.get_unit_grid(actor)
	var cover_cell := actor_cell + Vector3i.RIGHT
	var cover_data := grid.get_cell_data(cover_cell)
	var previous_cover := cover_data.cover_type
	cover_data.cover_type = MapCellData.CoverType.LOW
	var combined := service.query_attack(threat.tactical_id, actor.tactical_id)
	check(combined.shield_applied and combined.cover_type == MapCellData.CoverType.LOW and combined.hit_chance == 30, "Half cover and shield remain separately inspectable and combine to 30 percent")
	cover_data.cover_type = MapCellData.CoverType.FULL
	var combined_full := service.query_attack(threat.tactical_id, actor.tactical_id)
	check(combined_full.shield_applied and combined_full.cover_type == MapCellData.CoverType.FULL and combined_full.hit_chance == 30, "Full environmental cover and shield remain separately inspectable")
	cover_data.cover_type = previous_cover
	level.turn_manager.current_phase = TurnManager.TurnPhase.ENEMY_TURN
	level.turn_manager.active_unit = threat
	threat.stats.current_ap = 2
	threat.stats.current_supply_points = 4
	service.set("_combat_rng", _rng_for_outcome(incoming.hit_chance, true))
	var hp_before := actor.stats.current_hp
	var hit := await service.submit_attack(service.make_attack_request(threat, actor, TacticalActionRequest.Source.AI), true)
	check(hit != null and hit.did_hit and hit.damage == 9 and actor.stats.current_hp == hp_before - 9, "Committed attack inside the arc applies rounded shield damage exactly once")
	threat.stats.current_ap = 2
	service.set("_combat_rng", _rng_for_outcome(incoming.hit_chance, false))
	hp_before = actor.stats.current_hp
	var miss := await service.submit_attack(service.make_attack_request(threat, actor, TacticalActionRequest.Source.AI), true)
	check(miss != null and not miss.did_hit and miss.damage == 0 and actor.stats.current_hp == hp_before, "Miss inside the arc applies no shielded damage")
	actor.tactical_state.shield_facing = -actor.tactical_state.shield_facing
	var rear := service.query_attack(threat.tactical_id, actor.tactical_id)
	check(not rear.shield_applied and rear.damage_on_hit == 25, "Attack outside the arc receives no shield protection")
	actor.tactical_state.shield_facing = result.facing
	actor.tactical_state.begin_activation(level.turn_manager.current_round + 1, int(level.turn_manager.current_phase))
	check(not actor.tactical_state.is_shielding, "Shield Stance expires at the next activation start")
	check(result.to_replay_record().schema_version == 5 and ReplayRecordTools.validate_action_record(result.to_replay_record().merged({"expected_state": "x", "record_index": 0}), 3).is_empty(), "Replay accepts the typed Shield payload")
	var recorder = level.get("_replay_recorder")
	var shield_record_count := 0
	for record in recorder.recording.actions if recorder else []:
		if record.get("kind", "") == "shield": shield_record_count += 1
	check(shield_record_count == 1, "Shield commit is recorded exactly once by the ordinary replay recorder")
	level.queue_free()
	await process_frame
	await process_frame

func _test_arc_boundary() -> void:
	var facing := Vector2.RIGHT
	var boundary := Vector2(cos(deg_to_rad(60.0)), sin(deg_to_rad(60.0)))
	var outside := Vector2(cos(deg_to_rad(60.1)), sin(deg_to_rad(60.1)))
	check(CombatRules.is_within_protected_arc(facing, facing, 120.0), "Front of shield is protected")
	check(CombatRules.is_within_protected_arc(facing, boundary, 120.0), "Exact 120-degree arc boundary is inclusive")
	check(not CombatRules.is_within_protected_arc(facing, outside, 120.0), "Direction beyond the arc boundary is unprotected")

func _test_compatibility() -> void:
	var legacy := BattleConfiguration.new()
	legacy.apply_replay({"player_count": 1, "enemy_count": 1, "supply_points_enabled": true, "aim_enabled": true})
	check(not legacy.shield_enabled, "Historical replay configuration retains pre-Shield semantics")
	check(BattleConfiguration.new().to_replay().shield_enabled, "New battles record Shield semantics explicitly")

func _rng_for_outcome(hit_chance: int, should_hit: bool) -> RandomNumberGenerator:
	for candidate_seed in range(10000):
		var candidate := RandomNumberGenerator.new()
		candidate.seed = candidate_seed
		var rolled_hit := candidate.randf() * 100.0 < float(hit_chance)
		if rolled_hit == should_hit:
			candidate.seed = candidate_seed
			return candidate
	return RandomNumberGenerator.new()

func _prepare_adjacent(level: BattleLevel, actor: TacticalUnit, threat: TacticalUnit) -> void:
	var grid := level.battle_controller.grid_manager
	var actor_cell := grid.get_unit_grid(actor)
	var old_threat_cell := grid.get_unit_grid(threat)
	var threat_cell := actor_cell + Vector3i.RIGHT
	var data := grid.get_cell_data(threat_cell)
	if data:
		data.cover_type = MapCellData.CoverType.NONE
		data.cover_height = 0.0
		data.blocks_line_of_sight = false
	grid.map_data.rebuild_los_index()
	threat.global_position = grid.grid_to_world(threat_cell) + Vector3.UP * threat.standing_height
	grid.update_unit_position(threat, old_threat_cell, threat_cell)
