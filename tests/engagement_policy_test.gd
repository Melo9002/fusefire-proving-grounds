extends "res://tests/contextual_battlefield_test.gd"

func _run() -> void:
	var level := await _depot(BattlefieldCatalog.CONTEXTUAL_DEPOT, 950507647)
	if not level.battle_initialization_succeeded:
		quit(1)
		return
	var battle := level.battle_controller
	var service := battle.action_service
	var grid := battle.grid_manager
	var alpha: TacticalUnit = level.turn_manager.player_units[0]
	var hostile: TacticalUnit = level.turn_manager.enemy_units[0]
	_place(alpha, Vector3i(17, 0, 15), grid)
	_place(hostile, Vector3i(22, 0, 22), grid)
	for policy in [0, 1, 2, 3]:
		grid.map_data.engagement_policy = policy
		var back := CombatRules.evaluate_attack(alpha, hostile, grid, null)
		var incoming := CombatRules.evaluate_attack(hostile, alpha, grid, null)
		check(not back.is_legal and back.reason == "Blocked", "Alpha keeps the genuine truck obstruction under policy %d" % policy)
		check(incoming.is_legal == (policy == 0), "Only Legacy allows the peripheral one-way truck shot in policy %d" % policy)
		if policy == 1: check(incoming.reason == CombatRules.INSUFFICIENT_EXPOSURE, "Head/core rejects peripheral exposure explicitly")
		if policy == 2: check(incoming.reason == CombatRules.NO_MUTUAL_LANE, "Symmetrical rejects the clear outbound ray without claiming a collision")
		var forecast := CombatRules.evaluate_attack_from_cell(hostile, hostile.grid_position, alpha, grid, null)
		check(forecast.is_legal == incoming.is_legal and forecast.reason == incoming.reason, "Hypothetical preview uses the same policy")

	_place(alpha, Vector3i(22, 0, 21), grid)
	for policy in [0, 1, 2, 3]:
		grid.map_data.engagement_policy = policy
		check(CombatRules.evaluate_attack(alpha, hostile, grid, null).is_legal
			and CombatRules.evaluate_attack(hostile, alpha, grid, null).is_legal, "Open bilateral shot remains available under policy %d" % policy)
	grid.map_data.engagement_policy = CombatRules.EngagementPolicy.SYMMETRIC
	var range_before := hostile.attack_range
	hostile.attack_range = 0
	check(CombatRules.evaluate_attack(alpha, hostile, grid, null).is_legal
		and not CombatRules.evaluate_attack(hostile, alpha, grid, null).is_legal, "Reciprocity excludes action range restrictions")
	hostile.attack_range = range_before
	var supply_before := hostile.stats.current_supply_points
	var ap_before := hostile.stats.current_ap
	hostile.stats.current_supply_points = 0
	hostile.stats.set_available_ap_for_setup(0)
	check(battle.query_attack(alpha, hostile).is_legal(), "Opponent AP and SP shortages cannot grant immunity")
	hostile.stats.current_supply_points = supply_before
	hostile.stats.set_available_ap_for_setup(ap_before)

	var alpha_faction := alpha.faction
	alpha.faction = hostile.faction
	hostile.faction = alpha_faction
	check(CombatRules.evaluate_attack(alpha, hostile, grid, null).is_legal
		and CombatRules.evaluate_attack(hostile, alpha, grid, null).is_legal, "Swapping factions preserves mutual physical geometry")
	hostile.faction = alpha.faction
	alpha.faction = alpha_faction

	var armed := await service.submit_overwatch(service.make_overwatch_request(alpha, TacticalActionRequest.Source.PLAYER), true)
	check(armed != null, "Reserve Guard against an otherwise valid mutual lane")
	if armed:
		var supply := alpha.stats.current_supply_points
		var normal := service.query_guard_reaction(alpha, hostile)
		check(normal.can_fire, "Guard A uses the shared physical lane")
		service.guard_minimum_chance = 100
		var hold := service.query_guard_reaction(alpha, hostile)
		check(not hold.can_fire and hold.get("held_fire", false) and hold.evaluation.is_legal,
			"Guard B can decline a legal sub-threshold reaction")
		check(alpha.stats.current_supply_points == supply and alpha.tactical_state.is_overwatching,
			"Holding fire leaves SP and the reaction reservation intact")
		level.turn_manager.current_phase = TurnManager.TurnPhase.ENEMY_TURN
		level.turn_manager.call("_set_active_unit", hostile)
		var expected_rng := RandomNumberGenerator.new()
		expected_rng.state = service.get_combat_rng_state()
		expected_rng.randf() # The initiating Attack's roll.
		var strike := await service.submit_attack(service.make_attack_request(hostile, alpha, TacticalActionRequest.Source.AI))
		check(strike != null and strike.reaction_events.is_empty() and strike.guard_checks.get(alpha.tactical_id, {}).get("held_fire", false),
			"Attack retaliation uses experimental quality without spending the reaction")
		check(alpha.stats.current_supply_points == supply and alpha.tactical_state.is_overwatching,
			"Committed enemy attack preserves the declined retaliation and SP")
		check(service.get_combat_rng_state() == expected_rng.state, "A declined retaliation draws no random roll")
	level.queue_free()
	await process_frame

	await _mutual_contextual()
	for mode in [1, 2, 3]:
		await _replay_policy(mode)
	print("Engagement policy: %d checks, %d failure(s)" % [checks, failures])
	quit(int(failures > 0))

func _mutual_contextual() -> void:
	var level := await _depot(BattlefieldCatalog.CONTEXTUAL_DEPOT, 16)
	if not level.battle_initialization_succeeded:
		level.queue_free()
		await process_frame
		return
	var battle := level.battle_controller
	var grid := battle.grid_manager
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	var enemy: TacticalUnit = level.turn_manager.enemy_units[0]
	_place(actor, Vector3i(23, 0, 15), grid)
	_place(enemy, Vector3i(30, 0, 15), grid)
	grid.map_data.engagement_policy = CombatRules.EngagementPolicy.SYMMETRIC
	var shot := CombatRules.evaluate_attack(actor, enemy, grid, null)
	var return_shot := CombatRules.evaluate_attack(enemy, actor, grid, null)
	check(shot.is_legal and shot.firing_solution.body_offset != Vector3.ZERO and return_shot.is_legal,
		"Reciprocal policy allows a certified contextual lane paired with a real return")
	grid.map_data.contextual_discovery_enabled = false
	shot = CombatRules.evaluate_attack(actor, enemy, grid, null)
	return_shot = CombatRules.evaluate_attack(enemy, actor, grid, null)
	check(not shot.is_legal and shot.reason == "Blocked" and not return_shot.is_legal and return_shot.reason == CombatRules.NO_MUTUAL_LANE,
		"Removing the certified posture closes both policy directions, preserving the actual blocker")
	level.queue_free()
	await process_frame

func _replay_policy(mode: int) -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.CONTEXTUAL_SHOWCASE)
	config.battle_seed = 16
	config.player_count = 1
	config.enemy_count = 1
	config.engagement_policy = mode
	config.guard_minimum_chance = 17
	config.contextual_firing_disabled = true
	config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, 1)
	var level := Scene.instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	check(level.battle_initialization_succeeded, "Set up replay with selected combat policy")
	if not level.battle_initialization_succeeded:
		level.queue_free()
		await process_frame
		return
	var battle := level.battle_controller
	var grid := battle.grid_manager
	var actor: TacticalUnit = level.turn_manager.player_units[0]
	var enemy: TacticalUnit = level.turn_manager.enemy_units[0]
	var fired := false
	var reached := battle.pathfinder.get_reachable_cells(actor.grid_position, actor.stats.speed)
	for cell in reached:
		var move := battle.query_move(actor, cell)
		if cell == actor.grid_position or not move.is_legal() or move.actor_ap_after < TacticalActionService.ATTACK_AP_COST:
			continue
		var forecast := CombatRules.evaluate_attack_from_cell(actor, cell, enemy, grid, null)
		if not forecast.is_legal: continue
		check(await battle.try_move(actor, cell), "Commit a real move under experimental replay settings")
		var live := battle.query_attack(actor, enemy)
		check(live.is_legal() and live.hit_chance == forecast.hit_chance, "Forecast matches the live attack after moving")
		fired = await battle.try_attack(actor, enemy)
		break
	check(fired, "Commit an experimental Attack for replay")
	var recording: BattleReplayRecording = level._replay_recorder.recording
	var path := "user://combat-policy-%d-%d.json" % [OS.get_process_id(), mode]
	var save_status := recording.save_json(path)
	check(recording.actions.size() > 0 and save_status == OK, "Serialize an actual experimental transaction (%s)" % error_string(save_status))
	var saved := BattleReplayRecording.load_json(path)
	check(saved.is_playable() and saved.configuration.engagement_policy == mode and saved.configuration.guard_minimum_chance == 17
		and saved.configuration.contextual_firing_disabled, "Experimental settings survive disk codec")
	level.queue_free()
	await process_frame
	DirAccess.remove_absolute(path)
	if not saved.is_playable(): return
	var playback := Scene.instantiate() as BattleLevel
	playback.configure_replay(saved)
	root.add_child(playback)
	var player := playback.get_node("BattleReplayPlayer") as BattleReplayPlayer
	player.set_playback_speed(4)
	var deadline := Time.get_ticks_msec() + 12000
	while not player.playback_complete and Time.get_ticks_msec() < deadline: await process_frame
	check(player.playback_succeeded and player.verified_actions == saved.actions.size(), "Experimental replay verifies authoritatively: " + player.last_divergence)
	playback.queue_free()
	await process_frame
