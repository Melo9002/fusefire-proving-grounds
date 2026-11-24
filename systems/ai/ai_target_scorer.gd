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
	attack_prediction: AttackQueryResult = null,
	affordable_shots := 1
) -> Dictionary:
	var missing_hp := target.stats.max_hp - target.stats.current_hp
	var vulnerability := float(missing_hp) * policy.wounded_target_weight
	var fallback := CombatRules.evaluate_attack(attacker, target, grid, attacker.get_world_3d()) if attack_prediction == null else null
	var damage: int = attack_prediction.damage_on_hit if attack_prediction else CombatRules.damage_of(fallback)
	var chance: int = attack_prediction.hit_chance if attack_prediction else fallback.hit_chance
	var damage_value := minf(target.stats.current_hp, damage) * float(chance) / 100.0 * policy.expected_damage_weight
	# The finishing bonus is the probability that the shots the unit can actually afford kill the target,
	# not a flat bonus whenever one hit would: a 10% finishing shot is worth a tenth of a certain one, and
	# a target that two affordable shots very likely kill is worth more than a single shot suggests.
	var shots: Array[int] = []
	for shot in maxi(1, affordable_shots):
		shots.append(chance)
	var kill_chance := kill_probability(shots, damage, target.stats.current_hp)
	vulnerability += 20.0 * policy.finishing_bonus_weight * kill_chance
	# Spreading fire is a preference: it fades as the shot becomes a likely finisher (SquadContext.target_adjustment).
	var focus_adjustment := squad.target_adjustment(attacker, target, kill_chance) if squad else 0.0
	var focus := focus_adjustment * policy.focus_penalty_weight
	var vip := 25.0 * policy.target_vip_weight if target.mission_actor and target.mission_actor.is_vip() else 0.0
	var threat := _threat_score(target, friendlies, grid) * policy.target_threat_weight
	var mission := _mission_score(attacker, target, intent, objectives, grid) * policy.target_mission_weight
	return {
		"total": vulnerability + focus + vip + threat + mission + damage_value,
		"damage_value": damage_value,
		"damage_on_hit": damage,
		"vulnerability": vulnerability,
		"focus": focus,
		"vip": vip,
		"threat": threat,
		"mission": mission,
		"focus_count": squad.focus_count(attacker, target) if squad else 0,
		"kill_chance": kill_chance,
		# Damage value is HP-capped; a miss still deals zero and does not become a guaranteed finisher.
		"hit_chance": chance,
		"expected_damage": float(damage) * float(chance) / 100.0,
		"summary": "damage %+.1f, vulnerable %+.0f, VIP %+.0f, threat %+.0f, mission %+.0f, focus %+.0f, kill %d%%" % [damage_value, vulnerability, vip, threat, mission, focus, roundi(kill_chance * 100.0)],
	}

static func _threat_score(target: TacticalUnit, friendlies: Array[TacticalUnit], grid: GridManager) -> float:
	var score := 0.0
	for friendly in friendlies:
		if not is_instance_valid(friendly) or not friendly.stats or friendly.stats.is_defeated:
			continue
		var shot := CombatRules.evaluate_attack(target, friendly, grid, target.get_world_3d())
		if shot.is_legal:
			score += 8.0 * float(shot.hit_chance) / 100.0
			if friendly.stats.current_hp <= CombatRules.damage_of(shot):
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

## Probability that a sequence of shots at the given chances deals at least `hp` damage, `damage` per
## hit. No random draws: the exact distribution over hits.
static func kill_probability(chances: Array[int], damage: int, hp: int) -> float:
	if damage <= 0 or hp <= 0 or chances.is_empty(): return 0.0
	var probabilities: Array[float] = [1.0]
	for chance in chances:
		var next: Array[float] = []
		next.resize(probabilities.size() + 1)
		next.fill(0.0)
		var hit := clampf(float(chance) / 100.0, 0.0, 1.0)
		for hits in probabilities.size():
			next[hits] += probabilities[hits] * (1.0 - hit)
			next[hits + 1] += probabilities[hits] * hit
		probabilities = next
	var kill := 0.0
	for hits in probabilities.size():
		if hits * damage >= hp: kill += probabilities[hits]
	return kill

## Bounded same-target sequence value: HP-capped expected damage plus kill probability.
## No random draws, no hypothetical mutation, and Aim applies only to the first shot.
static func shot_sequence_value(chances: Array[int], damage: int, hp: int, kill_bonus: float) -> float:
	if damage <= 0 or hp <= 0: return 0.0
	var probabilities: Array[float] = [1.0]
	for chance in chances:
		var next: Array[float] = []
		next.resize(probabilities.size() + 1)
		next.fill(0.0)
		var hit := clampf(float(chance) / 100.0, 0.0, 1.0)
		for hits in probabilities.size():
			next[hits] += probabilities[hits] * (1.0 - hit)
			next[hits + 1] += probabilities[hits] * hit
		probabilities = next
	var value := 0.0
	for hits in probabilities.size():
		value += probabilities[hits] * (minf(hp, hits * damage) + (kill_bonus if hits * damage >= hp else 0.0))
	return value
