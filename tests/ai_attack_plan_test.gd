extends SceneTree
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _run() -> void:
	var tuning = CombatRules.cover_tuning
	CombatRules.cover_tuning = tuning.duplicate()
	var config := BattleConfiguration.new()
	config.player_count = 2
	config.enemy_count = 1
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.TACTICAL_TEST_RANGE)
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	await process_frame
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	var battle := level.battle_controller
	var grid := battle.grid_manager
	var actor := level.turn_manager.player_units[0]
	var enemy := level.turn_manager.enemy_units[0]
	for pair in [[actor, Vector3i(1, 0, 16)], [enemy, Vector3i(1, 0, 20)]]:
		var unit: TacticalUnit = pair[0]
		grid.update_unit_position(unit, unit.grid_position, pair[1])
		unit.global_position = grid.grid_to_world(pair[1]) + Vector3.UP * unit.standing_height
	actor.attack_range = 10
	enemy.attack_range = 10
	var ai := AIController.new()
	ai.unit = actor
	ai.turn_manager = level.turn_manager
	ai.battle_controller = battle
	level.add_child(ai)
	actor.stats.set_available_ap_for_setup(2)
	var rng := battle.action_service.get_combat_rng_state()
	CombatRules.cover_tuning.base_accuracy = 90
	check(battle.query_attack(actor, enemy).hit_chance == 90, "Controlled shot is 90 percent")
	check(not await ai._try_aim_for_attack(enemy), "Two useful shots outrank Aim plus one against healthy target")
	check(actor.stats.current_ap == 2 and not actor.tactical_state.is_aiming, "Declining Aim spends nothing")
	actor.stats.current_supply_points = 1
	check(await ai._try_aim_for_attack(enemy), "With one remaining shot, Aim's improvement is useful")
	check(actor.stats.current_ap == 1 and actor.tactical_state.is_aiming, "Chosen Aim commits its actual cost and state")
	check(battle.action_service.get_combat_rng_state() == rng, "Plan evaluation and Aim consume no combat rolls")
	var policy := AIDifficultyPolicy.create(AIDifficultyPolicy.Tier.NORMAL)
	var query := AttackQueryResult.new()
	query.hit_chance = 100
	query.damage_on_hit = 31
	query.expected_damage = 31
	enemy.stats.current_hp = 30
	var enhanced := AITargetScorer.evaluate(actor, enemy, [], MissionIntent.new(), null, grid, policy, null, query)
	query.damage_on_hit = 9
	query.expected_damage = 9
	var shielded := AITargetScorer.evaluate(actor, enemy, [], MissionIntent.new(), null, grid, policy, null, query)
	check(enhanced.vulnerability > shielded.vulnerability and enhanced.damage_value > shielded.damage_value, "Finishers follow edited damage and shield-reduced on-hit damage")
	query.hit_chance = 10
	query.expected_damage = 0.9
	var unlikely := AITargetScorer.evaluate(actor, enemy, [], MissionIntent.new(), null, grid, policy, null, query)
	check(unlikely.total < shielded.total, "Otherwise equal target score values actual chance")
	check(policy.score_target(70, 30, 0, 31) > policy.score_target(70, 30, 0, 9), "Legacy policy helper also accepts actual predicted damage")
	check(AITargetScorer.shot_sequence_value([100], 9, 20, 20) == 9, "Shielded hit is not a false finishing kill")
	check(AITargetScorer.shot_sequence_value([100], 25, 20, 20) == 40, "Damage value caps overkill and adds actual kill value")
	check(AITargetScorer.shot_sequence_value([95], 25, 100, 20) < AITargetScorer.shot_sequence_value([60, 60], 25, 100, 20), "Sequence comparison counts the second unaimed attack")
	var second := level.turn_manager.player_units[1]
	grid.update_unit_position(second, second.grid_position, Vector3i(1, 0, 21))
	second.global_position = grid.grid_to_world(second.grid_position) + Vector3.UP * second.standing_height
	ai.unit = enemy
	check(ai._nearest_vip_escort() == second, "VIP escort selection uses distance rather than roster order")
	CombatRules.cover_tuning = tuning
	level.queue_free()
	await process_frame
	print("AI attack plans: %d failures" % failures)
	quit(1 if failures else 0)
