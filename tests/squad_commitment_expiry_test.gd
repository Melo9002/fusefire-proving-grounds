extends SceneTree
## Milestone 05 step 8: squad commitments end when their basis ends. Pure SquadContext checks (no battle): lifetimes, death, vanished targets,
## changed objectives, a carrier's lane (trimmed, abandoned, retargeted), the finishing-aware focus preference and the expiry record.
## Every release path has a control that proves the commitment is held while its basis still holds, so a release is never the default.

var failures := 0
var checks := 0
var _made: Array[TacticalUnit] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _unit(id: StringName, cell := Vector3i.ZERO) -> TacticalUnit:
	var unit := TacticalUnit.new()
	unit.name = String(id).capitalize()
	unit.tactical_id = id
	unit.stats = UnitStats.new()
	unit.add_child(unit.stats)
	unit.grid_position = cell
	_made.append(unit)
	return unit

func _lane(cells: Array[Vector3i]) -> Dictionary:
	var lane := {}
	for cell in cells:
		lane[cell] = true
	return lane

func _reasons(context: SquadContext) -> Array:
	return context.expiry_log.map(func(entry: Dictionary) -> String: return String(entry.reason))

func _run() -> void:
	_lifetime()
	_death_and_vanished_targets()
	_objectives()
	_corridor()
	_focus()
	_expiry_record()
	_determinism()
	for unit in _made:
		unit.free()
	print("squad_commitment_expiry_test: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

## Claims belong to one round, whatever else happens.
func _lifetime() -> void:
	var context := SquadContext.new()
	var first := _unit(&"a1", Vector3i(4, 0, 4))
	var second := _unit(&"a2")
	var foe := _unit(&"e1")
	context.begin_round(3)
	context.reserve_destination(first, Vector3i(4, 0, 4))
	context.reserve_target(first, foe)
	context.reserve_objective(first, &"hold")
	check(context.claim_count() == 3 and SquadContext.LIFETIME_ROUNDS == 1, "A destination, a target and an objective are three commitments with a one-round lifetime")
	context.revalidate([first, second, foe])
	check(context.claim_count() == 3, "Control: nothing is released while owner, target and cell are all still good")
	context.begin_round(3)
	check(context.claim_count() == 3, "Control: asking for the same round again does not expire anything")
	context.begin_round(4)
	check(context.claim_count() == 0 and context.reserved_destinations.is_empty() and context.objective_handlers.is_empty(), "A new round releases every commitment")
	check(_reasons(context).any(func(r: String) -> bool: return r.contains("round 3 ended") and r.contains("3 commitment")), "and the record says the round ended and how many it released")

## An actor dying or leaving, and a target dying or leaving, release exactly what depended on them.
func _death_and_vanished_targets() -> void:
	var context := SquadContext.new()
	var owner := _unit(&"owner", Vector3i(2, 0, 2))
	var bystander := _unit(&"bystander", Vector3i(6, 0, 6))
	var foe := _unit(&"foe")
	var other_foe := _unit(&"other_foe")
	context.begin_round(1)
	context.reserve_destination(owner, Vector3i(2, 0, 2))
	context.reserve_destination(bystander, Vector3i(6, 0, 6))
	context.reserve_target(owner, foe)
	context.reserve_target(bystander, foe)
	context.reserve_target(bystander, other_foe) # replaces its claim on foe
	context.reserve_objective(owner, &"rescue")
	context.reserve_corridor(owner, _lane([Vector3i(2, 0, 2), Vector3i(3, 0, 2)]))
	# Eager release at the moment of death.
	context.release_unit(&"owner", "defeated")
	check(not context.reserved_destinations.has(Vector3i(2, 0, 2)) and context.reserved_corridor.is_empty() and context.corridor_owner.is_empty(), "A defeated owner's destination and lane go at once")
	check(context.objective_handlers.get(&"rescue", []).is_empty(), "and its objective handling")
	check(context.target_adjustment(bystander, foe) == 0.0 and context.intended_targets.get(&"foe", 0) == 0, "and its focus on a target")
	check(context.reserved_destinations.has(Vector3i(6, 0, 6)), "Control: another actor's destination is untouched")
	check(context.target_adjustment(owner, other_foe) == -SquadContext.FOCUS_PENALTY, "Control: the bystander's current target claim is untouched")
	var held := context.claim_count()
	context.release_unit(&"owner", "defeated")
	check(context.claim_count() == held, "Releasing the same actor twice changes nothing")
	# A defeated target releases the claims aimed at it, eagerly...
	context.release_unit(&"other_foe", "defeated")
	check(context.target_adjustment(owner, other_foe) == 0.0 and context.claim_count() == 1, "A defeated target releases the claim aimed at it, and only that")
	# ...and lazily, from the roster, when nothing announced it.
	var lazy := SquadContext.new()
	var shooter := _unit(&"shooter", Vector3i(1, 0, 1))
	var quarry := _unit(&"quarry")
	lazy.begin_round(1)
	lazy.reserve_target(shooter, quarry)
	lazy.revalidate([shooter, quarry])
	check(lazy.claim_count() == 1, "Control: a living target keeps its claim")
	quarry.stats.is_defeated = true
	lazy.revalidate([shooter, quarry])
	check(lazy.claim_count() == 0 and _reasons(lazy).any(func(r: String) -> bool: return r.contains("defeated")), "A target defeated without announcement is released at the next check, with the reason")
	var gone := SquadContext.new()
	gone.begin_round(1)
	gone.reserve_target(shooter, quarry)
	quarry.stats.is_defeated = false
	gone.revalidate([shooter])
	check(gone.claim_count() == 0 and _reasons(gone).any(func(r: String) -> bool: return r.contains("left the battle")), "A target that left the roster (extracted, removed) is released, and not called defeated")
	# A destination whose owner has moved on is not a commitment.
	var mover := _unit(&"mover", Vector3i(5, 0, 5))
	var travel := SquadContext.new()
	travel.begin_round(1)
	travel.reserve_destination(mover, Vector3i(5, 0, 5))
	travel.revalidate([mover])
	check(travel.reserved_destinations.has(Vector3i(5, 0, 5)), "Control: a destination its owner still stands on is held")
	mover.grid_position = Vector3i(5, 0, 8)
	travel.revalidate([mover])
	check(travel.reserved_destinations.is_empty(), "A destination its owner has left is released")

## An objective that ends has no handlers; one that continues keeps them.
func _objectives() -> void:
	var context := SquadContext.new()
	var a := _unit(&"oa")
	var b := _unit(&"ob")
	context.begin_round(1)
	check(context.reserve_objective(a, &"rescue") == 0 and context.reserve_objective(b, &"rescue") == 1, "A later handler sees the earlier ones")
	check(context.reserve_objective(a, &"rescue") == 1, "Asking again does not count the asker as another handler")
	context.reserve_objective(b, &"extract")
	context.release_objective(&"rescue")
	check(not context.objective_handlers.has(&"rescue") and context.objective_handlers[&"extract"] == [&"ob"], "A completed objective drops its handlers and no other objective's")
	check(context.reserve_objective(a, &"rescue") == 0, "A handler can take an objective up again afterwards")
	context.release_objective(&"never_handled")
	check(context.claim_count() == 2, "Releasing an objective nobody handles is a no-op")

## The carrier's lane: trimmed behind it, dropped when it leaves or retargets, never kept for a lane that is not there.
func _corridor() -> void:
	var lane_cells: Array[Vector3i] = [Vector3i(1, 0, 1), Vector3i(2, 0, 1), Vector3i(3, 0, 1), Vector3i(4, 0, 1), Vector3i(5, 0, 1)]
	var exit_set := {Vector3i(5, 0, 1): true}
	var carrier := _unit(&"carrier", lane_cells[0])
	carrier.carried_unit = _unit(&"casualty")
	var escort := _unit(&"escort", Vector3i(9, 0, 9))
	var context := SquadContext.new()
	context.begin_round(1)
	context.reserve_corridor(carrier, _lane(lane_cells))
	check(context.block_reason(escort, lane_cells[2]).contains("carrier"), "Setup: an escort may not take a lane cell")
	context.revalidate([carrier, escort], exit_set)
	check(context.reserved_corridor.size() == 5 and context.corridor_owner == &"carrier", "Control: a carrier at the head of its lane, with the exit unchanged, keeps all five cells")
	# Walked part of the way.
	carrier.grid_position = lane_cells[2]
	context.revalidate([carrier, escort], exit_set)
	check(context.reserved_corridor.keys() == [lane_cells[2], lane_cells[3], lane_cells[4]], "Cells the carrier has passed are given back; its own cell and the way ahead stay")
	check(context.block_reason(escort, lane_cells[0]).is_empty() and context.block_reason(escort, lane_cells[1]).is_empty(), "so an escort may stand where the carrier has been")
	check(not context.block_reason(escort, lane_cells[3]).is_empty(), "while the way ahead stays forbidden to it")
	check(context.corridor_owner == &"carrier", "and the lane still belongs to the carrier")
	# Idempotent.
	context.revalidate([carrier, escort], exit_set)
	check(context.reserved_corridor.size() == 3, "Checking again changes nothing")
	# Retargeted exit.
	var retarget := SquadContext.new()
	retarget.begin_round(1)
	carrier.grid_position = lane_cells[0]
	retarget.reserve_corridor(carrier, _lane(lane_cells))
	retarget.revalidate([carrier, escort], {Vector3i(12, 0, 1): true})
	check(retarget.reserved_corridor.is_empty() and retarget.corridor_owner.is_empty(), "A lane that no longer ends in the extraction zone is released")
	check(_reasons(retarget).any(func(r: String) -> bool: return r.contains("extraction zone changed")), "and the record says the exit changed")
	var roster_only := SquadContext.new()
	roster_only.begin_round(1)
	roster_only.reserve_corridor(carrier, _lane(lane_cells))
	roster_only.prune([carrier, escort])
	check(roster_only.reserved_corridor.size() == 5, "Control: a roster-only check cannot know the exit changed, which is why the battle passes the zone")
	# Carrier displaced off the lane.
	var displaced := SquadContext.new()
	displaced.begin_round(1)
	displaced.reserve_corridor(carrier, _lane(lane_cells))
	carrier.grid_position = Vector3i(3, 0, 6)
	displaced.revalidate([carrier, escort], exit_set)
	check(displaced.reserved_corridor.is_empty() and displaced.corridor_owner.is_empty(), "A carrier that has left its lane no longer holds it")
	check(_reasons(displaced).any(func(r: String) -> bool: return r.contains("left the lane")), "and the record says so")
	# Put the casualty down.
	var dropped := SquadContext.new()
	dropped.begin_round(1)
	carrier.grid_position = lane_cells[0]
	dropped.reserve_corridor(carrier, _lane(lane_cells))
	var casualty := carrier.carried_unit
	carrier.carried_unit = null
	dropped.revalidate([carrier, escort], exit_set)
	check(dropped.reserved_corridor.is_empty(), "A carrier that put its casualty down holds no lane")
	carrier.carried_unit = casualty
	# Carrier killed.
	var killed := SquadContext.new()
	killed.begin_round(1)
	killed.reserve_corridor(carrier, _lane(lane_cells))
	killed.release_unit(&"carrier", "defeated")
	check(killed.reserved_corridor.is_empty() and killed.corridor_owner.is_empty(), "A carrier that is defeated releases its lane immediately")
	# A lane with nothing in it is not a commitment (a failed route).
	var failed := SquadContext.new()
	failed.begin_round(1)
	failed.reserve_corridor(carrier, {})
	check(failed.corridor_owner.is_empty() and failed.claim_count() == 0, "A route that could not be planned reserves nothing and names no owner")
	failed.reserve_corridor(carrier, _lane(lane_cells))
	failed.reserve_corridor(carrier, {})
	check(failed.reserved_corridor.is_empty() and failed.corridor_owner.is_empty(), "and replacing a lane with a failed route clears it")
	# A second carrier is not confused with the first.
	var other_carrier := _unit(&"carrier2", Vector3i(20, 0, 20))
	other_carrier.carried_unit = _unit(&"casualty2")
	var two := SquadContext.new()
	two.begin_round(1)
	two.reserve_corridor(carrier, _lane(lane_cells))
	two.revalidate([carrier, other_carrier, escort], exit_set)
	check(two.corridor_owner == &"carrier" and two.reserved_corridor.size() == 5, "Another carrier elsewhere does not disturb a lane")

## Focus fire and spreading are a preference that depends on whether the shot finishes the target.
func _focus() -> void:
	var context := SquadContext.new()
	var shooter := _unit(&"s1")
	var second := _unit(&"s2")
	var third := _unit(&"s3")
	var foe := _unit(&"foe2")
	context.begin_round(1)
	context.reserve_target(shooter, foe)
	context.reserve_target(second, foe)
	check(context.focus_count(third, foe) == 2 and context.focus_count(shooter, foe) == 1, "Focus counts allies already on a target, not the asker's own earlier shot")
	check(context.target_adjustment(third, foe) == -30.0, "Control: with no kill in prospect each ally on the target costs the full penalty (spreading out)")
	check(context.target_adjustment(third, foe, 0.0) == -30.0 and context.target_adjustment(third, foe, -1.0) == -30.0, "A zero or nonsensical kill chance changes nothing")
	check(is_equal_approx(context.target_adjustment(third, foe, 0.5), -15.0), "A coin-flip finisher halves the penalty")
	check(context.target_adjustment(third, foe, 1.0) == 0.0 and context.target_adjustment(third, foe, 2.0) == 0.0, "A certain kill costs nothing: finishing is not wasted fire")
	check(context.target_adjustment(third, foe, 0.5) > context.target_adjustment(third, foe, 0.25), "The penalty falls steadily as the kill gets likelier")
	check(context.target_adjustment(_unit(&"s4"), _unit(&"fresh")) == 0.0, "A target nobody has fired on has no focus effect")

## The record: bounded, ordered, and read-only evidence.
func _expiry_record() -> void:
	var context := SquadContext.new()
	var actor := _unit(&"logger", Vector3i(1, 0, 1))
	context.begin_round(1)
	for index in SquadContext.EXPIRY_LOG_LIMIT + 10:
		context.reserve_destination(actor, Vector3i(1, 0, 1))
		actor.grid_position = Vector3i(1, 0, 1)
		context.revalidate([actor])
		actor.grid_position = Vector3i(2, 0, 2)
		context.revalidate([actor])
	check(context.expiry_log.size() == SquadContext.EXPIRY_LOG_LIMIT, "The record is bounded (%d entries after %d releases)" % [context.expiry_log.size(), SquadContext.EXPIRY_LOG_LIMIT + 10])
	check(context.expiry_log.all(func(entry: Dictionary) -> bool: return entry.has("round") and entry.has("kind") and entry.has("owner") and entry.has("reason")), "and every entry names its round, kind, owner and reason")

## The same events give the same state, entry for entry.
func _determinism() -> void:
	var snapshots: Array = []
	for run in 2:
		var context := SquadContext.new()
		var carrier := _unit(&"dc", Vector3i(1, 0, 1))
		carrier.carried_unit = _unit(&"dcas")
		var foe := _unit(&"dfoe")
		context.begin_round(2)
		context.reserve_corridor(carrier, _lane([Vector3i(1, 0, 1), Vector3i(2, 0, 1), Vector3i(3, 0, 1)]))
		context.reserve_target(carrier, foe)
		carrier.grid_position = Vector3i(2, 0, 1)
		context.revalidate([carrier, foe], {Vector3i(3, 0, 1): true})
		context.release_unit(&"dfoe", "defeated")
		snapshots.append({"corridor": context.reserved_corridor.keys(), "claims": context.claim_count(), "reasons": _reasons(context)})
	check(snapshots[0] == snapshots[1], "The same sequence of events leaves the same commitments and the same record")
