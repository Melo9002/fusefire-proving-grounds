extends SceneTree
## Milestone 05 step 6, slice B: the finishing bonus is the probability that the shots the unit can
## afford kill the target, not a flat bonus whenever one hit would. Exact distribution, no random draws.
const Fixture := preload("res://tests/support/ai_scenario_fixture.gd")

var failures := 0
var checks := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.0005

func _run() -> void:
	_kill_probability()
	await _scorer_and_resources()
	print("AI target value: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

func _kill_probability() -> void:
	check(_near(AITargetScorer.kill_probability([100], 25, 25), 1.0), "A certain hit that deals the target's HP always kills")
	check(_near(AITargetScorer.kill_probability([100], 25, 26), 0.0), "One hit short of the HP never kills")
	check(_near(AITargetScorer.kill_probability([50], 25, 25), 0.5), "A 50% finishing shot kills half the time")
	check(_near(AITargetScorer.kill_probability([50, 50], 25, 50), 0.25), "Two 50% shots both hit a quarter of the time")
	check(_near(AITargetScorer.kill_probability([50, 50], 25, 25), 0.75), "Either of two 50% shots kills a one-hit target 75% of the time")
	check(_near(AITargetScorer.kill_probability([80, 80, 80], 25, 50), 0.896), "Two of three 80% shots kill a two-hit target 89.6% of the time")
	check(AITargetScorer.kill_probability([], 25, 25) == 0.0 and AITargetScorer.kill_probability([100], 0, 25) == 0.0 and AITargetScorer.kill_probability([100], 25, 0) == 0.0, "No shots, no damage or no HP is never a kill")
	check(AITargetScorer.kill_probability([60, 60], 25, 50) > AITargetScorer.kill_probability([60], 25, 50), "More shots never lower the kill chance")
	check(AITargetScorer.kill_probability([70, 70], 25, 50) > AITargetScorer.kill_probability([50, 50], 25, 50), "A better chance never lowers it")

func _scorer_and_resources() -> void:
	var f := Fixture.new()
	await f.setup(self, 1, 1, 0, null, AIDifficultyPolicy.Tier.HARD)
	var actor: TacticalUnit = f.turns.player_units[0]
	var enemy: TacticalUnit = f.turns.enemy_units[0]
	f.place(actor, Vector3i(3, 0, 12)); f.place(enemy, Vector3i(11, 0, 12))
	f.ready_actor(actor, 3, 4)
	var policy := AIDifficultyPolicy.create(AIDifficultyPolicy.Tier.NORMAL)
	var weight := 20.0 * policy.finishing_bonus_weight
	var query := AttackQueryResult.new()

	# The finishing bonus is the kill probability times its weight: read it out of the vulnerability term.
	var wounded_term := func(hp: int, chance: int, damage: int, shots: int) -> Dictionary:
		enemy.stats.current_hp = hp
		query.hit_chance = chance
		query.damage_on_hit = damage
		query.expected_damage = float(damage) * float(chance) / 100.0
		var scored := AITargetScorer.evaluate(actor, enemy, [], MissionIntent.new(), null, f.grid, policy, null, query, shots)
		scored["finisher"] = float(scored.vulnerability) - float(enemy.stats.max_hp - hp) * policy.wounded_target_weight
		return scored
	var certain: Dictionary = wounded_term.call(30, 100, 31, 1)
	var even: Dictionary = wounded_term.call(30, 50, 31, 1)
	var unlikely: Dictionary = wounded_term.call(30, 10, 31, 1)
	check(_near(certain.finisher, weight) and _near(certain.kill_chance, 1.0), "A certain finisher earns the full bonus (%.2f)" % certain.finisher)
	check(_near(even.finisher, weight * 0.5), "A 50%% finisher earns half of it (%.2f of %.2f)" % [even.finisher, weight])
	check(_near(unlikely.finisher, weight * 0.1), "A 10%% finisher earns a tenth, not the full flat bonus (%.2f)" % unlikely.finisher)
	check(certain.total > even.total and even.total > unlikely.total, "Better odds of the kill rank the target higher, all else equal")

	var one_shot: Dictionary = wounded_term.call(50, 100, 25, 1)
	var two_shots: Dictionary = wounded_term.call(50, 100, 25, 2)
	check(_near(one_shot.finisher, 0.0) and _near(two_shots.finisher, weight), "A two-hit target earns the bonus only when two shots are affordable")
	var coin_two: Dictionary = wounded_term.call(50, 50, 25, 2)
	var coin_three: Dictionary = wounded_term.call(50, 50, 25, 3)
	check(_near(coin_two.finisher, weight * 0.25) and _near(coin_three.finisher, weight * 0.5), "The bonus follows the real kill chance over the shots the unit can afford (%.2f, %.2f)" % [coin_two.finisher, coin_three.finisher])
	check(String(certain.summary).contains("kill 100%") and String(even.summary).contains("kill 50%"), "The explanation states the kill chance (%s)" % certain.summary)
	enemy.stats.current_hp = enemy.stats.max_hp
	query.hit_chance = 70
	query.damage_on_hit = 25
	var default_call := AITargetScorer.evaluate(actor, enemy, [], MissionIntent.new(), null, f.grid, policy, null, query)
	var single := AITargetScorer.evaluate(actor, enemy, [], MissionIntent.new(), null, f.grid, policy, null, query, 1)
	check(_near(default_call.total, single.total), "Without the argument the scorer keeps its single-shot meaning")

	# Affordable shots come from the unit's real AP and ammo.
	var real_query: AttackQueryResult = f.battle.query_attack(actor, enemy)
	check(real_query.is_legal(), "Setup: a legal shot")
	check(AIPlanEvaluator.affordable_attack_shots(actor, real_query, f.battle, AIController.MAX_ATTACK_PLAN_AP) == 3, "Three AP and four rounds afford three shots")
	actor.stats.current_supply_points = 1
	check(AIPlanEvaluator.affordable_attack_shots(actor, real_query, f.battle, AIController.MAX_ATTACK_PLAN_AP) == 1, "One round of ammo affords one shot")
	actor.stats.current_supply_points = 4
	actor.stats.set_available_ap_for_setup(1)
	check(AIPlanEvaluator.affordable_attack_shots(actor, real_query, f.battle, AIController.MAX_ATTACK_PLAN_AP) == 1, "One AP affords one shot")
	actor.stats.set_available_ap_for_setup(3)
	check(AIPlanEvaluator.affordable_attack_shots(actor, real_query, f.battle, 2) == 2, "The planning horizon caps the count")
	# The whole-number plan counts drop the remainder (truncating toward zero), including a negative numerator.
	check(AIPlanEvaluator.shots_with(5, 9, 2, 4, true, 6) == 2, "Five AP at two per shot, nine ammo at four per shot: the remainders are dropped (2)")
	check(AIPlanEvaluator.shots_with(7, 9, 2, 4, false, 6) == 3, "The horizon (6 AP) caps before the quotient: 6 / 2 = 3")
	check(AIPlanEvaluator.shots_with(-1, 9, 2, 4, false, 6) == 0, "A move that leaves a negative AP budget affords nothing")
	await f.dispose(self)
