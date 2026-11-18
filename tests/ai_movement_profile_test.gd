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
