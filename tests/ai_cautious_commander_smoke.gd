extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	await _check_legal_position_tradeoffs()
	await _check_required_objective_advance()
	print("AI cautious commander smoke: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _check_legal_position_tradeoffs() -> void:
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	var config := BattleConfiguration.new()
	config.player_count = 1
	config.enemy_count = 2
	config.battle_seed = 41321
	config.player_commander = AICommanderPolicy.Profile.CAUTIOUS
	level.configure_battle(config)
	root.add_child(level)
	await create_timer(0.2).timeout
	var battle := level.battle_controller
	var grid := battle.grid_manager
	var actor := level.turn_manager.player_units[0]
	var hostiles: Array[TacticalUnit] = level.turn_manager.enemy_units.duplicate()
	_relocate(grid, hostiles[0], Vector3i(8, 0, 8))
	_relocate(grid, hostiles[1], Vector3i(8, 0, 11))
	var query := battle.query_move(actor)
	check(query.is_legal() and query.legal_destination_cells.size() > 1, "Comparison uses authoritative legal movement destinations")
	var base := AIDifficultyPolicy.create(AIDifficultyPolicy.Tier.NORMAL)
	var cautious := AICommanderPolicy.create(AICommanderPolicy.Profile.CAUTIOUS).compose(base)
	var start := actor.grid_position
	var goal := hostiles[0].grid_position
	var context := SquadContext.new()
	var candidates: Array[Dictionary] = []
	for cell in query.legal_destination_cells:
		if cell == start: continue
		var progress := start.distance_to(goal) - cell.distance_to(goal)
		var ordinary := AIPositionScorer.evaluate(actor, cell, start, goal, progress, false, hostiles, grid, base, context)
		var protected := AIPositionScorer.evaluate(actor, cell, start, goal, progress, false, hostiles, grid, cautious, context)
		candidates.append({"cell": cell, "default": ordinary, "cautious": protected})
	check(not candidates.is_empty(), "Comparison found scored legal movement candidates")
	if candidates.is_empty():
		level.queue_free()
		return
	var exposed := candidates.filter(func(item: Dictionary): return item.default.exposure < 0.0)
	var covered := candidates.filter(func(item: Dictionary): return item.default.cover > 0.0)
	var crossfire := candidates.filter(func(item: Dictionary): return item.default.danger < 0.0)
	check(not exposed.is_empty() and exposed.all(func(item: Dictionary): return item.cautious.exposure < item.default.exposure), "Cautious penalizes incoming firing lanes more strongly")
	check(not covered.is_empty() and covered.all(func(item: Dictionary): return item.cautious.cover > item.default.cover), "Cautious values effective directional cover more strongly")
	check(not crossfire.is_empty() and crossfire.all(func(item: Dictionary): return item.cautious.danger < item.default.danger), "Cautious penalizes close or multiple-lane danger more strongly")
	var default_choice := _best(candidates, "default")
	var cautious_choice := _best(candidates, "cautious")
	var tradeoff := _find_preference_flip(candidates)
	check(not tradeoff.is_empty(), "Identical legal opportunities contain a Default/Cautious preference reversal")
	if not tradeoff.is_empty():
		var default_preference: Dictionary = tradeoff.default_preference
		var cautious_preference: Dictionary = tradeoff.cautious_preference
		check(default_preference.default.total > cautious_preference.default.total, "Default prefers the more offensive/progressive tradeoff")
		check(cautious_preference.cautious.total > default_preference.cautious.total, "Cautious selects the safer side of the same tradeoff")
		print("[CautiousTradeoff] Default prefers %s %.1f>%.1f; Cautious prefers %s %.1f>%.1f" % [
			default_preference.cell, default_preference.default.total, cautious_preference.default.total,
			cautious_preference.cell, cautious_preference.cautious.total, default_preference.cautious.total,
		])
	print("[CautiousComparison] Default %s %.1f; Cautious %s %.1f" % [default_choice.cell, default_choice.default.total, cautious_choice.cell, cautious_choice.cautious.total])
	level.queue_free()
	await process_frame

func _check_required_objective_advance() -> void:
	var previous_time_scale := Engine.time_scale
	Engine.time_scale = 8.0
	var simulator := AIMatchSimulator.new()
	root.add_child(simulator)
	var result := await simulator.run_match({
		"seed": 1,
		"mission_kind": MissionObjectiveDefinition.Kind.REACH,
		"player_count": 1,
		"enemy_count": 1,
		"generated_map": false,
		"difficulty": AIDifficultyPolicy.Tier.HARD,
		"player_commander": AICommanderPolicy.Profile.CAUTIOUS,
		"maximum_rounds": 12,
		"timeout_seconds": 20.0,
	})
	check(result.completed(), "Cautious completes a required advance instead of remaining passive")
	check(result.decision_records.any(func(record: Dictionary): return record.get("action", "") == "Move"), "Cautious makes objective-progress movement decisions")
	Engine.time_scale = previous_time_scale
	simulator.queue_free()
	await process_frame

func _best(candidates: Array[Dictionary], key: String) -> Dictionary:
	var result := candidates[0]
	for candidate in candidates.slice(1):
		if candidate[key].total > result[key].total:
			result = candidate
	return result

func _find_preference_flip(candidates: Array[Dictionary]) -> Dictionary:
	for first in candidates:
		for second in candidates:
			if first == second: continue
			if first.default.total <= second.default.total: continue
			if first.cautious.total >= second.cautious.total: continue
			var first_protection: float = first.default.cover + first.default.exposure + first.default.danger
			var second_protection: float = second.default.cover + second.default.exposure + second.default.danger
			if second_protection > first_protection:
				return {"default_preference": first, "cautious_preference": second}
	return {}

func _relocate(grid: GridManager, actor: TacticalUnit, destination: Vector3i) -> void:
	var origin := actor.grid_position
	grid.update_unit_position(actor, origin, destination)
	actor.global_position = grid.grid_to_world(destination) + Vector3.UP * actor.standing_height
