class_name AIPlanEvaluator
extends RefCounted
## Builds and values the short plans a unit can afford against one target, using only the shared
## queries and combat rules: the authoritative hit chance, on-hit damage and costs, the unit's real AP
## and supply, and HP-capped expected damage with kill probability. Pure reads: nothing is executed,
## no combat roll is drawn and no state is changed.

## How many attacks the unit can pay for right now against this query's cost: its real AP (within the
## planning horizon) and, when supply is in use, its real ammo. At least one, since a target is only
## scored when a shot is legal.
static func affordable_attack_shots(unit: TacticalUnit, attack_query: AttackQueryResult, battle: BattleController, max_plan_ap: int) -> int:
	var count := mini(unit.stats.current_ap, max_plan_ap) / maxi(1, attack_query.cost.ap)
	if battle.supply_points_enabled:
		count = mini(count, unit.stats.current_supply_points / maxi(1, attack_query.supply_points_cost))
	return maxi(1, count)

## How many attacks `ap` action points and the given supply can pay for, within the planning horizon.
static func shots_with(ap: int, supply: int, attack_ap: int, attack_supply: int, uses_supply: bool, max_plan_ap: int) -> int:
	var count := mini(ap, max_plan_ap) / maxi(1, attack_ap)
	if uses_supply:
		count = mini(count, supply / maxi(1, attack_supply))
	return maxi(0, count)

## The best shot sequence the unit could fire from `cell` (its own cell, or a hypothetical one after a
## move) at any of `hostiles`: `shots` attacks at the authoritative chance and damage the combat rules give
## for that standing cell, valued as HP-capped expected damage plus kill value. Ties go to the lower
## tactical ID, so the result never depends on iteration luck. Returns {value, target, chance, damage, shots}
## with value 0.0 and a null target when no hostile can be shot from there.
static func best_attack_from(unit: TacticalUnit, cell: Vector3i, hostiles: Array[TacticalUnit], battle: BattleController, shots: int, kill_bonus: float, accuracy_bonus := 0) -> Dictionary:
	var best := {"value": 0.0, "target": null, "chance": 0, "damage": 0, "shots": shots}
	if shots < 1:
		return best
	for hostile in hostiles:
		if not is_instance_valid(hostile) or not hostile.stats or hostile.stats.is_defeated:
			continue
		var evaluation := CombatRules.evaluate_attack_from_cell(unit, cell, hostile, battle.grid_manager, unit.get_world_3d(), accuracy_bonus, battle.shield_enabled)
		if not evaluation.is_legal:
			continue
		var damage := CombatRules.cover_tuning.damage_for_hit(evaluation.shield_damage_multiplier)
		var chances: Array[int] = []
		for shot in shots:
			chances.append(evaluation.hit_chance)
		var value := AITargetScorer.shot_sequence_value(chances, damage, hostile.stats.current_hp, kill_bonus)
		var better := value > float(best.value) + 0.0001
		var tied := absf(value - float(best.value)) <= 0.0001 and best.target != null and String(hostile.tactical_id) < String(best.target.tactical_id)
		if better or tied:
			best = {"value": value, "target": hostile, "chance": evaluation.hit_chance, "damage": damage, "shots": shots}
	return best

## The plan "move to `destination`, then fire `shots` times", valued from a best_attack_from result.
static func move_then_attack(destination: Vector3i, shot: Dictionary, move_ap: int, attack_ap: int, attack_supply: int) -> AIActionPlan:
	var plan := AIActionPlan.new()
	plan.steps.append(AIActionPlan.MOVE)
	for index in int(shot.shots):
		plan.steps.append(AIActionPlan.ATTACK)
	plan.destination = destination
	plan.shots = int(shot.shots)
	plan.ap_cost = move_ap + plan.shots * attack_ap
	plan.supply_cost = plan.shots * attack_supply
	plan.value = float(shot.value)
	var target: TacticalUnit = shot.target
	plan.target_id = target.tactical_id if is_instance_valid(target) else &""
	plan.summary = "Move to %s, then %d shot(s) at %s (%d%% each)" % [destination, plan.shots, String(plan.target_id), int(shot.chance)]
	return plan

## The Shield stance, valued as the damage it is expected to prevent. Shield only lowers damage taken: for
## every hostile that can shoot the unit from inside the protected arc, the hit chance drops by the
## capability's accuracy modifier and the damage is multiplied by its damage multiplier. Each hostile's
## unshielded chance and damage come from the combat rules; the shielded ones are derived from the same
## rules (CombatRules.chance_for_raw, cover_tuning.damage_for_hit). The facing that covers the most
## expected damage wins, ties to the lower tactical ID. Pure: the unit's own stance is not touched.
## Returns null when the unit has no Shield, cannot pay for it, or nobody can shoot it. The plan's
## `target_id` is the hostile the unit would face.
static func best_shield_plan(unit: TacticalUnit, hostiles: Array[TacticalUnit], battle: BattleController) -> AIActionPlan:
	var capability := unit.shield_capability
	if capability == null or not battle.shield_enabled or unit.stats.current_ap < capability.stance_ap_cost:
		return null
	var grid := battle.grid_manager
	var my_cell := grid.get_unit_grid(unit)
	var threats: Array[Dictionary] = []
	for hostile in hostiles:
		if not is_instance_valid(hostile) or not hostile.stats or hostile.stats.is_defeated:
			continue
		var incoming := CombatRules.evaluate_attack(hostile, unit, grid, hostile.get_world_3d(), 0, false)
		if not incoming.is_legal:
			continue
		threats.append({"hostile": hostile, "chance": incoming.hit_chance, "raw": incoming.raw_chance,
			"direction": CombatRules.shield_direction(my_cell, grid.get_unit_grid(hostile), grid)})
	if threats.is_empty():
		return null
	var full_damage := mini(CombatRules.cover_tuning.damage_for_hit(1.0), unit.stats.current_hp)
	var shielded_damage := mini(CombatRules.cover_tuning.damage_for_hit(capability.damage_multiplier), unit.stats.current_hp)
	var best: AIActionPlan = null
	for facing_threat in threats:
		var prevented := 0.0
		var covered := 0
		var values: Array[float] = []
		for threat in threats:
			if not CombatRules.is_within_protected_arc(facing_threat.direction, threat.direction, capability.protected_arc_degrees):
				continue
			var shielded_chance := CombatRules.chance_for_raw(float(threat.raw) + float(capability.accuracy_modifier))
			values.append(float(threat.chance) / 100.0 * float(full_damage) - float(shielded_chance) / 100.0 * float(shielded_damage))
		# A shield with a capacity covers only that many attacks: the most valuable ones count.
		values.sort()
		values.reverse()
		for value in values:
			if not capability.has_capacity(covered):
				break
			prevented += value
			covered += 1
		var hostile: TacticalUnit = facing_threat.hostile
		var better := best == null or prevented > best.value + 0.0001
		var tied := best != null and absf(prevented - best.value) <= 0.0001 and String(hostile.tactical_id) < String(best.target_id)
		if better or tied:
			best = AIActionPlan.new()
			best.steps.append(AIActionPlan.SHIELD)
			best.target_id = hostile.tactical_id
			best.ap_cost = capability.stance_ap_cost
			best.value = prevented
			best.summary = "Shield facing %s prevents about %.1f expected damage from %d of %d attacker(s)" % [String(hostile.tactical_id), prevented, covered, threats.size()]
	return best

## Direct shots versus Aim followed by shots, over at most `max_plan_ap` action points. Aim affects only
## the first shot. Returns {} when the comparison does not apply (Aim not legal, no shot, a certain
## hit, too few AP or ammo for Aim plus a shot). Otherwise:
##   direct / aimed: AIActionPlan, choose_aim: bool, trace: the established _last_attack_plan keys.
static func compare_aim(unit: TacticalUnit, target: TacticalUnit, battle: BattleController, kill_bonus: float, max_plan_ap: int) -> Dictionary:
	var aim_query := battle.query_aim(unit)
	if not aim_query.is_legal():
		return {}
	var attack_query := battle.query_attack(unit, target)
	if unit.stats.current_ap < aim_query.cost.ap + attack_query.cost.ap \
	or not attack_query.is_legal() or attack_query.hit_chance >= 100:
		return {}
	var planning_ap := mini(unit.stats.current_ap, max_plan_ap)
	var direct_count := planning_ap / maxi(1, attack_query.cost.ap)
	var aimed_count := (planning_ap - aim_query.cost.ap) / maxi(1, attack_query.cost.ap)
	if battle.supply_points_enabled:
		var ammo := unit.stats.current_supply_points / maxi(1, attack_query.supply_points_cost)
		direct_count = mini(direct_count, ammo)
		aimed_count = mini(aimed_count, ammo)
	if aimed_count < 1:
		return {}
	var aimed := CombatRules.evaluate_attack(unit, target, battle.grid_manager,
		unit.get_world_3d(), aim_query.accuracy_bonus, battle.shield_enabled)
	var direct_chances: Array[int] = []
	var aimed_chances: Array[int] = []
	for shot in direct_count: direct_chances.append(attack_query.hit_chance)
	for shot in aimed_count: aimed_chances.append(aimed.hit_chance if shot == 0 else attack_query.hit_chance)
	var hp := target.stats.current_hp
	var direct := _attack_sequence(target, direct_chances, attack_query, hp, kill_bonus, false, aim_query.cost.ap)
	var aimed_plan := _attack_sequence(target, aimed_chances, attack_query, hp, kill_bonus, true, aim_query.cost.ap)
	var choose_aim := aimed_plan.value > direct.value + 0.001
	return {
		"direct": direct,
		"aimed": aimed_plan,
		"choose_aim": choose_aim,
		"trace": {"target": String(target.tactical_id), "direct_shots": direct_count, "aimed_shots": aimed_count,
			"direct_value": direct.value, "aimed_value": aimed_plan.value, "choice": "Aim" if choose_aim else "Attack"},
	}

static func _attack_sequence(target: TacticalUnit, chances: Array[int], attack_query: AttackQueryResult, hp: int, kill_bonus: float, with_aim: bool, aim_ap: int) -> AIActionPlan:
	var plan := AIActionPlan.new()
	plan.target_id = target.tactical_id
	if with_aim:
		plan.steps.append(AIActionPlan.AIM)
	for shot in chances.size():
		plan.steps.append(AIActionPlan.ATTACK)
	plan.shots = chances.size()
	plan.ap_cost = (aim_ap if with_aim else 0) + chances.size() * attack_query.cost.ap
	plan.supply_cost = chances.size() * attack_query.supply_points_cost
	plan.value = AITargetScorer.shot_sequence_value(chances, attack_query.damage_on_hit, hp, kill_bonus)
	plan.summary = "%s%d shot(s) at %s, chances %s" % ["Aim, then " if with_aim else "", chances.size(), String(target.tactical_id), str(chances)]
	return plan
