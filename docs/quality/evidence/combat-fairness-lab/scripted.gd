extends "res://tests/contextual_firing_bay_test.gd"
## Preview/commit consistency and tactical ordering on the existing calibrated bay.
## Analytic directional correctness lives in geometry.gd.

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if not args.is_empty() else ""
	for mode in 4:
		for seed_value in [1, 3]:
			for steps in [false, true]:
				await _attack_retreat(mode, seed_value, steps, out)
		for guard_threshold in [0, 15, 25]:
			await _guard_crossing(mode, guard_threshold)
	print("[ScriptedSummary] ", JSON.stringify({"check_count": checks, "failures": failures}))
	quit(int(failures > 0))

func _configured_bay(mode: int, seed_value: int, steps: bool, guard_threshold := 0) -> BattleLevel:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.CONTEXTUAL_BAY)
	config.battle_seed = seed_value
	config.player_count = 1
	config.enemy_count = 1
	config.engagement_policy = mode
	config.contextual_firing_disabled = not steps
	config.guard_minimum_chance = guard_threshold
	config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, 1)
	var level := Scene.instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	check(level.battle_initialization_succeeded, "Scripted bay initializes")
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	return level

func _attack_retreat(mode: int, seed_value: int, steps: bool, out: String) -> void:
	var level := _configured_bay(mode, seed_value, steps)
	var battle := level.battle_controller
	var service := battle.action_service
	var actor := level.turn_manager.player_units[0]
	var enemy := level.turn_manager.enemy_units[0]
	var grid := battle.grid_manager
	var origin := actor.grid_position
	var rng_state := service.get_combat_rng_state()
	var revision := service.state_revision
	var query := battle.query_attack(actor, enemy)
	var predicted: CombatRules.AttackEvaluation = query.evaluation
	var return_before := CombatRules.evaluate_attack(enemy, actor, grid, null)
	check(service.state_revision == revision and service.get_combat_rng_state() == rng_state, "Attack preview is read-only")
	var receipt := await service.submit_attack(service.make_attack_request(actor, enemy, TacticalActionRequest.Source.PLAYER), true)
	check((receipt != null) == query.is_legal(), "Authority agrees with unchanged preview")
	var retreat := {}
	if receipt:
		check(receipt.firing_solution.to_replay_record() == predicted.firing_solution.to_replay_record()
			and actor.grid_position == origin and receipt.actor_ap_after == receipt.actor_ap_before - 1,
			"Commit preserves forecast origin, canonical occupancy and ordinary AP cost")
		var move_inventory := service.query_move(actor.tactical_id)
		for candidate in move_inventory.legal_destination_cells:
			var incoming := CombatRules.evaluate_attack_after_move(enemy, actor, candidate, grid, null)
			if incoming.is_legal or incoming.reason == "Out of range": continue
			var outgoing := CombatRules.evaluate_attack_from_cell(actor, candidate, enemy, grid, null)
			var move := await service.submit_move(service.make_move_request(actor, candidate, TacticalActionRequest.Source.PLAYER), true)
			check(move != null and actor.grid_position == candidate, "An affordable safe destination can be committed")
			if move:
				var current := CombatRules.evaluate_attack(enemy, actor, grid, null)
				check(current.is_legal == incoming.is_legal and current.reason == incoming.reason, "Arrival forecast matches actual incoming lane")
				retreat = {"cell": str(candidate), "incoming": current.reason, "outgoing": outgoing.reason, "ap": move.actor_ap_after}
			break
	if not out.is_empty() and seed_value == 1 and steps and not retreat.is_empty():
		var file := out.path_join("bay-attack-retreat-mode-%d.json" % mode)
		check(level._replay_recorder.recording.save_json(file) == OK, "Preserve actionable matched witness")
	print("[ScriptedCase] ", JSON.stringify({"case":"fire_retreat","mode":mode,"seed":seed_value,"steps":steps,
		"attack":receipt != null,"why":query.reason,"return_before":return_before.is_legal,"retreat":retreat}))
	level.queue_free()
	await process_frame

func _guard_crossing(mode: int, threshold: int) -> void:
	var level := _configured_bay(mode, 1, true, threshold)
	var service := level.battle_controller.action_service
	var turns := level.turn_manager
	var watcher := turns.player_units[0]
	var mover := turns.enemy_units[0]
	var armed := await service.submit_overwatch(service.make_overwatch_request(watcher, TacticalActionRequest.Source.PLAYER), true)
	check(armed != null, "Guard reserves normally")
	# Existing battle fixture activation setup. These crossings are authority
	# checks, while the fire/retreat witnesses use a replayable normal activation.
	turns.current_phase = TurnManager.TurnPhase.ENEMY_TURN
	turns.active_unit = mover
	var rows := []
	var blocked_path := {}
	var crossing_path := {}
	for dest in service.query_move(mover.tactical_id).legal_destination_cells:
		var query := service.query_move(mover.tactical_id, dest)
		if not query.is_legal() or query.path_cells.size() < 2: continue
		var first := -1
		for index in range(1, query.path_cells.size()):
			var verdict := service.query_guard_reaction(watcher, mover, query.path_cells[index])
			if verdict.can_fire:
				first = index
				break
		if first < 0 and blocked_path.is_empty():
			blocked_path = {"cell":dest,"first":first,"path":query.path_cells}
		if first >= 0 and crossing_path.is_empty():
			crossing_path = {"cell":dest,"first":first,"path":query.path_cells}
		if not blocked_path.is_empty() and not crossing_path.is_empty(): break
	var selected := blocked_path if threshold == 25 and not blocked_path.is_empty() else crossing_path
	if selected.is_empty(): selected = blocked_path
	if not selected.is_empty() and armed:
		var sp := watcher.stats.current_supply_points
		var move := await service.submit_move(service.make_move_request(mover, selected.cell, TacticalActionRequest.Source.AI), true)
		var expected: bool = selected.first >= 0
		check(move != null and (move.reaction_events.size() == 1) == expected, "Move reactions agree with the first valid preview checkpoint")
		if move and not move.reaction_events.is_empty():
			check(move.reaction_events[0].checkpoint_index == selected.first and watcher.stats.current_supply_points == sp - 1
				and not watcher.tactical_state.is_overwatching, "Reaction consumes one SP and its reservation at the expected checkpoint")
		elif move:
			check(watcher.stats.current_supply_points == sp and watcher.tactical_state.is_overwatching, "Safe crossing preserves Guard")
		rows.append({"checkpoint":selected.first,"destination":str(selected.cell),"shots":move.reaction_events.size() if move else -1})
	print("[ScriptedCase] ", JSON.stringify({"case":"guard_crossing","mode":mode,"threshold":threshold,
		"crossing_available":not crossing_path.is_empty(),"outside_available":not blocked_path.is_empty(),"actual":rows}))
	level.queue_free()
	await process_frame
