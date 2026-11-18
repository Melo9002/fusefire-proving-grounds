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
	await _shield_plan()
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

## Shield only lowers damage taken, so its value is the expected damage it prevents, from the real rules.
func _shield_plan() -> void:
	var f := Fixture.new()
	await f.setup(self, 1, 2, 0, null, AIDifficultyPolicy.Tier.HARD)
	var actor: TacticalUnit = f.turns.player_units[0]
	var east: TacticalUnit = f.turns.enemy_units[0]
	var west: TacticalUnit = f.turns.enemy_units[1]
	actor.shield_capability = load("res://units/capabilities/physical_shield.tres")
	var capability: ShieldCapability = actor.shield_capability
	f.place(actor, Vector3i(12, 0, 12)); f.place(east, Vector3i(18, 0, 12)); f.place(west, Vector3i(6, 0, 12))
	f.ready_actor(actor, 3, 4)
	east.attack_range = 10
	west.attack_range = 10
	var hostiles: Array[TacticalUnit] = [east, west]
	var tuning = CombatRules.cover_tuning
	var full := mini(tuning.damage_for_hit(1.0), actor.stats.current_hp)
	var shielded := mini(tuning.damage_for_hit(capability.damage_multiplier), actor.stats.current_hp)
	var prevented_by := func(hostile: TacticalUnit) -> float:
		var e := CombatRules.evaluate_attack(hostile, actor, f.grid, hostile.get_world_3d(), 0, false)
		return float(e.hit_chance) / 100.0 * float(full) - float(CombatRules.chance_for_raw(e.raw_chance + float(capability.accuracy_modifier))) / 100.0 * float(shielded)
	check(CombatRules.chance_for_raw(CombatRules.evaluate_attack(east, actor, f.grid, east.get_world_3d(), 0, false).raw_chance) == CombatRules.evaluate_attack(east, actor, f.grid, east.get_world_3d(), 0, false).hit_chance, "The shared chance rule reproduces the combat rules' own chance")
	var rng_before: Variant = f.battle.action_service.get_combat_rng_state()
	var plan := AIPlanEvaluator.best_shield_plan(actor, hostiles, f.battle)
	check(plan != null and plan.first_step() == AIActionPlan.SHIELD and plan.ap_cost == capability.stance_ap_cost, "A unit with a Shield and attackers gets a Shield plan at the stance's real AP cost")
	if plan == null:
		await f.dispose(self)
		return
	# One attacker on each side: the arc covers only the one it faces, so the value is one attacker's prevented damage.
	check(is_equal_approx(plan.value, prevented_by.call(east)), "Facing one side prevents that attacker's expected damage only (%.2f vs %.2f)" % [plan.value, prevented_by.call(east)])
	check(plan.value > 0.0, "The Shield is worth something against a shooter who can hit")
	check(plan.target_id == east.tactical_id, "Equal threats go to the lower tactical ID (%s)" % String(plan.target_id))
	check(not actor.tactical_state.is_shielding and f.battle.action_service.get_combat_rng_state() == rng_before, "Valuing the plan changes no state and draws no roll")
	# Both attackers on the same side: one facing covers both.
	f.place(west, Vector3i(19, 0, 13))
	var both := AIPlanEvaluator.best_shield_plan(actor, hostiles, f.battle)
	check(both != null and is_equal_approx(both.value, prevented_by.call(east) + prevented_by.call(west)), "One facing that covers both attackers is worth both (%.2f)" % (both.value if both != null else -1.0))
	check(both != null and both.value > plan.value, "Covering more expected damage ranks higher")
	# Not worth planning, or impossible.
	east.attack_range = 3
	west.attack_range = 3
	check(AIPlanEvaluator.best_shield_plan(actor, hostiles, f.battle) == null, "Nobody who can shoot the unit: no plan")
	east.attack_range = 10
	actor.stats.set_available_ap_for_setup(0)
	check(AIPlanEvaluator.best_shield_plan(actor, hostiles, f.battle) == null, "No AP for the stance: no plan")
	actor.stats.set_available_ap_for_setup(3)
	actor.shield_capability = null
	check(AIPlanEvaluator.best_shield_plan(actor, hostiles, f.battle) == null, "A unit without a Shield has no plan")
	actor.shield_capability = capability
	f.battle.shield_enabled = false
	check(AIPlanEvaluator.best_shield_plan(actor, hostiles, f.battle) == null, "With Shield disabled in the battle: no plan")
	f.battle.shield_enabled = true
	await f.dispose(self)
