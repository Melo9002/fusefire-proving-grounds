class_name SquadContext
extends RefCounted

## A cell an ally holds is forbidden outright; a cell merely beside one is only discouraged.
## Scoring must never outweigh the first kind: see block_reason().
const HARD_BLOCK := -1000.0
const CROWDING_PENALTY := -12.0

var round_number := -1
var reserved_destinations: Dictionary = {}
var intended_targets: Dictionary[StringName, int] = {}
var objective_handlers: Dictionary[StringName, Array] = {}
var reserved_corridor: Dictionary = {}
var corridor_owner: StringName = &""
var _actor_destinations: Dictionary[StringName, Vector3i] = {}
var _actor_targets: Dictionary[StringName, StringName] = {}
var _actor_objectives: Dictionary[StringName, StringName] = {}

func begin_round(current_round: int) -> void:
	if round_number == current_round:
		return
	round_number = current_round
	reserved_destinations.clear()
	intended_targets.clear()
	objective_handlers.clear()
	reserved_corridor.clear()
	corridor_owner = &""
	_actor_destinations.clear()
	_actor_targets.clear()
	_actor_objectives.clear()

func begin_unit(actor: TacticalUnit) -> void:
	release_actor_id(_actor_id(actor))

func release_actor_id(actor_id: StringName) -> void:
	if corridor_owner == actor_id:
		reserved_corridor.clear()
		corridor_owner = &""
	if _actor_destinations.has(actor_id):
		reserved_destinations.erase(_actor_destinations[actor_id])
		_actor_destinations.erase(actor_id)
	if _actor_targets.has(actor_id):
		var target_id := _actor_targets[actor_id]
		intended_targets[target_id] = maxi(0, intended_targets.get(target_id, 1) - 1)
		_actor_targets.erase(actor_id)
	if _actor_objectives.has(actor_id):
		var objective_id := _actor_objectives[actor_id]
		var handlers: Array = objective_handlers.get(objective_id, [])
		handlers.erase(actor_id)
		objective_handlers[objective_id] = handlers
		_actor_objectives.erase(actor_id)

func reserve_destination(actor: TacticalUnit, cell: Vector3i) -> void:
	var actor_id := _actor_id(actor)
	if reserved_destinations.has(cell) and reserved_destinations[cell] != actor_id: return
	if _actor_destinations.has(actor_id):
		var previous: Vector3i = _actor_destinations[actor_id]
		if reserved_destinations.get(previous) == actor_id:
			reserved_destinations.erase(previous)
	reserved_destinations[cell] = actor_id
	_actor_destinations[actor_id] = cell

## Why `actor` may not use `cell`, or "" when it may. These are genuine commitments (an ally's
## exact destination, an escort's carrier corridor), not preferences, and name their owner.
func block_reason(actor: TacticalUnit, cell: Vector3i) -> String:
	if reserved_corridor.has(cell) and corridor_owner != _actor_id(actor):
		return "Corridor reserved by %s" % corridor_owner
	if reserved_destinations.has(cell) and reserved_destinations[cell] != _actor_id(actor):
		return "Destination reserved by %s" % reserved_destinations[cell]
	return ""

## The soft crowding preference only: staying out of the immediate neighbourhood of allies' destinations.
func crowding_adjustment(actor: TacticalUnit, cell: Vector3i) -> float:
	var adjustment := 0.0
	for reserved_cell in reserved_destinations:
		if reserved_destinations[reserved_cell] != _actor_id(actor) and cell.distance_to(reserved_cell) <= 1.0:
			adjustment += CROWDING_PENALTY
	return adjustment

## Both together, kept for callers that want one number: a block is HARD_BLOCK, otherwise crowding.
func destination_adjustment(actor: TacticalUnit, cell: Vector3i) -> float:
	if not block_reason(actor, cell).is_empty():
		return HARD_BLOCK
	return crowding_adjustment(actor, cell)

func reserve_corridor(actor: TacticalUnit, cells: Dictionary) -> void:
	reserved_corridor = cells.duplicate()
	corridor_owner = _actor_id(actor)

func is_reserved_for_other(actor: TacticalUnit, cell: Vector3i) -> bool:
	return reserved_corridor.has(cell) and corridor_owner != _actor_id(actor)

func reserve_target(actor: TacticalUnit, target: TacticalUnit) -> void:
	var actor_id := _actor_id(actor)
	var target_id := _actor_id(target)
	if _actor_targets.get(actor_id) == target_id:
		return
	if _actor_targets.has(actor_id):
		var previous_id := _actor_targets[actor_id]
		intended_targets[previous_id] = maxi(0, intended_targets.get(previous_id, 1) - 1)
	intended_targets[target_id] = intended_targets.get(target_id, 0) + 1
	_actor_targets[actor_id] = target_id

func target_adjustment(actor: TacticalUnit, target: TacticalUnit) -> float:
	var target_id := _actor_id(target)
	var focus_count: int = intended_targets.get(target_id, 0)
	if _actor_targets.get(_actor_id(actor)) == target_id:
		focus_count = maxi(0, focus_count - 1)
	return -15.0 * focus_count

func reserve_objective(actor: TacticalUnit, objective_id: StringName) -> int:
	var actor_id := _actor_id(actor)
	if _actor_objectives.has(actor_id) and _actor_objectives[actor_id] != objective_id:
		var previous_handlers: Array = objective_handlers.get(_actor_objectives[actor_id], [])
		previous_handlers.erase(actor_id)
		_actor_objectives.erase(actor_id)
	if objective_id.is_empty(): return 0
	var handlers: Array = objective_handlers.get(objective_id, [])
	var existing := handlers.size()
	if not handlers.has(actor_id):
		handlers.append(actor_id)
		objective_handlers[objective_id] = handlers
		_actor_objectives[actor_id] = objective_id
	return existing

static func _actor_id(actor: TacticalUnit) -> StringName:
	return actor.tactical_id if not actor.tactical_id.is_empty() else StringName(actor.name)

## Claims last no later than the current round, and disappear when an owner or target leaves.
func prune(actors: Array[TacticalUnit]) -> void:
	var alive := {}
	for actor in actors:
		if is_instance_valid(actor) and actor.stats and not actor.stats.is_defeated:
			alive[_actor_id(actor)] = actor
	for owner: StringName in _actor_destinations.keys():
		if alive.has(owner) and alive[owner].grid_position != _actor_destinations[owner]:
			reserved_destinations.erase(_actor_destinations[owner])
			_actor_destinations.erase(owner)
	var owners := _actor_destinations.keys() + _actor_targets.keys() + _actor_objectives.keys()
	if not corridor_owner.is_empty(): owners.append(corridor_owner)
	for owner: StringName in owners:
		if not alive.has(owner): release_actor_id(owner)
	if not corridor_owner.is_empty() and alive.has(corridor_owner) and not alive[corridor_owner].is_carrying_unit():
		reserved_corridor.clear()
		corridor_owner = &""
	for owner: StringName in _actor_targets.keys():
		var target_id := _actor_targets[owner]
		if not alive.has(target_id):
			intended_targets[target_id] = maxi(0, intended_targets.get(target_id, 1) - 1)
			_actor_targets.erase(owner)
