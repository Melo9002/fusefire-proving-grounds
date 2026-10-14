extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	await _check_legal_position_tradeoffs_and_risk_limit()
	await _check_finishing_preference()
	await _check_required_objective_pressure()
	await _check_same_seed_doctrine_comparison()
	print("AI aggressive commander smoke: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _check_legal_position_tradeoffs_and_risk_limit() -> void:
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	var config := BattleConfiguration.new()
	config.player_count = 1
	config.enemy_count = 3
	config.battle_seed = 41322
	config.player_commander = AICommanderPolicy.Profile.AGGRESSIVE
	level.configure_battle(config)
	root.add_child(level)
	await create_timer(0.2).timeout
	var battle := level.battle_controller
	var grid := battle.grid_manager
	var actor := level.turn_manager.player_units[0]
	var hostiles: Array[TacticalUnit] = level.turn_manager.enemy_units.duplicate()
	_relocate(grid, hostiles[0], Vector3i(8, 0, 8))
	_relocate(grid, hostiles[1], Vector3i(8, 0, 11))
	_relocate(grid, hostiles[2], Vector3i(7, 0, 6))
	var query := battle.query_move(actor)
	check(query.is_legal() and query.legal_destination_cells.size() > 1, "Aggressive comparison uses authoritative legal destinations")
	var base := AIDifficultyPolicy.create(AIDifficultyPolicy.Tier.NORMAL)
	var cautious := AICommanderPolicy.create(AICommanderPolicy.Profile.CAUTIOUS).compose(base)
	var aggressive := AICommanderPolicy.create(AICommanderPolicy.Profile.AGGRESSIVE).compose(base)
	var start := actor.grid_position
	var goal := hostiles[0].grid_position
	var context := SquadContext.new()
	var candidates: Array[Dictionary] = []
	for cell in query.legal_destination_cells:
		if cell == start: continue
		var progress := start.distance_to(goal) - cell.distance_to(goal)
		var ordinary := AIPositionScorer.evaluate(actor, cell, start, goal, progress, false, hostiles, grid, base, context)
		var protected := AIPositionScorer.evaluate(actor, cell, start, goal, progress, false, hostiles, grid, cautious, context)
		var pressing := AIPositionScorer.evaluate(actor, cell, start, goal, progress, false, hostiles, grid, aggressive, context)
		candidates.append({"cell": cell, "default": ordinary, "cautious": protected, "aggressive": pressing})
	check(not candidates.is_empty(), "Aggressive comparison found scored legal candidates")
	if candidates.is_empty():
		level.queue_free()
		return
	var tradeoff := _find_aggressive_preference_flip(candidates)
	check(not tradeoff.is_empty(), "Identical legal opportunities contain an Aggressive protection/offense preference reversal")
	if not tradeoff.is_empty():
		var safe: Dictionary = tradeoff.safe
		var offensive: Dictionary = tradeoff.offensive
		check(safe.cautious.total > offensive.cautious.total, "Cautious prefers the safer side of the tradeoff")
		check(offensive.aggressive.total > safe.aggressive.total, "Aggressive prefers the offensive side of the tradeoff")
		print("[AggressiveTradeoff] Cautious prefers %s %.1f>%.1f; Aggressive prefers %s %.1f>%.1f" % [
			safe.cell, safe.cautious.total, offensive.cautious.total,
			offensive.cell, offensive.aggressive.total, safe.aggressive.total,
		])
	var aggressive_choice := _best(candidates, "aggressive")
	var worst_protection := candidates[0]
	for candidate in candidates.slice(1):
		if _protection(candidate.default) < _protection(worst_protection.default):
			worst_protection = candidate
	check(aggressive_choice.cell != worst_protection.cell, "Aggressive rejects the disproportionately dangerous legal destination")
	check(aggressive_choice.aggressive.exposure < 0.0 or aggressive_choice.aggressive.danger < 0.0, "Aggressive may accept meaningful, calculated exposure")
	level.queue_free()
	await process_frame

func _check_finishing_preference() -> void:
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	var config := BattleConfiguration.new()
	config.player_count = 1
	config.enemy_count = 2
	config.battle_seed = 41323
	level.configure_battle(config)
	root.add_child(level)
	await create_timer(0.2).timeout
	var battle := level.battle_controller
	var grid := battle.grid_manager
	var actor := level.turn_manager.player_units[0]
	var targets: Array[TacticalUnit] = level.turn_manager.enemy_units.duplicate()
	_relocate(grid, targets[0], Vector3i(4, 0, 8))
	_relocate(grid, targets[1], Vector3i(4, 0, 10))
	targets[0].stats.current_hp = 25
	var inventory := battle.query_attack(actor)
	var wounded_query := inventory.get_candidate(targets[0].tactical_id)
	var healthy_query := inventory.get_candidate(targets[1].tactical_id)
	check(wounded_query != null and wounded_query.is_legal() and healthy_query != null and healthy_query.is_legal(), "Finishing comparison uses two authoritative legal attacks")
	var base := AIDifficultyPolicy.create(AIDifficultyPolicy.Tier.HARD)
	var aggressive := AICommanderPolicy.create(AICommanderPolicy.Profile.AGGRESSIVE).compose(base)
	var friendlies: Array[TacticalUnit] = [actor]
	var context := SquadContext.new()
	var default_wounded := AITargetScorer.evaluate(actor, targets[0], friendlies, null, null, grid, base, context, wounded_query)
	var default_healthy := AITargetScorer.evaluate(actor, targets[1], friendlies, null, null, grid, base, context, healthy_query)
	var aggressive_wounded := AITargetScorer.evaluate(actor, targets[0], friendlies, null, null, grid, aggressive, context, wounded_query)
	var aggressive_healthy := AITargetScorer.evaluate(actor, targets[1], friendlies, null, null, grid, aggressive, context, healthy_query)
	check(default_wounded.total > default_healthy.total, "Default recognizes a legal finishing opportunity")
	check(aggressive_wounded.total - aggressive_healthy.total > default_wounded.total - default_healthy.total, "Aggressive strengthens the finishing preference without changing legality")
	level.queue_free()
	await process_frame

func _check_required_objective_pressure() -> void:
	var previous_time_scale := Engine.time_scale
	Engine.time_scale = 8.0
	var simulator := AIMatchSimulator.new()
	root.add_child(simulator)
	var result := await simulator.run_match({
		"seed": 2,
		"mission_kind": MissionObjectiveDefinition.Kind.REACH,
		"player_count": 1,
		"enemy_count": 1,
		"generated_map": false,
		"difficulty": AIDifficultyPolicy.Tier.HARD,
		"player_commander": AICommanderPolicy.Profile.AGGRESSIVE,
		"enemy_commander": AICommanderPolicy.Profile.CAUTIOUS,
		"maximum_rounds": 12,
		"timeout_seconds": 20.0,
	})
	check(result.completed(), "Aggressive completes the required advance")
	check(result.decision_records.any(func(record: Dictionary): return record.get("action", "") == "Move"), "Aggressive makes objective-progress movement decisions")
	Engine.time_scale = previous_time_scale
	simulator.queue_free()
	await process_frame

func _check_same_seed_doctrine_comparison() -> void:
	var previous_time_scale := Engine.time_scale
	Engine.time_scale = 16.0
	var simulator := AIMatchSimulator.new()
	root.add_child(simulator)
	var matchups := [
		{"label": "Default/Default", "player": AICommanderPolicy.Profile.DEFAULT, "enemy": AICommanderPolicy.Profile.DEFAULT},
		{"label": "Cautious/Cautious", "player": AICommanderPolicy.Profile.CAUTIOUS, "enemy": AICommanderPolicy.Profile.CAUTIOUS},
		{"label": "Aggressive/Cautious", "player": AICommanderPolicy.Profile.AGGRESSIVE, "enemy": AICommanderPolicy.Profile.CAUTIOUS},
	]
	for matchup in matchups:
		var result := await simulator.run_match({
			"seed": 23231,
			"mission_kind": MissionObjectiveDefinition.Kind.ELIMINATE,
			"player_count": 2,
			"enemy_count": 2,
			"generated_map": false,
			"difficulty": AIDifficultyPolicy.Tier.HARD,
			"player_commander": matchup.player,
			"enemy_commander": matchup.enemy,
			"maximum_rounds": 20,
			"timeout_seconds": 20.0,
		})
		check(result.completed(), "%s same-seed comparison completes" % matchup.label)
		print("[DoctrineComparison] %s — %s — actions %s" % [matchup.label, result.summary(), _action_counts(result.decision_records)])
	Engine.time_scale = previous_time_scale
	simulator.queue_free()
	await process_frame

func _best(candidates: Array[Dictionary], key: String) -> Dictionary:
	var result := candidates[0]
	for candidate in candidates.slice(1):
		if candidate[key].total > result[key].total:
			result = candidate
	return result

func _find_aggressive_preference_flip(candidates: Array[Dictionary]) -> Dictionary:
	for safe in candidates:
		for offensive in candidates:
			if safe == offensive: continue
			if _protection(safe.default) <= _protection(offensive.default): continue
			var safe_offense: float = safe.default.progress + safe.default.firing
			var offensive_value: float = offensive.default.progress + offensive.default.firing
			if offensive_value <= safe_offense: continue
			if safe.cautious.total <= offensive.cautious.total: continue
			if offensive.aggressive.total <= safe.aggressive.total: continue
			return {"safe": safe, "offensive": offensive}
	return {}

func _protection(score: Dictionary) -> float:
	return score.cover + score.exposure + score.danger

func _action_counts(records: Array[Dictionary]) -> Dictionary:
	var counts := {}
	for record in records:
		var action := String(record.get("action", "Unknown"))
		counts[action] = int(counts.get(action, 0)) + 1
	return counts

func _relocate(grid: GridManager, actor: TacticalUnit, destination: Vector3i) -> void:
	var origin := actor.grid_position
	grid.update_unit_position(actor, origin, destination)
	actor.global_position = grid.grid_to_world(destination) + Vector3.UP * actor.standing_height
