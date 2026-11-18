extends SceneTree
## Milestone 05 step 7: movement profiles are editable layers on the position score. The first slice
## turns the two hard-coded blocks (objective route, carrier) into profiles with today's exact numbers;
## this checks the data, the selection and the arithmetic, and that no layer changes legality.
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
	return absf(a - b) < 0.0001

func _run() -> void:
	_catalog()
	await _scoring_and_selection()
	_stance_selection()
	await _stances_are_distinguishable()
	await _flanking_and_cohesion()
	await _decision_names_its_profile()
	print("AI movement profiles: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

func _catalog() -> void:
	check(AIMovementProfiles.validate_catalog().is_empty(), "The profile catalog is valid and has a default")
	var neutral := AIMovementProfiles.DEFAULT
	check(_near(neutral.route_progress, 1.0) and _near(neutral.goal_progress, 1.0) and _near(neutral.cover, 1.0) and _near(neutral.exposure, 1.0) and _near(neutral.firing, 1.0) and _near(neutral.danger, 1.0) and _near(neutral.crowding, 1.0) and neutral.flank_weight == 0.0 and neutral.ally_cohesion_weight == 0.0, "The default profile changes nothing")
	var route := AIMovementProfiles.OBJECTIVE_ROUTE
	check(_near(route.route_progress, 2.0) and _near(route.cover, 1.25) and _near(route.exposure, 1.5) and _near(route.firing, 0.0) and _near(route.danger, 1.0) and _near(route.goal_progress, 1.0), "The objective-route profile is the former hard-coded block (progress x2, cover x1.25, exposure x1.5, no firing)")
	var carrier := AIMovementProfiles.CARRIER
	check(_near(carrier.cover, 1.5) and _near(carrier.exposure, 2.5) and _near(carrier.danger, 2.0) and _near(carrier.firing, 1.0) and _near(carrier.route_progress, 1.0), "The carrier profile is the former hard-coded block (cover x1.5, exposure x2.5, danger x2.0)")
	check(AIMovementProfiles.get_profile(&"carrier") == carrier and AIMovementProfiles.get_profile(&"nope") == null, "Profiles are found by ID")
	check(route.summary().contains("route x2.00") and route.summary().contains("firing x0.00") and neutral.summary().contains("no change"), "A profile describes itself (%s)" % route.summary())

func _pick(situation: Dictionary, objective_route := false) -> Dictionary:
	return AIMovementProfiles.select(null, objective_route, "test", situation)

## The stance rules, each with its reason and the fixed precedence between them.
func _stance_selection() -> void:
	check(_pick({}).ids == ["default"], "No facts, no stance")
	check(_pick({"hp_fraction": 0.3}).ids == ["defensive"] and String(_pick({"hp_fraction": 0.3}).reason).contains("badly hurt (30% HP)"), "Badly hurt: Defensive, with the HP in the reason")
	check(_pick({"out_of_ammo": true}).ids == ["defensive"] and String(_pick({"out_of_ammo": true}).reason).contains("out of ammunition"), "Out of ammunition: Defensive")
	check(_pick({"threats": 3, "nearby_allies": 1}).ids == ["defensive"] and String(_pick({"threats": 3, "nearby_allies": 1}).reason).contains("outmatched"), "Outmatched by two or more: Defensive")
	check(_pick({"threats": 2, "nearby_allies": 1}).ids == ["default"], "Outmatched by one is not enough")
	check(_pick({"support_unit": true}).ids == ["support"] and _pick({"wounded_ally": true}).ids == ["support"], "A support unit, or a hurt ally nearby: Support")
	check(_pick({"flank_possible": true}).ids == ["flanking"], "An ally already has the target: Flanking")
	check(_pick({"hp_fraction": 1.0, "wounded_target": true}).ids == ["aggressive"], "Healthy with a wounded target in reach: Aggressive")
	check(_pick({"hp_fraction": 1.0, "threats": 1, "nearby_allies": 1}).ids == ["aggressive"] and _pick({"hp_fraction": 0.6, "wounded_target": true}).ids == ["default"], "Aggressive needs health (60% HP: no stance)")
	check(_pick({"hp_fraction": 0.3, "flank_possible": true, "wounded_target": true}).ids == ["defensive"], "Precedence: being hurt outranks flanking and pressing")
	check(_pick({"wounded_ally": true, "flank_possible": true}).ids == ["support"], "Precedence: support outranks flanking")
	check(_pick({"escorting": true, "hp_fraction": 0.2}).ids == ["escort"], "Precedence: escorting outranks everything else")
	check(_pick({"hp_fraction": 0.2, "flank_possible": true}, true).ids == ["objective_route"], "On an objective route a tactical stance never applies")
	check(_pick({"escorting": true}, true).ids == ["objective_route", "escort"], "An escort on a route keeps both layers, in order")
	var order := AIMovementProfiles.all().map(func(p: AIMovementProfile) -> String: return String(p.profile_id))
	check(order == ["default", "objective_route", "carrier", "escort", "defensive", "aggressive", "flanking", "support"] and AIMovementProfiles.validate_catalog().is_empty(), "All eight presets are in the valid catalog")

func _scoring_and_selection() -> void:
	var f := Fixture.new()
	await f.setup(self, 1, 1, 0, null, AIDifficultyPolicy.Tier.HARD)
	var actor: TacticalUnit = f.turns.player_units[0]
	var enemy: TacticalUnit = f.turns.enemy_units[0]
	f.place(actor, Vector3i(3, 0, 12)); f.place(enemy, Vector3i(11, 0, 12))
	f.ready_actor(actor)
	var start := Vector3i(3, 0, 12)
	var candidate := Vector3i(6, 0, 12)
	var goal := Vector3i(20, 0, 12)
	var policy := AIDifficultyPolicy.create(AIDifficultyPolicy.Tier.NORMAL)
	var hostiles: Array[TacticalUnit] = [enemy]
	var base := AIPositionScorer.evaluate(actor, candidate, start, goal, 3.0, [], hostiles, f.grid, policy, null)
	check(float(base.firing) > 0.0 and float(base.exposure) < 0.0 and float(base.progress) > 0.0, "Setup: the cell has a firing lane, exposure and progress (%s)" % base.summary)

	var objective := AIPositionScorer.evaluate(actor, candidate, start, goal, 3.0, [AIMovementProfiles.OBJECTIVE_ROUTE], hostiles, f.grid, policy, null)
	check(_near(objective.firing, 0.0) and _near(objective.exposure, float(base.exposure) * 1.5) and _near(objective.cover, float(base.cover) * 1.25) and _near(objective.danger, float(base.danger)), "The objective layer drops firing, scales exposure x1.5 and cover x1.25")
	var goal_term := (start.distance_to(goal) - candidate.distance_to(goal)) * 1.5 * policy.movement_progress_weight
	var base_route_term := 3.0 * 4.0 * policy.movement_progress_weight
	check(_near(base.progress, base_route_term + goal_term) and _near(objective.progress, 3.0 * 8.0 * policy.movement_progress_weight + goal_term), "It doubles only the route-progress term, not the goal-distance term")

	var both := AIPositionScorer.evaluate(actor, candidate, start, goal, 3.0, [AIMovementProfiles.OBJECTIVE_ROUTE, AIMovementProfiles.CARRIER], hostiles, f.grid, policy, null)
	check(_near(both.exposure, float(base.exposure) * 1.5 * 2.5) and _near(both.danger, float(base.danger) * 2.0) and _near(both.cover, float(base.cover) * 1.25 * 1.5), "Layers multiply in order: a carrier on an objective route")
	var neutral_layer := AIPositionScorer.evaluate(actor, candidate, start, goal, 3.0, [AIMovementProfiles.DEFAULT], hostiles, f.grid, policy, null)
	check(_near(neutral_layer.total, base.total), "A default layer changes no score")
	var scaled := AIMovementProfile.new()
	scaled.crowding = 0.0
	scaled.firing = 2.0
	var tuned := AIPositionScorer.evaluate(actor, candidate, start, goal, 3.0, [scaled], hostiles, f.grid, policy, null)
	check(_near(tuned.firing, float(base.firing) * 2.0), "A newly authored layer re-weights the score without code changes")

	# Selection and its explanation.
	var none := AIMovementProfiles.select(actor, false, "None")
	check(none.layers.is_empty() and none.ids == ["default"] and String(none.reason).contains("no situational change"), "No role: the default profile, and it says so")
	var route := AIMovementProfiles.select(actor, true, "Reach Zone")
	check(route.ids == ["objective_route"] and String(route.reason).contains("mission intent is Reach Zone"), "A route intent selects the objective-route profile and names the intent (%s)" % route.reason)
	actor.carried_unit = enemy
	var carrying := AIMovementProfiles.select(actor, true, "Extract")
	check(carrying.ids == ["objective_route", "carrier"] and carrying.layers.size() == 2, "A carrier on a route gets both layers in order")
	var carrying_idle := AIMovementProfiles.select(actor, false, "None")
	check(carrying_idle.ids == ["carrier"], "A carrier with no route still gets the carrier layer")
	actor.carried_unit = null
	await f.dispose(self)

## The same two cells ranked under different stances: a forward, exposed firing position against a quiet
## position far back. Defensive prefers the back, Aggressive the front, and Default sits between.
func _stances_are_distinguishable() -> void:
	var f := Fixture.new()
	await f.setup(self, 1, 1, 0, null, AIDifficultyPolicy.Tier.HARD)
	var actor: TacticalUnit = f.turns.player_units[0]
	var enemy: TacticalUnit = f.turns.enemy_units[0]
	f.place(actor, Vector3i(3, 0, 12)); f.place(enemy, Vector3i(14, 0, 12))
	f.ready_actor(actor)
	enemy.attack_range = 10
	var start := Vector3i(3, 0, 12)
	var front := Vector3i(9, 0, 12)
	var back := Vector3i(3, 0, 20)
	var goal := Vector3i(14, 0, 12)
	var policy := AIDifficultyPolicy.create(AIDifficultyPolicy.Tier.NORMAL)
	var hostiles: Array[TacticalUnit] = [enemy]
	var gap := func(layers: Array) -> float:
		var forward := AIPositionScorer.evaluate(actor, front, start, goal, 3.0, layers, hostiles, f.grid, policy, null)
		var behind := AIPositionScorer.evaluate(actor, back, start, goal, 0.0, layers, hostiles, f.grid, policy, null)
		return float(forward.total) - float(behind.total)
	var plain: float = gap.call([])
	var cautious: float = gap.call([AIMovementProfiles.DEFENSIVE])
	var pressing: float = gap.call([AIMovementProfiles.AGGRESSIVE])
	check(cautious < plain and plain < pressing, "The same cells rank differently: Defensive %.1f < Default %.1f < Aggressive %.1f (front minus back)" % [cautious, plain, pressing])
	# Legality is not a matter of profile: a hard squad veto holds under every profile.
	var context := SquadContext.new()
	context.reserve_destination(enemy, front)
	var all_veto := true
	for layers in [[], [AIMovementProfiles.DEFENSIVE], [AIMovementProfiles.AGGRESSIVE], [AIMovementProfiles.FLANKING], [AIMovementProfiles.SUPPORT], [AIMovementProfiles.ESCORT]]:
		all_veto = all_veto and AIPositionScorer.evaluate(actor, front, start, goal, 3.0, layers, hostiles, f.grid, policy, context).total == -INF
	check(all_veto, "A cell held by another unit stays vetoed under every profile")
	await f.dispose(self)

## The two terms that look at the surroundings: flanking spreads fire onto a new bearing, support stays near allies.
func _flanking_and_cohesion() -> void:
	var f := Fixture.new()
	await f.setup(self, 2, 1, 0, null, AIDifficultyPolicy.Tier.HARD)
	var actor: TacticalUnit = f.turns.player_units[0]
	var ally: TacticalUnit = f.turns.player_units[1]
	var enemy: TacticalUnit = f.turns.enemy_units[0]
	f.place(actor, Vector3i(4, 0, 12)); f.place(ally, Vector3i(6, 0, 12)); f.place(enemy, Vector3i(12, 0, 12))
	f.ready_actor(actor); f.ready_actor(ally)
	enemy.attack_range = 10
	var policy := AIDifficultyPolicy.create(AIDifficultyPolicy.Tier.NORMAL)
	var hostiles: Array[TacticalUnit] = [enemy]
	var friendlies: Array[TacticalUnit] = [actor, ally]
	var context := AIMovementContext.build(actor, friendlies, hostiles, f.grid)
	check(context.focus_target == enemy and context.focus_bearings.size() == 1 and context.allies == [ally], "The context finds the target the ally already has and the ally's bearing")
	var same_side := Vector3i(7, 0, 13)
	var other_side := Vector3i(12, 0, 6)
	var layers: Array = [AIMovementProfiles.FLANKING]
	var near_ally_line := AIPositionScorer.evaluate(actor, same_side, actor.grid_position, Vector3i(-1, -1, -1), 0.0, layers, hostiles, f.grid, policy, null, context)
	var new_bearing := AIPositionScorer.evaluate(actor, other_side, actor.grid_position, Vector3i(-1, -1, -1), 0.0, layers, hostiles, f.grid, policy, null, context)
	check(float(new_bearing.flank) > float(near_ally_line.flank) and float(new_bearing.flank) > AIMovementProfiles.FLANKING.flank_weight * 0.5, "A firing position on a new bearing earns the flank bonus; one on the ally's line earns little (%.1f against %.1f)" % [new_bearing.flank, near_ally_line.flank])
	var far_cell := Vector3i(30, 0, 12)
	var out_of_range := AIPositionScorer.evaluate(actor, far_cell, actor.grid_position, Vector3i(-1, -1, -1), 0.0, layers, hostiles, f.grid, policy, null, context)
	check(not CombatRules.evaluate_attack_from_cell(actor, far_cell, enemy, f.grid, actor.get_world_3d()).is_legal and float(out_of_range.flank) == 0.0, "No firing lane, no flank bonus")
	var without_context := AIPositionScorer.evaluate(actor, other_side, actor.grid_position, Vector3i(-1, -1, -1), 0.0, layers, hostiles, f.grid, policy, null)
	check(float(without_context.flank) == 0.0 and float(without_context.cohesion) == 0.0, "Without a context the extra terms are zero")
	var default_layer := AIPositionScorer.evaluate(actor, other_side, actor.grid_position, Vector3i(-1, -1, -1), 0.0, [], hostiles, f.grid, policy, null, context)
	check(float(default_layer.flank) == 0.0 and float(default_layer.cohesion) == 0.0, "A profile without those weights ignores them")
	var support_layers: Array = [AIMovementProfiles.SUPPORT]
	var beside := AIPositionScorer.evaluate(actor, Vector3i(7, 0, 12), actor.grid_position, Vector3i(-1, -1, -1), 0.0, support_layers, hostiles, f.grid, policy, null, context)
	var alone := AIPositionScorer.evaluate(actor, Vector3i(7, 0, 22), actor.grid_position, Vector3i(-1, -1, -1), 0.0, support_layers, hostiles, f.grid, policy, null, context)
	check(float(beside.cohesion) > float(alone.cohesion) and float(alone.cohesion) == 0.0, "Support rewards a cell beside an ally and nothing far from one (%.1f, %.1f)" % [beside.cohesion, alone.cohesion])
	check(String(beside.summary).contains("cohesion"), "The explanation names the extra terms when they apply")
	await f.dispose(self)

## A real decision records which profile shaped it and why.
func _decision_names_its_profile() -> void:
	var f := Fixture.new()
	await f.setup(self, 1, 1, 0, null, AIDifficultyPolicy.Tier.HARD, [], true)
	var actor: TacticalUnit = f.turns.player_units[0]
	var enemy: TacticalUnit = f.turns.enemy_units[0]
	f.place(actor, Vector3i(3, 0, 28)); f.place(enemy, Vector3i(28, 0, 28))
	f.ready_actor(actor)
	actor.stats.current_hp = 30
	var r: Dictionary = await f.activate(actor, self)
	var named := ""
	for decision in r.decisions:
		if String(decision.get("movement_profile", "None")) != "None":
			named = String(decision.movement_profile)
	check(named.contains("Defensive") and named.contains("badly hurt"), "A hurt unit's movement decision says it used the Defensive profile and why (%s)" % named)
	await f.dispose(self)
