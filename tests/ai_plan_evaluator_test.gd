extends SceneTree
## Milestone 05 step 6, slice A: the typed plan record and the evaluator that replaced the controller's
## inline Aim comparison. Values come from the shared queries; resources are hard limits; evaluating a
## plan changes nothing and draws no combat roll.
const Fixture := preload("res://tests/support/ai_scenario_fixture.gd")

var failures := 0
var checks := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	_plan_record()
	_policy_switch_survives_composition()
	await _aim_comparison()
	print("AI plan evaluator: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

## The controller reads a composed policy (difficulty plus commander). Every field it consumes must
## survive composition, or a tier's setting is silently lost.
func _policy_switch_survives_composition() -> void:
	check(AIDifficultyPolicy.create(AIDifficultyPolicy.Tier.NORMAL).plans_repositioning and AIDifficultyPolicy.create(AIDifficultyPolicy.Tier.HARD).plans_repositioning, "Normal and Hard plan repositioning")
	check(not AIDifficultyPolicy.create(AIDifficultyPolicy.Tier.EASY).plans_repositioning, "Easy does not")
	for tier in [AIDifficultyPolicy.Tier.EASY, AIDifficultyPolicy.Tier.NORMAL, AIDifficultyPolicy.Tier.HARD]:
		for profile in [AICommanderPolicy.Profile.DEFAULT, AICommanderPolicy.Profile.CAUTIOUS, AICommanderPolicy.Profile.AGGRESSIVE]:
			var base := AIDifficultyPolicy.create(tier)
			var composed := AICommanderPolicy.create(profile).compose(base)
			check(composed.plans_repositioning == base.plans_repositioning, "Composition keeps the repositioning switch (%s, %s)" % [AIDifficultyPolicy.get_label(tier), AICommanderPolicy.get_label(profile)])

func _plan_record() -> void:
	var plan := AIActionPlan.new()
	plan.steps = [AIActionPlan.MOVE, AIActionPlan.ATTACK, AIActionPlan.ATTACK]
	plan.ap_cost = 3
	plan.supply_cost = 2
	plan.value = 30.0
	plan.risk = 4.0
	check(plan.first_step() == AIActionPlan.MOVE and plan.has_move(), "A plan knows its first step and whether it moves")
	check(is_equal_approx(plan.net_value(), 26.0), "Net value subtracts risk")
	check(plan.is_affordable(3, 2, true) and not plan.is_affordable(2, 4, true), "Affordability respects AP")
	check(not plan.is_affordable(3, 1, true) and plan.is_affordable(3, 0, false), "Affordability respects supply only when supply is in use")
	var data := plan.to_dictionary()
	check(data.steps == ["move", "attack", "attack"] and data.ap_cost == 3 and data.supply_cost == 2 and is_equal_approx(float(data.value), 30.0), "A plan serializes its facts")
	check(AIActionPlan.new().first_step() == &"" and not AIActionPlan.new().has_move(), "An empty plan has no first step")

func _aim_comparison() -> void:
	var f := Fixture.new()
	await f.setup(self, 1, 1, 0, null, AIDifficultyPolicy.Tier.HARD)
	var actor: TacticalUnit = f.turns.player_units[0]
	var enemy: TacticalUnit = f.turns.enemy_units[0]
	f.place(actor, Vector3i(3, 0, 12)); f.place(enemy, Vector3i(11, 0, 12))
	f.ready_actor(actor, 3, 4)
	f.act_as(actor)
	var ai: AIController = f.ai_of(actor)
	ai._ensure_policy()
	var kill_bonus := 20.0 * ai._ensure_policy().finishing_bonus_weight
	var query: AttackQueryResult = f.battle.query_attack(actor, enemy)
	check(query.is_legal() and query.hit_chance < 100, "Setup: a legal shot that is not a certain hit")
	var rng_before: Variant = f.battle.action_service.get_combat_rng_state()
	var ap_before := actor.stats.current_ap
	var comparison := AIPlanEvaluator.compare_aim(actor, enemy, f.battle, kill_bonus, AIController.MAX_ATTACK_PLAN_AP)
	check(not comparison.is_empty(), "With AP, ammo and a shot, the comparison applies")
	if comparison.is_empty():
		await f.dispose(self)
		return
	var direct: AIActionPlan = comparison.direct
	var aimed: AIActionPlan = comparison.aimed
	var trace: Dictionary = comparison.trace
	check(trace.keys() == ["target", "direct_shots", "aimed_shots", "direct_value", "aimed_value", "choice"], "The trace keeps its established keys (%s)" % str(trace.keys()))
	check(direct.shots == trace.direct_shots and aimed.shots == trace.aimed_shots, "Plan shot counts match the trace")
	check(direct.steps.all(func(step: StringName) -> bool: return step == AIActionPlan.ATTACK), "The direct plan is attacks only")
	check(aimed.first_step() == AIActionPlan.AIM and aimed.steps.size() == aimed.shots + 1, "The aimed plan is Aim, then its shots")
	check(direct.ap_cost == direct.shots and aimed.ap_cost == 1 + aimed.shots, "Plan AP costs are the real action costs (%d, %d)" % [direct.ap_cost, aimed.ap_cost])
	check(direct.supply_cost == direct.shots and aimed.supply_cost == aimed.shots, "Plan supply costs are one per shot")
	check(direct.is_affordable(actor.stats.current_ap, actor.stats.current_supply_points, true) and aimed.is_affordable(actor.stats.current_ap, actor.stats.current_supply_points, true), "Both plans are affordable with the unit's real resources")
	var expected_direct := AITargetScorer.shot_sequence_value(_repeat(query.hit_chance, direct.shots), query.damage_on_hit, enemy.stats.current_hp, kill_bonus)
	check(is_equal_approx(direct.value, expected_direct) and is_equal_approx(float(trace.direct_value), expected_direct), "The direct value is the sequence value of the real chances")
	check(String(trace.choice) == ("Aim" if comparison.choose_aim else "Attack") and comparison.choose_aim == (aimed.value > direct.value + 0.001), "The choice is Aim exactly when it is worth more")
	# Pure: nothing changed and no combat roll was drawn.
	check(actor.stats.current_ap == ap_before and not actor.tactical_state.is_aiming, "Evaluating plans spends and changes nothing")
	check(f.battle.action_service.get_combat_rng_state() == rng_before, "Evaluating plans draws no combat roll")

	# Resources are hard limits.
	actor.stats.set_available_ap_for_setup(1)
	check(AIPlanEvaluator.compare_aim(actor, enemy, f.battle, kill_bonus, AIController.MAX_ATTACK_PLAN_AP).is_empty(), "One AP cannot pay for Aim plus a shot: no comparison")
	actor.stats.set_available_ap_for_setup(3)
	actor.stats.current_supply_points = 0
	check(AIPlanEvaluator.compare_aim(actor, enemy, f.battle, kill_bonus, AIController.MAX_ATTACK_PLAN_AP).is_empty(), "No ammo: no comparison")
	actor.stats.current_supply_points = 1
	var one_shot := AIPlanEvaluator.compare_aim(actor, enemy, f.battle, kill_bonus, AIController.MAX_ATTACK_PLAN_AP)
	check(not one_shot.is_empty() and one_shot.direct.shots == 1 and one_shot.aimed.shots == 1, "One round of ammo limits both plans to one shot")
	actor.stats.current_supply_points = 4
	# The controller acts on exactly this comparison.
	var planned := AIPlanEvaluator.compare_aim(actor, enemy, f.battle, kill_bonus, AIController.MAX_ATTACK_PLAN_AP)
	var aimed_now: bool = await ai._try_aim_for_attack(enemy)
	check(aimed_now == planned.choose_aim and ai._last_attack_plan == planned.trace, "The controller's choice and trace come from the evaluator")
	await f.dispose(self)

func _repeat(chance: int, count: int) -> Array[int]:
	var result: Array[int] = []
	for i in count: result.append(chance)
	return result
