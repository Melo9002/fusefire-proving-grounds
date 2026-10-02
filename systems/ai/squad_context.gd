class_name SquadContext
extends RefCounted

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
	var actor_id := StringName(actor.name)
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
	var actor_id := StringName(actor.name)
	reserved_destinations[cell] = actor_id
	_actor_destinations[actor_id] = cell

func destination_adjustment(actor: TacticalUnit, cell: Vector3i) -> float:
	if reserved_corridor.has(cell) and corridor_owner != StringName(actor.name):
		return -1000.0
	if reserved_destinations.has(cell) and reserved_destinations[cell] != StringName(actor.name):
		return -1000.0
	var adjustment := 0.0
	for reserved_cell in reserved_destinations:
		if reserved_destinations[reserved_cell] != StringName(actor.name) and cell.distance_to(reserved_cell) <= 1.0:
			adjustment -= 12.0
	return adjustment

func reserve_corridor(actor: TacticalUnit, cells: Dictionary) -> void:
	reserved_corridor = cells.duplicate()
	corridor_owner = StringName(actor.name)

func is_reserved_for_other(actor: TacticalUnit, cell: Vector3i) -> bool:
	return reserved_corridor.has(cell) and corridor_owner != StringName(actor.name)

func reserve_target(actor: TacticalUnit, target: TacticalUnit) -> void:
	var actor_id := StringName(actor.name)
	var target_id := StringName(target.name)
	if _actor_targets.get(actor_id) == target_id:
		return
	if _actor_targets.has(actor_id):
		var previous_id := _actor_targets[actor_id]
		intended_targets[previous_id] = maxi(0, intended_targets.get(previous_id, 1) - 1)
	intended_targets[target_id] = intended_targets.get(target_id, 0) + 1
	_actor_targets[actor_id] = target_id

func target_adjustment(actor: TacticalUnit, target: TacticalUnit) -> float:
	var target_id := StringName(target.name)
	var focus_count: int = intended_targets.get(target_id, 0)
	if _actor_targets.get(StringName(actor.name)) == target_id:
		focus_count = maxi(0, focus_count - 1)
	return -15.0 * focus_count

func reserve_objective(actor: TacticalUnit, objective_id: StringName) -> int:
	if objective_id.is_empty():
		return 0
	var actor_id := StringName(actor.name)
	var handlers: Array = objective_handlers.get(objective_id, [])
	var existing := handlers.size()
	if not handlers.has(actor_id):
		handlers.append(actor_id)
		objective_handlers[objective_id] = handlers
		_actor_objectives[actor_id] = objective_id
	return existing
