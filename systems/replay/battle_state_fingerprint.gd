class_name BattleStateFingerprint
extends RefCounted

static func capture(turn_manager: TurnManager, grid: GridManager, objectives: ObjectiveManager, include_supply_points := true, include_aim := true) -> String:
	var active_id := "none"
	if is_instance_valid(turn_manager.active_unit):
		active_id = _unit_id(turn_manager.active_unit)
	var parts: Array[String] = [
		"round=%d" % turn_manager.current_round,
		"phase=%d" % turn_manager.current_phase,
		"active=%s" % active_id,
		"result=%d" % turn_manager.battle_result,
	]
	var units: Array[TacticalUnit] = []
	for value in grid.occupancy_map.values():
		var unit := value as TacticalUnit
		if is_instance_valid(unit) and not units.has(unit):
			units.append(unit)
	units.sort_custom(func(first: TacticalUnit, second: TacticalUnit): return _unit_id(first) < _unit_id(second))
	for unit in units:
		var cell := grid.get_unit_grid(unit)
		var carried_id := "none"
		if unit.is_carrying_unit():
			carried_id = _unit_id(unit.carried_unit)
		if include_supply_points and include_aim:
			parts.append("unit=%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%s" % [
				_unit_id(unit), unit.faction, cell.x, cell.y, cell.z,
				unit.stats.current_hp if unit.stats else -1,
				unit.stats.current_ap if unit.stats else -1,
				unit.stats.current_supply_points if unit.stats else -1,
				unit.stats.max_supply_points if unit.stats else -1,
				int(unit.stats.is_defending) if unit.stats else 0,
				int(unit.tactical_state.is_aiming) if unit.tactical_state else 0,
				carried_id,
			])
		elif include_supply_points:
			parts.append("unit=%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%s" % [
				_unit_id(unit), unit.faction, cell.x, cell.y, cell.z,
				unit.stats.current_hp if unit.stats else -1,
				unit.stats.current_ap if unit.stats else -1,
				unit.stats.current_supply_points if unit.stats else -1,
				unit.stats.max_supply_points if unit.stats else -1,
				int(unit.stats.is_defending) if unit.stats else 0,
				carried_id,
			])
		else:
			parts.append("unit=%s,%d,%d,%d,%d,%d,%d,%d,%s" % [
				_unit_id(unit), unit.faction, cell.x, cell.y, cell.z,
				unit.stats.current_hp if unit.stats else -1,
				unit.stats.current_ap if unit.stats else -1,
				int(unit.stats.is_defending) if unit.stats else 0,
				carried_id,
			])
	if objectives and objectives.mission:
		for state in objectives.get_objectives():
			parts.append("objective=%s,%d,%d" % [state.definition.objective_id, state.status, state.progress])
		parts.append("extraction=%d,%d,%d" % [objectives.extracted_vips, objectives.extracted_units, objectives.escaped_enemies])
	return "|".join(parts)

static func _unit_id(unit: TacticalUnit) -> String:
	if not is_instance_valid(unit):
		return "none"
	return String(unit.tactical_id) if not unit.tactical_id.is_empty() else String(unit.name)
