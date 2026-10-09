class_name AITargetScorer
extends RefCounted

static func evaluate(
	attacker: TacticalUnit,
	target: TacticalUnit,
	friendlies: Array[TacticalUnit],
	intent: MissionIntent,
	objectives: ObjectiveManager,
	grid: GridManager,
	policy: AIDifficultyPolicy,
	squad: SquadContext,
	attack_prediction: AttackQueryResult = null
) -> Dictionary:
	var missing_hp := target.stats.max_hp - target.stats.current_hp
	var vulnerability := float(missing_hp) * policy.wounded_target_weight
	if target.stats.current_hp <= 25:
		vulnerability += 20.0 * policy.finishing_bonus_weight
	var focus_adjustment := squad.target_adjustment(attacker, target) if squad else 0.0
	var focus := focus_adjustment * policy.focus_penalty_weight
	var vip := 25.0 * policy.target_vip_weight if target.mission_actor and target.mission_actor.is_vip() else 0.0
	var threat := _threat_score(target, friendlies, grid) * policy.target_threat_weight
	var mission := _mission_score(attacker, target, intent, objectives, grid) * policy.target_mission_weight
	return {
		"total": vulnerability + focus + vip + threat + mission,
		"vulnerability": vulnerability,
		"focus": focus,
		"vip": vip,
		"threat": threat,
		"mission": mission,
		"focus_count": int(-focus_adjustment / 15.0),
		# Tactical facts remain visible to AI diagnostics without becoming a new
		# doctrine or silently changing Prototype 1 target preferences.
		"hit_chance": attack_prediction.hit_chance if attack_prediction != null else 0,
		"expected_damage": attack_prediction.expected_damage if attack_prediction != null else 0.0,
		"summary": "vulnerable %+.0f, VIP %+.0f, threat %+.0f, mission %+.0f, focus %+.0f" % [vulnerability, vip, threat, mission, focus],
	}

static func _threat_score(target: TacticalUnit, friendlies: Array[TacticalUnit], grid: GridManager) -> float:
	var score := 0.0
	for friendly in friendlies:
		if not is_instance_valid(friendly) or not friendly.stats or friendly.stats.is_defeated:
			continue
		var shot := CombatRules.evaluate_attack(target, friendly, grid, target.get_world_3d())
		if shot.is_legal:
			score += 8.0 * float(shot.hit_chance) / 100.0
			if friendly.stats.current_hp <= 25:
				score += 4.0
	return minf(score, 28.0)

static func _mission_score(attacker: TacticalUnit, target: TacticalUnit, intent: MissionIntent, objectives: ObjectiveManager, grid: GridManager) -> float:
	if not objectives:
		return 0.0
	var target_cell := grid.get_unit_grid(target)
	var score := 0.0
	if target.is_carrying_unit():
		score += 25.0
	if objectives.mission and objectives.mission.mission_id == &"prototype_enemy_evacuation" and target.faction == TacticalUnit.Faction.ENEMY:
		var exit_distance := _nearest_zone_distance(target_cell, grid.map_data.get_objective_zone(&"enemy_extract"))
		if exit_distance <= 2.0:
			score += 30.0
		elif exit_distance <= 5.0:
			score += 18.0
	match intent.kind:
		MissionIntent.Kind.PROTECT:
			var protected_actor := objectives.find_mission_actor(intent.target_ids)
			if _can_threaten(target, protected_actor, grid):
				score += 22.0
		MissionIntent.Kind.RESCUE:
			var rescue_target := objectives.find_mission_actor(intent.target_ids)
			if rescue_target and target_cell.distance_to(grid.get_unit_grid(rescue_target)) <= 3.0:
				score += 10.0
		MissionIntent.Kind.EXTRACT:
			var carrier := objectives.find_rescue_carrier(attacker.faction)
			if _can_threaten(target, carrier, grid):
				score += 22.0
			var exit_distance := _nearest_zone_distance(target_cell, grid.map_data.get_objective_zone(intent.zone_id))
			if exit_distance <= 2.0:
				score += 8.0
		MissionIntent.Kind.REACH:
			if grid.map_data.get_objective_zone(intent.zone_id).has(target_cell):
				score += 16.0
	return score

static func _can_threaten(attacker: TacticalUnit, defended: TacticalUnit, grid: GridManager) -> bool:
	return is_instance_valid(defended) and CombatRules.evaluate_attack(attacker, defended, grid, attacker.get_world_3d()).is_legal

static func _nearest_zone_distance(from: Vector3i, zone: Array[Vector3i]) -> float:
	var nearest := INF
	for cell in zone:
		nearest = minf(nearest, from.distance_to(cell))
	return nearest
