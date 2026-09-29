extends RefCounted

signal command_executed(message: String)

var battle_controller: BattleController
var turn_manager: TurnManager
var objective_manager: ObjectiveManager
var grid_manager: GridManager

func configure(battle: BattleController, turns: TurnManager, objectives: ObjectiveManager, grid: GridManager) -> void:
	battle_controller = battle
	turn_manager = turns
	objective_manager = objectives
	grid_manager = grid

func get_actors() -> Array[TacticalUnit]:
	var actors: Array[TacticalUnit] = []
	if not grid_manager:
		return actors
	for value in grid_manager.occupancy_map.values():
		var actor := value as TacticalUnit
		if is_instance_valid(actor) and not actors.has(actor):
			actors.append(actor)
	actors.sort_custom(func(a: TacticalUnit, b: TacticalUnit): return String(a.name) < String(b.name))
	return actors

func get_active_objectives() -> Array[MissionObjectiveState]:
	var result: Array[MissionObjectiveState] = []
	if not objective_manager or not objective_manager.mission:
		return result
	for state in objective_manager.get_objectives():
		if state.is_active():
			result.append(state)
	return result

func advance_round() -> bool:
	if not turn_manager or turn_manager.battle_result != TurnManager.BattleResult.ONGOING:
		return _reject("Advance round rejected: battle is not active.")
	if turn_manager.is_any_unit_moving():
		return _reject("Advance round rejected: a unit is moving.")
	var previous := turn_manager.current_round
	turn_manager._end_round()
	return _accept("Advanced round %d → %d." % [previous, turn_manager.current_round])

func complete_objective(objective_id: StringName) -> bool:
	if not objective_manager or not objective_manager.complete_objective(objective_id):
		return _reject("Complete objective rejected: %s is not active." % objective_id)
	return _accept("Completed objective: %s." % objective_id)

func fail_objective(objective_id: StringName) -> bool:
	if not objective_manager or not objective_manager.fail_objective(objective_id):
		return _reject("Fail objective rejected: %s is not active." % objective_id)
	return _accept("Failed objective: %s." % objective_id)

func teleport_actor(actor: TacticalUnit, destination: Vector3i) -> bool:
	if not is_instance_valid(actor) or not grid_manager:
		return _reject("Teleport rejected: actor is unavailable.")
	var cell := grid_manager.get_cell_data(destination)
	if not cell or not cell.walkable or not cell.can_stop:
		return _reject("Teleport rejected: %s is not a legal stopping cell." % destination)
	var occupant := grid_manager.get_unit_at(destination)
	if is_instance_valid(occupant) and occupant != actor:
		return _reject("Teleport rejected: %s is occupied by %s." % [destination, occupant.name])
	var origin := grid_manager.get_unit_grid(actor)
	if origin == destination:
		return _reject("Teleport rejected: %s is already at %s." % [actor.name, destination])
	grid_manager.update_unit_position(actor, origin, destination)
	actor.global_position = cell.world_position + Vector3.UP * actor.standing_height
	battle_controller.unit_moved.emit(actor, origin, destination)
	return _accept("Teleported %s: %s → %s." % [actor.name, origin, destination])

func force_extract(actor: TacticalUnit) -> bool:
	if not is_instance_valid(actor) or not objective_manager or not objective_manager.mission:
		return _reject("Force extraction rejected: actor or mission is unavailable.")
	var extraction := _find_extraction_objective(actor)
	if not extraction:
		return _reject("Force extraction rejected: %s has no active extraction objective." % actor.name)
	var survive := objective_manager.get_objective(&"survive")
	if survive and survive.is_active():
		objective_manager.complete_objective(&"survive")
	var zone_id := extraction.definition.zone_id if not extraction.definition.zone_id.is_empty() else &"extract"
	var destination := _find_open_zone_cell(zone_id, actor)
	if destination.x < 0:
		return _reject("Force extraction rejected: zone %s has no open cell." % zone_id)
	var origin := grid_manager.get_unit_grid(actor)
	if origin != destination:
		grid_manager.update_unit_position(actor, origin, destination)
		actor.global_position = grid_manager.get_cell_data(destination).world_position + Vector3.UP * actor.standing_height
	if not await objective_manager.try_extract(actor):
		if is_instance_valid(actor) and origin != destination:
			grid_manager.update_unit_position(actor, destination, origin)
			actor.global_position = grid_manager.get_cell_data(origin).world_position + Vector3.UP * actor.standing_height
		return _reject("Force extraction rejected by mission rules for %s." % actor.name)
	return _accept("Forced extraction: %s via %s." % [actor.name, zone_id])

func _find_extraction_objective(actor: TacticalUnit) -> MissionObjectiveState:
	for state in objective_manager.get_objectives():
		if not state.is_active() or state.definition.kind != MissionObjectiveDefinition.Kind.EXTRACT:
			continue
		if not state.definition.is_pursued_by(actor.faction):
			continue
		if state.definition.target_ids.is_empty() or state.definition.target_ids.has(actor.get_mission_id()):
			return state
		if actor.is_carrying_unit() and state.definition.target_ids.has(actor.carried_unit.get_mission_id()):
			return state
	return null

func _find_open_zone_cell(zone_id: StringName, actor: TacticalUnit) -> Vector3i:
	for coordinate in grid_manager.map_data.get_objective_zone(zone_id):
		var cell := grid_manager.get_cell_data(coordinate)
		var occupant := grid_manager.get_unit_at(coordinate)
		if cell and cell.walkable and cell.can_stop and (not is_instance_valid(occupant) or occupant == actor):
			return coordinate
	return Vector3i(-1, -1, -1)

func _accept(message: String) -> bool:
	print_rich("[color=hot_pink][DebugMission][/color] %s" % message)
	command_executed.emit(message)
	return true

func _reject(message: String) -> bool:
	print_rich("[color=yellow][DebugMission][/color] %s" % message)
	command_executed.emit(message)
	return false

