extends SceneTree
## Milestone 05 step 5: hard constraints are explicit. An attractive score cannot make an illegal
## action legal, rejections carry the shared query's own reason and code, and the AI and the
## player's UI agree because both read the same authoritative queries.
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
	Engine.time_scale = 12.0
	await _illegal_target_rejection_matches_the_query()
	await _wait_reason_when_no_move_is_legal()
	await _wait_reason_when_moves_exist_but_none_is_taken()
	await _transient_engine_state_is_not_a_reason()
	await _blocked_route_is_named()
	await _one_ap_never_commits_a_two_ap_plan()
	await _squad_commitments_are_vetoes_and_crowding_is_soft()
	Engine.time_scale = 1.0
	print("AI hard constraints: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

func _setup(enemies := 1, allies := 0, flag := false):
	var f := Fixture.new()
	await f.setup(self, 1, enemies, allies, null, AIDifficultyPolicy.Tier.HARD, [], flag)
	return f

func _prepare(f, actor: TacticalUnit) -> AIController:
	var ai: AIController = f.ai_of(actor)
	f.act_as(actor)
	ai._ensure_policy()
	ai._squad_context = f.battle.get_squad_context(actor)
	ai.current_mission_intent = ai._get_ai_mission_intent()
	return ai

## A target the shared Attack query rejects is recorded with that query's reason and code, and is
## never chosen, whatever the other candidate scores.
func _illegal_target_rejection_matches_the_query() -> void:
	var f = await _setup(2)
	var actor: TacticalUnit = f.turns.player_units[0]
	var near: TacticalUnit = f.turns.enemy_units[0]
	var far: TacticalUnit = f.turns.enemy_units[1]
	f.place(actor, Vector3i(5, 0, 10)); f.place(near, Vector3i(10, 0, 10)); f.place(far, Vector3i(22, 0, 10))
	f.ready_actor(actor)
	var ai := _prepare(f, actor)
	var far_query: AttackQueryResult = f.battle.query_attack(actor, far)
	check(not far_query.is_legal(), "Setup: the distant hostile is not a legal target")
	var chosen: TacticalUnit = ai._find_attack_target()
	check(chosen == near, "The only legal target is chosen")
	var rejected: AITargetCandidate = null
	for candidate in ai._last_target_candidates:
		if candidate.target == String(far.name): rejected = candidate
	check(rejected != null and rejected.is_rejected(), "The illegal target is recorded as rejected")
	if rejected != null:
		check(rejected.code == String(far_query.validation.code), "The rejection code is the shared query's code (%s vs %s)" % [rejected.code, far_query.validation.code])
		check(rejected.reason == far_query.reason, "The rejection reason is the shared query's reason (%s)" % rejected.reason)
		check(not rejected.chosen, "A rejected target is never marked chosen")
	await f.dispose(self)

## With no action points no move is legal. The wait reason says so using the shared Move query's
## own message, instead of the generic "no reachable legal destination".
func _wait_reason_when_no_move_is_legal() -> void:
	var f = await _setup()
	var actor: TacticalUnit = f.turns.player_units[0]
	f.place(actor, Vector3i(5, 0, 10)); f.place(f.turns.enemy_units[0], Vector3i(20, 0, 10))
	f.ready_actor(actor, 0, 4)
	var ai := _prepare(f, actor)
	var query: MoveQueryResult = f.battle.query_move(actor)
	check(not query.is_legal(), "Setup: with no AP no move is legal")
	var reason: String = ai._movement_wait_reason("Test.")
	check(reason.contains(String(query.validation.message)), "The reason carries the Move query's message (%s | %s)" % [reason, query.validation.message])
	check(reason.contains("no legal destination") and not reason.contains("no reachable legal destination"), "The reason says no move is legal (%s)" % reason)
	await f.dispose(self)

## Legal moves exist, so the reason must not claim otherwise: it states how many and that none was worth taking.
func _wait_reason_when_moves_exist_but_none_is_taken() -> void:
	var f = await _setup()
	var actor: TacticalUnit = f.turns.player_units[0]
	f.place(actor, Vector3i(5, 0, 10)); f.place(f.turns.enemy_units[0], Vector3i(20, 0, 10))
	f.ready_actor(actor)
	var ai := _prepare(f, actor)
	var legal: Array[Vector3i] = f.legal_moves(actor)
	check(not legal.is_empty(), "Setup: legal moves exist")
	ai._last_position_candidates.clear()
	var reason: String = ai._movement_wait_reason("Test.")
	check(reason.contains("%d legal destinations" % legal.size()), "The reason states the real number of legal destinations (%s, expected %d)" % [reason, legal.size()])
	await f.dispose(self)

## An ally standing in a one-cell corridor blocks the route; the explanation names the ally.
func _blocked_route_is_named() -> void:
	var f = await _setup(1, 1, true)
	var actor: TacticalUnit = f.turns.player_units[0]
	var ally: TacticalUnit = f.turns.allied_units[0]
	var enemy: TacticalUnit = f.turns.enemy_units[0]
	f.wall_band(10, 14, 28)
	f.place(actor, Vector3i(3, 0, 28)); f.place(ally, Vector3i(12, 0, 28)); f.place(enemy, Vector3i(28, 0, 28))
	f.ready_actor(actor)
	var ai := _prepare(f, actor)
	var moved: bool = await ai._move_toward(enemy)
	check(not moved, "The unit cannot pass the ally")
	check(ai._route_block_note.contains(String(ally.name)), "The route note names the ally (%s)" % ai._route_block_note)
	check(ai._movement_wait_reason("Test.").contains(ai._route_block_note), "The wait reason includes the route note")
	# With the ally gone the note must not linger.
	f.place(ally, Vector3i(3, 0, 20))
	await ai._move_toward(enemy)
	check(ai._route_block_note.is_empty() or not ai._route_block_note.contains(String(ally.name)), "A stale blocker is not reported once it has moved away (%s)" % ai._route_block_note)
	await f.dispose(self)

## An Aim plan needs two action points. With one, the AI must not start it: it attacks or does something else legal.
func _one_ap_never_commits_a_two_ap_plan() -> void:
	var f = await _setup()
	var actor: TacticalUnit = f.turns.player_units[0]
	var enemy: TacticalUnit = f.turns.enemy_units[0]
	f.place(actor, Vector3i(5, 0, 10)); f.place(enemy, Vector3i(14, 0, 10))
	f.ready_actor(actor, 1, 4)
	var r: Dictionary = await f.activate(actor, self)
	check(r.rejected.is_empty(), "No action is rejected by the authoritative service with one AP")
	check(not ("aim" in r.committed and r.ap_spent > 1), "One AP never pays for an Aim plan (committed %s, AP spent %d)" % [r.committed, r.ap_spent])
	check(r.ap_spent <= 1, "Spending stays within the single AP (%d)" % r.ap_spent)
	await f.dispose(self)

## An ally's exact destination and an escort's corridor are forbidden, with the owner named. Being beside
## an ally's destination is only a score penalty. The scorer enforces the veto whatever the other terms say.
func _squad_commitments_are_vetoes_and_crowding_is_soft() -> void:
	var f = await _setup(1, 1)
	var actor: TacticalUnit = f.turns.player_units[0]
	var ally: TacticalUnit = f.turns.allied_units[0]
	var enemy: TacticalUnit = f.turns.enemy_units[0]
	f.place(actor, Vector3i(5, 0, 10)); f.place(ally, Vector3i(6, 0, 12)); f.place(enemy, Vector3i(20, 0, 10))
	var ai := _prepare(f, actor)
	var ally_id := String(ally.tactical_id if not ally.tactical_id.is_empty() else StringName(ally.name))
	var context := SquadContext.new()
	context.begin_round(1)
	var held := Vector3i(8, 0, 10)
	var beside := Vector3i(8, 0, 11)
	var elsewhere := Vector3i(9, 0, 9)
	context.reserve_destination(ally, held)
	check(context.block_reason(actor, held).contains(ally_id), "The held destination is forbidden and names its owner (%s)" % context.block_reason(actor, held))
	check(context.destination_adjustment(actor, held) == SquadContext.HARD_BLOCK, "A held destination keeps the hard-block value")
	check(context.block_reason(ally, held).is_empty(), "The owner may use its own destination")
	check(context.block_reason(actor, beside).is_empty(), "A cell beside a held destination is not forbidden")
	check(context.crowding_adjustment(actor, beside) == SquadContext.CROWDING_PENALTY and context.destination_adjustment(actor, beside) == SquadContext.CROWDING_PENALTY, "A cell beside a held destination is only discouraged")
	check(context.crowding_adjustment(actor, elsewhere) == 0.0 and context.block_reason(actor, elsewhere).is_empty(), "An unrelated cell is neither forbidden nor discouraged")
	var policy: AIDifficultyPolicy = ai._policy
	var hostiles: Array[TacticalUnit] = [enemy]
	var start := Vector3i(5, 0, 10)
	var blocked_score: Dictionary = AIPositionScorer.evaluate(actor, held, start, Vector3i(-1, -1, -1), 50.0, [AIMovementProfiles.OBJECTIVE_ROUTE], hostiles, f.grid, policy, context)
	check(is_inf(float(blocked_score.total)) and float(blocked_score.total) < 0.0, "No score can make a held destination attractive (total %s)" % str(blocked_score.total))
	check(String(blocked_score.summary).contains(ally_id), "The rejection names the owner (%s)" % blocked_score.summary)
	var soft_score: Dictionary = AIPositionScorer.evaluate(actor, beside, start, Vector3i(-1, -1, -1), 50.0, [AIMovementProfiles.OBJECTIVE_ROUTE], hostiles, f.grid, policy, context)
	check(is_finite(float(soft_score.total)) and float(soft_score.squad) < 0.0, "Crowding lowers a score without removing the option (squad %s)" % str(soft_score.squad))
	context.reserve_corridor(ally, {elsewhere: true})
	check(context.block_reason(actor, elsewhere).begins_with("Corridor reserved by ") and context.block_reason(actor, elsewhere).contains(ally_id), "A carrier corridor is forbidden to others and names its owner (%s)" % context.block_reason(actor, elsewhere))
	check(context.block_reason(ally, elsewhere).is_empty(), "The corridor's owner may use it")
	await f.dispose(self)

## A move query refused only because an action is still being presented describes the moment, not the
## tactical situation. The wait reason must not present it as the cause.
func _transient_engine_state_is_not_a_reason() -> void:
	var f = await _setup()
	var actor: TacticalUnit = f.turns.player_units[0]
	f.place(actor, Vector3i(5, 0, 10)); f.place(f.turns.enemy_units[0], Vector3i(20, 0, 10))
	f.ready_actor(actor)
	var ai := _prepare(f, actor)
	f.battle.action_service.is_busy = true
	var query: MoveQueryResult = f.battle.query_move(actor)
	check(not query.is_legal() and query.validation.code == &"action_busy", "Setup: a busy action service refuses the query (%s)" % query.validation.code)
	var reason: String = ai._movement_wait_reason("Test.")
	check(not reason.contains("resolved or presented") and not reason.contains("no legal destination"), "A busy engine is not given as the reason (%s)" % reason)
	check(reason.contains("no destination was worth taking"), "The reason says nothing was worth taking (%s)" % reason)
	f.battle.action_service.is_busy = false
	await f.dispose(self)
