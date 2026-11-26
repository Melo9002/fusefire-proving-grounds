extends SceneTree
## Milestone 05 step 8 on the real battle: the Tactical Test Range and the controlled fixture, real AI controllers, real defeats, real carrier state.
## It proves the commitments follow what actually happens (a defeat, a moved exit, a carrier that walks its lane, an ended objective) and that the
## preferences they feed stay deliberate: spreading fire when the target is healthy, finishing when it is not. Legality is asserted strictly;
## preferences as properties, never one arbitrary tile.

const Fixture = preload("res://tests/support/ai_scenario_fixture.gd")

var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	Engine.time_scale = 12.0
	await _defeat_releases_at_once()
	await _focus_prefers_a_finisher_but_still_spreads()
	await _carrier_lane_follows_the_carrier()
	await _committed_route_is_replanned_when_the_map_changes()
	await _objective_completion_releases_handlers()
	await _reservations_never_make_a_cell_legal()
	Engine.time_scale = 1.0
	print("squad_commitment_scenarios_test: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

func _context_of(f, unit: TacticalUnit) -> SquadContext:
	return f.battle.peek_squad_context(unit)

## A real defeat (stats, then the battle's own handler) ends the actor's commitments and everything aimed at it before anything else reads them.
func _defeat_releases_at_once() -> void:
	var f := Fixture.new()
	await f.setup(self, 2, 2, 0, null, AIDifficultyPolicy.Tier.HARD)
	var first: TacticalUnit = f.turns.player_units[0]
	var second: TacticalUnit = f.turns.player_units[1]
	var foe: TacticalUnit = f.turns.enemy_units[0]
	var other_foe: TacticalUnit = f.turns.enemy_units[1]
	f.place(first, Vector3i(5, 0, 10)); f.place(second, Vector3i(5, 0, 12))
	f.place(foe, Vector3i(15, 0, 10)); f.place(other_foe, Vector3i(15, 0, 12))
	var team: SquadContext = f.battle.get_squad_context(first)
	var enemy_team: SquadContext = f.battle.get_squad_context(foe)
	team.reserve_destination(first, Vector3i(5, 0, 10))
	team.reserve_destination(second, Vector3i(5, 0, 12))
	team.reserve_target(first, foe)
	team.reserve_target(second, foe)
	team.reserve_objective(first, &"kill_all")
	enemy_team.reserve_destination(other_foe, Vector3i(15, 0, 12))
	check(team.claim_count() == 5 and enemy_team.claim_count() == 1, "Setup: the player side holds five commitments and the enemy side one")
	first.stats.take_damage(9999)
	await process_frame
	var after: SquadContext = _context_of(f, second)
	check(not after.reserved_destinations.has(Vector3i(5, 0, 10)) and after.objective_handlers.get(&"kill_all", []).is_empty(), "A real defeat releases the actor's destination and objective at once (nothing asked for a new squad context)")
	check(after.focus_count(second, foe) == 0 and after.intended_targets.get(foe.tactical_id, 0) == 1, "and removes only its own fire on the target (the other ally's remains)")
	check(after.reserved_destinations.has(Vector3i(5, 0, 12)), "Control: the surviving ally keeps its destination")
	check(_context_of(f, other_foe).reserved_destinations.has(Vector3i(15, 0, 12)), "Control: the other side's commitments are untouched")
	foe.stats.take_damage(9999)
	await process_frame
	check(_context_of(f, second).claim_count() == 1 and _context_of(f, second).focus_count(second, foe) == 0, "A real defeat of the target releases the fire aimed at it and keeps the shooter's destination")
	var reasons: Array = _context_of(f, second).expiry_log.map(func(e: Dictionary) -> String: return String(e.reason))
	check(reasons.any(func(r: String) -> bool: return r.contains("defeated")), "and the record names the defeat")
	await f.dispose(self)

## The scored decision: a wounded target allies are already firing on is still the finisher's best shot; a healthy one is spread away from.
func _focus_prefers_a_finisher_but_still_spreads() -> void:
	var f := Fixture.new()
	await f.setup(self, 3, 2, 0, null, AIDifficultyPolicy.Tier.HARD)
	var actor: TacticalUnit = f.turns.player_units[0]
	var ally_a: TacticalUnit = f.turns.player_units[1]
	var ally_b: TacticalUnit = f.turns.player_units[2]
	var target: TacticalUnit = f.turns.enemy_units[0]
	var rival: TacticalUnit = f.turns.enemy_units[1]
	f.place(actor, Vector3i(5, 0, 10)); f.place(ally_a, Vector3i(5, 0, 6)); f.place(ally_b, Vector3i(5, 0, 14))
	f.place(target, Vector3i(10, 0, 8)); f.place(rival, Vector3i(10, 0, 12))
	f.ready_actor(actor, 1)
	var squad: SquadContext = f.battle.get_squad_context(actor)
	# Healthy and equal: two allies already on the target. The actor spreads to the other.
	squad.reserve_target(ally_a, target)
	squad.reserve_target(ally_b, target)
	check(f.choose_target(actor) == rival, "Two allies on a healthy target: the actor shoots the other hostile (spreading is a preference)")
	var ai: AIController = f.ai_of(actor)
	var healthy_score: Dictionary = AITargetScorer.evaluate(actor, target, ai._get_friendly_units(), ai.current_mission_intent, ai._objective_manager, f.grid, ai._policy, squad, f.battle.query_attack(actor, target))
	check(healthy_score.focus < 0.0 and healthy_score.focus_count == 2, "Control: the healthy target carries the full penalty for both allies (%.1f)" % healthy_score.focus)
	# The same two allies on a target one hit from death, against a rival that is almost as good a kill (one hit from death too, but behind low cover: 80% to hit).
	# The rival's extra missing HP keeps this a genuine near-tie after Hard discounts wounds on less reliable shots.
	target.stats.current_hp = 25
	rival.stats.max_hp = 116
	rival.stats.current_hp = 25
	f.set_cover(Vector3i(9, 0, 12), MapCellData.CoverType.LOW, 0.9)
	var evaluate := func(candidate: TacticalUnit) -> Dictionary:
		return AITargetScorer.evaluate(actor, candidate, ai._get_friendly_units(), ai.current_mission_intent, ai._objective_manager, f.grid, ai._policy, squad, f.battle.query_attack(actor, candidate))
	var wounded_score: Dictionary = evaluate.call(target)
	var rival_score: Dictionary = evaluate.call(rival)
	check(wounded_score.kill_chance > rival_score.kill_chance and wounded_score.kill_chance >= 0.99, "Setup: the target is a certain kill (%d%%) and the rival a likely one (%d%%)" % [wounded_score.kill_chance * 100.0, rival_score.kill_chance * 100.0])
	check(wounded_score.focus > healthy_score.focus and absf(wounded_score.focus) < 1.0, "A certain finisher costs nothing to join (%.1f, against %.1f for a healthy target)" % [wounded_score.focus, healthy_score.focus])
	# What the earlier fixed penalty would have done with the same facts: two allies at 15 each, whatever the kill chance.
	var old_total: float = wounded_score.total - wounded_score.focus + -SquadContext.FOCUS_PENALTY * 2.0 * ai._policy.focus_penalty_weight
	check(old_total < rival_score.total and wounded_score.total > rival_score.total, "Setup: this is a near-tie the fixed penalty used to lose (old %.1f < rival %.1f < now %.1f)" % [old_total, rival_score.total, wounded_score.total])
	check(f.choose_target(actor) == target, "A certain kill is taken even with two allies already on it, over the 80% alternative")
	# Control: with nobody on it the finisher is chosen too (so the claims did not create the preference).
	squad.begin_round(squad.round_number + 1)
	check(f.choose_target(actor) == target, "Control: with no allied fire at all the finisher is also chosen")
	await f.dispose(self)

## A carrier that walks its lane gives back the cells behind it; a moved exit or a displaced carrier ends the lane; an escort follows the live lane.
func _carrier_lane_follows_the_carrier() -> void:
	var f := Fixture.new()
	await f.setup(self, 1, 1, 1, MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.RESCUE, 1), AIDifficultyPolicy.Tier.HARD, [], true)
	var escort: TacticalUnit = f.turns.player_units[0]
	var carrier: TacticalUnit = f.turns.allied_units[0]
	var casualty := f.level.get_node("Units/ObjectiveUnits/RescueTarget") as TacticalUnit
	var exit := Vector3i(1, 0, 23)
	var zone: Array[Vector3i] = [exit]
	f.grid.map_data.set_objective_zone(&"extract", zone)
	var start := Vector3i(1, 0, 16)
	f.place(carrier, start)
	f.place(casualty, f.free_cell_near(casualty, Vector3i(6, 0, 16), 3))
	f.place(escort, f.free_cell_near(escort, Vector3i(6, 0, 18), 4))
	carrier.carried_unit = casualty   # the carrier predicate only; no action is submitted
	var squad: SquadContext = f.battle.get_squad_context(carrier)
	var lane: Dictionary = (await f.ai_of(carrier)._carrier_route(carrier))
	check(lane.size() >= 4 and lane.keys()[0] == start and lane.keys()[-1] == exit, "Setup: the carrier's lane runs from where it stands to the exit (%d cells)" % lane.size())
	squad.reserve_corridor(carrier, lane)
	var lane_cells: Array = lane.keys()
	var ahead: Vector3i = lane_cells[lane_cells.size() - 2]
	check(not squad.block_reason(escort, ahead).is_empty(), "The way ahead of the carrier is forbidden to its escort")
	# The carrier steps along its lane.
	var step: Vector3i = lane_cells[2]
	f.place(carrier, step)
	squad = f.battle.get_squad_context(escort)
	check(squad.reserved_corridor.keys()[0] == step and not squad.reserved_corridor.has(start), "After the carrier moves, the cells it passed are no longer reserved")
	check(squad.block_reason(escort, start).is_empty() and not squad.block_reason(escort, ahead).is_empty(), "so the escort may use them, and the way ahead stays held")
	check(squad.corridor_owner == SquadContext._actor_id(carrier), "and the lane is still the carrier's")
	# The escort's own view of the lane is the live one, not a stale copy.
	var escort_view: Dictionary = (await f.ai_of(escort)._carrier_route(carrier))
	check(escort_view.keys()[0] == step, "The escort reads the trimmed lane, starting at the carrier's cell")
	# The exit moves.
	var moved_exit := Vector3i(8, 0, 20)
	var new_zone: Array[Vector3i] = [moved_exit]
	f.grid.map_data.set_objective_zone(&"extract", new_zone)
	squad = f.battle.get_squad_context(escort)
	check(squad.reserved_corridor.is_empty() and squad.corridor_owner.is_empty(), "A moved exit ends the old lane at the next squad lookup")
	var new_lane: Dictionary = (await f.ai_of(escort)._carrier_route(carrier))
	check(new_lane.is_empty() or new_lane.keys()[-1] == moved_exit, "and the escort's route to the carrier's exit is the new one")
	# Control: the exit unchanged keeps the lane.
	f.grid.map_data.set_objective_zone(&"extract", zone)
	squad = f.battle.get_squad_context(carrier)
	squad.reserve_corridor(carrier, (await f.ai_of(carrier)._carrier_route(carrier)))
	squad = f.battle.get_squad_context(escort)
	check(not squad.reserved_corridor.is_empty(), "Control: with the exit where it was the lane is kept")
	# The carrier is displaced off the lane.
	f.place(carrier, Vector3i(1, 0, 14))
	squad = f.battle.get_squad_context(escort)
	check(squad.reserved_corridor.is_empty(), "A carrier displaced off its lane no longer holds it")
	# The carrier is defeated.
	f.place(carrier, step)
	squad = f.battle.get_squad_context(carrier)
	squad.reserve_corridor(carrier, (await f.ai_of(carrier)._carrier_route(carrier)))
	check(not f.battle.peek_squad_context(carrier).reserved_corridor.is_empty(), "Setup: a lane is held again")
	carrier.carried_unit = null
	carrier.stats.take_damage(9999)
	await process_frame
	check(f.battle.peek_squad_context(escort).reserved_corridor.is_empty() and f.battle.peek_squad_context(escort).corridor_owner.is_empty(), "A defeated carrier's lane is gone at once")
	await f.dispose(self)

## The route a carrier committed to is only as good as the map it was planned on: closing a cell on it makes the carrier plan again.
func _committed_route_is_replanned_when_the_map_changes() -> void:
	var f := Fixture.new()
	await f.setup(self, 1, 1, 1, MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.RESCUE, 1), AIDifficultyPolicy.Tier.HARD, [], true)
	var carrier: TacticalUnit = f.turns.allied_units[0]
	var casualty := f.level.get_node("Units/ObjectiveUnits/RescueTarget") as TacticalUnit
	var exit := Vector3i(1, 0, 23)
	var zone: Array[Vector3i] = [exit]
	f.grid.map_data.set_objective_zone(&"extract", zone)
	f.place(carrier, Vector3i(1, 0, 16))
	f.place(casualty, f.free_cell_near(casualty, Vector3i(6, 0, 16), 3))
	carrier.carried_unit = casualty
	var ai: AIController = f.ai_of(carrier)
	var first: Array = (await ai._carrier_route(carrier)).keys()
	check(first.size() >= 4, "Setup: the carrier commits to a route of %d cells" % first.size())
	check((await ai._carrier_route(carrier)).keys() == first and ai._committed_carrier_route.size() == first.size(), "Control: asked again on an unchanged map, it keeps the committed route")
	# Something other than a unit changes the map: a cell in the middle of the route closes.
	var closed: Vector3i = first[first.size() / 2]
	f.set_walls([closed])
	var second: Array = (await ai._carrier_route(carrier)).keys()
	check(not second.has(closed), "A cell that closed on the route is not in the route the carrier plans next (%s)" % str(closed))
	check(second.is_empty() or second[-1] == exit, "and any route it does plan still reaches the exit")
	check(ai._committed_route_graph == f.battle.pathfinder.graph_revision(), "and the new route is committed against the current map")
	# Units standing about do not count as the map changing.
	var after_walls: Array = ai._committed_carrier_route.duplicate()
	f.place(casualty, f.free_cell_near(casualty, Vector3i(7, 0, 16), 3))
	(await ai._carrier_route(carrier))
	check(ai._committed_carrier_route == after_walls, "Control: moving a unit leaves the committed route alone")
	carrier.carried_unit = null
	await f.dispose(self)

## A real mission objective that completes drops its handlers; others stay.
func _objective_completion_releases_handlers() -> void:
	var f := Fixture.new()
	await f.setup(self, 2, 1, 0, MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, 1), AIDifficultyPolicy.Tier.HARD)
	var manager: ObjectiveManager = f.battle._objective_manager
	check(manager != null and manager.get_objectives().size() >= 1, "Setup: the mission has an objective manager")
	if manager == null:
		await f.dispose(self)
		return
	var first: TacticalUnit = f.turns.player_units[0]
	var second: TacticalUnit = f.turns.player_units[1]
	var squad: SquadContext = f.battle.get_squad_context(first)
	var objective_id: StringName = manager.get_objectives()[0].definition.objective_id
	squad.reserve_objective(first, objective_id)
	squad.reserve_objective(second, &"some_other_objective")
	manager.objective_completed.emit(manager.get_objectives()[0])
	var after: SquadContext = f.battle.peek_squad_context(first)
	check(after.objective_handlers.get(objective_id, []).is_empty(), "A completed objective's handlers are released")
	check(after.objective_handlers.get(&"some_other_objective", []).size() == 1, "Control: another objective's handler is kept")
	await f.dispose(self)

## No commitment can make an illegal cell legal or a legal cell unreachable beyond its own owner's claim: a reserved cell is vetoed only for other actors.
func _reservations_never_make_a_cell_legal() -> void:
	var f := Fixture.new()
	await f.setup(self, 2, 1, 0, null, AIDifficultyPolicy.Tier.HARD)
	var actor: TacticalUnit = f.turns.player_units[0]
	var ally: TacticalUnit = f.turns.player_units[1]
	f.place(actor, Vector3i(5, 0, 10)); f.place(ally, Vector3i(5, 0, 14)); f.place(f.turns.enemy_units[0], Vector3i(20, 0, 10))
	f.ready_actor(actor)
	var legal_before: Array[Vector3i] = f.legal_moves(actor)
	var squad: SquadContext = f.battle.get_squad_context(actor)
	var held := Vector3i(6, 0, 10)
	squad.reserve_destination(ally, held)
	check(f.legal_moves(actor) == legal_before, "A squad reservation does not change what the shared Move query allows")
	check(squad.block_reason(actor, held).contains(String(ally.tactical_id)), "but it vetoes that cell for the other actor, naming the owner")
	check(squad.block_reason(ally, held).is_empty(), "and never for the owner itself")
	f.place(ally, Vector3i(7, 0, 14))
	squad = f.battle.get_squad_context(actor)
	check(squad.block_reason(actor, held).is_empty(), "Once the owner is no longer there the cell is free again")
	await f.dispose(self)
