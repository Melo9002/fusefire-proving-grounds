extends SceneTree

var failures := 0

func _initialize() -> void:
	var context := SquadContext.new()
	var first := TacticalUnit.new()
	first.name = "First"
	var second := TacticalUnit.new()
	second.name = "Second"
	var target := TacticalUnit.new()
	target.name = "Target"

	context.begin_round(1)
	context.reserve_destination(first, Vector3i(5, 0, 5))
	check(context.destination_adjustment(second, Vector3i(5, 0, 5)) <= -1000.0, "An ally's exact destination is unavailable")
	check(context.destination_adjustment(second, Vector3i(5, 0, 6)) == -12.0, "A neighboring reservation discourages crowding")
	context.reserve_target(first, target)
	check(context.target_adjustment(second, target) == -15.0, "Existing allied focus softly reduces target score")
	check(context.target_adjustment(first, target) == 0.0, "A unit does not penalize its own continuing target intent")
	check(context.reserve_objective(first, &"rescue") == 0, "The first objective handler has no duplication penalty")
	check(context.reserve_objective(second, &"rescue") == 1, "Later units see an existing objective handler")

	context.reserve_destination(first, Vector3i(7, 0, 5))
	check(not context.reserved_destinations.has(Vector3i(5, 0, 5)), "Replacing a destination releases the superseded tile")
	context.begin_unit(first)
	check(context.reserved_destinations.is_empty(), "Next activation leaves no orphan destination")
	context.begin_unit(first)
	check(context.reserved_destinations.is_empty(), "Repeated activation cleanup is idempotent")

	context.begin_round(2)
	check(context.reserved_destinations.is_empty() and context.intended_targets.is_empty() and context.objective_handlers.is_empty(), "Squad intentions reset for a new round")
	first.tactical_id = &"stable-first"
	second.tactical_id = &"stable-second"
	target.tactical_id = &"stable-target"
	for actor in [first, second, target]:
		actor.stats = UnitStats.new()
		actor.add_child(actor.stats)
	first.grid_position = Vector3i(8, 0, 8)
	context.reserve_destination(first, Vector3i(8, 0, 8))
	context.reserve_destination(second, Vector3i(8, 0, 8))
	check(context.reserved_destinations[Vector3i(8, 0, 8)] == &"stable-first", "Another actor cannot steal an exact reservation")
	context.reserve_target(first, target)
	context.reserve_objective(first, &"rescue")
	context.reserve_objective(first, &"extract")
	check(not context.objective_handlers[&"rescue"].has(&"stable-first"), "Changing objective releases the previous handler claim")
	context.reserve_objective(first, &"")
	check(context.objective_handlers[&"extract"].is_empty(), "No mission intent releases its handler")
	context.reserve_objective(first, &"extract")
	context.reserve_corridor(first, {Vector3i(9, 0, 8): true})
	first.name = "RenamedNode"
	check(context.destination_adjustment(first, Vector3i(8, 0, 8)) == 0 and context.target_adjustment(first, target) == 0, "Stable tactical identity survives a node rename")
	context.prune([first, second])
	check(context.reserved_destinations.has(Vector3i(8, 0, 8)), "Current live destination survives revalidation")
	check(context.target_adjustment(second, target) == 0, "Removed target releases focus")
	context.prune([second, target])
	check(context.reserved_destinations.is_empty() and context.reserved_corridor.is_empty() and context.objective_handlers[&"extract"].is_empty(), "Removed owner releases destination, corridor and objective")
	first.free()
	second.free()
	target.free()
	print("Squad context smoke: %d failure(s)" % failures)
	quit(1 if failures else 0)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
