extends "res://docs/quality/evidence/contextual-04/replay_audit.gd"
## Inspect counterfactuals synchronously at verified historical checkpoints.

func _capture(index: int, _total: int) -> void:
	var battle := level.battle_controller
	var service := battle.action_service
	var revision := service.state_revision
	if revision not in [22, 23, 28, 35, 36, 55, 56, 64, 66, 67, 70, 72, 73, 74, 80]: return
	var grid := battle.grid_manager
	var data := grid.map_data
	var rows := []
	var original := data.engagement_policy
	for actor in level.turn_manager.player_units:
		if not is_instance_valid(actor) or actor.stats.is_defeated: continue
		for enemy in level.turn_manager.enemy_units:
			if not is_instance_valid(enemy) or enemy.stats.is_defeated: continue
			rows.append(_compare_pair(actor, enemy, grid))
	data.engagement_policy = original
	print("[PolicyReplay] ", JSON.stringify({"revision": revision, "index": index, "contextual": data.contextual_discovery_enabled, "pairs": rows}))
	if revision != 22 or recording.configuration.seed != 407140976: return
	var watcher := service.actor_registry.resolve(&"PlayerUnit2")
	var mover := service.actor_registry.resolve(&"EnemyUnit1")
	var path: Array = recording.actions[index].resolved.path
	var guard_rows := []
	for point in path.slice(1):
		var cell := Vector3i(point[0], point[1], point[2])
		var normal := service.query_guard_reaction(watcher, mover, cell)
		service.guard_minimum_chance = 15
		var experimental := service.query_guard_reaction(watcher, mover, cell)
		service.guard_minimum_chance = 0
		guard_rows.append({"cell": str(cell), "legal": normal.can_fire, "guard_b": experimental.can_fire, "reason_b": experimental.reason,
			"chance": normal.evaluation.hit_chance if normal.has("evaluation") else 0})
	print("[PolicyGuard] ", JSON.stringify(guard_rows))

func _compare_pair(actor: TacticalUnit, enemy: TacticalUnit, grid: GridManager) -> Dictionary:
	var policies := []
	for policy in [0, 1, 2, 3]:
		grid.map_data.engagement_policy = policy
		policies.append([_shot(actor, enemy, grid), _shot(enemy, actor, grid)])
	return {"actor": actor.tactical_id, "enemy": enemy.tactical_id, "source": str(actor.grid_position), "target": str(enemy.grid_position), "policies": policies}

func _shot(actor: TacticalUnit, target: TacticalUnit, grid: GridManager) -> Dictionary:
	var aim: int = CombatRules.cover_tuning.aim_accuracy_bonus if actor.tactical_state and actor.tactical_state.is_aiming else 0
	var evaluation := CombatRules.evaluate_attack(actor, target, grid, null, aim)
	var solution := evaluation.firing_solution
	var source := grid.get_unit_grid(actor)
	var destination := grid.get_unit_grid(target)
	var direct := CombatRules._evaluate_target_visibility_cells(actor, source, target, destination, grid)
	var central_points: Array[Vector3] = [CombatRules.get_support_position(destination, grid) + Vector3.UP * target.standing_height * 1.2,
		CombatRules.get_support_position(destination, grid) + Vector3.UP * target.standing_height * 1.75]
	var origin := CombatRules.get_support_position(source, grid) + Vector3.UP * actor.standing_height
	var ignore: Array[Vector3i] = [source, destination]
	var near_counts := []
	for offset in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var shifted: Vector3 = origin + offset * 0.01
		var count := 0
		for point in central_points:
			count += int(not CombatRules._get_geometry_between(shifted, point, grid, false, ignore, false))
		near_counts.append(count)
	return {"legal": evaluation.is_legal, "reason": evaluation.reason, "chance": evaluation.hit_chance,
		"cover": evaluation.cover_type, "samples": solution.target_samples.size() if solution else 0,
		"direct_samples": direct.visible_count, "direct_central": direct.central_visible, "central_1cm_origin_sensitivity": near_counts,
		"step": str(solution.body_offset) if solution else "", "ap": actor.stats.current_ap, "sp": actor.stats.current_supply_points}
