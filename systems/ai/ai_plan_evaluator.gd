class_name AIPlanEvaluator
extends RefCounted
## Builds and values the short plans a unit can afford against one target, using only the shared
## queries and combat rules: the authoritative hit chance, on-hit damage and costs, the unit's real AP
## and supply, and HP-capped expected damage with kill probability. Pure reads: nothing is executed,
## no combat roll is drawn and no state is changed.

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
